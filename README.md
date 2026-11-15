# BusLens Mac

**English** | **[简体中文](README.zh-CN.md)**

**Native macOS utility that lists attached Thunderbolt, USB4, and USB devices and their negotiated link speeds from `system_profiler` — with a headless `--json` CLI and live `中文 / EN` bilingual switching.**

![BusLens Mac Bench (DEMO)](docs/screenshot-main.png)

> **`[DEMO]` Screenshot Notice:** Both screenshots on this page are rendered from `BusLensMonitor.preview()` synthetic demo data (`--export-screenshots`), **not** a live capture from a real Mac.

USB-C ports and cables look identical from the outside whether a link negotiates `40 Gb/s` (Thunderbolt 4 / USB4), `20 Gb/s`, `10 Gb/s`, `5 Gb/s`, `480 Mb/s`, `12 Mb/s`, or `1.5 Mb/s`. **BusLens Mac** consolidates `SPThunderboltDataType`, `SPUSBHostDataType` (plus legacy `SPUSBDataType` fallback), and `SPPowerDataType` into one read-only hardware bench window, menu bar popover, and scriptable CLI without requiring `sudo`.

## What It Does (`since v0.3.0` — M0)

> **Release Note:** The earlier tag `v0.2.0` predates the M0 honesty fixes below. Pre-AppKit CLI exit handling, `--json`, `--input`, `--demo`, `--help`, `--version`, `./Scripts/test.sh`, and the three-state non-guessing verdicts below are available **since v0.3.0**.

- **Per-Device Negotiated Link Speeds** — Reads each Thunderbolt / USB4 device's own upstream link speed (`receptacle_upstream_ambiguous_tag`, including daisy-chained devices) and each USB peripheral's `USBDeviceKeyLinkSpeed` so device rates are never overwritten by upstream host bus rates.
- **Honest Three-State Link Verdicts (Zero Name Guessing)** — `system_profiler` exposes negotiated link speed, not a peripheral's maximum hardware capability or USB interface class. In M0, BusLens Mac never inspects product or vendor names and reports only three factual verdicts:
  1. **`Full bus rate`** — Negotiated speed meets an explicitly reported controller ceiling or runs at `>= 40 Gb/s` Thunderbolt / USB4 rate.
  2. **`Low-speed peripheral`** — USB 1.x link negotiated at `1.5 Mb/s` or `12 Mb/s` (`<= 0.0125 Gbps`), classified strictly from negotiated link speed.
  3. **`Indeterminate`** — `"Negotiated at X; cannot determine if cable/hub-limited without device max capability."` Every `480 Mb/s` (USB 2.0) and `5 Gb/s` / `10 Gb/s` / `20 Gb/s` link below an explicit bus ceiling is reported as `Indeterminate` because `system_profiler` omits per-device max capability and device-class descriptors.
- **Explicit vs `Unknown` Ceilings, Structural Hub Handling & Power State** — Displays `Unknown` whenever `system_profiler` omits an explicit controller ceiling on that bus (never fabricated as `10 Gb/s` or `40 Gb/s` and never copied across sibling buses), displays `Unknown` when power source or Low Power Mode is absent from `SPPowerDataType` / `pmset`, filters Apple's internal motherboard hubs via `USBKeyHardwareType: Built-in` / `Built-in_Device: Yes`, and identifies external USB hub containers structurally via child `_items` or explicit USB hub class (`0x09`) rather than matching `"hub"` in product names.
- **Headless CLI & `--json` Output (`since v0.3.0`)** — Handles `--cli`, `--help`, `--version`, and `--export-screenshots` before AppKit / SwiftUI starts, exiting cleanly with `0` on success, `1` on runtime/input errors, and `2` on unknown subcommands or invalid flags.
- **Live `中文 / EN` Bilingual Switching & Identifier Redaction** — Switch languages live via the `中文 | EN` pill, `⇧⌘L`, or `--lang en|zh`, while device serial numbers and Thunderbolt UUIDs are scrubbed at parse time.

<p align="center">
  <img src="docs/screenshot-menubar.png" width="380" alt="BusLens Mac Menu Bar Popover (DEMO)" />
</p>
<p align="center"><em><code>[DEMO]</code> Synthetic preview topology rendered from <code>BusLensMonitor.preview()</code>.</em></p>

## Verification Status & Hardware Matrix

Measured on **2026-11-14** on Apple Silicon Mac mini running **macOS 27.0.1 (`26A434`) arm64** (raw log in [`reports/m0-acceptance.txt`](reports/m0-acceptance.txt)):

