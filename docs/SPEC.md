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
- **No fabricated ceilings or power defaults**: Missing controller ceilings and missing `SPPowerDataType` / `pmset` fields remain `nil` (`null` in JSON) and render as `Unknown` (`未知`).
- **Unverified hardware matrices**:
  - **macOS 14–15 legacy `SPUSBDataType` schema**: *Unverified on real hardware (synthetic fixtures only) / 尚未在真机上验证（仅合成样本测试）*.
  - **Thunderbolt 5 (`80 Gb/s` / `120 Gb/s`)**: *Unverified on real hardware (synthetic fixtures only) / 尚未在真机上验证（仅合成样本测试）*.
  - **Real-hardware charging-only cable & external USB 2.0 hub throttling captures**: *Unverified on real hardware (synthetic fixtures only) / 尚未在真机上验证（仅合成样本测试）*.

---

## 2. Non-Goals & Privacy Invariants

- **Zero Root Privileges & Read-Only Inspection**: Uses user-space read-only `/usr/sbin/system_profiler`, `/usr/sbin/ioreg -a -r -c AppleUSBHostPort -l`, `/usr/sbin/ioreg -a -r -c IOThunderboltSwitch -l`, and `/usr/bin/pmset -g` without `sudo`, DriverKit, or opening `IOUSBHostDevice` user clients.
- **Zero Network Access**: Offline pure-SwiftPM (`macOS 14.0+`, `arm64`) executable.
- **Zero Preferences Side Effects in Headless / Test Runs**: CLI invocations exit via `Darwin.exit` before `NSApplication` / AppKit starts; unit tests inject `InMemoryPreferenceStore` so `~/Library/Preferences` is never modified.
- **Automatic Hardware Identifier Redaction**: Serial numbers (`serial_num`, `device_serial`, `USBDeviceKeySerialNumber`, `kUSBSerialNumberString`, `USB Serial Number`) and UUIDs/UIDs (`domain_uuid_key`, `switch_uid_key`, `uid_key`, `kUSBContainerID`, `Device GUID`, `Switch UID`, `Domain UUID`) are scrubbed while preserving link speed and topology tags (`receptacle_upstream_ambiguous_tag`, `locationID`, `UsbIOPort`).

---

## 3. Data Collection & Five-State Verdicts

### 3.1 Collectors (`BusProfilerCollector.swift` & `IORegistryCollector.swift`)
1. **`SPThunderboltDataType` + `IOThunderboltSwitch`**:
   - Reads per-device `receptacle_upstream_ambiguous_tag.current_speed_key` across direct and daisy-chained switches.
   - Maps host `Router ID` -> `IOThunderboltPort` `Socket ID` -> physical port (`Port-USB-C@N`) and decodes `Supported Link Speed` × `Supported Link Width` for host ceiling and attached switch max capability.
2. **`SPUSBHostDataType` / `SPUSBDataType` + `AppleUSBHostPort`**:
   - Resolves `locationID` to ancestor host `AppleUSBHostPort` (`UsbIOPort`, e.g. `Port-USB-C@6`), propagating `"UsbProtocolCompanion (3.x)"` SuperSpeed ceilings onto USB 2.0 companion ports sharing the same physical connector.
   - Filters only Apple built-in hubs (`Built-in` / `USBPortType` `1` or `2`) and explicit USB Hub Class (`bDeviceClass == 9`) containers (`U13`); composite (`0`) and Billboard (`17`) docks with downstream devices remain visible.
3. **`SPPowerDataType` + `pmset -g`**:
   - Extracts optional AC / Battery state, USB-C PD wattage, and Low Power Mode (`Unknown` / `未知` when absent).

### 3.2 Descriptor-Backed Verdicts (`BottleneckDiagnoser.swift`)
1. **`fullRate`** (`Full bus rate` / `满速`) — Negotiated speed meets explicit port ceiling or `>= 40 Gb/s` without falling below proven device max capability.
2. **`normal`** (`Normal` / `正常`) — Negotiated speed matches proven hardware capability (`0x0200` at `480 Mb/s`, `0x0300` at `5 Gb/s`, `0x0310` at `10 Gb/s`, or healthy `bDeviceClass == 17` Billboard).
3. **`lowSpeedPeripheral`** (`HID peripheral` / `HID / 低速外设`) — Verified USB HID (`class == 3`) at `1.5 Mb/s` or `12 Mb/s` (`U14`).
4. **`throttled`** (`Throttled` / `被限速`) — Proven device capability exceeds negotiated rate (e.g. BOS `bcdUSB == 0x0210` below `5 Gb/s`, `bcdUSB >= 0x0300` below `5 Gb/s`, or Thunderbolt switch capability > negotiated bandwidth), classified into `port` (`端口限速`), `hub` (`集线器限速`), or `cable` (`线缆限速`).
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
