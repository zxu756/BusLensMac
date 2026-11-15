# BusLensMac — Engineering Specification (`since v0.3.0` — M0)

## 1. Scope & Honesty Contract (M0)

USB-C ports and cables look identical on the outside regardless of whether a link negotiates `40 Gb/s` (Thunderbolt 4 / USB4), `20 Gb/s`, `10 Gb/s`, `5 Gb/s`, `480 Mb/s`, `12 Mb/s`, or `1.5 Mb/s`. Apple's built-in *System Information.app* splits Thunderbolt trees, USB host controllers, and AC / Power Delivery state across separate raw panels.

In **M0 (`since v0.3.0`)**, **BusLens Mac** provides a read-only GUI, menu-bar popover, and headless `--cli topology [--json]` inspector that lists attached Thunderbolt, USB4, and USB devices alongside the exact negotiated link speeds reported by `system_profiler`, with live `中文 / EN` switching.

### What M0 Does Not Claim
- **Zero name-based classification**: `system_profiler` reports a link's *current negotiated speed*, not a peripheral's maximum hardware capability or USB interface class. Until M1 reads per-device USB/Thunderbolt capability and class descriptors from `ioreg`, BusLens Mac never inspects product or vendor names to guess whether a device is storage, a hub, or a keyboard/mouse/UPS (for example, `"Groups Backup Drive"`, `"Hidden Disk"`, `"Wooting 60HE"`, or `"Hubble Backup Drive"`).
- **No fabricated or cross-bus controller ceilings**: When `system_profiler` omits an explicit `"Up to ..."` / `max_speed_key` ceiling on a specific controller or Thunderbolt bus, BusLens Mac sets `portCeilingGbps = nil` and displays `Unknown` (`未知`) rather than assuming `40 Gb/s` or `10 Gb/s` or copying an explicit ceiling from a sibling Thunderbolt bus.
- **No fabricated power defaults**: When `SPPowerDataType` and `pmset -g` do not report power source or Low Power Mode, `powerSource` and `lowPowerMode` remain `nil` (`null` in JSON) and render as `Unknown` (`未知`) rather than defaulting to `"AC Power"` or `false`.
- **Unverified hardware matrices**:
  - **macOS 14–15 legacy `SPUSBDataType` schema**: *Unverified on real hardware (synthetic fixtures only) / 尚未在真机上验证（仅合成样本测试）*.
  - **Thunderbolt 5 (`80 Gb/s` / `120 Gb/s`)**: *Unverified on real hardware (synthetic fixtures only) / 尚未在真机上验证（仅合成样本测试）*.
  - Real-hardware verification in M0 covers **macOS 27.0.1 (`26A434`) arm64** on Apple Silicon Mac mini (`SPThunderboltDataType`, `SPUSBHostDataType`, `SPPowerDataType`).

---

## 2. Non-Goals & Privacy Invariants

- **Zero Root Privileges**: Uses user-space `system_profiler SPThunderboltDataType SPUSBHostDataType SPUSBDataType SPPowerDataType -json` (with `pmset -g` fallback for Low Power Mode) without `sudo` or DriverKit entitlements.
- **Zero Network Access**: Offline pure-SwiftPM (`macOS 14.0+`, `arm64`) executable.
- **Zero Preferences Side Effects in Headless / Test Runs**: CLI invocations (`--cli`, `--help`, `--version`, `--export-screenshots`) use `AppLocalizer(fixedLanguage:)` and exit via `Darwin.exit` before `NSApplication` / AppKit starts; unit tests inject `InMemoryPreferenceStore` so `~/Library/Preferences` is never modified.
- **Automatic Hardware Identifier Redaction**: Device serial numbers (`serial_num`, `device_serial`, `USBDeviceKeySerialNumber`) and Thunderbolt UUIDs (`domain_uuid_key`, `switch_uid_key`, `uid_key`) are scrubbed at parse time while preserving non-identifying link tags such as `receptacle_upstream_ambiguous_tag` needed for per-device Thunderbolt negotiated speeds.

---

## 3. Data Collection & Three-State M0 Verdicts

