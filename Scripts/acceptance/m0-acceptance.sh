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

echo "=== BusLens Mac M0 Acceptance Gate ==="
echo "Date (UTC): $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "Host: $(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion)) $(uname -m)"
echo "Binary: $BIN"
echo ""

python3 - "$ROOT" "$BIN" <<'PY'
import glob
import json
import os
import pathlib
import re
import statistics
import subprocess
import sys
import tempfile
import time

root = pathlib.Path(sys.argv[1])
bin_path = sys.argv[2]
host_fixture = root / "Tests/BusLensMacTests/Fixtures/host_macmini_scrubbed.json"

def run_cmd(args):
    t0 = time.perf_counter()
    proc = subprocess.run(args, capture_output=True, text=True)
    dt_ms = (time.perf_counter() - t0) * 1000.0
    return proc.returncode, proc.stdout, proc.stderr, dt_ms

# Extract live serials/UUIDs from system_profiler (read-only) to verify zero leakage
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
                if k in {"serial_num", "device_serial", "USBDeviceKeySerialNumber", "domain_uuid_key", "switch_uid_key"} or "serial" in kl or "uuid" in kl or "uid_key" in kl:
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
        assert secret.lower() not in out.lower(), f"Row 1 leaked hardware identifier in CLI JSON output"
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
# Row 3: Synthetic TB device 20 Gb/s on 40 Gb/s bus (+ daisy-chain 20 Gb/s)
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

        rc_t, out_t, _, _ = run_cmd([bin_path, "--cli", "topology", "--input", str(c6_path), "--lang", lang])
        assert rc_t == 0
        for forbidden in ("40 Gb/s", "replace", "bottleneck", "WARN", "更换", "瓶颈"):
            assert forbidden.lower() not in out_t.lower(), f"Row 4 ({lang}) found forbidden token {forbidden!r} in {out_t!r}"
            assert forbidden.lower() not in out_j.lower(), f"Row 4 ({lang} json) found forbidden token {forbidden!r}"

    print("[PASS] Row 4: Synthetic Samsung T7 at 10 Gb/s is indeterminate (ceiling Unknown/未知), never flagged throttled or told to replace cable in EN & ZH")

# ---------------------------------------------------------------------------
# Row 5: Scrubbed real host fixture (3 devices, speeds match fixture, 0 leaks)
# ---------------------------------------------------------------------------
assert host_fixture.is_file(), f"Row 5 missing host fixture at {host_fixture}"
fixture_text = host_fixture.read_text(encoding="utf-8")
for secret in live_secrets:
    assert secret.lower() not in fixture_text.lower(), "Row 5 host_macmini_scrubbed.json contains live hardware identifier!"

fixture_obj = json.loads(fixture_text)
expected_devices = {
    "TBU405Pro": ("40 Gb/s", "full_rate", 40.0, False),
    "Wooting 60HE v2": ("480 Mb/s", "low_speed_peripheral", None, False),
    "AJAZZ AJ159 APEX": ("12 Mb/s", "low_speed_peripheral", None, False),
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
        assert "[HID / low-latency peripheral]" in out_t, "Row 5 EN truncated HID label!"
        assert "HID / low-latenc]" not in out_t
    else:
        assert "低速外设（正常）" in out_t

# Also verify Sources/ contains zero storage keyword guesses
for swift_file in (root / "Sources").rglob("*.swift"):
    src = swift_file.read_text(encoding="utf-8").lower()
    for banned in ('"t7"', '"extreme pro"', 'replace charge-only', '"receptacle_upstream_ambiguous_tag"'):
        if swift_file.name == "BusProfilerCollector.swift" and banned == '"receptacle_upstream_ambiguous_tag"':
            # Allowed in findFirstReceptacle / findDeviceReceptacle, forbidden in redactedKeys
            redacted_match = re.search(r"redactedkeys.*?\]", src, flags=re.S)
            assert redacted_match and "receptacle_upstream_ambiguous_tag" not in redacted_match.group(0)
        else:
            assert banned not in src, f"Banned token {banned} found in {swift_file}"

print("[PASS] Row 5: Real scrubbed fixture `host_macmini_scrubbed.json` parsed 3 devices (40 Gb/s, 480 Mb/s, 12 Mb/s) matching raw speeds, 0 internal-hub false positives, 0 identifier leaks")

# ---------------------------------------------------------------------------
# Row 6: `swift test` leaves zero new `BusLensMacTests.*` in ~/Library/Preferences
# ---------------------------------------------------------------------------
prefs_dir = pathlib.Path.home() / "Library/Preferences"
before_files = set(glob.glob(str(prefs_dir / "BusLensMacTests.*")))
before_app_plist_mtime = None
app_plist = prefs_dir / "local.xu.BusLensMac.plist"
if app_plist.exists():
    before_app_plist_mtime = app_plist.stat().st_mtime_ns

st = subprocess.run(["swift", "test", "--no-parallel"], cwd=str(root), capture_output=True, text=True)
assert st.returncode == 0, f"Row 6 `swift test --no-parallel` failed:\n{st.stdout}\n{st.stderr}"

after_files = set(glob.glob(str(prefs_dir / "BusLensMacTests.*")))
new_files = sorted(after_files - before_files)
assert len(new_files) == 0, f"Row 6 `swift test` created leftover Preferences files: {new_files}"
if before_app_plist_mtime is not None and app_plist.exists():
    assert app_plist.stat().st_mtime_ns == before_app_plist_mtime, "Row 6 `swift test` modified local.xu.BusLensMac.plist"
else:
    assert not app_plist.exists(), "Row 6 `swift test` created local.xu.BusLensMac.plist"

print(f"[PASS] Row 6: `swift test --no-parallel` passed with 0 new `BusLensMacTests.*` files in ~/Library/Preferences (before={len(before_files)}, after={len(after_files)}, added=0)")
print("\n=== ALL 6 M0 ACCEPTANCE ROWS PASSED ===")
PY
