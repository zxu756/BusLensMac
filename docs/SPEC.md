# BusLensMac — Engineering Specification (`v0.1.0`)

## 1. Problem Statement & Hardware Suite Role
USB-C connectors look identical whether they carry **80 Gb/s Thunderbolt 5**, **40 Gb/s Thunderbolt 4 / USB4**, **10 Gb/s USB 3.2 Gen 2**, **480 Mb/s USB 2.0** (charging cable fallback!), or **USB Power Delivery**. Apple's built-in *System Information.app* buries Thunderbolt switch trees, USB host controllers, and USB-C PD wattage across three separate raw trees without highlighting when an external NVMe SSD or dock is silently running at **25% or 1.2% of its rated link speed** due to a passive cable or hub bottleneck.

**BusLensMac** completes the native macOS hardware diagnostic trilogy alongside `CrystalDiskInfoMac` (SMART health) and `CrystalDiskMarkMac` (sequential/random I/O throughput):
- `CrystalDiskMarkMac` tells you *your external SSD only hit 920 MB/s instead of 3,200 MB/s*.
- `BusLensMac` tells you *why*: Port 2 negotiated a `10 Gb/s` USB 3.2 fallback instead of a `40 Gb/s` USB4/Thunderbolt PCIe tunnel.

---

## 2. Non-Goals & Privacy Invariants
- **Zero Root Privileges**: Uses documented user-space macOS hardware introspection (`system_profiler SPThunderboltDataType SPUSBHostDataType SPUSBDataType SPPowerDataType -json`), supporting both macOS 14–15 (`SPUSBDataType`) and macOS 26–27+ (`SPUSBHostDataType` / `USBDeviceKeyLinkSpeed`) in `<1s` without `sudo` or DriverKit entitlements.
- **Zero Network Access**: 100% offline pure-SwiftPM (`macOS 14.0+`, `arm64`) binary.
- **Automatic Hardware Identifier Redaction**: Device `serial_num`, Thunderbolt `domain_uuid_key`, `switch_uid_key`, and host UUIDs are scrubbed at parse time and never displayed in UI screenshots, CLI exports, or logs.

---

## 3. Data Collection & Bottleneck Heuristics

### 3.1 Collectors (`BusProfilerCollector.swift`)
1. **`SPThunderboltDataType`**:
   - Extracts each Apple Silicon Thunderbolt / USB4 Bus (`_name`, `domain_uuid_key` redacted, receptacle tag, `receptacle_status_key`, connected `_items` devices with `device_name_key`, `vendor_name_key`, `mode_key`, and `current_speed_key` / `link_status_key`).
2. **`SPUSBDataType` + `ioreg` Link Speed Enrichment**:
   - Walks nested USB controller & hub `_items` trees, capturing ` _name`, `manufacturer`, `vendor_id`, `location_id`, `bus_power`, `bus_power_used`, and negotiated `host_controller` / `link_speed` (`Up to 480 Mb/sec`, `Up to 5 Gb/sec`, `Up to 10 Gb/sec`, `Up to 20 Gb/sec`, `Up to 40 Gb/sec`).
3. **`SPPowerDataType`**:
   - Extracts USB-C Power Delivery AC charger negotiated wattage (`sppower_ac_charger_watts`), connection state, and cable rating hints when running on MacBook models (or AC desktop supply status on Mac mini / Mac Studio / Mac Pro).

### 3.2 Bottleneck Diagnostic Engine (`BottleneckDiagnoser.swift`)
Classifies every attached device into one of four link health states:
- **`optimalTunnel` (Cobalt / Emerald)** — Negotiated at `>= 40 Gb/s` (`Thunderbolt 3/4/5` or `USB4` tunnel).
- **`cableOrHubBottleneck` (Coral / Amber Warning)** — Storage/dock/display class device (`SSD`, `NVMe`, `Enclosure`, `ASM2464`, `RTL9210`, `TBU`, `Dock`, `Hub`) negotiated at `<= 10 Gb/s` on a `40 Gb/s`-capable Mac, or any USB-C storage device trapped at `480 Mb/s` (charging-only USB 2.0 cable!).
- **`usb3SuperSpeed` (Cyan)** — Standard `5 Gb/s` or `10 Gb/s` peripheral operating at expected SuperSpeed rate (audio interfaces, capture cards, SD readers).
- **`hidFullOrHighSpeed` (Slate / Emerald)** — Keyboards, mice, 8K wireless receivers, audio DACs operating at `12 Mb/s` or `480 Mb/s` where USB 2.0 lanes are expected and optimal.

---

## 4. Architecture & Targets
- `BusLensMacCore` (Swift library):
  - `Models/BusModels.swift`
  - `Collectors/BusProfilerCollector.swift` (live `system_profiler` JSON parser + privacy redactor)
  - `Diagnostics/BottleneckDiagnoser.swift` (speed string parser `Mb/s` / `Gb/s` → ` Double` Gbps + cable/hub bottleneck rules)
  - `ViewModels/BusLensMonitor.swift` (`@MainActor` store + `.preview()` deterministic hardware bench dataset + `ScreenshotExporter`)
  - `Views/BusDashboardView.swift` & `Views/BusMenuBarView.swift`
- `BusLensMac` (Executable):
  - `@main` SwiftUI app (`Window` + `MenuBarExtra(.window)`)
  - Headless CLI flags: `--cli topology`, `--cli bottlenecks`, `--export-screenshots <dir>`
- `BusLensMacCoreTests` (Swift Testing suite):
  - `SPThunderboltDataType` + `SPUSBDataType` JSON parsing tests
  - Cable bottleneck detection tests (`40 Gb/s` Thunderbolt enclosure vs `10 Gb/s` USB-C cable vs `480 Mb/s` charging-cable trap)
  - Hardware serial & UUID redaction verification test
  - 2x Retina screenshot rendering test
