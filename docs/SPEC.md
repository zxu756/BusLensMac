# BusLensMac — Engineering Specification (`Unreleased (after v0.2.0)` — M0 & M1)

## 1. Scope & Honesty Contract (M0 & M1)

USB-C ports and cables look identical on the outside regardless of whether a link negotiates `40 Gb/s` (Thunderbolt 4 / USB4), `20 Gb/s`, `10 Gb/s`, `5 Gb/s`, `480 Mb/s`, `12 Mb/s`, or `1.5 Mb/s`. Apple's built-in *System Information.app* splits Thunderbolt trees, USB host controllers, and AC / Power Delivery state across separate panels without cross-referencing `ioreg` device capability descriptors or physical port tags.

In **M0 & M1 (`Unreleased (after v0.2.0)`)**, **BusLens Mac** provides a read-only GUI, menu-bar popover, and headless `--cli topology|bottlenecks [--json]` inspector that pairs `system_profiler` with `ioreg` (`AppleUSBHostPort` and `IOThunderboltSwitch`) to map physical ports and compare negotiated link speeds against hardware capability descriptors, with live `中文 / EN` switching.

### Honesty Boundaries & What Is Not Claimed
- **Zero name-based classification**: BusLens Mac never inspects product or vendor names to guess whether a device is storage, a hub, or an input peripheral.
- **Protocol-honest `Indeterminate` fallback**:
  - When `ioreg` descriptors are absent (e.g. offline `--input` without `--ioreg-input`), non-ceiling links report `Indeterminate` (`无法判断是否被限速`), and `--cli bottlenecks --input` without `--ioreg-input` exits `1`.
  - Per USB 2.0 §9.6.1, Full-Speed (`12 Mb/s`) devices legally report `bcdUSB = 0x0200`; unless USB class `3` proves HID, `bcdUSB = 0x0200` at `12 Mb/s` reports `Indeterminate`.
  - Per USB 3.2 §9.6.1, USB 3.2 Gen 1x1 (`5 Gb/s`) devices can report `bcdUSB = 0x0320`; because user-space `ioreg` does not expose SuperSpeedPlus sublink speed attributes, `bcdUSB = 0x0320` at `5 Gb/s` or `10 Gb/s` reports `Indeterminate`.
- **No fabricated ceilings, synthesized port labels, or power defaults**: Missing controller ceilings, missing `UsbIOPort` physical port labels, and missing `SPPowerDataType` / `pmset` fields remain `nil` (`null` in JSON) and render as `Unknown` (`未知`). When host port ceiling is unknown, bottleneck attribution reports `Cannot determine if cable or port` (`无法判断是线还是口`) instead of defaulting to cable.
- **Explicit `inferred` (`推断`) marker on inferred values and conclusions**: Any value or conclusion derived by inference rather than read directly (`bcdUSB` conclusions, USB Billboard class `17` auxiliary status, pure USB 2.0 / 1.x protocol-constant port ceilings, and Thunderbolt cable-limit attribution by elimination) carries an explicit `(inferred)` / `（推断）` marker across CLI text, `--json` (`isInferred: true`), menu bar, and dashboard outputs.
- **Real-hardware verification scope & unverified matrices**:
  - **Verified on real hardware**: Only external device enumeration count (`3` attached devices) and negotiated link speeds (`40 Gb/s`, `480 Mb/s`, `12 Mb/s`; `0` throttled devices) on `1` machine (Apple Silicon Mac mini, macOS 27.0.1 arm64).
  - **Link throttling & bottleneck segment judgment (`Throttled` / `bcdUSB` inference, charging-only cables & external USB 2.0 hub throttling)**: *Unverified on real hardware (synthetic fixtures only) / 未在真机验证（仅合成样本测试）*.
  - **macOS 14–15 legacy `SPUSBDataType` schema**: *Unverified on real hardware (synthetic fixtures only) / 尚未在真机上验证（仅合成样本测试）*.
  - **Retained legacy & AC charger keys (`location_id`, `vendor_id`, `Built-in_Device`, `device_speed`, `serial_num`, `sppower_ac_charger_watts`)**: *Key names sourced from public legacy-format samples (`Built-in_Device` from XML; JSON key name unconfirmed) or macOS built-in SystemProfiler string tables; not verified on the author's machine / 键名来自旧格式的公开样本或系统自带的字符串表，没有在作者的机器上验证*.
  - **Thunderbolt 5 (`80 Gb/s` / `120 Gb/s`)**: *Unverified on real hardware (synthetic fixtures only) / 尚未在真机上验证（仅合成样本测试）*.

---

## 2. Non-Goals & Privacy Invariants

