#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

if [[ -n "${BUSLENS_BIN:-}" ]]; then
    BIN="$BUSLENS_BIN"
else
    swift build --product BusLensMac >/dev/null
    BIN="$(swift build --show-bin-path)/BusLensMac"
fi

if [[ ! -x "$BIN" ]]; then
    echo "[FAIL] Executable not found: $BIN" >&2
    exit 1
fi

DISPLAY_BIN="${BIN/#$ROOT/<REPO_ROOT>}"

echo "=== BusLens Mac M1 Differential & Capability Gate ==="
echo "Date (UTC): $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "Host: $(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion)) $(uname -m)"
echo "Binary: $DISPLAY_BIN"
echo ""

python3 - "$ROOT" "$BIN" <<'PY'
from __future__ import annotations
import getpass
import json
import os
import pathlib
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import time

root = pathlib.Path(sys.argv[1])
bin_path = sys.argv[2]

passed_checks = 0
skipped_checks = 0

def run_cmd(args, cwd=None, env=None):
    t0 = time.perf_counter()
    proc = subprocess.run(args, cwd=cwd, env=env, capture_output=True, text=True)
    dt_ms = (time.perf_counter() - t0) * 1000.0
    return proc.returncode, proc.stdout, proc.stderr, dt_ms

def parse_speed_gbps(raw: str | None) -> float:
    if not raw:
        return 0.0
    m = re.search(r"([0-9]+(?:\.[0-9]+)?)\s*(gb|mb|kb)", raw.lower())
    if not m:
        return 0.0
    val = float(m.group(1))
    unit = m.group(2)
    if unit == "gb":
        return val
    if unit == "mb":
        return val / 1000.0
    return val / 1_000_000.0

def parse_loc_int(raw) -> int | None:
    if isinstance(raw, int):
        return raw & 0xFFFFFFFF
    if isinstance(raw, str):
        tok = raw.strip().lower().split()[0]
        if tok.startswith("0x"):
            try:
                return int(tok, 16) & 0xFFFFFFFF
            except ValueError:
                return None
        try:
            return int(tok) & 0xFFFFFFFF
        except ValueError:
            return None
    return None

# ---------------------------------------------------------------------------
# Row 1: Independent Reference Oracle (system_profiler + ioreg) vs BusLensMac
# ---------------------------------------------------------------------------
sp_raw = subprocess.check_output([
    "/usr/sbin/system_profiler",
    "SPThunderboltDataType",
    "SPUSBHostDataType",
    "SPUSBDataType",
    "SPPowerDataType",
    "-json",
])
sp_json = json.loads(sp_raw)

usb_ioreg_raw = subprocess.check_output(["/usr/sbin/ioreg", "-a", "-r", "-c", "AppleUSBHostPort", "-l"])
usb_ioreg = plistlib.loads(usb_ioreg_raw) or []

tb_ioreg_raw = subprocess.check_output(["/usr/sbin/ioreg", "-a", "-r", "-c", "IOThunderboltSwitch", "-l"])
tb_ioreg = plistlib.loads(tb_ioreg_raw) or []

platform_ioreg_raw = subprocess.check_output(["/usr/sbin/ioreg", "-a", "-r", "-d", "1", "-c", "IOPlatformExpertDevice"])
platform_ioreg = plistlib.loads(platform_ioreg_raw) or []

# Harvest live hardware serials, UUIDs, UIDs, ContainerIDs, and OS username (read-only)
live_secrets: set[str] = set()
current_user = getpass.getuser().strip()
if len(current_user) >= 2:
    live_secrets.add("/" + "Users/" + current_user)

SECRET_EXACT_KEYS = {
    "serial_num",
    "device_serial",
    "USBDeviceKeySerialNumber",
    "domain_uuid_key",
    "switch_uid_key",
    "kUSBSerialNumberString",
    "USB Serial Number",
    "kUSBContainerID",
    "ContainerID",
    "Device GUID",
    "UUID",
    "UID",
    "Switch UID",
    "Domain UUID",
    "IOPlatformSerialNumber",
    "IOPlatformUUID",
}

def harvest_secrets(obj):
    if isinstance(obj, dict):
        for k, v in obj.items():
            kl = k.lower()
            is_secret_key = (
                k in SECRET_EXACT_KEYS
                or "serial" in kl
                or "uuid" in kl
                or "uid_key" in kl
                or "switch uid" in kl
                or "containerid" in kl
            )
            if is_secret_key:
                if isinstance(v, str) and len(v.strip()) >= 4:
                    live_secrets.add(v.strip())
                elif isinstance(v, int) and v > 0xFFFF:
                    live_secrets.add(f"0x{v:x}")
                    live_secrets.add(str(v))
            else:
                harvest_secrets(v)
    elif isinstance(obj, list):
        for elem in obj:
            harvest_secrets(elem)

harvest_secrets(sp_json)
harvest_secrets(usb_ioreg)
harvest_secrets(tb_ioreg)
harvest_secrets(platform_ioreg)

# Build independent USB locationID -> physical port & class oracle from ioreg
usb_host_port_by_loc: dict[int, str] = {}
usb_dev_port_by_loc: dict[int, str] = {}
usb_dev_class_by_loc: dict[int, int] = {}
usb_dev_speed_by_loc: dict[int, float] = {}
usb_dev_internal_by_loc: dict[int, bool] = {}
socket_to_port: dict[str, str] = {}