| Capability / Schema | Verification Status | Evidence |
|---|---|---|
| `SPThunderboltDataType` + `SPUSBHostDataType` + `SPPowerDataType` (macOS 27.0.1 arm64) | **Verified on real hardware** | Scrubbed live capture (`Tests/BusLensMacTests/Fixtures/host_macmini_scrubbed.json`: `40 Gb/s` USB4 enclosure, `480 Mb/s` USB 2.0 device, `12 Mb/s` USB 1.x receiver) + 50 consecutive `--cli topology --json` runs (< 0.9 s/run, 0 hangs, exit `0`). |
| Legacy `SPUSBDataType` schema (macOS 14–15) | **Unverified on real hardware (synthetic fixtures only)** | Tested via synthetic unit fixtures in `CollectorTests` (`Tests/BusLensMacCoreTests/CollectorTests.swift`). |
| Thunderbolt 5 (`80 Gb/s` / `120 Gb/s`) | **Unverified on real hardware (synthetic fixtures only)** | Speed parser tested with synthetic inputs only; not yet tested on Thunderbolt 5 Mac hardware. |

## Planned (Not in M0)

- **Planned (M1) — Per-Device Capability & Device-Class Probing via `ioreg`**: Read USB BOS / SuperSpeed capability descriptors, USB device/interface classes, and Thunderbolt link capability registers from `ioreg` to compare a device's hardware maximum rate against its negotiated link speed (and enable `--cli bottlenecks`).
- **Planned (M2) — Live IOKit Hot-Plug Stream**: Event-driven topology updates and historical link-retrain counters.

## Install

### Homebrew Cask (`v0.3.0` release)

```bash
brew install --cask zxu756/tap/buslens-mac
```

### Build from Source (macOS 14.0+, Apple Silicon)

> `./Scripts/test.sh` is available **since v0.3.0**.

```bash
git clone https://github.com/zxu756/BusLensMac.git
cd BusLensMac
./Scripts/test.sh scope Diagnoser Collector CLI
./Scripts/test.sh milestone 0
./Scripts/build-app.sh
open build/BusLensMac.app
```

To launch the GUI in a specific language (or inspect the synthetic `[DEMO]` topology in the window, `since v0.3.0`), pass `--lang en`, `--lang zh`, or `--demo` when invoking the app binary.

## CLI Usage

> **Availability:** `--cli topology`, `--lang en|zh`, and `--export-screenshots <dir>` exist in `v0.2.0`; `--json`, `--input <path>`, `--demo`, `--help` (`-h`), `--version` (`-v`), and pre-AppKit exit codes (`0` / `1` / `2`) are available **since v0.3.0**.

Every local CLI command below runs headlessly without launching a GUI window and is verified automatically by [`Scripts/acceptance/readme-commands.sh`](Scripts/acceptance/readme-commands.sh) (logged in [`reports/readme-commands.txt`](reports/readme-commands.txt)):

```bash
# Print live host bus and device negotiated speeds (English or Simplified Chinese)
build/BusLensMac.app/Contents/MacOS/BusLensMac --cli topology --lang en
build/BusLensMac.app/Contents/MacOS/BusLensMac --cli topology --lang zh

# Emit structured JSON topology output — since v0.3.0
build/BusLensMac.app/Contents/MacOS/BusLensMac --cli topology --json --lang en
build/BusLensMac.app/Contents/MacOS/BusLensMac --cli topology --json --lang zh

# Inspect a saved system_profiler -json file instead of querying the live host — since v0.3.0
build/BusLensMac.app/Contents/MacOS/BusLensMac --cli topology --input Tests/BusLensMacTests/Fixtures/host_macmini_scrubbed.json --lang en
build/BusLensMac.app/Contents/MacOS/BusLensMac --cli topology --input Tests/BusLensMacTests/Fixtures/host_macmini_scrubbed.json --lang zh

# Explicitly inspect built-in synthetic [DEMO] topology — since v0.3.0
build/BusLensMac.app/Contents/MacOS/BusLensMac --cli topology --demo --lang en
build/BusLensMac.app/Contents/MacOS/BusLensMac --cli topology --demo --lang zh

# Export 2x Retina [DEMO] screenshots to a scratch directory
build/BusLensMac.app/Contents/MacOS/BusLensMac --export-screenshots .build/demo-shots --lang en
build/BusLensMac.app/Contents/MacOS/BusLensMac --export-screenshots .build/demo-shots --lang zh

# Show CLI usage and version — since v0.3.0
build/BusLensMac.app/Contents/MacOS/BusLensMac --help --lang en
build/BusLensMac.app/Contents/MacOS/BusLensMac --help --lang zh
build/BusLensMac.app/Contents/MacOS/BusLensMac --version
```

## Architecture & Spec

See [docs/SPEC.md](docs/SPEC.md).

## License

MIT
