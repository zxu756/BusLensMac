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

echo "=== BusLens Mac M0 Acceptance Gate ==="
echo "Date (UTC): $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "Host: $(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion)) $(uname -m)"
echo "Binary: $DISPLAY_BIN"
echo ""

python3 - "$ROOT" "$BIN" <<'PY'
from __future__ import annotations
import hashlib
import json
import os
import pathlib
import plistlib
import re
import shutil
import statistics
import subprocess
import sys
import tempfile
import time

root = pathlib.Path(sys.argv[1])
bin_path = sys.argv[2]
host_fixture = root / "Tests/BusLensMacTests/Fixtures/host_macmini_scrubbed.json"

def run_cmd(args, cwd=None, env=None):
    t0 = time.perf_counter()
    proc = subprocess.run(args, cwd=cwd, env=env, capture_output=True, text=True)
    dt_ms = (time.perf_counter() - t0) * 1000.0
    return proc.returncode, proc.stdout, proc.stderr, dt_ms

def snapshot_preferences(prefs_dir: pathlib.Path) -> tuple[int, str, dict[str, str]]:
    if not prefs_dir.exists():
        return 0, hashlib.sha256(b"missing").hexdigest(), {}
    entries = sorted(p for p in prefs_dir.iterdir() if p.is_file() or p.is_symlink())
    digest = hashlib.sha256()
    per_file: dict[str, str] = {}
    for p in entries:
        digest.update(p.name.encode("utf-8"))
        digest.update(b"\0")
        try:
            fh = hashlib.sha256(p.read_bytes()).hexdigest()
            digest.update(bytes.fromhex(fh))
            per_file[p.name] = fh
        except PermissionError:
            st = p.lstat()
            tag = f"perm:{st.st_size}:{st.st_mtime_ns}"
            digest.update(tag.encode("utf-8"))
            per_file[p.name] = tag
        except FileNotFoundError:
            continue
        digest.update(b"\n")
    return len(per_file), digest.hexdigest(), per_file

# Extract live serials/UUIDs from system_profiler & ioreg (read-only) to verify zero leakage
live_secrets = set()
try:
    sp_raw = subprocess.check_output([
        "/usr/sbin/system_profiler",
        "SPThunderboltDataType",
        "SPUSBHostDataType",
        "SPUSBDataType",
        "SPPowerDataType",
        "-json"
    ])
    sp_json = json.loads(sp_raw)
    def harvest_secrets(obj):
        if isinstance(obj, dict):
            for k, v in obj.items():
                kl = k.lower()
                if k in {"serial_num", "USBDeviceKeySerialNumber", "domain_uuid_key", "switch_uid_key", "kUSBSerialNumberString", "USB Serial Number", "Device GUID"} or "serial" in kl or "uuid" in kl or "uid_key" in kl or "switch uid" in kl:
                    if isinstance(v, str) and len(v.strip()) >= 4:
                        live_secrets.add(v.strip())
                else:
                    harvest_secrets(v)
        elif isinstance(obj, list):
            for item in obj:
                harvest_secrets(item)
    harvest_secrets(sp_json)
except Exception as exc:
    print(f"[WARN] Could not query live system_profiler secrets: {exc}")

# ---------------------------------------------------------------------------
# Row 1: 50 consecutive executions of `--cli topology --json` (< 5s each, rc=0)
# ---------------------------------------------------------------------------
durations_ms = []
for idx in range(50):
    lang = "en" if idx % 2 == 0 else "zh"
    rc, out, err, dt_ms = run_cmd([bin_path, "--cli", "topology", "--json", "--lang", lang])
    assert rc == 0, f"Row 1 run #{idx+1} ({lang}) failed with exit code {rc}: {err}"
    assert err == "", f"Row 1 run #{idx+1} ({lang}) wrote unexpected stderr: {err}"
    assert dt_ms < 5000.0, f"Row 1 run #{idx+1} ({lang}) exceeded 5s budget: {dt_ms:.1f} ms"
    parsed = json.loads(out)
    assert isinstance(parsed.get("devices"), list), f"Row 1 run #{idx+1} invalid devices array"
    assert parsed.get("isDemo") is False, "Row 1 live run must have isDemo=false"
    expected_lang = "en" if lang == "en" else "zh-Hans"
    assert parsed.get("language") == expected_lang, f"Row 1 expected language {expected_lang}, got {parsed.get('language')}"
    for secret in live_secrets:
        assert secret.lower() not in out.lower(), "Row 1 leaked hardware identifier in CLI JSON output"
    durations_ms.append(dt_ms)

