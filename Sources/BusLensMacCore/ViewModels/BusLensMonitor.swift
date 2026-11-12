import AppKit
import Combine
import Foundation
import SwiftUI

public enum BusFilterMode: String, CaseIterable, Identifiable, Sendable {
    case all = "All attached devices"
    case bottlenecks = "Cable bottlenecks"
    case thunderbolt = "Thunderbolt / USB4"
    case usbPeripherals = "USB peripherals"

    public var id: String { rawValue }
}

@MainActor
public final class BusLensMonitor: ObservableObject {
    @Published public var snapshot: BusTopologySnapshot
    @Published public var filterMode: BusFilterMode = .all
    public let isStaticPreview: Bool
    private var refreshTimer: Timer?

    public init(
        snapshot: BusTopologySnapshot? = nil,
        isStaticPreview: Bool = false,
        autoRefreshSeconds: TimeInterval? = 12.0
    ) {
        self.isStaticPreview = isStaticPreview
        if let snapshot {
            self.snapshot = snapshot
        } else {
            self.snapshot = BusProfilerCollector.collectLiveHost()
        }

        if !isStaticPreview, let interval = autoRefreshSeconds, interval > 0 {
            self.refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refresh()
                }
            }
        }
    }

    public func refresh() {
        guard !isStaticPreview else { return }
        snapshot = BusProfilerCollector.collectLiveHost()
    }

    public var filteredDevices: [AttachedBusDevice] {
        snapshot.devices.filter { dev in
            switch filterMode {
            case .all: return true
            case .bottlenecks: return dev.verdict == .cableOrHubBottleneck
            case .thunderbolt: return dev.protocolKind == .thunderboltUSB4
            case .usbPeripherals: return dev.protocolKind == .usbHost
            }
        }
    }

    public var menuBarLabelText: String {
        let warnCount = snapshot.bottleneckDevices.count
        if warnCount > 0 {
            return "\(warnCount) bottleneck"
        }
        let peak = snapshot.peakNegotiatedGbps
        return peak > 0 ? BottleneckDiagnoser.formatSpeedGbps(peak) : "Ports idle"
    }

    // MARK: - Deterministic Hardware Bench Preview

    public static func preview() -> BusLensMonitor {
        let now = Date(timeIntervalSince1970: 1_794_556_800)
        let tbSSD = AttachedBusDevice(
            id: "tb1-nvme",
            name: "TBU405Pro NVMe Enclosure",
            vendor: "ACASIS",
            busName: "Thunderbolt / USB4 Bus 1",
            protocolKind: .thunderboltUSB4,
            negotiatedSpeedLabel: "40 Gb/s",
            negotiatedGbps: 40.0,
            portCeilingGbps: 40.0,
            depth: 0,
            modeDescription: "thunderbolt 3",
            verdict: .optimalTunnel,
            diagnosticDetail: "Active Thunderbolt / USB4 (40 Gb/s) PCIe tunnel — full storage & display throughput available."
        )
        let throttledSSD = AttachedBusDevice(
            id: "usb1-ssd-throttled",
            name: "Portable SSD X9 Pro",
            vendor: "Crucial",
            busName: "USB 3.1 Bus #1",
            protocolKind: .usbHost,
            negotiatedSpeedLabel: "480 Mb/s",
            negotiatedGbps: 0.48,
            portCeilingGbps: 40.0,
            depth: 0,
            modeDescription: "direct root port",
            verdict: .cableOrHubBottleneck,
            diagnosticDetail: "Storage/dock trapped at USB 2.0 (480 Mb/s) — replace charge-only USB-C cable with certified 40 Gb/s USB4/TB4 cable."
        )
        let hubThrottledNVMe = AttachedBusDevice(
            id: "usb1-asm2464",
            name: "ASM2464PD USB4 NVMe Bridge",
            vendor: "ASMedia",
            busName: "USB 3.1 Bus #1",
            protocolKind: .usbHost,
            negotiatedSpeedLabel: "10 Gb/s",
            negotiatedGbps: 10.0,
            portCeilingGbps: 40.0,
            depth: 1,
            modeDescription: "via USB hub",
            verdict: .cableOrHubBottleneck,
            diagnosticDetail: "Negotiated 10 Gb/s (routed through intermediate USB hub); connect directly with a 40 Gb/s cable if enclosure supports USB4/TB3."
        )
        let captureCard = AttachedBusDevice(
            id: "usb2-camlink",
            name: "StreamCapture 4K60 UVC",
            vendor: "Elgato",
            busName: "USB 3.1 Bus #2",
            protocolKind: .usbHost,
            negotiatedSpeedLabel: "5 Gb/s",
            negotiatedGbps: 5.0,
            portCeilingGbps: 10.0,
            depth: 0,
            modeDescription: "direct root port",
            verdict: .superSpeedOptimal,
            diagnosticDetail: "Operating at USB 3 SuperSpeed (5 Gb/s)."
        )
        let keyboardHID = AttachedBusDevice(
            id: "usb2-kb",
            name: "Hall-Effect 60HE Analog Keyboard",
            vendor: "Wooting",
            busName: "USB 3.1 Bus #2",
            protocolKind: .usbHost,
            negotiatedSpeedLabel: "480 Mb/s",
            negotiatedGbps: 0.48,
            portCeilingGbps: 10.0,
            depth: 1,
            modeDescription: "via USB hub",
            verdict: .hidOptimal,
            diagnosticDetail: "Dedicated USB 2.0 lane (480 Mb/s) — expected for HID / low-latency peripherals."
        )

        let controllers: [PhysicalPortController] = [
            PhysicalPortController(
                id: "c0",
                title: "Thunderbolt / USB4 Bus 0",
                protocolKind: .thunderboltUSB4,
                maxRateLabel: "40 Gb/s",
                maxGbps: 40.0,
                negotiatedGbps: 0.0,
                isConnected: false,
                devices: []
            ),
            PhysicalPortController(
                id: "c1",
                title: "Thunderbolt / USB4 Bus 1",
                protocolKind: .thunderboltUSB4,
                maxRateLabel: "40 Gb/s",
                maxGbps: 40.0,
                negotiatedGbps: 40.0,
                isConnected: true,
                devices: [tbSSD]
            ),
            PhysicalPortController(
                id: "c2",
                title: "Thunderbolt / USB4 Bus 2",
                protocolKind: .thunderboltUSB4,
                maxRateLabel: "40 Gb/s",
                maxGbps: 40.0,
                negotiatedGbps: 0.0,
                isConnected: false,
                devices: []
            ),
            PhysicalPortController(
                id: "u1",
                title: "USB 3.1 Bus #1",
                protocolKind: .usbHost,
                maxRateLabel: "10 Gb/s",
                maxGbps: 10.0,
                negotiatedGbps: 10.0,
                isConnected: true,
                devices: [hubThrottledNVMe, throttledSSD]
            ),
            PhysicalPortController(
                id: "u2",
                title: "USB 3.1 Bus #2",
                protocolKind: .usbHost,
                maxRateLabel: "10 Gb/s",
                maxGbps: 10.0,
                negotiatedGbps: 5.0,
                isConnected: true,
                devices: [captureCard, keyboardHID]
            )
        ]

        let snap = BusTopologySnapshot(
            capturedAt: now,
            controllers: controllers,
            devices: [tbSSD, hubThrottledNVMe, throttledSSD, captureCard, keyboardHID],
            power: PowerDeliverySummary(powerSource: "USB-C PD", negotiatedWatts: 140, lowPowerMode: false)
        )
        return BusLensMonitor(snapshot: snap, isStaticPreview: true, autoRefreshSeconds: nil)
    }
}

public enum BusScreenshotExporter {
    @MainActor
    public static func exportMarketingScreenshots(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let monitor = BusLensMonitor.preview()

        let mainView = BusDashboardView(monitor: monitor)
            .frame(width: 980, height: 700)
            .environment(\.colorScheme, .light)
        try renderPNG(view: mainView, to: directory.appendingPathComponent("screenshot-main.png"))

        let menuView = BusMenuBarView(monitor: monitor, onOpenWindow: {}, onQuit: {})
            .frame(width: 380, height: 416)
            .padding(14)
            .background(Color(red: 0.859, green: 0.851, blue: 0.824))
            .environment(\.colorScheme, .light)
        try renderPNG(view: menuView, to: directory.appendingPathComponent("screenshot-menubar.png"))
    }

    @MainActor
    public static func renderPNG<V: View>(view: V, to url: URL) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        renderer.isOpaque = true
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "BusLensMac.ScreenshotExporter", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to rasterize BusLensMac SwiftUI view"
            ])
        }
        try png.write(to: url, options: .atomic)
    }
}