def walk_usb_oracle(node: dict, parent_internal: bool, current_host_port: str | None):
    cls = node.get("IOObjectClass", "")
    next_internal = parent_internal
    next_host_port = current_host_port

    if "USB" in cls and cls.endswith("Port"):
        loc = parse_loc_int(node.get("locationID"))
        io_port = node.get("UsbIOPort")
        port_num = node.get("PortNumber")
        port_label = None
        if isinstance(io_port, str) and "/" in io_port:
            port_label = io_port.rsplit("/", 1)[-1]
        elif isinstance(port_num, int) and port_num > 0:
            port_label = f"Port-USB-C@{port_num}"
        if isinstance(port_num, int) and port_label:
            socket_to_port[str(port_num)] = port_label
        if parent_internal and (port_label or "XHCIPort" in cls or "XHCIARMPort" in cls):
            if loc is not None and port_label:
                usb_host_port_by_loc[loc] = port_label
            if port_label:
                next_host_port = port_label
    elif cls == "IOUSBHostDevice":
        loc = parse_loc_int(node.get("locationID"))
        ptype = node.get("USBPortType")
        is_int = ptype in (1, 2)
        next_internal = is_int
        if loc is not None:
            usb_dev_internal_by_loc[loc] = is_int
            if isinstance(node.get("bDeviceClass"), int):
                usb_dev_class_by_loc[loc] = node["bDeviceClass"]
            if isinstance(node.get("UsbLinkSpeed"), int) and node["UsbLinkSpeed"] > 0:
                usb_dev_speed_by_loc[loc] = node["UsbLinkSpeed"] / 1_000_000_000.0
            if current_host_port:
                usb_dev_port_by_loc[loc] = current_host_port

    for ch in node.get("IORegistryEntryChildren", []) or []:
        if isinstance(ch, dict):
            walk_usb_oracle(ch, next_internal, next_host_port)

for root_entry in usb_ioreg:
    if isinstance(root_entry, dict):
        walk_usb_oracle(root_entry, True, None)

# Build independent Thunderbolt router -> physical port oracle from ioreg
tb_router_to_port: dict[int, str] = {}
for tb_root in tb_ioreg:
    if not isinstance(tb_root, dict):
        continue
    if "IOThunderboltSwitch" not in tb_root.get("IOObjectClass", ""):
        continue
    if tb_root.get("Depth", 0) != 0:
        continue
    router_id = tb_root.get("Router ID")
    if not isinstance(router_id, int):
        continue
    for ch in tb_root.get("IORegistryEntryChildren", []) or []:
        if isinstance(ch, dict) and "IOThunderboltPort" in ch.get("IOObjectClass", ""):
            sid = ch.get("Socket ID")
            if sid is not None:
                sid_s = str(sid)
                tb_router_to_port[router_id] = socket_to_port.get(sid_s, f"Port-USB-C@{sid_s}")
                break

# Independently enumerate external devices from system_profiler + ioreg oracle
oracle_devices: list[tuple[str, float, str | None]] = []

def walk_sp_tb_items(items: list, bus_speed_gbps: float, phys_port: str | None):
    for item in items:
        if not isinstance(item, dict):
            continue
        up_tag = item.get("receptacle_upstream_ambiguous_tag") or {}
        spd = parse_speed_gbps(up_tag.get("current_speed_key")) or parse_speed_gbps(item.get("current_speed_key")) or bus_speed_gbps
        oracle_devices.append(("tb", round(spd, 6), phys_port))
        sub = item.get("_items") or []
        if isinstance(sub, list) and sub:
            walk_sp_tb_items(sub, spd, phys_port)

for tb_bus in sp_json.get("SPThunderboltDataType", []) or []:
    if not isinstance(tb_bus, dict):
        continue
    raw_bus_name = tb_bus.get("_name", "")
    m_r = re.search(r"_(\d+)$", raw_bus_name)
    router_id = int(m_r.group(1)) if m_r else None
    phys_port = tb_router_to_port.get(router_id) if router_id is not None else None
    if phys_port is None:
        for k, v in tb_bus.items():
            if k.startswith("receptacle_") and k.endswith("_tag") and isinstance(v, dict):
                rid = v.get("receptacle_id_key")
                if rid:
                    phys_port = socket_to_port.get(str(rid), f"Port-USB-C@{rid}")
                    break
    bus_spd = 0.0
    for k, v in tb_bus.items():
        if k.startswith("receptacle_") and k.endswith("_tag") and isinstance(v, dict):
            bus_spd = max(bus_spd, parse_speed_gbps(v.get("current_speed_key")))
    walk_sp_tb_items(tb_bus.get("_items") or [], bus_spd, phys_port)

usb_buses = sp_json.get("SPUSBHostDataType") or []
if not usb_buses:
    usb_buses = sp_json.get("SPUSBDataType") or []

def walk_sp_usb_items(items: list):
    for item in items:
        if not isinstance(item, dict):
            continue
        loc = parse_loc_int(item.get("USBKeyLocationID") or item.get("location_id"))
        hw_type = str(item.get("USBKeyHardwareType", "")).lower()
        built_in = (
            hw_type == "built-in"
            or str(item.get("Built-in_Device", "")).lower() == "yes"
            or (loc is not None and usb_dev_internal_by_loc.get(loc, False))
        )
        dev_class = item.get("bDeviceClass")
        if not isinstance(dev_class, int) and loc is not None:
            dev_class = usb_dev_class_by_loc.get(loc)
        is_hub_container = built_in or (dev_class == 9)

        children = item.get("_items") or []
        if not is_hub_container:
            spd = parse_speed_gbps(item.get("USBDeviceKeyLinkSpeed") or item.get("speed"))
            if spd <= 0 and loc is not None:
                spd = usb_dev_speed_by_loc.get(loc, 0.0)
            phys_port = usb_dev_port_by_loc.get(loc) if loc is not None else None
            oracle_devices.append(("usb", round(spd, 6), phys_port))
        if isinstance(children, list) and children:
            walk_sp_usb_items(children)

for ub in usb_buses:
    if isinstance(ub, dict):
        walk_sp_usb_items(ub.get("_items") or [])

