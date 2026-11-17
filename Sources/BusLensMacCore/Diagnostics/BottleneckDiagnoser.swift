import Foundation

public struct DeviceDiagnosticEvaluation: Equatable, Sendable {
    public let verdict: LinkHealthVerdict
    public let bottleneckSegment: BottleneckSegment?
    public let deviceMaxGbps: Double?
    public let isInferred: Bool
    public let detail: String

    public init(
        verdict: LinkHealthVerdict,
        bottleneckSegment: BottleneckSegment? = nil,
        deviceMaxGbps: Double? = nil,
        isInferred: Bool = false,
        detail: String
    ) {
        self.verdict = verdict
        self.bottleneckSegment = bottleneckSegment
        self.deviceMaxGbps = deviceMaxGbps
        self.isInferred = isInferred
        self.detail = detail
    }
}

public enum BottleneckDiagnoser {

    /// Maximum negotiated rate for USB Full-Speed (12 Mb/s) and Low-Speed (1.5 Mb/s), expressed in Gbps.
    public static let usb1FullSpeedMaxGbps: Double = 0.0125

    /// Converts macOS speed strings ("40 Gb/s", "Up to 10 Gb/sec", "480 Mb/s", "12 Mb/sec", "1.5 Mb/s") into Gbps.
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

    /// Parses legacy `SPUSBDataType` `device_speed` enum tokens (sourced only from public legacy-format output samples found online;
    /// this machine has no `SPUSBReporter`, so there is no local source; unverified on the author's machine).
    /// Returns 0.0 (rendered as Unknown / 未知) for any unrecognized value.
    public static func parseLegacyUSBDeviceSpeedGbps(_ raw: String) -> Double {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "low_speed":
            return 0.0015
        case "full_speed":
            return 0.012
        case "high_speed":
            return 0.48
        case "super_speed":
            return 5.0
        case "super_speed_plus":
            return 10.0
        case "super_speed_plus_x2":
            return 20.0
        default:
            return 0.0
        }
    }

    public static func formatSpeedGbps(_ gbps: Double) -> String {
        if gbps >= 1.0 {
            if gbps.truncatingRemainder(dividingBy: 1.0) == 0 {
                return "\(Int(gbps)) Gb/s"
            }
            return String(format: "%.1f Gb/s", gbps)
        }
        if gbps > 0 {
            let mbps = gbps * 1000.0
            if abs(mbps.rounded() - mbps) < 0.05 {
                return "\(Int(mbps.rounded())) Mb/s"
            }
            return String(format: "%.1f Mb/s", mbps)
        }
        return "Idle"
    }

    /// Evaluates negotiated link speed strictly from hardware descriptors, port ceilings, and hub topology.
    /// Never inspects product or vendor names.
    public static func evaluate(
        protocolKind: BusProtocolKind,
        negotiatedGbps: Double,
        portCeilingGbps: Double?,
        isPortCeilingInferred: Bool = false,
        behindExternalHub: Bool,
        upstreamHubGbps: Double? = nil,
        capability: DeviceCapabilityDescriptor? = nil
    ) -> DeviceDiagnosticEvaluation {
        let rate = negotiatedGbps > 0 ? formatSpeedGbps(negotiatedGbps) : "Unknown"

        switch protocolKind {
        case .thunderboltUSB4:
            return evaluateThunderbolt(
                negotiatedGbps: negotiatedGbps,
                rateLabel: rate,
                portCeilingGbps: portCeilingGbps,
                isPortCeilingInferred: isPortCeilingInferred,
                behindExternalHub: behindExternalHub,
                upstreamHubGbps: upstreamHubGbps,
                capability: capability
            )
        case .usbHost:
            return evaluateUSB(
                negotiatedGbps: negotiatedGbps,
                rateLabel: rate,
                portCeilingGbps: portCeilingGbps,
                isPortCeilingInferred: isPortCeilingInferred,
                behindExternalHub: behindExternalHub,
                upstreamHubGbps: upstreamHubGbps,
                capability: capability
            )
        }
    }

    /// Backwards-compatible convenience entry point (product/vendor parameters are intentionally unused).
    public static func evaluateDevice(
        name _: String,
        vendor _: String,
        protocolKind: BusProtocolKind,
        negotiatedGbps: Double,
        portCeilingGbps: Double?,
        behindHub: Bool,
        upstreamHubGbps: Double? = nil,
        capability: DeviceCapabilityDescriptor? = nil
    ) -> (verdict: LinkHealthVerdict, detail: String) {
        let eval = evaluate(
            protocolKind: protocolKind,
            negotiatedGbps: negotiatedGbps,
            portCeilingGbps: portCeilingGbps,
            behindExternalHub: behindHub,
            upstreamHubGbps: upstreamHubGbps,
            capability: capability
        )
        return (eval.verdict, eval.detail)
    }

    // MARK: - Protocol Evaluators

    private static func evaluateThunderbolt(
        negotiatedGbps: Double,
        rateLabel: String,
        portCeilingGbps: Double?,
        isPortCeilingInferred: Bool,
        behindExternalHub: Bool,
        upstreamHubGbps: Double?,
        capability: DeviceCapabilityDescriptor?
    ) -> DeviceDiagnosticEvaluation {
        guard negotiatedGbps > 0 else {
            return DeviceDiagnosticEvaluation(
                verdict: .indeterminate,
                detail: "Negotiated at \(rateLabel); cannot determine if cable/hub-limited without device max capability."
            )
        }

        if let devMax = capability?.tbSupportedLinkGbps, devMax > 0 {
            if negotiatedGbps + 0.01 < devMax {
                let seg = classifyBottleneckSegment(
                    negotiatedGbps: negotiatedGbps,
                    requiredSpeedGbps: devMax,
                    portCeilingGbps: portCeilingGbps,
                    behindExternalHub: behindExternalHub,
                    upstreamHubGbps: upstreamHubGbps
                )
                // Cable speed is not read directly from user-space ioreg; attributing a throttled Thunderbolt link to `.cable` is inferred by elimination.
                let segInferred = (seg == .cable) || (isPortCeilingInferred && seg == .port)
                return DeviceDiagnosticEvaluation(
                    verdict: .throttled,
                    bottleneckSegment: seg,
                    deviceMaxGbps: devMax,
                    isInferred: segInferred,
                    detail: throttledEnglishDetail(
                        rateLabel: rateLabel,
                        maxGbps: devMax,
                        isExactMax: true,
                        segment: seg,
                        portCeilingGbps: portCeilingGbps,
                        isPortCeilingInferred: isPortCeilingInferred,
                        upstreamHubGbps: upstreamHubGbps,
                        inferredFromBcdUSB: false
                    )
                )
            }
            if let ceiling = portCeilingGbps, ceiling > 0, negotiatedGbps + 0.01 >= ceiling {
                return DeviceDiagnosticEvaluation(
                    verdict: .fullRate,
                    deviceMaxGbps: devMax,
                    isInferred: isPortCeilingInferred,
                    detail: "Negotiated at \(rateLabel) (full bus rate)."
                )
            }
            if negotiatedGbps >= 40.0 {
                return DeviceDiagnosticEvaluation(
                    verdict: .fullRate,
                    deviceMaxGbps: devMax,
                    detail: "Negotiated at \(rateLabel) (full bus rate)."
                )
            }
            return DeviceDiagnosticEvaluation(
                verdict: .normal,
                deviceMaxGbps: devMax,
                detail: "Negotiated at \(rateLabel) (matches device capability \(formatSpeedGbps(devMax)))."
            )
        }

        if let ceiling = portCeilingGbps, ceiling > 0, negotiatedGbps >= ceiling {
            return DeviceDiagnosticEvaluation(
                verdict: .fullRate,
                isInferred: isPortCeilingInferred,
                detail: "Negotiated at \(rateLabel) (full bus rate)."
            )
        }
        if negotiatedGbps >= 40.0 {
            return DeviceDiagnosticEvaluation(
                verdict: .fullRate,
                detail: "Negotiated at \(rateLabel) (full bus rate)."
            )
        }

        return DeviceDiagnosticEvaluation(
            verdict: .indeterminate,
            detail: "Negotiated at \(rateLabel); cannot determine if cable/hub-limited without device max capability."
        )
    }

    private static func evaluateUSB(
        negotiatedGbps: Double,
        rateLabel: String,
        portCeilingGbps: Double?,
        isPortCeilingInferred: Bool,
        behindExternalHub: Bool,
        upstreamHubGbps: Double?,
        capability: DeviceCapabilityDescriptor?
    ) -> DeviceDiagnosticEvaluation {
        guard negotiatedGbps > 0 else {
            return DeviceDiagnosticEvaluation(
                verdict: .indeterminate,
                detail: "Negotiated at \(rateLabel); cannot determine if cable/hub-limited without device max capability."
            )
        }

        guard let capability else {
            return DeviceDiagnosticEvaluation(
                verdict: .indeterminate,
                detail: "Negotiated at \(rateLabel); cannot determine if cable/hub-limited without device max capability."
            )
        }

        // 1. USB Billboard auxiliary controller (bDeviceClass == 17 / 0x11): max speed is not directly exposed in ioreg; normal status is inferred from USB Billboard class 17.
        if capability.isAuxiliaryBillboardEndpoint {
            return DeviceDiagnosticEvaluation(
                verdict: .normal,
                deviceMaxGbps: nil,
                isInferred: true,
                detail: "Negotiated at \(rateLabel) (inferred normal from USB Billboard class 17 auxiliary endpoint)."
            )
        }

        // 2. USB Device Descriptor bcdUSB + USB-IF Device/Interface Class evaluation
        if let bcd = capability.bcdUSB {
            // SuperSpeed-capable device operating in USB 2.0/1.1 mode MUST report bcdUSB == 0x0210 (USB 3.2 §9.6.1),
            // or bcdUSB >= 0x0300.
            if bcd == 0x0210 || bcd >= 0x0300 {
                let minSuperSpeed: Double = (bcd >= 0x0400) ? 20.0 : 5.0
                if negotiatedGbps + 0.01 < minSuperSpeed {
                    let seg = classifyBottleneckSegment(
                        negotiatedGbps: negotiatedGbps,
                        requiredSpeedGbps: minSuperSpeed,
                        portCeilingGbps: portCeilingGbps,
                        behindExternalHub: behindExternalHub,
                        upstreamHubGbps: upstreamHubGbps
                    )
                    return DeviceDiagnosticEvaluation(
                        verdict: .throttled,
                        bottleneckSegment: seg,
                        deviceMaxGbps: (bcd == 0x0300) ? 5.0 : minSuperSpeed,
                        isInferred: true,
                        detail: throttledEnglishDetail(
                            rateLabel: rateLabel,
                            maxGbps: minSuperSpeed,
                            isExactMax: bcd == 0x0300,
                            segment: seg,
                            portCeilingGbps: portCeilingGbps,
                            isPortCeilingInferred: isPortCeilingInferred,
                            upstreamHubGbps: upstreamHubGbps,
                            inferredFromBcdUSB: true
                        )
                    )
                }

                // Negotiated at >= 5 Gb/s: check whether bcdUSB establishes an exact protocol ceiling
                if bcd == 0x0300 {
                    // USB 3.0 only defines Gen 1 (5 Gb/s)
                    return DeviceDiagnosticEvaluation(
                        verdict: .normal,
                        deviceMaxGbps: 5.0,
                        isInferred: true,
                        detail: "Negotiated at \(rateLabel) (inferred normal from bcdUSB 0x0300: matches USB 3.0 Gen 1 ceiling 5 Gb/s)."
                    )
                }
                if bcd >= 0x0310 && bcd < 0x0320 {
                    // USB 3.1 defines up to Gen 2 (10 Gb/s); at 10 Gb/s it is at its spec ceiling.
                    if negotiatedGbps >= 9.9 {
                        return DeviceDiagnosticEvaluation(
                            verdict: .normal,
                            deviceMaxGbps: 10.0,
                            isInferred: true,
                            detail: "Negotiated at \(rateLabel) (inferred normal from bcdUSB 0x\(String(format: "%04x", bcd)): matches USB 3.1 Gen 2 ceiling 10 Gb/s)."
                        )
                    }
                    // At 5 Gb/s without SuperSpeedPlus sublink attribute, USB 3.1 Gen 1 vs Gen 2 is ambiguous.
                    return DeviceDiagnosticEvaluation(
                        verdict: .indeterminate,
                        detail: "Negotiated at \(rateLabel); bcdUSB 0x\(String(format: "%04x", bcd)) alone cannot distinguish 5 Gb/s Gen 1 from 10 Gb/s Gen 2."
                    )
                }
                if bcd >= 0x0320 && bcd < 0x0400 {
                    // USB 3.2 defines Gen 1x1 (5G), Gen 2x1 (10G), Gen 2x2 (20G).
                    if negotiatedGbps >= 19.9 {
                        return DeviceDiagnosticEvaluation(
                            verdict: .normal,
                            deviceMaxGbps: 20.0,
                            isInferred: true,
                            detail: "Negotiated at \(rateLabel) (inferred normal from bcdUSB 0x\(String(format: "%04x", bcd)): matches USB 3.2 Gen 2x2 ceiling 20 Gb/s)."
                        )
                    }
                    return DeviceDiagnosticEvaluation(
                        verdict: .indeterminate,
                        detail: "Negotiated at \(rateLabel); bcdUSB 0x\(String(format: "%04x", bcd)) without SuperSpeedPlus lane attributes cannot distinguish native \(rateLabel) from higher USB 3.2 tiers."
                    )
                }
                if bcd >= 0x0400 && negotiatedGbps >= 39.9 {
                    return DeviceDiagnosticEvaluation(
                        verdict: .normal,
                        deviceMaxGbps: 40.0,
                        isInferred: true,
                        detail: "Negotiated at \(rateLabel) (inferred normal from bcdUSB 0x\(String(format: "%04x", bcd)): matches USB4 ceiling 40 Gb/s)."
                    )
                }
            }

            // Pure USB 2.0 (0x0200) or USB 2.0 LPM without SuperSpeed BOS (0x0201)
            if bcd == 0x0200 || bcd == 0x0201 {
                if negotiatedGbps >= 0.47 {
                    return DeviceDiagnosticEvaluation(
                        verdict: .normal,
                        deviceMaxGbps: 0.48,
                        isInferred: true,
                        detail: "Negotiated at \(rateLabel) (inferred normal from bcdUSB 0x\(String(format: "%04x", bcd)): matches USB 2.0 High-Speed ceiling 480 Mb/s)."
                    )
                }
                // Operating below 480 Mb/s (e.g. 12 Mb/s Full-Speed or 1.5 Mb/s Low-Speed):
                if capability.isVerifiedHIDPeripheral && negotiatedGbps <= usb1FullSpeedMaxGbps {
                    return DeviceDiagnosticEvaluation(
                        verdict: .lowSpeedPeripheral,
                        deviceMaxGbps: negotiatedGbps,
                        detail: "Negotiated at \(rateLabel) (USB HID class 3 peripheral, normal)."
                    )
                }
                // USB 2.0 §9.6.1 permits Full-Speed-only devices to report bcdUSB = 0x0200.
                return DeviceDiagnosticEvaluation(
                    verdict: .indeterminate,
                    detail: "Negotiated at \(rateLabel); bcdUSB 0x\(String(format: "%04x", bcd)) alone cannot distinguish Full-Speed-only hardware from throttled High-Speed."
                )
            }

            // USB 1.0 / 1.1 (bcdUSB <= 0x0110)
            if bcd <= 0x0110 {
                if capability.isVerifiedHIDPeripheral && negotiatedGbps <= usb1FullSpeedMaxGbps {
                    return DeviceDiagnosticEvaluation(
                        verdict: .lowSpeedPeripheral,
                        deviceMaxGbps: 0.012,
                        detail: "Negotiated at \(rateLabel) (USB HID class 3 peripheral, normal)."
                    )
                }
                if negotiatedGbps >= 0.0115 {
                    return DeviceDiagnosticEvaluation(
                        verdict: .normal,
                        deviceMaxGbps: 0.012,
                        isInferred: true,
                        detail: "Negotiated at \(rateLabel) (inferred normal from bcdUSB 0x\(String(format: "%04x", bcd)): matches USB 1.1 Full-Speed ceiling 12 Mb/s)."
                    )
                }
            }
        }

        // 3. Verified HID class == 3 at 1.5 Mb/s or 12 Mb/s without bcdUSB
        if capability.isVerifiedHIDPeripheral && negotiatedGbps <= usb1FullSpeedMaxGbps {
            return DeviceDiagnosticEvaluation(
                verdict: .lowSpeedPeripheral,
                detail: "Negotiated at \(rateLabel) (USB HID class 3 peripheral, normal)."
            )
        }

        return DeviceDiagnosticEvaluation(
            verdict: .indeterminate,
            detail: "Negotiated at \(rateLabel); cannot determine if cable/hub-limited without device max capability."
        )
    }

    // MARK: - Bottleneck Segment Attribution

    public static func classifyBottleneckSegment(
        negotiatedGbps: Double,
        requiredSpeedGbps: Double,
        portCeilingGbps: Double?,
        behindExternalHub: Bool,
        upstreamHubGbps: Double?
    ) -> BottleneckSegment {
        // 1. Host physical port max speed is explicitly known, lower than device capability, and caps negotiated speed
        if let portCeiling = portCeilingGbps,
           portCeiling > 0,
           portCeiling + 0.01 < requiredSpeedGbps,
           negotiatedGbps + 0.01 >= portCeiling,
           (!behindExternalHub || ((upstreamHubGbps ?? 0) + 0.01 >= portCeiling)) {
            return .port
        }

        // 2. External USB hub speed is explicitly known, lower than device capability, and caps negotiated speed
        if behindExternalHub,
           let hubSpeed = upstreamHubGbps,
           hubSpeed > 0,
           hubSpeed + 0.01 < requiredSpeedGbps,
           negotiatedGbps <= hubSpeed + 0.01 {
            return .hub
        }

        // 3. Blame cable only when host port ceiling (and any upstream hub speed) is explicitly known to exceed negotiated speed
        if let portCeiling = portCeilingGbps,
           portCeiling > negotiatedGbps + 0.01,
           (!behindExternalHub || ((upstreamHubGbps ?? 0) > negotiatedGbps + 0.01)) {
            return .cable
        }

        // 4. Otherwise host port (or upstream hub) ceiling is missing -> cannot determine whether cable or port
        return .cableOrPortIndeterminate
    }

    private static func throttledEnglishDetail(
        rateLabel: String,
        maxGbps: Double,
        isExactMax: Bool,
        segment: BottleneckSegment,
        portCeilingGbps: Double?,
        isPortCeilingInferred: Bool = false,
        upstreamHubGbps: Double?,
        inferredFromBcdUSB: Bool = false
    ) -> String {
        let capPrefix = isExactMax ? "" : ">= "
        let capStr = "\(capPrefix)\(formatSpeedGbps(maxGbps))"
        let inferredPrefix = inferredFromBcdUSB ? "inferred from bcdUSB, " : ""
        switch segment {
        case .port:
            let basePortStr = portCeilingGbps.map(formatSpeedGbps) ?? rateLabel
            let portStr = isPortCeilingInferred ? "\(basePortStr) (inferred)" : basePortStr
            let portPrefix = (!inferredFromBcdUSB && isPortCeilingInferred) ? "inferred, " : inferredPrefix
            return "Throttled (\(portPrefix)port-limited): device supports \(capStr), negotiated at \(rateLabel) due to \(portStr) host port ceiling."
        case .hub:
            let hubStr = upstreamHubGbps.map(formatSpeedGbps) ?? rateLabel
            return "Throttled (\(inferredPrefix)hub-limited): device supports \(capStr), negotiated at \(rateLabel) behind \(hubStr) external USB hub."
        case .cable:
            let cablePrefix = inferredFromBcdUSB ? "inferred from bcdUSB and port ceiling, " : "inferred: "
            return "Throttled (\(cablePrefix)cable-limited): device supports \(capStr), negotiated at \(rateLabel); host port supports higher speed, so cable limit is inferred."
        case .cableOrPortIndeterminate:
            return "Throttled (\(inferredPrefix)cannot determine if cable or port): device supports \(capStr), negotiated at \(rateLabel); host port ceiling is unknown."
        }
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
        let rate = device.negotiatedGbps > 0 ? formatSpeedGbps(device.negotiatedGbps) : "未知"
        switch device.verdict {
        case .fullRate:
            return "实际速率 \(rate)（满速）。"
        case .normal:
            if device.capability?.isAuxiliaryBillboardEndpoint == true {
                return "实际速率 \(rate)（推断：按 USB Billboard 第 17 类辅助控制接口推断，正常）。"
            }
            if device.isInferred {
                if let devMax = device.deviceMaxGbps, devMax > 0 {
                    return "实际速率 \(rate)（推断：按 bcdUSB 推断已达协议最高能力 \(formatSpeedGbps(devMax))，正常）。"
                }
                return "实际速率 \(rate)（推断：按 bcdUSB 推断，正常）。"
            }
            if let devMax = device.deviceMaxGbps, devMax > 0 {
                return "实际速率 \(rate)（已达设备最高能力 \(formatSpeedGbps(devMax))，正常）。"
            }
            return "实际速率 \(rate)（正常）。"
        case .lowSpeedPeripheral:
            return "实际速率 \(rate)（USB HID 第 3 类低速外设，正常）。"
        case .throttled:
            let isExact: Bool = {
                if let exact = device.capability?.tbSupportedLinkGbps, exact > 0 { return true }
                if device.capability?.bcdUSB == 0x0300 { return true }
                return false
            }()
            let capStr: String = {
                if let maxG = device.deviceMaxGbps, maxG > 0 {
                    return isExact ? formatSpeedGbps(maxG) : ">= \(formatSpeedGbps(maxG))"
                }
                return "更高速率"
            }()
            let fromBcdUSB = (device.protocolKind == .usbHost && device.capability?.bcdUSB != nil)
            let inferredPrefix: String = {
                if fromBcdUSB { return "推断：按 bcdUSB 推断，" }
                if device.isInferred { return "推断：" }
                return ""
            }()
            switch device.bottleneckSegment ?? .cableOrPortIndeterminate {
            case .port:
                let basePortStr = device.portCeilingGbps.map(formatSpeedGbps) ?? rate
                let portStr = device.isPortCeilingInferred ? "\(basePortStr)（推断）" : basePortStr
                return "被限速（\(inferredPrefix)端口限速）：设备支持 \(capStr)，当前仅 \(rate)（受限于主机端口上限 \(portStr)）。"
            case .hub:
                let hubStr = device.upstreamHubGbps.map(formatSpeedGbps) ?? rate
                return "被限速（\(inferredPrefix)集线器限速）：设备支持 \(capStr)，当前经由 \(hubStr) 外接 USB 集线器协商为 \(rate)。"
            case .cable:
                let cablePrefix = fromBcdUSB ? "推断：按 bcdUSB 与端口上限推断，" : "推断："
                return "被限速（\(cablePrefix)线缆限速）：设备支持 \(capStr)，当前仅协商为 \(rate)（主机端口支持更高速率，推断限速在连接线缆）。"
            case .cableOrPortIndeterminate:
                return "被限速（\(inferredPrefix)无法判断是线还是口）：设备支持 \(capStr)，当前仅协商为 \(rate)（主机端口上限未知，无法判断是线还是口）。"
            }
        case .indeterminate:
            return "实际速率 \(rate)，无法判断是否被限速。"
        }
    }
}
