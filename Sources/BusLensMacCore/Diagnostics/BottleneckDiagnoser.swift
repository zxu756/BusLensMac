import Foundation

public enum BottleneckDiagnoser {

    private static let highBandwidthDeviceHints: [String] = [
        "nvme", "ssd", "tbu", "asm2464", "asm2364", "asm2362", "rtl9210",
        "jms583", "enclosure", "thunderbolt", "usb4", "raid", "san",
        "portable ssd", "extreme pro", "t7", "t9", "x9", "x10", "dock", "caldigit", "owc"
    ]

    private static let hidOrAudioHints: [String] = [
        "keyboard", "wooting", "keychron", "hhkb", "mouse", "trackpad",
        "receiver", "2.4g", "8k", "ajazz", "logitech", "razer", "audio",
        "dac", "mic", "yeti", "webcam", "ups", "bluetooth"
    ]

    /// Converts macOS speed strings ("40 Gb/s", "Up to 10 Gb/sec", "480 Mb/s", "12 Mb/sec") into Gbps.
    public static func parseSpeedGbps(_ raw: String) -> Double {
        let lower = raw.lowercased()
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*(gb|mb)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
              let numRange = Range(match.range(at: 1), in: lower),
              let unitRange = Range(match.range(at: 2), in: lower),
              let val = Double(lower[numRange]) else {
            return 0.0
        }
        let unit = String(lower[unitRange])
        if unit == "gb" {
            return val
        }
        return val / 1000.0
    }

    public static func formatSpeedGbps(_ gbps: Double) -> String {
        if gbps >= 1.0 {
            if gbps.truncatingRemainder(dividingBy: 1.0) == 0 {
                return "\(Int(gbps)) Gb/s"
            }
            return String(format: "%.1f Gb/s", gbps)
        }
        if gbps > 0 {
            let mbps = Int(round(gbps * 1000.0))
            return "\(mbps) Mb/s"
        }
        return "Idle"
    }

    public static func evaluateDevice(
        name: String,
        vendor: String,
        protocolKind: BusProtocolKind,
        negotiatedGbps: Double,
        portCeilingGbps: Double,
        behindHub: Bool
    ) -> (verdict: LinkHealthVerdict, detail: String) {
        let combined = "\(name) \(vendor)".lowercased()
        let looksHighBandwidth = highBandwidthDeviceHints.contains { combined.contains($0) }
        let looksHID = hidOrAudioHints.contains { combined.contains($0) }

        if negotiatedGbps >= 40.0 {
            let gen = negotiatedGbps >= 80.0 ? "Thunderbolt 5 (80 Gb/s)" : "Thunderbolt / USB4 (40 Gb/s)"
            return (
                .optimalTunnel,
                "Active \(gen) PCIe tunnel — full storage & display throughput available."
            )
        }

        if looksHighBandwidth && negotiatedGbps > 0 && negotiatedGbps <= 10.0 {
            if negotiatedGbps <= 0.5 {
                return (
                    .cableOrHubBottleneck,
                    "Storage/dock trapped at USB 2.0 (480 Mb/s) — replace charge-only USB-C cable with certified 40 Gb/s USB4/TB4 cable."
                )
            }
            let hubNote = behindHub
                ? "routed through intermediate USB hub"
                : "using a 10 Gb/s USB-C cable or USB 3.2 bridge"
            return (
                .cableOrHubBottleneck,
                "Negotiated \(formatSpeedGbps(negotiatedGbps)) (\(hubNote)); connect directly with a 40 Gb/s cable if enclosure supports USB4/TB3."
            )
        }

        if negotiatedGbps >= 5.0 {
            return (
                .superSpeedOptimal,
                "Operating at USB 3 SuperSpeed (\(formatSpeedGbps(negotiatedGbps)))."
            )
        }

        if looksHID || negotiatedGbps <= 0.48 {
            return (
                .hidOptimal,
                "Dedicated USB 2.0 lane (\(formatSpeedGbps(negotiatedGbps))) — expected for HID / low-latency peripherals."
            )
        }

        return (.superSpeedOptimal, "Active link at \(formatSpeedGbps(negotiatedGbps)).")
    }

    @MainActor
    public static func formatSpeedGbps(_ gbps: Double, localizer: AppLocalizer) -> String {
        if gbps <= 0 {
            return localizer.L("Idle", "空闲")
        }
        return formatSpeedGbps(gbps)
    }

    public static func chineseDiagnosticDetail(for device: AttachedBusDevice) -> String {
        let rate = formatSpeedGbps(device.negotiatedGbps)
        switch device.verdict {
        case .optimalTunnel:
            let gen = device.negotiatedGbps >= 80.0 ? "雷雳 5 (80 Gb/s)" : "雷雳 / USB4 (40 Gb/s)"
            return "已建立 \(gen) 满速 PCIe 隧道 — 外置高速存储与显示器带宽完全释放。"
        case .cableOrHubBottleneck:
            if device.negotiatedGbps <= 0.5 {
                return "高速存储/扩展坞受困于 USB 2.0 (480 Mb/s) — 请更换仅充电线为认证 40 Gb/s USB4 数据线。"
            }
            let behindHub = device.depth > 0 || device.modeDescription.lowercased().contains("hub")
            if behindHub {
                return "当前协商速率仅 \(rate)（经由中间 USB 集线器降速）；若硬盘盒支持 USB4/雷雳 3，请使用 40 Gb/s 线材直连机身端口。"
            }
            return "当前协商速率仅 \(rate)（受限于 10 Gb/s 线材或 USB 3.2 桥接）；若外设支持 USB4/雷雳 3，请更换 40 Gb/s 认证线材。"
        case .superSpeedOptimal:
            return "正以 USB 3 SuperSpeed (\(rate)) 高速模式稳定运行。"
        case .hidOptimal:
            return "独立 USB 2.0 通道 (\(rate)) — 符合键盘鼠标等低延迟 HID 外设的最佳工作速率。"
        case .idlePort:
            return "物理端口当前空闲，未接入设备。"
        }
    }
}