for lang in ("en", "zh"):
    rc_j, out_j, err_j, dt_ms = run_cmd([bin_path, "--cli", "topology", "--json", "--lang", lang])
    assert rc_j == 0 and err_j == "", f"Row 1 ({lang}) topology --json failed (rc={rc_j}): {err_j}"
    rc_t, out_t, err_t, _ = run_cmd([bin_path, "--cli", "topology", "--lang", lang])
    assert rc_t == 0 and err_t == "", f"Row 1 ({lang}) topology text failed (rc={rc_t}): {err_t}"
    rc_b, out_b, err_b, _ = run_cmd([bin_path, "--cli", "bottlenecks", "--json", "--lang", lang])
    assert rc_b == 0 and err_b == "", f"Row 1 ({lang}) bottlenecks --json failed (rc={rc_b}): {err_b}"

    for secret in live_secrets:
        for mode_lbl, blob in [("topology --json", out_j), ("topology text", out_t), ("bottlenecks --json", out_b)]:
            assert secret.lower() not in blob.lower(), (
                f"Row 1 ({lang}) leaked live identifier/path in {mode_lbl}!"
            )

    parsed = json.loads(out_j)
    got_devs = parsed["devices"]
    assert len(got_devs) == len(oracle_devices), (
        f"Row 1 ({lang}) external device count mismatch: BusLens={len(got_devs)} vs oracle={len(oracle_devices)}"
    )
    got_tuples = sorted(
        (
            "tb" if ("thunderbolt" in d["protocolKind"].lower() or "雷雳" in d["protocolKind"]) else "usb",
            round(float(d["negotiatedGbps"]), 6),
            d.get("physicalPort"),
        )
        for d in got_devs
    )
    exp_tuples = sorted(oracle_devices)
    assert got_tuples == exp_tuples, (
        f"Row 1 ({lang}) item-by-item differential mismatch:\n  BusLens={got_tuples}\n  Oracle ={exp_tuples}"
    )

anon_summary = ", ".join(
    f"{proto.upper()}@{port or 'unmapped'}={spd:g}Gbps"
    for proto, spd, port in sorted(oracle_devices)
) or "0 attached devices"
passed_checks += 1
print(
    f"[PASS] Row 1 (Live differential oracle vs system_profiler + ioreg in EN & ZH): "
    f"devices={len(oracle_devices)} ({anon_summary}), 100% match on count/speed/port, "
    f"0 leaks across {len(live_secrets)} live identifiers"
)

# ---------------------------------------------------------------------------
# Row 2 & Row 3: Real-hardware cable-swapping captures — explicitly NOT RUN
# ---------------------------------------------------------------------------
skipped_checks += 1
print("[SKIP] Row 2 (Real hardware enclosure w/ charging-only cable): 没跑 (requires human cable-swapping)")
skipped_checks += 1
print("[SKIP] Row 3 (Real hardware enclosure w/ stock cable): 没跑 (requires human cable-swapping)")

# ---------------------------------------------------------------------------
# Row 4 + U13 + U14 + Paired 2026-11-15 Scrubbed Fixture
# ---------------------------------------------------------------------------
sp_20261115 = root / "Tests/BusLensMacTests/Fixtures/host_macmini_20261115_sp_scrubbed.json"
ioreg_20261115 = root / "Tests/BusLensMacTests/Fixtures/host_macmini_20261115_ioreg_scrubbed.plist"
assert sp_20261115.is_file() and ioreg_20261115.is_file(), "Missing 2026-11-15 paired host fixtures"

sp_meta = json.loads(sp_20261115.read_text(encoding="utf-8")).get("_capture_metadata", {})
assert "2026-11-15" in sp_meta.get("captured_at_utc", "") and "system_profiler" in sp_meta.get("command", "")
ioreg_head = ioreg_20261115.read_text(encoding="utf-8")[:600]
assert "2026-11-15" in ioreg_head and "/usr/sbin/ioreg" in ioreg_head
for secret in live_secrets:
    assert secret.lower() not in sp_20261115.read_text(encoding="utf-8").lower(), "2026-11-15 SP fixture leaked live identifier"
    assert secret.lower() not in ioreg_20261115.read_text(encoding="utf-8").lower(), "2026-11-15 ioreg fixture leaked live identifier"

rc_pair, out_pair, err_pair, _ = run_cmd([
    bin_path, "--cli", "topology",
    "--input", str(sp_20261115),
    "--ioreg-input", str(ioreg_20261115),
    "--json", "--lang", "en",
])
assert rc_pair == 0 and err_pair == ""
pair_devs = json.loads(out_pair)["devices"]
assert len(pair_devs) == 2
assert {d["physicalPort"] for d in pair_devs} == {"Port-USB-C@2", "Port-USB-C@6"}
passed_checks += 1
print("[PASS] Paired 2026-11-15 scrubbed Mac mini fixture (system_profiler + ioreg): verified capture headers, 0 leaks, and Port-USB-C@2 / Port-USB-C@6 mapping")

