import Foundation

public enum BottleneckDiagnoser {

    private static let confirmedLowSpeedPeripheralHints: [String] = [
        "keyboard", "mouse", "trackpad", "keypad", "receiver", "unifying",
        "wooting", "keychron", "hhkb", "realforce", "ajazz", "logitech",
        "nuphy", "2.4g", "hid", "yubikey", "fido", "webcam", "microphone",
        "yeti", "ups", "bluetooth"
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

    /// Evaluates negotiated link speed honestly without guessing device capability from product names.
    /// Until M1 reads per-device capability descriptors from `ioreg`, returns only:
    /// 1. `.fullRate` — Thunderbolt / USB4 link at known bus ceiling (or >= 40 Gb/s full tunnel rate).
    /// 2. `.lowSpeedPeripheral` — Confirmed low-speed HID / input / audio peripheral at USB 1.x / 2.0 rate.
    /// 3. `.indeterminate` — Negotiated at X; cannot determine if cable/hub-limited without device max capability.
    public static func evaluateDevice(
        name: String,
        vendor: String,
        protocolKind: BusProtocolKind,
        negotiatedGbps: Double,
        portCeilingGbps: Double?,
        behindHub: Bool
    ) -> (verdict: LinkHealthVerdict, detail: String) {
        let rate = formatSpeedGbps(negotiatedGbps)

        if protocolKind == .thunderboltUSB4 && negotiatedGbps > 0 {
            if let ceiling = portCeilingGbps, ceiling > 0 {
                if negotiatedGbps >= ceiling {
                    return (
                        .fullRate,
                        "Negotiated at \(rate) (full bus rate)."
                    )
                }
            } else if negotiatedGbps >= 40.0 {
                return (
                    .fullRate,
                    "Negotiated at \(rate) (full bus rate)."
                )
            }
        }

        if protocolKind == .usbHost && negotiatedGbps > 0 && negotiatedGbps <= 0.48 {
            let combined = "\(name) \(vendor)".lowercased()
            let isUSB1LowSpeed = negotiatedGbps <= 0.002
            let isKnownLowSpeedHID = confirmedLowSpeedPeripheralHints.contains { combined.contains($0) }
            if isUSB1LowSpeed || isKnownLowSpeedHID {
                return (
                    .lowSpeedPeripheral,
                    "Negotiated at \(rate) — normal for HID / low-latency peripherals."
                )
            }
        }

        return (
            .indeterminate,
            "Negotiated at \(rate); cannot determine if cable/hub-limited without device max capability."
        )
    }

    @MainActor
    public static func formatSpeedGbps(_ gbps: Double, localizer: AppLocalizer) -> String {
        if gbps <= 0 {
            return localizer.L("Idle", "空闲")
        }
        return formatSpeedGbps(gbps)
    }

    @MainActor
    public static func formatCeilingGbps(_ ceilingGbps: Double?, localizer: AppLocalizer) -> String {
        guard let ceilingGbps, ceilingGbps > 0 else {
            return localizer.L("Unknown", "未知")
        }
        return formatSpeedGbps(ceilingGbps)
    }

    public static func chineseDiagnosticDetail(for device: AttachedBusDevice) -> String {
        let rate = formatSpeedGbps(device.negotiatedGbps)
        switch device.verdict {
        case .fullRate:
            return "实际速率 \(rate)（满速）。"
        case .lowSpeedPeripheral:
            return "实际速率 \(rate) — 低速外设（正常）。"
        case .indeterminate:
            return "实际速率 \(rate)，无法判断是否被限速。"
        }
    }
}
