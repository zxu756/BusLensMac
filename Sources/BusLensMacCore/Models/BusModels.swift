import Foundation
import SwiftUI

public enum BusProtocolKind: String, Codable, Equatable, Sendable {
    case thunderboltUSB4 = "Thunderbolt / USB4"
    case usbHost = "USB Host"

    public var badgeColor: Color {
        switch self {
        case .thunderboltUSB4: return Color(red: 0.082, green: 0.341, blue: 0.690) // Thunderbolt Cobalt #1557B0
        case .usbHost: return Color(red: 0.075, green: 0.451, blue: 0.337)         // SuperSpeed Pine #137356
        }
    }

    @MainActor
    public func localizedTitle(_ localizer: AppLocalizer) -> String {
        switch self {
        case .thunderboltUSB4: return localizer.L("Thunderbolt / USB4", "雷雳 / USB4")
        case .usbHost: return localizer.L("USB Host", "USB 主控")
        }
    }
}

public enum LinkHealthVerdict: String, Codable, Equatable, Sendable {
    case fullRate = "Full bus rate"
    case lowSpeedPeripheral = "Low-speed peripheral"
    case indeterminate = "Indeterminate"

    public var jsonCode: String {
        switch self {
        case .fullRate: return "full_rate"
        case .lowSpeedPeripheral: return "low_speed_peripheral"
        case .indeterminate: return "indeterminate"
        }
    }

    public var isWarning: Bool {
        false
    }

    public var color: Color {
        switch self {
        case .fullRate: return Color(red: 0.082, green: 0.341, blue: 0.690)             // Thunderbolt Cobalt #1557B0
        case .lowSpeedPeripheral: return Color(red: 0.075, green: 0.451, blue: 0.337)   // SuperSpeed Pine #137356
        case .indeterminate: return Color(red: 0.341, green: 0.349, blue: 0.369)        // Silkscreen Graphite #57595E
        }
    }

    @MainActor
    public func localizedLabel(_ localizer: AppLocalizer) -> String {
        switch self {
        case .fullRate: return localizer.L("Full bus rate", "满速")
        case .lowSpeedPeripheral: return localizer.L("Low-speed peripheral", "低速外设（USB 1.x）")
        case .indeterminate: return localizer.L("Indeterminate", "无法判断是否被限速")
        }
    }
}

public struct AttachedBusDevice: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var vendor: String
    public var busName: String
    public var protocolKind: BusProtocolKind
    public var negotiatedSpeedLabel: String
    public var negotiatedGbps: Double
    public var portCeilingGbps: Double?
    public var depth: Int
    public var behindExternalHub: Bool
    public var modeDescription: String
    public var verdict: LinkHealthVerdict
    public var diagnosticDetail: String

    public init(
        id: String,
        name: String,
        vendor: String,
        busName: String,
        protocolKind: BusProtocolKind,
        negotiatedSpeedLabel: String,
        negotiatedGbps: Double,
        portCeilingGbps: Double?,
        depth: Int = 0,
        behindExternalHub: Bool? = nil,
        modeDescription: String = "",
        verdict: LinkHealthVerdict,
        diagnosticDetail: String
    ) {
        self.id = id
        self.name = name
        self.vendor = vendor
        self.busName = busName
        self.protocolKind = protocolKind
        self.negotiatedSpeedLabel = negotiatedSpeedLabel
        self.negotiatedGbps = max(0, negotiatedGbps)
        if let portCeilingGbps, portCeilingGbps > 0 {
            self.portCeilingGbps = portCeilingGbps
        } else {
            self.portCeilingGbps = nil
        }
        self.depth = depth
        self.behindExternalHub = behindExternalHub ?? (depth > 0 && modeDescription.lowercased().contains("hub"))
        self.modeDescription = modeDescription
        self.verdict = verdict
        self.diagnosticDetail = diagnosticDetail
    }

    public var utilizationFraction: Double? {
        guard let ceiling = portCeilingGbps, ceiling > 0 else { return nil }
        return min(1.0, max(0.04, negotiatedGbps / ceiling))
    }

    @MainActor
    public func localizedVendor(_ localizer: AppLocalizer) -> String {
        if vendor == "Unknown vendor" {
            return localizer.L("Unknown vendor", "未知厂商")
        }
        return vendor
    }

    @MainActor
    public func localizedPortCeilingLabel(_ localizer: AppLocalizer) -> String {
        BottleneckDiagnoser.formatCeilingGbps(portCeilingGbps, localizer: localizer)
    }

    @MainActor
    public func localizedBusName(_ localizer: AppLocalizer) -> String {
        guard localizer.isChinese else { return busName }
        return busName
            .replacingOccurrences(of: "Thunderbolt / USB4 Bus", with: "雷雳 / USB4 总线")
            .replacingOccurrences(of: "Thunderbolt Bus", with: "雷雳总线")
            .replacingOccurrences(of: "USB 3.1 Bus", with: "USB 3.1 总线")
            .replacingOccurrences(of: "USB 3.0 Bus", with: "USB 3.0 总线")
            .replacingOccurrences(of: "USB31Bus", with: "USB 3.1 总线")
            .replacingOccurrences(of: "USB Bus", with: "USB 总线")
            .replacingOccurrences(of: "(bus ", with: "(总线序号 ")
    }

    @MainActor
    public func localizedModeDescription(_ localizer: AppLocalizer) -> String {
        guard localizer.isChinese else { return modeDescription }
        let lower = modeDescription.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch lower {
        case "thunderbolt 3": return "雷雳 3 隧道模式"
        case "thunderbolt 4": return "雷雳 4 隧道模式"
        case "thunderbolt 5": return "雷雳 5 隧道模式"
        case "usb4", "usb 4": return "USB4 隧道模式"
        case "via external usb hub", "via usb hub": return "经由外接 USB 集线器"
        case "direct host bus", "direct root port": return "主板总线直连"
        default: return modeDescription
        }
    }

    @MainActor
    public func localizedDiagnosticDetail(_ localizer: AppLocalizer) -> String {
        guard localizer.isChinese else { return diagnosticDetail }
        return BottleneckDiagnoser.chineseDiagnosticDetail(for: self)
    }
}