print(
    f"[PASS] Row 1: 50x consecutive `--cli topology --json` (25 en + 25 zh): "
    f"all 50 exited 0 under 5.0s (min={min(durations_ms):.1f}ms, "
    f"median={statistics.median(durations_ms):.1f}ms, max={max(durations_ms):.1f}ms, "
    f"total={sum(durations_ms)/1000.0:.2f}s, 0 identifier leaks)"
)

# ---------------------------------------------------------------------------
# Row 2: `--cli bogus` exits with code 2 in both EN and ZH
# ---------------------------------------------------------------------------
for lang, expected_phrase in [
    ("en", "Unknown CLI subcommand 'bogus'"),
    ("zh", "未知命令行子命令 'bogus'"),
]:
    rc, out, err, _ = run_cmd([bin_path, "--cli", "bogus", "--lang", lang])
    assert rc == 2, f"Row 2 ({lang}) expected exit code 2, got {rc}"
    assert out == "", f"Row 2 ({lang}) expected empty stdout, got: {out!r}"
    assert expected_phrase in err, f"Row 2 ({lang}) expected {expected_phrase!r} in stderr, got: {err!r}"

rc_def, out_def, err_def, _ = run_cmd([bin_path, "--cli", "bogus"])
assert rc_def == 2 and out_def == "" and "bogus" in err_def
print("[PASS] Row 2: `--cli bogus` (--lang en, --lang zh, default) exited with code 2, 0-byte stdout, localized stderr")