### 3.1 Collectors (`BusProfilerCollector.swift`)
1. **`SPThunderboltDataType`**:
   - Reads bus-level `receptacle_*_tag` speeds and walks nested `_items` trees (including daisy-chained downstream devices), preferring each device's own `receptacle_upstream_ambiguous_tag.current_speed_key` over the upstream host receptacle speed.
   - Extracts explicit ceiling strictly per bus when `"Up to ..."` or `max_speed_key` is present on that bus (`nil` / `Unknown` otherwise; never copied across sibling buses).
2. **`SPUSBHostDataType` (macOS 26–27+) & Legacy `SPUSBDataType` (macOS 14–15 synthetic fallback)**:
   - Walks controller and hub `_items` trees.
   - Filters Apple's built-in internal root/companion hubs strictly via `USBKeyHardwareType == "Built-in"` or `Built-in_Device == "Yes"`.
   - Identifies external USB hub containers structurally via child `_items` or explicit USB hub device class (`9` / `0x09`), never by substring `"hub"` in product names, so leaf peripherals whose product names contain `"hub"` remain visible.
   - Labels USB host controllers by hardware location ID (e.g., `(0x02000000)`) when available instead of sequential `#1` numbering.
3. **`SPPowerDataType` + `pmset -g`**:
   - Extracts optional AC / Battery state (`powerSource: String?`), USB-C PD negotiated wattage (`wattage: Int?`), and optional Low Power Mode (`lowPowerMode: Bool?`), reporting `Unknown` / `未知` whenever power telemetry is absent.

### 3.2 Honest M0 Verdicts (`BottleneckDiagnoser.swift`)
Every attached device receives one of three factual verdicts without inspecting device or vendor names:
1. **`fullRate`** (`Full bus rate` / `满速`) — Negotiated speed meets or exceeds an explicit controller ceiling (`>= ceiling`), or operates at `>= 40 Gb/s` Thunderbolt / USB4 link rate when ceiling is unreported.
2. **`lowSpeedPeripheral`** (`Low-speed peripheral` / `低速外设（USB 1.x）`) — USB 1.x link operating at `1.5 Mb/s` or `12 Mb/s` (`<= 0.0125 Gbps`), classified strictly from negotiated link speed.
3. **`indeterminate`** (`Indeterminate` / `无法判断是否被限速`) — Reports `"Negotiated at X; cannot determine if cable/hub-limited without device max capability."` (`"实际速率 X，无法判断是否被限速。"`). All `480 Mb/s` (USB 2.0) and `5 Gb/s` / `10 Gb/s` / `20 Gb/s` links below an explicit ceiling receive `indeterminate` in M0.

---

## 4. Planned Roadmap (Out of M0 Scope)

- **Planned (M1)**: Read per-device hardware capability descriptors (`bcdUSB`, SuperSpeed USB Device Capability BOS descriptors, USB device/interface class descriptors, and Thunderbolt link capability registers) from `ioreg` to compare actual device maximum capability against negotiated speed, enabling evidence-backed `--cli bottlenecks`.
- **Planned (M2)**: Live hot-plug stream (`IOKit` notification port) and historical link-drop counter.

---

## 5. Targets & Verification Gates

- `BusLensMacCore` (Swift library): Models, `BusProfilerCollector`, `BottleneckDiagnoser`, `BusCLIRunner`, `AppLocalizer`, SwiftUI views, and `[DEMO]` screenshot exporter.
- `BusLensMac` (Executable): `BusLensMain.swift` (`@main`) intercepts CLI flags strictly before SwiftUI `App.main()` initializes AppKit.
- `Scripts/test.sh`:
  - `./Scripts/test.sh scope <Diagnoser|Collector|CLI>` — fast scoped unit tests.
  - `./Scripts/test.sh milestone 0 [--record]` — scoped suites + `Scripts/acceptance/m0-acceptance.sh` + `Scripts/acceptance/readme-commands.sh` (writes scrubbed `reports/*.txt` only when `--record` is passed).
  - `./Scripts/test.sh release` — full test suite, app bundle build, scrubbed acceptance reports (`reports/m0-acceptance.txt`, `reports/readme-commands.txt`), and `rea-build-guard` audit.
