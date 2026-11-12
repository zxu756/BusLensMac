import Foundation
import SwiftUI

public enum BusProtocolKind: String, Codable, Equatable, Sendable {
    case thunderboltUSB4 = "Thunderbolt / USB4"
    case usbHost = "USB Host"

    public var badgeColor: Color {
        switch self {
        case .thunderboltUSB4: return Color(red: 0.38, green: 0.65, blue: 0.98) // Cobalt #60A5FA
        case .usbHost: return Color(red: 0.22, green: 0.74, blue: 0.97)         // Cyan #38BDF8
        }
    }
}

public enum LinkHealthVerdict: String, Codable, Equatable, Sendable {
    case optimalTunnel = "Full PCIe / USB4 tunnel"
    case cableOrHubBottleneck = "Cable or hub bottleneck"
    case superSpeedOptimal = "SuperSpeed USB optimal"
    case hidOptimal = "HID / low-latency USB2"
    case idlePort = "Receptacle open"

    public var isWarning: Bool {
        self == .cableOrHubBottleneck
    }

    public var color: Color {
        switch self {
        case .optimalTunnel: return Color(red: 0.38, green: 0.65, blue: 0.98)       // Cobalt
        case .cableOrHubBottleneck: return Color(red: 0.98, green: 0.44, blue: 0.52) // Coral #FB7185
        case .superSpeedOptimal: return Color(red: 0.20, green: 0.83, blue: 0.60)   // Emerald #34D399
        case .hidOptimal: return Color(red: 0.55, green: 0.64, blue: 0.75)          // Slate
        case .idlePort: return Color(red: 0.42, green: 0.49, blue: 0.58)
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
    public var portCeilingGbps: Double
    public var depth: Int
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
        portCeilingGbps: Double,
        depth: Int = 0,
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
        self.portCeilingGbps = max(0.48, portCeilingGbps)
        self.depth = depth
        self.modeDescription = modeDescription
        self.verdict = verdict
        self.diagnosticDetail = diagnosticDetail
    }

    public var utilizationFraction: Double {
        guard portCeilingGbps > 0 else { return 0 }
        return min(1.0, max(0.03, negotiatedGbps / portCeilingGbps))
    }
}

public struct PhysicalPortController: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var protocolKind: BusProtocolKind
    public var maxRateLabel: String
    public var maxGbps: Double
    public var negotiatedGbps: Double
    public var isConnected: Bool
    public var devices: [AttachedBusDevice]

    public init(
        id: String,
        title: String,
        protocolKind: BusProtocolKind,
        maxRateLabel: String,
        maxGbps: Double,
        negotiatedGbps: Double,
        isConnected: Bool,
        devices: [AttachedBusDevice]
    ) {
        self.id = id
        self.title = title
        self.protocolKind = protocolKind
        self.maxRateLabel = maxRateLabel
        self.maxGbps = maxGbps
        self.negotiatedGbps = negotiatedGbps
        self.isConnected = isConnected
        self.devices = devices
    }
}

public struct PowerDeliverySummary: Codable, Equatable, Sendable {
    public var powerSource: String
    public var negotiatedWatts: Int?
    public var lowPowerMode: Bool

    public init(powerSource: String, negotiatedWatts: Int? = nil, lowPowerMode: Bool = false) {
        self.powerSource = powerSource
        self.negotiatedWatts = negotiatedWatts
        self.lowPowerMode = lowPowerMode
    }

    public var displayBadge: String {
        if let w = negotiatedWatts, w > 0 {
            return "\(w)W USB-C PD"
        }
        return powerSource
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
        devices.filter { $0.verdict == .cableOrHubBottleneck }
    }

    public var activeTunnelCount: Int {
        devices.filter { $0.negotiatedGbps >= 40.0 }.count
    }

    public var peakNegotiatedGbps: Double {
        devices.map(\.negotiatedGbps).max() ?? 0.0
    }
}