with tempfile.TemporaryDirectory(prefix="buslens-m1-syn-") as tmpdir:
    tmp = pathlib.Path(tmpdir)

    # All synthetic files include 'synthetic' in both filename and header per fixture rule
    syn_sp_path = tmp / "synthetic_16_scenarios_sp.json"
    syn_ioreg_path = tmp / "synthetic_16_scenarios_ioreg.plist"

    syn_sp_obj = {
        "_fixture_header": "synthetic M1 16-scenario system_profiler fixture (synthetic test input)",
        "SPThunderboltDataType": [
            {
                "_name": "thunderboltusb4_bus_0",
                "receptacle_1_tag": {
                    "current_speed_key": "Up to 40 Gb/s",
                    "receptacle_id_key": "1",
                    "receptacle_status_key": "receptacle_connected",
                },
                "_items": [
                    {
                        "_name": "OWC Envoy NVMe",
                        "device_name_key": "OWC Envoy NVMe",
                        "vendor_name_key": "Acme",
                        "mode_key": "thunderbolt_three",
                        "route_string_key": "1",
                        "receptacle_upstream_ambiguous_tag": {
                            "current_speed_key": "20 Gb/s",
                            "receptacle_status_key": "receptacle_connected",
                        },
                    }
                ],
            },
            {
                "_name": "thunderboltusb4_bus_1",
                "receptacle_1_tag": {
                    "current_speed_key": "Up to 40 Gb/s",
                    "receptacle_id_key": "2",
                    "receptacle_status_key": "receptacle_connected",
                },
                "_items": [
                    {
                        "_name": "USB4 Hub NVMe",
                        "device_name_key": "USB4 Hub NVMe",
                        "vendor_name_key": "Acme",
                        "mode_key": "usb4",
                        "route_string_key": "1",
                        "receptacle_upstream_ambiguous_tag": {
                            "current_speed_key": "40 Gb/s",
                            "receptacle_status_key": "receptacle_connected",
                        },
                        "_items": [
                            {
                                "_name": "Samsung X5",
                                "device_name_key": "Samsung X5",
                                "vendor_name_key": "Acme",
                                "mode_key": "thunderbolt_three",
                                "route_string_key": "301",
                                "receptacle_upstream_ambiguous_tag": {
                                    "current_speed_key": "20 Gb/s",
                                    "receptacle_status_key": "receptacle_connected",
                                },
                            }
                        ],
                    }
                ],
            },
        ],
        "SPUSBHostDataType": [
            {
                "_name": "USB 3.1 Bus",
                "USBKeyLocationID": "0x01000000",
                "_items": [
                    {"_name": "ASM2464PD 480M", "USBKeyLocationID": "0x01110000", "USBDeviceKeyLinkSpeed": "480 Mb/s", "USBDeviceKeyVendorName": "ASMedia"},
                    {"_name": "ASM2464PD 10G", "USBKeyLocationID": "0x01210000", "USBDeviceKeyLinkSpeed": "10 Gb/s", "USBDeviceKeyVendorName": "ASMedia"},
                    {"_name": "Wooting 60HE", "USBKeyLocationID": "0x01120000", "USBDeviceKeyLinkSpeed": "480 Mb/s", "USBDeviceKeyVendorName": "Wooting"},
                    {"_name": "USB Optical Mouse", "USBKeyLocationID": "0x01130000", "USBDeviceKeyLinkSpeed": "12 Mb/s", "USBDeviceKeyVendorName": "Vendor"},
                    {"_name": "2.4G Wireless Receiver", "USBKeyLocationID": "0x01140000", "USBDeviceKeyLinkSpeed": "12 Mb/s", "USBDeviceKeyVendorName": "Vendor"},
                    {"_name": "Logitech Unifying Receiver", "USBKeyLocationID": "0x01150000", "USBDeviceKeyLinkSpeed": "12 Mb/s", "USBDeviceKeyVendorName": "Logitech"},
                    {"_name": "USB DISK 2.0", "USBKeyLocationID": "0x01160000", "USBDeviceKeyLinkSpeed": "480 Mb/s", "USBDeviceKeyVendorName": "Kingston"},
                    {"_name": "My Passport 25E2", "USBKeyLocationID": "0x01170000", "USBDeviceKeyLinkSpeed": "480 Mb/s", "USBDeviceKeyVendorName": "Western Digital"},
                    {"_name": "SanDisk Extreme PRO USB2 Drive", "USBKeyLocationID": "0x01180000", "USBDeviceKeyLinkSpeed": "480 Mb/s", "USBDeviceKeyVendorName": "SanDisk"},
                    {
                        "_name": "External USB2 Hub",
                        "USBKeyLocationID": "0x01190000",
                        "USBDeviceKeyLinkSpeed": "480 Mb/s",
                        "USBDeviceKeyVendorName": "Generic",
                        "_items": [
                            {"_name": "Portable SSD T7 Behind USB2 Hub", "USBKeyLocationID": "0x01191000", "USBDeviceKeyLinkSpeed": "480 Mb/s", "USBDeviceKeyVendorName": "Samsung"}
                        ],
                    },
                    {"_name": "Portable SSD T7 Native 10G", "USBKeyLocationID": "0x01220000", "USBDeviceKeyLinkSpeed": "10 Gb/s", "USBDeviceKeyVendorName": "Samsung"},
                    {"_name": "Samsung T5", "USBKeyLocationID": "0x01230000", "USBDeviceKeyLinkSpeed": "5 Gb/s", "USBDeviceKeyVendorName": "Samsung"},
                    {"_name": "CalDigit TS4 Dock", "USBKeyLocationID": "0x011a0000", "USBDeviceKeyLinkSpeed": "480 Mb/s", "USBDeviceKeyVendorName": "CalDigit"},
                    {
                        "_name": "External USB3 Gen2 Hub",
                        "USBKeyLocationID": "0x01240000",
                        "USBDeviceKeyLinkSpeed": "10 Gb/s",
                        "USBDeviceKeyVendorName": "Genesys",
                        "_items": [
                            {"_name": "Elements SE", "USBKeyLocationID": "0x01241000", "USBDeviceKeyLinkSpeed": "5 Gb/s", "USBDeviceKeyVendorName": "WD"}
                        ],
                    },
                    {"_name": "SuperSpeed Drive On USB2 Host Port", "USBKeyLocationID": "0x04100000", "USBDeviceKeyLinkSpeed": "480 Mb/s", "USBDeviceKeyVendorName": "Acme"},
                ],
            }
        ],
    }
    syn_sp_path.write_text(json.dumps(syn_sp_obj, indent=2), encoding="utf-8")

    syn_ioreg_obj = {
        "AppleUSBHostPort": [
            {
                "IOObjectClass": "AppleUSB20XHCIARMPort",
                "locationID": 0x01100000,
                "UsbIOPort": "IOService:/AppleARMPE/Port-USB-C@1",
                "UsbProtocol (2.0)": True,
                "UsbProtocolCompanion (3.x)": "IOService:/usb-ss@01200000",
                "IORegistryEntryChildren": [
                    {"IOObjectClass": "IOUSBHostDevice", "locationID": 0x01110000, "bcdUSB": 0x0210, "bDeviceClass": 0, "IORegistryEntryChildren": [{"IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 8}]},
                    {"IOObjectClass": "IOUSBHostDevice", "locationID": 0x01120000, "bcdUSB": 0x0200, "bDeviceClass": 0, "IORegistryEntryChildren": [{"IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 3}]},
                    {"IOObjectClass": "IOUSBHostDevice", "locationID": 0x01130000, "bcdUSB": 0x0200, "bDeviceClass": 0, "IORegistryEntryChildren": [{"IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 3}]},
                    {"IOObjectClass": "IOUSBHostDevice", "locationID": 0x01140000, "bcdUSB": 0x0200, "bDeviceClass": 0, "IORegistryEntryChildren": [{"IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 3}]},
                    {"IOObjectClass": "IOUSBHostDevice", "locationID": 0x01150000, "bcdUSB": 0x0200, "bDeviceClass": 0, "IORegistryEntryChildren": [{"IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 3}]},
                    {"IOObjectClass": "IOUSBHostDevice", "locationID": 0x01160000, "bcdUSB": 0x0200, "bDeviceClass": 0, "IORegistryEntryChildren": [{"IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 8}]},
                    {"IOObjectClass": "IOUSBHostDevice", "locationID": 0x01170000, "bcdUSB": 0x0210, "bDeviceClass": 0, "IORegistryEntryChildren": [{"IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 8}]},
                    {"IOObjectClass": "IOUSBHostDevice", "locationID": 0x01180000, "bcdUSB": 0x0200, "bDeviceClass": 0, "IORegistryEntryChildren": [{"IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 8}]},
                    {
                        "IOObjectClass": "IOUSBHostDevice",
                        "locationID": 0x01190000,
                        "bcdUSB": 0x0200,
                        "bDeviceClass": 9,
                        "UsbLinkSpeed": 480_000_000,
                        "IORegistryEntryChildren": [
                            {"IOObjectClass": "IOUSBHostDevice", "locationID": 0x01191000, "bcdUSB": 0x0210, "bDeviceClass": 0, "IORegistryEntryChildren": [{"IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 8}]}
                        ],
                    },
                    {"IOObjectClass": "IOUSBHostDevice", "locationID": 0x011A0000, "bcdUSB": 0x0201, "bDeviceClass": 17, "IORegistryEntryChildren": [{"IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 17}]},
                ],
            },
            {
                "IOObjectClass": "AppleUSB30XHCIARMPort",
                "locationID": 0x01200000,
                "UsbIOPort": "IOService:/AppleARMPE/Port-USB-C@1",
                "UsbProtocol (3.x)": True,
                "UsbHostPortLinkSpeedLimit": 5,
                "IORegistryEntryChildren": [
                    {"IOObjectClass": "IOUSBHostDevice", "locationID": 0x01210000, "bcdUSB": 0x0320, "bDeviceClass": 0, "IORegistryEntryChildren": [{"IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 8}]},
                    {"IOObjectClass": "IOUSBHostDevice", "locationID": 0x01220000, "bcdUSB": 0x0310, "bDeviceClass": 0, "IORegistryEntryChildren": [{"IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 8}]},
                    {"IOObjectClass": "IOUSBHostDevice", "locationID": 0x01230000, "bcdUSB": 0x0300, "bDeviceClass": 0, "IORegistryEntryChildren": [{"IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 8}]},
                    {
                        "IOObjectClass": "IOUSBHostDevice",
                        "locationID": 0x01240000,
                        "bcdUSB": 0x0310,
                        "bDeviceClass": 9,
                        "UsbLinkSpeed": 10_000_000_000,
                        "IORegistryEntryChildren": [
                            {"IOObjectClass": "IOUSBHostDevice", "locationID": 0x01241000, "bcdUSB": 0x0300, "bDeviceClass": 0, "IORegistryEntryChildren": [{"IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 8}]}
                        ],
                    },
                ],
            },
            {
                "IOObjectClass": "AppleUSB20XHCIPort",
                "locationID": 0x04100000,
                "UsbIOPort": "IOService:/AppleARMPE/Port-USB-A@1",
                "UsbProtocol (2.0)": True,
                "IORegistryEntryChildren": [
                    {"IOObjectClass": "IOUSBHostDevice", "locationID": 0x04100000, "bcdUSB": 0x0210, "bDeviceClass": 0, "IORegistryEntryChildren": [{"IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 8}]}
                ],
            },
        ],
        "IOThunderboltSwitch": [
            {
                "IOObjectClass": "IOThunderboltSwitchType5",
                "Router ID": 0,
                "Depth": 0,
                "Route String": 0,
                "IORegistryEntryChildren": [
                    {
                        "IOObjectClass": "IOThunderboltPort",
                        "Socket ID": "1",
                        "Supported Link Speed": 12,
                        "Supported Link Width": 2,
                        "Link Bandwidth": 200,
                        "IORegistryEntryChildren": [
                            {
                                "IOObjectClass": "IOThunderboltPort",
                                "Supported Link Speed": 12,
                                "Supported Link Width": 2,
                                "Link Bandwidth": 200,
                                "IORegistryEntryChildren": [
                                    {"IOObjectClass": "IOThunderboltSwitchType3", "Depth": 1, "Route String": 1, "Device Model Name": "OWC Envoy NVMe"}
                                ],
                            }
                        ],
                    }
                ],
            },
            {
                "IOObjectClass": "IOThunderboltSwitchType5",
                "Router ID": 1,
                "Depth": 0,
                "Route String": 0,
                "IORegistryEntryChildren": [
                    {
                        "IOObjectClass": "IOThunderboltPort",
                        "Socket ID": "2",
                        "Supported Link Speed": 12,
                        "Supported Link Width": 2,
                        "Link Bandwidth": 400,
                        "IORegistryEntryChildren": [
                            {
                                "IOObjectClass": "IOThunderboltPort",
                                "Supported Link Speed": 12,
                                "Supported Link Width": 2,
                                "Link Bandwidth": 400,
                                "IORegistryEntryChildren": [
                                    {
                                        "IOObjectClass": "IOThunderboltSwitchType5",
                                        "Depth": 1,
                                        "Route String": 1,
                                        "Device Model Name": "USB4 Hub NVMe",
                                        "IORegistryEntryChildren": [
                                            {
                                                "IOObjectClass": "IOThunderboltPort",
                                                "Supported Link Speed": 12,
                                                "Supported Link Width": 2,
                                                "Link Bandwidth": 200,
                                                "IORegistryEntryChildren": [
                                                    {
                                                        "IOObjectClass": "IOThunderboltPort",
                                                        "Supported Link Speed": 12,
                                                        "Supported Link Width": 2,
                                                        "Link Bandwidth": 200,
                                                        "IORegistryEntryChildren": [
                                                            {"IOObjectClass": "IOThunderboltSwitchType3", "Depth": 2, "Route String": "301", "Device Model Name": "Samsung X5"}
                                                        ],
                                                    }
                                                ],
                                            }
                                        ],
                                    }
                                ],
                            }
                        ],
                    }
                ],
            },
        ],
    }
    raw_plist = plistlib.dumps(syn_ioreg_obj, fmt=plistlib.FMT_XML).decode("utf-8")
    raw_plist = raw_plist.replace(
        "<plist version=\"1.0\">",
        "<!-- synthetic M1 16-scenario ioreg fixture -->\n<plist version=\"1.0\">",
        1,
    )
    syn_ioreg_path.write_text(raw_plist, encoding="utf-8")

    expected_16 = {
        "ASM2464PD 480M": ("throttled", "cable"),
        "ASM2464PD 10G": ("indeterminate", None),
        "Wooting 60HE": ("normal", None),
        "USB Optical Mouse": ("low_speed_peripheral", None),
        "2.4G Wireless Receiver": ("low_speed_peripheral", None),
        "Logitech Unifying Receiver": ("low_speed_peripheral", None),
        "USB DISK 2.0": ("normal", None),
        "My Passport 25E2": ("throttled", "cable"),
        "SanDisk Extreme PRO USB2 Drive": ("normal", None),
        "Portable SSD T7 Behind USB2 Hub": ("throttled", "hub"),
        "Portable SSD T7 Native 10G": ("normal", None),
        "Samsung T5": ("normal", None),
        "CalDigit TS4 Dock": ("normal", None),
        "Elements SE": ("normal", None),
        "OWC Envoy NVMe": ("throttled", "cable"),
        "USB4 Hub NVMe": ("full_rate", None),
        "Samsung X5": ("throttled", "cable"),
        "SuperSpeed Drive On USB2 Host Port": ("throttled", "port"),
    }

    for lang in ("en", "zh"):
        rc_16, out_16, err_16, _ = run_cmd([
            bin_path, "--cli", "topology",
            "--input", str(syn_sp_path),
            "--ioreg-input", str(syn_ioreg_path),
            "--json", "--lang", lang,
        ])
        assert rc_16 == 0 and err_16 == "", f"Row 4 ({lang}) failed: {err_16}"
        devs_16 = {d["name"]: d for d in json.loads(out_16)["devices"]}
        assert "External USB2 Hub" not in devs_16 and "External USB3 Gen2 Hub" not in devs_16
        for dname, (exp_v, exp_seg) in expected_16.items():
            assert dname in devs_16, f"Row 4 ({lang}) missing {dname}"
            assert devs_16[dname]["verdict"] == exp_v, f"Row 4 ({lang}) {dname}: {devs_16[dname]['verdict']} != {exp_v}"
            assert devs_16[dname]["bottleneckSegment"] == exp_seg, f"Row 4 ({lang}) {dname} seg: {devs_16[dname]['bottleneckSegment']} != {exp_seg}"

    passed_checks += 1
    print("[PASS] Row 4: All 16 synthetic scenarios (+ port-limited case) match expected verdicts & cable/hub/port bottleneck segments in EN & ZH")

    # U13 CLI verification: 10 Gb/s non-Class-9 dock with child device stays visible
    syn_u13_sp = tmp / "synthetic_u13_dock_sp.json"
    syn_u13_ioreg = tmp / "synthetic_u13_dock_ioreg.plist"
    syn_u13_sp.write_text(json.dumps({
        "_fixture_header": "synthetic U13 non-hub dock fixture",
        "SPUSBHostDataType": [{
            "_name": "USB 3.1 Bus",
            "USBKeyLocationID": "0x01000000",
            "_items": [{
                "_name": "Composite 10G Creator Dock",
                "USBKeyLocationID": "0x01100000",
                "USBDeviceKeyLinkSpeed": "10 Gb/s",
                "_items": [{
                    "_name": "Downstream Capture Stick",
                    "USBKeyLocationID": "0x01110000",
                    "USBDeviceKeyLinkSpeed": "5 Gb/s",
                }],
            }],
        }],
    }), encoding="utf-8")
    u13_plist = plistlib.dumps({
        "AppleUSBHostPort": [{
            "IOObjectClass": "AppleUSB30XHCIPort",
            "locationID": 0x01100000,
            "UsbIOPort": "IOService:/AppleARMPE/Port-USB-C@1",
            "UsbProtocol (3.x)": True,
            "IORegistryEntryChildren": [{
                "IOObjectClass": "IOUSBHostDevice",
                "locationID": 0x01100000,
                "bcdUSB": 0x0310,
                "bDeviceClass": 0,
                "IORegistryEntryChildren": [
                    {"IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 14},
                    {"IOObjectClass": "IOUSBHostDevice", "locationID": 0x01110000, "bcdUSB": 0x0300, "bDeviceClass": 0},
                ],
            }],
        }],
    }, fmt=plistlib.FMT_XML).decode("utf-8").replace("<plist version=\"1.0\">", "<!-- synthetic U13 ioreg -->\n<plist version=\"1.0\">", 1)
    syn_u13_ioreg.write_text(u13_plist, encoding="utf-8")

    rc_u13, out_u13, _, _ = run_cmd([
        bin_path, "--cli", "topology",
        "--input", str(syn_u13_sp),
        "--ioreg-input", str(syn_u13_ioreg),
        "--json", "--lang", "en",
    ])
    assert rc_u13 == 0
    u13_names = [d["name"] for d in json.loads(out_u13)["devices"]]
    assert "Composite 10G Creator Dock" in u13_names and "Downstream Capture Stick" in u13_names
    passed_checks += 1
    print("[PASS] U13: Non-Class-9 10 Gb/s dock with 5 Gb/s downstream child remains visible in device list")

    # U14 CLI verification: 12 Mb/s Mass Storage (bInterfaceClass == 8) is NEVER labeled HID / low_speed_peripheral
    syn_u14_sp = tmp / "synthetic_u14_msd12m_sp.json"
    syn_u14_ioreg = tmp / "synthetic_u14_msd12m_ioreg.plist"
    syn_u14_sp.write_text(json.dumps({
        "_fixture_header": "synthetic U14 12Mbps mass storage fixture",
        "SPUSBHostDataType": [{
            "_name": "USB 3.1 Bus",
            "USBKeyLocationID": "0x01000000",
            "_items": [
                {"_name": "ThumbDrive 64GB", "USBKeyLocationID": "0x01110000", "USBDeviceKeyLinkSpeed": "12 Mb/s"},
                {"_name": "Wired Keyboard", "USBKeyLocationID": "0x01120000", "USBDeviceKeyLinkSpeed": "12 Mb/s"},
            ],
        }],
    }), encoding="utf-8")
    u14_plist = plistlib.dumps({
        "AppleUSBHostPort": [{
            "IOObjectClass": "AppleUSB20XHCIPort",
            "locationID": 0x01100000,
            "UsbIOPort": "IOService:/AppleARMPE/Port-USB-C@1",
            "UsbProtocol (2.0)": True,
            "UsbProtocolCompanion (3.x)": "IOService:/usb-ss@01200000",
            "IORegistryEntryChildren": [
                {"IOObjectClass": "IOUSBHostDevice", "locationID": 0x01110000, "bcdUSB": 0x0210, "bDeviceClass": 0, "IORegistryEntryChildren": [{"IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 8}]},
                {"IOObjectClass": "IOUSBHostDevice", "locationID": 0x01120000, "bcdUSB": 0x0200, "bDeviceClass": 0, "IORegistryEntryChildren": [{"IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 3}]},
            ],
        }],
    }, fmt=plistlib.FMT_XML).decode("utf-8").replace("<plist version=\"1.0\">", "<!-- synthetic U14 ioreg -->\n<plist version=\"1.0\">", 1)
    syn_u14_ioreg.write_text(u14_plist, encoding="utf-8")

    for lang, exp_hid in [("en", "HID peripheral"), ("zh", "HID / 低速外设")]:
        rc_u14, out_u14, _, _ = run_cmd([
            bin_path, "--cli", "topology",
            "--input", str(syn_u14_sp),
            "--ioreg-input", str(syn_u14_ioreg),
            "--json", "--lang", lang,
        ])
        assert rc_u14 == 0
        u14_map = {d["name"]: d for d in json.loads(out_u14)["devices"]}
        assert u14_map["ThumbDrive 64GB"]["verdict"] == "throttled"
        assert u14_map["ThumbDrive 64GB"]["verdict"] != "low_speed_peripheral"
        assert u14_map["Wired Keyboard"]["verdict"] == "low_speed_peripheral"
        assert u14_map["Wired Keyboard"]["verdictLabel"] == exp_hid
    passed_checks += 1
    print("[PASS] U14: 12 Mb/s Mass Storage (bInterfaceClass=8) is diagnosed Throttled (never HID peripheral); verified HID (class=3) gets HID peripheral / HID / 低速外设")

# ---------------------------------------------------------------------------
# Row 5 & Row 6: Zero keyword lists in Sources/ + Unverified README disclosures
# ---------------------------------------------------------------------------
kw_re = re.compile(r"t7|extreme pro|wooting|keychron|logitech|ajazz", flags=re.I)
for swift_file in (root / "Sources").rglob("*.swift"):
    m = kw_re.search(swift_file.read_text(encoding="utf-8"))
    assert m is None, f"Row 5 found forbidden product/brand keyword {m.group(0)!r} in {swift_file}"

if (root / ".git").exists():
    rc_g1, out_g1, _, _ = run_cmd(["git", "grep", "-n", "-i", "-E", "t7|extreme pro", "Sources/"], cwd=str(root))
    assert rc_g1 == 1 and out_g1 == "", f"Row 5 git grep t7|extreme pro matched:\n{out_g1}"
    rc_g2, out_g2, _, _ = run_cmd(["git", "grep", "-n", "-i", "-E", "wooting|keychron|logitech|ajazz", "Sources/"], cwd=str(root))
    assert rc_g2 == 1 and out_g2 == "", f"Row 5 git grep brand names matched:\n{out_g2}"

passed_checks += 1
print("[PASS] Row 5: Zero storage or peripheral keyword guesses in Sources/ (`t7|extreme pro` = 0, `wooting|keychron|logitech|ajazz` = 0)")

readme_en = (root / "README.md").read_text(encoding="utf-8")
readme_zh = (root / "README.zh-CN.md").read_text(encoding="utf-8")
spec_md = (root / "docs/SPEC.md").read_text(encoding="utf-8")

assert "SPUSBDataType" in readme_en and "Thunderbolt 5" in readme_en and "Unverified on real hardware" in readme_en
assert "SPUSBDataType" in readme_zh and "Thunderbolt 5" in readme_zh and "尚未在真机上验证" in readme_zh
assert "Unverified on real hardware" in spec_md and "尚未在真机上验证" in spec_md
passed_checks += 1
print("[PASS] Row 6: Legacy SPUSBDataType (macOS 14-15) and Thunderbolt 5 (80 Gb/s) explicitly marked Unverified / 尚未在真机上验证 in README.md, README.zh-CN.md, and docs/SPEC.md")

# ---------------------------------------------------------------------------
# W1: M1 Scripted Mutation Checks in an Isolated Temporary Copy
# ---------------------------------------------------------------------------
m1_mutations = [
    (
        "M1_bcdUSB (disable bcdUSB == 0x0210 SuperSpeed-on-USB2 capability check)",
        "Sources/BusLensMacCore/Diagnostics/BottleneckDiagnoser.swift",
        "if bcd == 0x0210 || bcd >= 0x0300 || capability.usb3PreferredOrRequired {",
        "if bcd == 0x9999 || bcd >= 0x0300 || capability.usb3PreferredOrRequired {",
        "DiagnoserTests/testM1SixteenSyntheticScenariosWithIORegistryDescriptors",
        "M1 Row 4: All 16 synthetic hardware scenarios",
    ),
    (
        "M2_U13_class9 (hide any USB device with _items regardless of bDeviceClass == 9)",
        "Sources/BusLensMacCore/Collectors/BusProfilerCollector.swift",
        "let isHubContainer = isBuiltIn || isExplicitUSBHubClass(item) || (mergedCap?.usbDeviceClass == 9)",
        "let isHubContainer = isBuiltIn || isExplicitUSBHubClass(item) || (mergedCap?.usbDeviceClass == 9) || !children.isEmpty",
        "CollectorTests/testU13NonHubClassDockWithChildRemainsVisible",
        "U13: Only USB Device Class 9",
    ),
    (
        "M3_U14_hidClass3 (blanket-label all <= 12 Mb/s devices as HID peripheral ignoring bInterfaceClass == 8)",
        "Sources/BusLensMacCore/Diagnostics/BottleneckDiagnoser.swift",
        "if let bcd = capability.bcdUSB {",
        'if negotiatedGbps <= usb1FullSpeedMaxGbps { return DeviceDiagnosticEvaluation(verdict: .lowSpeedPeripheral, detail: "HID") }\n        if let bcd = capability.bcdUSB {',
        "DiagnoserTests/testU14TwelveMbpsMassStorageIsNeverLabeledLowSpeedPeripheral",
        "U14: 12 Mb/s Mass Storage disk",
    ),
    (
        "M4_U5_portMapping (drop locationID -> AppleUSBHostPort physical port mapping)",
        "Sources/BusLensMacCore/Collectors/IORegistryCollector.swift",
        "    private static func extractPhysicalPortLabel(usbIOPort: String?, portNumber: Int?) -> String? {",
        "    private static func extractPhysicalPortLabel(usbIOPort: String?, portNumber: Int?) -> String? {\n        if usbIOPort != nil || portNumber != nil { return nil }",
        "CollectorTests/testM1Real20261115PairedFixtureAndPhysicalPortMapping",
        "M1 Items 1 & 3 (U5): Real 2026-11-15 Mac mini",
    ),
]

with tempfile.TemporaryDirectory(prefix="buslens-m1-mut-") as mut_root_raw:
    mut_repo = pathlib.Path(mut_root_raw) / "repo"
    mut_repo.mkdir(parents=True)
    shutil.copy2(root / "Package.swift", mut_repo / "Package.swift")
    shutil.copytree(root / "Sources", mut_repo / "Sources")
    shutil.copytree(root / "Tests", mut_repo / "Tests")

    mut_env = os.environ.copy()
    mut_env.pop("BUSLENS_BIN", None)

    for mut_id, rel_file, target_str, replacement_str, test_filter, display_prefix in m1_mutations:
        fpath = mut_repo / rel_file
        original_text = fpath.read_text(encoding="utf-8")
        assert target_str in original_text, f"M1 mutation {mut_id} target string not found in {rel_file}"
        fpath.write_text(original_text.replace(target_str, replacement_str, 1), encoding="utf-8")
        try:
            rc_m, out_m, err_m, dt_m = run_cmd(
                ["swift", "test", "--no-parallel", "--filter", test_filter],
                cwd=str(mut_repo),
                env=mut_env,
            )
            combined = out_m + "\n" + err_m
            assert rc_m != 0, f"M1 MUTATION SURVIVED: {mut_id} exited 0 for --filter {test_filter}"
            assert "Build complete!" in combined, f"M1 COMPILE FAILURE: {mut_id}:\n{combined}"
            assert "Test run started" in combined, f"M1 NO TEST RUN: {mut_id}:\n{combined}"
            expected_fail_marker = f'✘ Test "{display_prefix}'
            assert expected_fail_marker in combined, (
                f"M1 WRONG FAILURE: {mut_id} did not fail {expected_fail_marker!r}:\n{combined}"
            )
            passed_checks += 1
            print(f"[PASS] W1 {mut_id} -> compiled & killed by `{test_filter}` (rc={rc_m}, {dt_m/1000.0:.2f}s)")
        finally:
            fpath.write_text(original_text, encoding="utf-8")

    rc_clean, out_clean, err_clean, _ = run_cmd(
        ["swift", "test", "--no-parallel", "--filter", "DiagnoserTests/testM1SixteenSyntheticScenariosWithIORegistryDescriptors"],
        cwd=str(mut_repo),
        env=mut_env,
    )
    assert rc_clean == 0, f"Restored temp repo failed clean check:\n{out_clean}\n{err_clean}"

print(f"\nM1_SUMMARY: passed={passed_checks} failed=0 skipped={skipped_checks}")
print("=== M1 DIFFERENTIAL, CAPABILITY, U13/U14 & MUTATION GATE PASSED (2 REAL-CABLE ROWS SKIPPED: 没跑) ===")
PY
