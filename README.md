# BusLens Mac (`v0.2.0`)

**English** | **[简体中文](README.zh-CN.md)**

**Native macOS Thunderbolt, USB4 & USB-C negotiated link-speed, cable bottleneck, and Power Delivery analyzer — with live `中文 / EN` bilingual switching.**

![BusLens Mac Bench](docs/screenshot-main.png)

Every USB-C cable looks identical from the outside—whether it negotiates an **80 Gb/s Thunderbolt 5** tunnel, a **40 Gb/s USB4 / Thunderbolt 4** link, a **10 Gb/s USB 3.2** fallback, or a **480 Mb/s USB 2.0** charging-cable trap that throttles a 3,200 MB/s NVMe SSD down to 38 MB/s.

**BusLens Mac** (`v0.2.0`) completes the native Apple Silicon storage & hardware diagnostic suite alongside [CrystalDiskInfoMac](https://github.com/zxu756/CrystalDiskInfoMac) (SMART health) and [CrystalDiskMarkMac](https://github.com/zxu756/CrystalDiskMarkMac) (disk I/O throughput).

## Highlights

- **Physical Port Receptacle Matrix** — Maps each Apple Silicon Thunderbolt / USB4 root bus and USB 3.1 host controller with live negotiated link speed vs controller ceiling.
- **Cable & Hub Bottleneck Detection** — Flags external NVMe enclosures, portable SSDs, and docks trapped at `480 Mb/s` (charging-only USB-C cable) or `10 Gb/s` (intermediate hub / non-USB4 cable) while recognizing that `480 Mb/s` is normal and optimal for low-latency HID keyboards and wireless receivers.
- **Live `中文 / EN` Bilingual Toggle (`v0.2.0`)** — Instant in-app Simplified Chinese / English switching from the `中文 | EN` pill in both the hardware bench window and menu bar popover, via `⇧⌘L`, or via `--lang zh|en` (auto-defaults to Simplified Chinese on `zh*` macOS locales).
- **Dual macOS 14–27+ Schema Support** — Parses both legacy `SPUSBDataType` (macOS 14–15) and modern `SPUSBHostDataType` (`USBDeviceKeyLinkSpeed`, macOS 26+) plus `SPThunderboltDataType` and `SPPowerDataType` with **zero root prompts**.
- **Privacy-First Hardware Scrubbing** — Automatically strips device serial numbers and Thunderbolt domain/switch UUIDs at parse time.

<p align="center">
  <img src="docs/screenshot-menubar.png" width="380" alt="BusLens Mac Menu Bar Popover" />
</p>

## Install (`v0.2.0`)

### Homebrew Cask

```bash
brew install --cask zxu756/tap/buslens-mac
```

### Build from Source (macOS 14.0+, Apple Silicon)

```bash
git clone https://github.com/zxu756/BusLensMac.git
cd BusLensMac
swift test --no-parallel
chmod +x Scripts/build-app.sh
./Scripts/build-app.sh
open build/BusLensMac.app
```

## CLI & Language Options

```bash
# Print full negotiated bus topology
build/BusLensMac.app/Contents/MacOS/BusLensMac --cli topology

# Exit-check only throttled cables / hub bottlenecks
build/BusLensMac.app/Contents/MacOS/BusLensMac --cli bottlenecks

# Launch GUI in Simplified Chinese or English explicitly
build/BusLensMac.app/Contents/MacOS/BusLensMac --lang zh
build/BusLensMac.app/Contents/MacOS/BusLensMac --lang en

# Export 2x Retina marketing screenshots (English + Simplified Chinese)
build/BusLensMac.app/Contents/MacOS/BusLensMac --export-screenshots docs --lang en
build/BusLensMac.app/Contents/MacOS/BusLensMac --export-screenshots docs --lang zh
```

## Architecture & Spec

See [docs/SPEC.md](docs/SPEC.md).

## License

MIT