public struct PhysicalPortController: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var protocolKind: BusProtocolKind
    public var maxRateLabel: String
    public var maxGbps: Double?
    public var negotiatedGbps: Double
    public var isConnected: Bool
    public var devices: [AttachedBusDevice]

    public init(
        id: String,
        title: String,
        protocolKind: BusProtocolKind,
        maxRateLabel: String? = nil,
        maxGbps: Double?,
        negotiatedGbps: Double,
        isConnected: Bool,
        devices: [AttachedBusDevice]
    ) {
        self.id = id
        self.title = title
        self.protocolKind = protocolKind
        if let maxGbps, maxGbps > 0 {
            self.maxGbps = maxGbps
            self.maxRateLabel = maxRateLabel ?? BottleneckDiagnoser.formatSpeedGbps(maxGbps)
        } else {
            self.maxGbps = nil
            self.maxRateLabel = maxRateLabel ?? "Unknown"
        }
        self.negotiatedGbps = negotiatedGbps
        self.isConnected = isConnected
        self.devices = devices
    }

    @MainActor
    public func localizedMaxRateLabel(_ localizer: AppLocalizer) -> String {
        BottleneckDiagnoser.formatCeilingGbps(maxGbps, localizer: localizer)
    }

    @MainActor
    public func localizedTitle(_ localizer: AppLocalizer) -> String {
        guard localizer.isChinese else { return title }
        return title
            .replacingOccurrences(of: "Thunderbolt / USB4 Bus", with: "雷雳 / USB4 总线")
            .replacingOccurrences(of: "Thunderbolt Bus", with: "雷雳总线")
            .replacingOccurrences(of: "USB 3.1 Bus", with: "USB 3.1 总线")
            .replacingOccurrences(of: "USB 3.0 Bus", with: "USB 3.0 总线")
            .replacingOccurrences(of: "USB31Bus", with: "USB 3.1 总线")
            .replacingOccurrences(of: "USB Bus", with: "USB 总线")
            .replacingOccurrences(of: "(bus ", with: "(总线序号 ")
    }
}

public struct PowerDeliverySummary: Codable, Equatable, Sendable {
    public var powerSource: String?
    public var negotiatedWatts: Int?
    public var lowPowerMode: Bool?

    public var lowPowerModeEnabled: Bool? {
        get { lowPowerMode }
        set { lowPowerMode = newValue }
    }

    public init(powerSource: String? = nil, negotiatedWatts: Int? = nil, lowPowerMode: Bool? = nil) {
        self.powerSource = powerSource
        self.negotiatedWatts = negotiatedWatts
        self.lowPowerMode = lowPowerMode
    }

    public var displayBadge: String {
        if let w = negotiatedWatts, w > 0 {
            return "\(w)W USB-C PD"
        }
        if let powerSource, !powerSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return powerSource
        }
        return "Unknown"
    }

    @MainActor
    public func localizedBadge(_ localizer: AppLocalizer) -> String {
        if let w = negotiatedWatts, w > 0 {
            return "\(w)W USB-C PD"
        }
        guard let powerSource, !powerSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return localizer.L("Unknown", "未知")
        }
        let lower = powerSource.lowercased()
        if lower == "unknown" {
            return localizer.L("Unknown", "未知")
        }
        guard localizer.isChinese else { return powerSource }
        if lower.contains("ac") { return "交流电源" }
        if lower.contains("battery") { return "内置电池" }
        if lower.contains("unknown") { return "未知" }
        return powerSource
    }

    @MainActor
    public func localizedLowPowerModeLabel(_ localizer: AppLocalizer) -> String {
        switch lowPowerMode {
        case .some(true):
            return localizer.L("Yes", "是")
        case .some(false):
            return localizer.L("No", "否")
        case .none:
            return localizer.L("Unknown", "未知")
        }
    }
}

public struct BusTopologySnapshot: Codable, Equatable, Sendable {
    public var capturedAt: Date
    public var controllers: [PhysicalPortController]
    public var devices: [AttachedBusDevice]
    public var power: PowerDeliverySummary

    public init(
        capturedAt: Date,
        controllers: [PhysicalPortController],
        devices: [AttachedBusDevice],
        power: PowerDeliverySummary
    ) {
        self.capturedAt = capturedAt
        self.controllers = controllers
        self.devices = devices
        self.power = power
    }

    public var bottleneckDevices: [AttachedBusDevice] {
        devices.filter { $0.verdict.isWarning }
    }

    public var indeterminateDevices: [AttachedBusDevice] {
        devices.filter { $0.verdict == .indeterminate }
    }

    public var activeTunnelCount: Int {
        devices.filter { $0.negotiatedGbps >= 40.0 }.count
    }

    public var peakNegotiatedGbps: Double {
        devices.map(\.negotiatedGbps).max() ?? 0.0
    }
}