# ---------------------------------------------------------------------------
# Row 3 & Row 4 & Supplemental U9 / U10 / U11 / U12 Synthetic Fixtures
# ---------------------------------------------------------------------------
with tempfile.TemporaryDirectory() as tmpdir:
    tmp = pathlib.Path(tmpdir)
    t1_path = tmp / "t1_tb_dev_20G_on_40bus.json"
    t1_path.write_text(json.dumps({
        "SPThunderboltDataType": [{
            "_name": "thunderboltusb4_bus_0",
            "receptacle_1_tag": {
                "current_speed_key": "40 Gb/s",
                "receptacle_status_key": "receptacle_connected"
            },
            "_items": [{
                "_name": "OWC Envoy NVMe",
                "device_name_key": "OWC Envoy NVMe",
                "vendor_name_key": "Acme",
                "mode_key": "thunderbolt_three",
                "receptacle_upstream_ambiguous_tag": {
                    "current_speed_key": "20 Gb/s",
                    "receptacle_status_key": "receptacle_connected"
                }
            }]
        }]
    }), encoding="utf-8")

    t3_path = tmp / "t3_usb4_and_daisy.json"
    t3_path.write_text(json.dumps({
        "SPThunderboltDataType": [{
            "_name": "thunderboltusb4_bus_0",
            "receptacle_1_tag": {
                "current_speed_key": "40 Gb/s",
                "receptacle_status_key": "receptacle_connected"
            },
            "_items": [{
                "_name": "USB4 Hub NVMe",
                "device_name_key": "USB4 Hub NVMe",
                "vendor_name_key": "Acme",
                "mode_key": "usb4",
                "receptacle_upstream_ambiguous_tag": {
                    "current_speed_key": "40 Gb/s",
                    "receptacle_status_key": "receptacle_connected"
                },
                "_items": [{
                    "_name": "Samsung X5",
                    "device_name_key": "Samsung X5",
                    "vendor_name_key": "Acme",
                    "mode_key": "thunderbolt_three",
                    "receptacle_upstream_ambiguous_tag": {
                        "current_speed_key": "20 Gb/s",
                        "receptacle_status_key": "receptacle_connected"
                    }
                }]
            }]
        }]
    }), encoding="utf-8")

    for lang in ("en", "zh"):
        rc, out_j, err_j, _ = run_cmd([bin_path, "--cli", "topology", "--input", str(t1_path), "--json", "--lang", lang])
        assert rc == 0 and err_j == ""
        p = json.loads(out_j)
        assert len(p["devices"]) == 1
        dev = p["devices"][0]
        assert dev["negotiatedGbps"] == 20.0, f"Row 3 ({lang}) expected 20.0 Gbps, got {dev['negotiatedGbps']}"
        assert dev["negotiatedSpeedLabel"] == "20 Gb/s", f"Row 3 ({lang}) expected '20 Gb/s', got {dev['negotiatedSpeedLabel']}"
        assert dev["verdict"] == "indeterminate"

        rc_t, out_t, _, _ = run_cmd([bin_path, "--cli", "topology", "--input", str(t1_path), "--lang", lang])
        assert rc_t == 0 and "20 Gb/s" in out_t

        rc_d, out_d, _, _ = run_cmd([bin_path, "--cli", "topology", "--input", str(t3_path), "--json", "--lang", lang])
        assert rc_d == 0
        pd = json.loads(out_d)
        by_name = {d["name"]: d for d in pd["devices"]}
        assert by_name["USB4 Hub NVMe"]["negotiatedSpeedLabel"] == "40 Gb/s"
        assert by_name["Samsung X5"]["negotiatedSpeedLabel"] == "20 Gb/s"

    print("[PASS] Row 3: Synthetic TB device 20 Gb/s on 40 Gb/s bus (+ daisy-chain) reports '20 Gb/s' (not 40 Gb/s) in EN & ZH")

    # -----------------------------------------------------------------------
    # Row 4: Synthetic Samsung T7 at 10 Gb/s — NOT flagged throttled, no cable advice
    # -----------------------------------------------------------------------
    c6_path = tmp / "c6_t7_native10.json"
    c6_path.write_text(json.dumps({
        "SPUSBHostDataType": [{
            "_name": "USB 3.1 Bus",
            "_items": [
                {
                    "_name": "Portable SSD T7",
                    "USBDeviceKeyLinkSpeed": "10 Gb/s",
                    "USBDeviceKeyVendorName": "Samsung"
                },
                {
                    "_name": "Samsung T5",
                    "USBDeviceKeyLinkSpeed": "5 Gb/s",
                    "USBDeviceKeyVendorName": "Samsung"
                }
            ]
        }]
    }), encoding="utf-8")

    for lang, expected_ceiling, expected_phrase in [
        ("en", "Unknown", "Negotiated at 10 Gb/s; cannot determine if cable/hub-limited without device max capability."),
        ("zh", "未知", "实际速率 10 Gb/s，无法判断是否被限速。"),
    ]:
        rc_j, out_j, err_j, _ = run_cmd([bin_path, "--cli", "topology", "--input", str(c6_path), "--json", "--lang", lang])
        assert rc_j == 0 and err_j == ""
        pj = json.loads(out_j)
        t7 = next(d for d in pj["devices"] if d["name"] == "Portable SSD T7")
        assert t7["negotiatedSpeedLabel"] == "10 Gb/s"
        assert t7["portCeilingGbps"] is None
        assert t7["portCeilingLabel"] == expected_ceiling
        assert t7["verdict"] == "indeterminate"
        assert t7["diagnosticDetail"] == expected_phrase
        assert t7["bottleneckSegment"] is None and t7["bottleneckSegmentLabel"] is None

        rc_t, out_t, _, _ = run_cmd([bin_path, "--cli", "topology", "--input", str(c6_path), "--lang", lang])
        assert rc_t == 0
        t7_json_values = " ".join(
            str(v) for v in (
                pj.get("headline", ""),
                t7.get("verdict", ""),
                t7.get("verdictLabel", ""),
                t7.get("diagnosticDetail", ""),
                t7.get("portCeilingLabel", ""),
            )
        )
        for forbidden in ("40 Gb/s", "replace", "bottleneck", "WARN", "更换", "瓶颈"):
            assert forbidden.lower() not in out_t.lower(), f"Row 4 ({lang}) found forbidden token {forbidden!r} in {out_t!r}"
            assert forbidden.lower() not in t7_json_values.lower(), f"Row 4 ({lang} json) found forbidden token {forbidden!r} in {t7_json_values!r}"

    print("[PASS] Row 4: Synthetic Samsung T7 at 10 Gb/s is indeterminate (ceiling Unknown/未知), never flagged throttled or told to replace cable in EN & ZH")

    # -----------------------------------------------------------------------
    # Supplemental U9 & U14: 480 Mb/s & unclassified 12 Mb/s -> Indeterminate; verified HID class 3 -> HID peripheral
    # -----------------------------------------------------------------------
    u9_path = tmp / "u9_no_name_guessing.json"
    u9_ioreg_path = tmp / "u9_no_name_guessing_ioreg.plist"
    u9_path.write_text(json.dumps({
        "SPUSBDataType": [{
            "_name": "USB 3.1 Bus",
            "_items": [
                {"_name": "Groups Backup Drive", "manufacturer": "Acme Storage", "device_speed": "high_speed"},
                {"_name": "Hidden Disk", "manufacturer": "Acme Storage", "device_speed": "high_speed"},
                {"_name": "Wooting 60HE", "manufacturer": "Wooting", "device_speed": "high_speed"},
                {"_name": "Unclassified 12M Disk", "manufacturer": "Acme Storage", "device_speed": "full_speed"},
                {"_name": "USB 1.0 HID Device", "location_id": "0x01150000", "manufacturer": "Generic", "device_speed": "low_speed"},
                {"_name": "USB 1.1 HID Receiver", "location_id": "0x01160000", "manufacturer": "Generic", "device_speed": "full_speed"}
            ]
        }]
    }), encoding="utf-8")
    u9_ioreg_path.write_bytes(plistlib.dumps({
        "AppleUSBHostPort": [{
            "IOObjectClass": "AppleUSB20XHCIPort",
            "locationID": 0x01100000,
            "IORegistryEntryChildren": [
                {"IOObjectClass": "IOUSBHostDevice", "locationID": 0x01150000, "IORegistryEntryChildren": [{"IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 3}]},
                {"IOObjectClass": "IOUSBHostDevice", "locationID": 0x01160000, "IORegistryEntryChildren": [{"IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 3}]},
            ],
        }]
    }, fmt=plistlib.FMT_XML))

    for lang, exp_indet_lbl, exp_low_lbl in [
        ("en", "Indeterminate", "HID peripheral"),
        ("zh", "无法判断是否被限速", "HID / 低速外设"),
    ]:
        rc_j, out_j, err_j, _ = run_cmd([bin_path, "--cli", "topology", "--input", str(u9_path), "--ioreg-input", str(u9_ioreg_path), "--json", "--lang", lang])
        assert rc_j == 0 and err_j == ""
        pj = json.loads(out_j)
        by_name = {d["name"]: d for d in pj["devices"]}
        for dev_name in ("Groups Backup Drive", "Hidden Disk", "Wooting 60HE", "Unclassified 12M Disk"):
            assert by_name[dev_name]["verdict"] == "indeterminate", f"U9 ({lang}) {dev_name} misclassified: {by_name[dev_name]}"
            assert by_name[dev_name]["verdictLabel"] == exp_indet_lbl
        for dev_name in ("USB 1.0 HID Device", "USB 1.1 HID Receiver"):
            assert by_name[dev_name]["verdict"] == "low_speed_peripheral"
            assert by_name[dev_name]["verdictLabel"] == exp_low_lbl

    # Verify zero keyboard/mouse brand substrings in Sources/
    brand_re = re.compile(r"wooting|keychron|logitech|ajazz", flags=re.I)
    for swift_file in (root / "Sources").rglob("*.swift"):
        m = brand_re.search(swift_file.read_text(encoding="utf-8"))
        assert m is None, f"U9 found brand keyword {m.group(0)!r} in {swift_file}"

    print("[PASS] U9: 480 Mb/s & unclassified 12 Mb/s -> Indeterminate / 无法判断是否被限速; only verified HID class 3 (1.5/12 Mb/s) -> HID peripheral; 0 brand hints in Sources/")

    # -----------------------------------------------------------------------
    # Supplemental U10: 480 Mb/s "Hubble Backup Drive" preserved in device list
    # -----------------------------------------------------------------------
    u10_path = tmp / "u10_hubble_drive.json"
    u10_path.write_text(json.dumps({
        "SPUSBDataType": [{
            "_name": "USB 3.1 Bus",
            "_items": [
                {"_name": "Hubble Backup Drive", "manufacturer": "Acme Storage", "device_speed": "high_speed"}
            ]
        }]
    }), encoding="utf-8")

    for lang in ("en", "zh"):
        rc_j, out_j, err_j, _ = run_cmd([bin_path, "--cli", "topology", "--input", str(u10_path), "--json", "--lang", lang])
        assert rc_j == 0 and err_j == ""
        pj = json.loads(out_j)
        assert len(pj["devices"]) == 1 and pj["devices"][0]["name"] == "Hubble Backup Drive"
        assert pj["devices"][0]["verdict"] == "indeterminate"
        rc_t, out_t, _, _ = run_cmd([bin_path, "--cli", "topology", "--input", str(u10_path), "--lang", lang])
        assert rc_t == 0 and "Hubble Backup Drive" in out_t

    print("[PASS] U10: 480 Mb/s leaf 'Hubble Backup Drive' preserved in CLI JSON and text output (never hidden by 'hub' substring)")

    # -----------------------------------------------------------------------
    # Supplemental U11: Sibling TB bus without speed reports Unknown / 未知
    # -----------------------------------------------------------------------
    u11_path = tmp / "u11_sibling_tb.json"
    u11_path.write_text(json.dumps({
        "SPThunderboltDataType": [
            {
                "_name": "thunderboltusb4_bus_0",
                "vendor_name_key": "Apple Inc.",
                "device_name_key": "Mac mini",
                "receptacle_1_tag": {
                    "current_speed_key": "Up to 40 Gb/s",
                    "receptacle_status_key": "receptacle_no_devices_connected"
                }
            },
            {
                "_name": "thunderboltusb4_bus_1",
                "vendor_name_key": "Apple Inc.",
                "device_name_key": "Mac mini",
                "receptacle_1_tag": {
                    "receptacle_status_key": "receptacle_no_devices_connected"
                }
            }
        ]
    }), encoding="utf-8")

    for lang, exp_unknown in [("en", "Unknown"), ("zh", "未知")]:
        rc_j, out_j, err_j, _ = run_cmd([bin_path, "--cli", "topology", "--input", str(u11_path), "--json", "--lang", lang])
        assert rc_j == 0 and err_j == ""
        pj = json.loads(out_j)
        ctrls = {c["id"]: c for c in pj["controllers"]}
        assert ctrls["tb::thunderboltusb4_bus_0"]["ceilingGbps"] == 40.0
        assert ctrls["tb::thunderboltusb4_bus_1"]["ceilingGbps"] is None
        assert ctrls["tb::thunderboltusb4_bus_1"]["ceilingLabel"] == exp_unknown

    print("[PASS] U11: Sibling Thunderbolt bus omitting speed reports ceilingGbps=null / Unknown / 未知 (no cross-bus ceiling copy)")

    # -----------------------------------------------------------------------
    # Supplemental U12: Missing SPPowerDataType reports Unknown / 未知
    # -----------------------------------------------------------------------
    u12_path = tmp / "u12_empty_power.json"
    u12_path.write_text(json.dumps({"SPPowerDataType": []}), encoding="utf-8")

    for lang, exp_unknown, exp_line in [
        ("en", "Unknown", "Power: Unknown (Low Power Mode: Unknown)"),
        ("zh", "未知", "供电状态：未知（低电量模式：未知）"),
    ]:
        rc_j, out_j, err_j, _ = run_cmd([bin_path, "--cli", "topology", "--input", str(u12_path), "--json", "--lang", lang])
        assert rc_j == 0 and err_j == ""
        pj = json.loads(out_j)
        assert pj["power"]["powerSource"] is None
        assert pj["power"]["lowPowerMode"] is None
        assert pj["power"]["localizedBadge"] == exp_unknown
        assert pj["power"]["lowPowerModeLabel"] == exp_unknown
        rc_t, out_t, _, _ = run_cmd([bin_path, "--cli", "topology", "--input", str(u12_path), "--lang", lang])
        assert rc_t == 0 and exp_line in out_t

    print("[PASS] U12: Missing SPPowerDataType reports powerSource=null, lowPowerMode=null, and Unknown / 未知 in EN & ZH")

# ---------------------------------------------------------------------------
# Row 5: Scrubbed real host fixture (3 devices, speeds match fixture, 0 leaks)
# ---------------------------------------------------------------------------
assert host_fixture.is_file(), f"Row 5 missing host fixture at {host_fixture}"
fixture_text = host_fixture.read_text(encoding="utf-8")
for secret in live_secrets:
    assert secret.lower() not in fixture_text.lower(), "Row 5 host_macmini_scrubbed.json contains live hardware identifier!"

expected_devices = {
    "TBU405Pro": ("40 Gb/s", "full_rate", None, False),
    "Wooting 60HE v2": ("480 Mb/s", "indeterminate", None, False),
    "AJAZZ AJ159 APEX": ("12 Mb/s", "indeterminate", None, False),
}

for lang in ("en", "zh"):
    rc_j, out_j, err_j, _ = run_cmd([bin_path, "--cli", "topology", "--input", str(host_fixture), "--json", "--lang", lang])
    assert rc_j == 0 and err_j == ""
    pj = json.loads(out_j)
    assert len(pj["devices"]) == 3, f"Row 5 ({lang}) expected 3 devices, got {len(pj['devices'])}"
    got = {d["name"]: d for d in pj["devices"]}
    for dev_name, (exp_speed, exp_verdict, exp_ceil, exp_hub) in expected_devices.items():
        assert dev_name in got, f"Row 5 ({lang}) missing device {dev_name}"
        d = got[dev_name]
        assert d["negotiatedSpeedLabel"] == exp_speed, f"Row 5 ({lang}) {dev_name} speed {d['negotiatedSpeedLabel']} != {exp_speed}"
        assert d["verdict"] == exp_verdict, f"Row 5 ({lang}) {dev_name} verdict {d['verdict']} != {exp_verdict}"
        assert d["portCeilingGbps"] == exp_ceil, f"Row 5 ({lang}) {dev_name} ceiling {d['portCeilingGbps']} != {exp_ceil}"
        assert d["behindExternalHub"] is exp_hub, f"Row 5 ({lang}) {dev_name} behindExternalHub != {exp_hub}"
        assert d["depth"] == 0, f"Row 5 ({lang}) {dev_name} depth {d['depth']} != 0"

    rc_t, out_t, _, _ = run_cmd([bin_path, "--cli", "topology", "--input", str(host_fixture), "--lang", lang])
    assert rc_t == 0
    if lang == "en":
        assert "[Full bus rate" in out_t
        assert "[Indeterminate" in out_t
    else:
        assert "满速" in out_t
        assert "无法判断是否被限速" in out_t

# Verify Sources/ contains zero storage keyword guesses and preserves receptacle_upstream_ambiguous_tag
for swift_file in (root / "Sources").rglob("*.swift"):
    src = swift_file.read_text(encoding="utf-8").lower()
    for banned in ('"t7"', '"extreme pro"', 'replace charge-only', '"receptacle_upstream_ambiguous_tag"'):
        if swift_file.name == "BusProfilerCollector.swift" and banned == '"receptacle_upstream_ambiguous_tag"':
            redacted_match = re.search(r"redactedkeys.*?\]", src, flags=re.S)
            assert redacted_match and "receptacle_upstream_ambiguous_tag" not in redacted_match.group(0)
        else:
            assert banned not in src, f"Banned token {banned} found in {swift_file}"

print("[PASS] Row 5: Real scrubbed fixture `host_macmini_scrubbed.json` parsed 3 devices (40 Gb/s full_rate, 480 Mb/s indeterminate, 12 Mb/s indeterminate without ioreg), 0 internal-hub false positives, 0 identifier leaks")

# ---------------------------------------------------------------------------
# Row 6: `swift test --no-parallel` leaves ~/Library/Preferences count & sha256 identical
# ---------------------------------------------------------------------------
prefs_dir = pathlib.Path.home() / "Library/Preferences"
matched_prefs = False
for attempt in range(1, 4):
    before_count, before_sha, before_map = snapshot_preferences(prefs_dir)
    st = subprocess.run(["swift", "test", "--no-parallel"], cwd=str(root), capture_output=True, text=True)
    assert st.returncode == 0, f"Row 6 `swift test --no-parallel` failed:\n{st.stdout}\n{st.stderr}"
    after_count, after_sha, after_map = snapshot_preferences(prefs_dir)

    before_buslens = {k: v for k, v in before_map.items() if "buslens" in k.lower()}
    after_buslens = {k: v for k, v in after_map.items() if "buslens" in k.lower()}
    assert before_buslens == after_buslens, (
        f"Row 6 `swift test` mutated BusLens Preferences files: before={before_buslens}, after={after_buslens}"
    )

    if before_count == after_count and before_sha == after_sha:
        matched_prefs = True
        break

    diff_names = sorted(
        (set(before_map) ^ set(after_map))
        | {k for k in (set(before_map) & set(after_map)) if before_map[k] != after_map[k]}
    )
    # Only retry if an unrelated macOS system daemon (com.apple.* / ContextStoreAgent.plist) flushed concurrently
    if not all(n.startswith("com.apple.") or n == "ContextStoreAgent.plist" for n in diff_names):
        raise AssertionError(
            f"Row 6 `swift test` mutated ~/Library/Preferences ({diff_names}): "
            f"before=({before_count}, {before_sha[:12]}), after=({after_count}, {after_sha[:12]})"
        )

assert matched_prefs, (
    f"Row 6 could not observe a quiet ~/Library/Preferences window across 3 runs; last diff={diff_names}"
)

print(f"[PASS] Row 6: `swift test --no-parallel` passed with 0 changes to ~/Library/Preferences (files={after_count}, sha256={after_sha[:12]}... identical)")

# ---------------------------------------------------------------------------
# W1: Scripted Mutation Checks in an Isolated Temporary Copy
# ---------------------------------------------------------------------------
mutations = [
    (
        "M1 (U1: redact receptacle_upstream_ambiguous_tag)",
        "Sources/BusLensMacCore/Collectors/BusProfilerCollector.swift",
        '"switch_uid_key"',
        '"switch_uid_key",\n        "receptacle_upstream_ambiguous_tag"',
        "CollectorTests/testThunderboltPerDeviceSpeedPreservedOn40GbpsBus",
        "U1 / Row 3: Preserves receptacle_upstream_ambiguous_tag",
    ),
    (
        "M2 (U2: blame cable with 40 Gb/s advice on Indeterminate)",
        "Sources/BusLensMacCore/Diagnostics/BottleneckDiagnoser.swift",
        '        guard let capability else {\n            return DeviceDiagnosticEvaluation(\n                verdict: .indeterminate,\n                detail: "Negotiated at \\(rateLabel); cannot determine if cable/hub-limited without device max capability."',
        '        guard let capability else {\n            return DeviceDiagnosticEvaluation(\n                verdict: .throttled,\n                detail: "Negotiated at \\(rateLabel); bottleneck detected — replace cable with 40 Gb/s lead."',
        "DiagnoserTests/testSamsungT7Native10GbpsNotFlaggedAsBottleneck",
        "U2 / Row 4: Samsung T7 at 10 Gb/s",
    ),
    (
        "M3 (U3: fabricate 10 Gb/s USB controller ceiling when missing)",
        "Sources/BusLensMacCore/Collectors/BusProfilerCollector.swift",
        "private static func explicitUSBControllerCeilingGbps(in usbBus: [String: Any]) -> Double? {",
        "private static func explicitUSBControllerCeilingGbps(in usbBus: [String: Any]) -> Double? {\n        if !usbBus.isEmpty { return 10.0 }",
        "CollectorTests/testUnknownBusCeilingsAreNotFabricated",
        "U3: Unknown Thunderbolt and USB bus ceilings",
    ),
    (
        "M4 (U5: disable Apple Built-in USB hub recognition)",
        "Sources/BusLensMacCore/Collectors/BusProfilerCollector.swift",
        "private static func isBuiltInUSBNode(_ item: [String: Any]) -> Bool {",
        "private static func isBuiltInUSBNode(_ item: [String: Any]) -> Bool {\n        if !item.isEmpty { return false }",
        "CollectorTests/testRealHostMacMiniScrubbedFixtureAndInternalHubHandling",
        "U5 & Row 5: Scrubbed Mac mini host fixture",
    ),
    (
        "M5 (U6: return exitCode 0 instead of 2 on unknown CLI subcommand)",
        "Sources/BusLensMacCore/CLI/BusCLIRunner.swift",
        '        default:\n            return BusCLIExecutionResult(\n                exitCode: 2,',
        '        default:\n            return BusCLIExecutionResult(\n                exitCode: 0,',
        "CLITests/testUnknownSubcommandAndOptionsExitWithCode2",
        "U6 / Row 2: Unknown CLI subcommand",
    ),
    (
        "M6 (U8: drop string 'yes' from Low Power Mode boolean parser)",
        "Sources/BusLensMacCore/Collectors/BusProfilerCollector.swift",
        'case "1", "yes", "true", "on", "enabled":',
        'case "1", "true", "on", "enabled":',
        "CollectorTests/testLowPowerModeStringIntegerAndPmsetParsing",
        "U8: Low Power Mode accepts string",
    ),
    (
        "M7 (U9: reintroduce blanket speed-based lowSpeedPeripheral at <= 480 Mb/s)",
        "Sources/BusLensMacCore/Diagnostics/BottleneckDiagnoser.swift",
        "        guard let capability else {",
        '        if negotiatedGbps <= 0.48 { return DeviceDiagnosticEvaluation(verdict: .lowSpeedPeripheral, detail: "HID") }\n        guard let capability else {',
        "DiagnoserTests/testNoNameGuessingForBackupDrivesAndKeyboardsAt480Mbps",
        "U9: 480 Mb/s 'Groups Backup Drive'",
    ),
    (
        "M8 (U10: reintroduce name.contains('hub') hiding Hubble Backup Drive)",
        "Sources/BusLensMacCore/Collectors/BusProfilerCollector.swift",
        "let isHubContainer = isBuiltIn || (mergedCap?.usbDeviceClass == 9)",
        'let isHubContainer = isBuiltIn || (mergedCap?.usbDeviceClass == 9) || name.lowercased().contains("hub")',
        "CollectorTests/testHubbleBackupDriveNotHiddenByHubSubstring",
        "U10: Leaf USB devices containing 'hub'",
    ),
    (
        "M9 (U11: fabricate 40 Gb/s ceiling on sibling Thunderbolt bus omitting speed)",
        "Sources/BusLensMacCore/Collectors/BusProfilerCollector.swift",
        "let ceilingGbps = explicitReceptacleCeilingGbps(in: rec)",
        "let ceilingGbps = explicitReceptacleCeilingGbps(in: rec) ?? 40.0",
        "CollectorTests/testSiblingThunderboltBusDoesNotCopyCeiling",
        "U11: Sibling Thunderbolt bus omitting speed",
    ),
    (
        "M10 (U12: default missing power telemetry to AC Power & Low Power Mode false)",
        "Sources/BusLensMacCore/Collectors/BusProfilerCollector.swift",
        "return PowerDeliverySummary(powerSource: source, negotiatedWatts: watts, lowPowerMode: lowPower)",
        'return PowerDeliverySummary(powerSource: source ?? "AC Power", negotiatedWatts: watts, lowPowerMode: lowPower ?? false)',
        "CollectorTests/testMissingPowerTelemetryReportsUnknownNotACPowerOrFalse",
        "U12: Missing SPPowerDataType and empty pmset",
    ),
]

with tempfile.TemporaryDirectory(prefix="buslens-m0-mut-") as mut_root_raw:
    mut_root = pathlib.Path(mut_root_raw)
    mut_repo = mut_root / "repo"
    mut_repo.mkdir(parents=True)
    shutil.copy2(root / "Package.swift", mut_repo / "Package.swift")
    shutil.copytree(root / "Sources", mut_repo / "Sources")
    shutil.copytree(root / "Tests", mut_repo / "Tests")

    mut_env = os.environ.copy()
    mut_env.pop("BUSLENS_BIN", None)

    for mut_id, rel_file, target_str, replacement_str, test_filter, display_prefix in mutations:
        fpath = mut_repo / rel_file
        original_text = fpath.read_text(encoding="utf-8")
        assert target_str in original_text, f"W1 mutation {mut_id} target string not found in {rel_file}"
        fpath.write_text(original_text.replace(target_str, replacement_str, 1), encoding="utf-8")
        try:
            rc_m, out_m, err_m, dt_m = run_cmd(
                ["swift", "test", "--no-parallel", "--filter", test_filter],
                cwd=str(mut_repo),
                env=mut_env,
            )
            combined = out_m + "\n" + err_m
            assert rc_m != 0, f"W1 SURVIVED: {mut_id} exited 0 for --filter {test_filter}"
            assert "Build complete!" in combined, (
                f"W1 COMPILE FAILURE (invalid mutation kill): {mut_id} did not reach 'Build complete!':\n{combined}"
            )
            assert "Test run started" in combined, (
                f"W1 NO TEST RUN: {mut_id} did not start test runner:\n{combined}"
            )
            expected_fail_marker = f'✘ Test "{display_prefix}'
            assert expected_fail_marker in combined, (
                f"W1 WRONG FAILURE: {mut_id} did not fail target test {expected_fail_marker!r}:\n{combined}"
            )
            print(f"[PASS] W1 {mut_id} -> compiled & killed by `{test_filter}` (rc={rc_m}, {dt_m/1000.0:.2f}s)")
        finally:
            fpath.write_text(original_text, encoding="utf-8")

    # Verify restored isolated copy passes cleanly
    rc_clean, out_clean, err_clean, _ = run_cmd(
        ["swift", "test", "--no-parallel", "--filter", "DiagnoserTests/testNoNameGuessingForBackupDrivesAndKeyboardsAt480Mbps"],
        cwd=str(mut_repo),
        env=mut_env,
    )
    assert rc_clean == 0, f"W1 restored temp repo failed clean check:\n{out_clean}\n{err_clean}"

print(f"[PASS] W1: All {len(mutations)} scripted mutations compiled and were killed by named assertions in isolated temp workspace")
print("M0_SUMMARY: passed=20 failed=0 skipped=0")
print("\n=== ALL 6 M0 ACCEPTANCE ROWS + U9-U12 + W1 MUTATION CHECKS PASSED ===")
PY