- **Zero Root Privileges & Read-Only Inspection**: Uses user-space read-only `/usr/sbin/system_profiler`, `/usr/sbin/ioreg -a -r -c AppleUSBHostPort -l`, `/usr/sbin/ioreg -a -r -c IOThunderboltSwitch -l`, and `/usr/bin/pmset -g` without `sudo`, DriverKit, or opening `IOUSBHostDevice` user clients.
- **Zero Network Access**: Offline pure-SwiftPM (`macOS 14.0+`, `arm64`) executable.
- **Zero Preferences Side Effects in Headless / Test Runs**: CLI invocations exit via `Darwin.exit` before `NSApplication` / AppKit starts; unit tests inject `InMemoryPreferenceStore` so `~/Library/Preferences` is never modified.
- **Automatic Hardware Identifier Redaction**: Serial numbers (`serial_num`, `USBDeviceKeySerialNumber`, `kUSBSerialNumberString`, `USB Serial Number`) and UUIDs/UIDs (`domain_uuid_key`, `switch_uid_key`, `uid_key`, `kUSBContainerID`, `Device GUID`, `Switch UID`, `Domain UUID`) are scrubbed while preserving link speed and topology tags (`receptacle_upstream_ambiguous_tag`, `locationID`, `UsbIOPort`).

---

## 3. Data Collection & Five-State Verdicts

### 3.1 Collectors (`BusProfilerCollector.swift` & `IORegistryCollector.swift`)
1. **`SPThunderboltDataType` + `IOThunderboltSwitch`**:
   - Reads per-device `receptacle_upstream_ambiguous_tag.current_speed_key` across direct and daisy-chained switches.
   - Maps host `Router ID` -> `IOThunderboltPort` `Socket ID` -> physical port (`Port-USB-C@N`) and decodes `Supported Link Speed` × `Supported Link Width` for host ceiling and attached switch max capability.
2. **`SPUSBHostDataType` / `SPUSBDataType` + `AppleUSBHostPort`**:
   - Resolves `locationID` to ancestor host `AppleUSBHostPort` (`UsbIOPort`, e.g. `Port-USB-C@6`); missing `UsbIOPort` or missing explicit port ceiling remains `nil` (`Unknown` / `未知`).
   - Filters only Apple built-in hubs (`Built-in` / `USBPortType` `1` or `2`) and explicit USB Hub Class (`bDeviceClass == 9`) containers (`U13`); composite (`0`) and Billboard (`17`) docks with downstream devices remain visible.
3. **`SPPowerDataType` + `pmset -g`**:
   - Extracts optional AC / Battery state, USB-C PD wattage, and Low Power Mode (`Unknown` / `未知` when absent).

### 3.2 Descriptor-Backed Verdicts (`BottleneckDiagnoser.swift`)
1. **`fullRate`** (`Full bus rate` / `满速`) — Negotiated speed meets explicit port ceiling or `>= 40 Gb/s` without falling below proven device max capability.
2. **`normal`** (`Normal` / `正常`, or `Normal (inferred)` / `正常（推断）` when derived from `bcdUSB`) — Negotiated speed matches explicit hardware capability (healthy `bDeviceClass == 17` Billboard) or `bcdUSB`-inferred ceiling (`0x0200` at `480 Mb/s`, `0x0300` at `5 Gb/s`, `0x0310` at `10 Gb/s`).
3. **`lowSpeedPeripheral`** (`HID peripheral` / `HID / 低速外设`) — Verified USB HID (`class == 3`) at `1.5 Mb/s` or `12 Mb/s` (`U14`).
4. **`throttled`** (`Throttled` / `被限速`, or `Throttled (inferred)` / `被限速（推断）` when derived from `bcdUSB`) — Device capability exceeds negotiated rate (explicit Thunderbolt switch capability > negotiated bandwidth, or `bcdUSB == 0x0210` / `>= 0x0300` inferred SuperSpeed device below `5 Gb/s`), classified into `port` (`端口限速`), `hub` (`集线器限速`), `cable` (`线缆限速`), or `cable_or_port_indeterminate` (`无法判断是线还是口`) when host port ceiling is unknown.
5. **`indeterminate`** (`Indeterminate` / `无法判断是否被限速`) — Capability descriptors absent or USB specification ambiguous.

---

## 4. Planned Roadmap (M2)

- **Planned (M2)**: Short sequential read probe integration with `CrystalDiskMarkMac`, event-driven `IOKit` hot-plug speed history, and user-space USB-C e-marker cable investigation.

---

## 5. Targets & Verification Gates

- `./Scripts/test.sh scope <Diagnoser|Collector|CLI>` — fast scoped unit tests.
- `./Scripts/test.sh milestone 0 [--record]` — M0 honesty gate + README command replay.
- `./Scripts/test.sh milestone 1 [--record]` — M1 live `system_profiler` + `ioreg` differential gate (`Scripts/acceptance/m1-differential.sh`) + 16 synthetic scenarios + `U13`/`U14` + mutation checks + README command replay.
- `./Scripts/test.sh release` — full unit tests, `.app` build, M0 + M1 gates, README replay, and `rea-build-guard`.
