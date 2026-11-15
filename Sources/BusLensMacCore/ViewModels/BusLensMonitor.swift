import AppKit
import Combine
import Foundation
import SwiftUI

public enum BusFilterMode: String, CaseIterable, Identifiable, Sendable {
    case all = "All attached devices"
    case indeterminate = "Unverified ceiling"
    case thunderbolt = "Thunderbolt / USB4"
    case usbPeripherals = "USB peripherals"

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(_ localizer: AppLocalizer) -> String {
        switch self {
        case .all: return localizer.L("All attached devices", "全部连接设备")
        case .indeterminate: return localizer.L("Unverified ceiling", "待确认速率上限")
        case .thunderbolt: return localizer.L("Thunderbolt / USB4", "雷雳 / USB4")
        case .usbPeripherals: return localizer.L("USB peripherals", "USB 外设")
        }
    }
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
            case .indeterminate: return dev.verdict == .indeterminate
            case .thunderbolt: return dev.protocolKind == .thunderboltUSB4
            case .usbPeripherals: return dev.protocolKind == .usbHost
            }
        }
    }

    public var menuBarLabelText: String {
        localizedMenuBarLabel(.shared)
    }

    public func localizedMenuBarLabel(_ localizer: AppLocalizer) -> String {
        let prefix = isStaticPreview ? "[DEMO] " : ""
        let peak = snapshot.peakNegotiatedGbps
        let label = peak > 0
            ? BottleneckDiagnoser.formatSpeedGbps(peak)
            : localizer.L("Ports idle", "端口空闲")
        return prefix + label
    }

    // MARK: - Deterministic Demo Bench Preview (Explicit --demo / Screenshot Export Only)

    public static func preview() -> BusLensMonitor {
        let now = Date(timeIntervalSince1970: 1_794_556_800)
        let tbEnclosure = AttachedBusDevice(
            id: "demo-tb1-enclosure",
            name: "TBU405Pro Enclosure",
            vendor: "ACASIS",
            busName: "Thunderbolt / USB4 Bus 1",
            protocolKind: .thunderboltUSB4,
            negotiatedSpeedLabel: "40 Gb/s",
            negotiatedGbps: 40.0,
            portCeilingGbps: 40.0,
            depth: 0,
            modeDescription: "thunderbolt 3",
            verdict: .fullRate,
            diagnosticDetail: "Negotiated at 40 Gb/s (full bus rate)."
        )
        let usb10GStorage = AttachedBusDevice(
            id: "demo-usb1-10g",
            name: "Portable Storage Bridge",
            vendor: "ASMedia",
            busName: "USB 3.1 Bus (0x02000000)",
            protocolKind: .usbHost,
            negotiatedSpeedLabel: "10 Gb/s",
            negotiatedGbps: 10.0,
            portCeilingGbps: nil,
            depth: 0,
            modeDescription: "direct host bus",
            verdict: .indeterminate,
            diagnosticDetail: "Negotiated at 10 Gb/s; cannot determine if cable/hub-limited without device max capability."
        )
        let usb480Device = AttachedBusDevice(
            id: "demo-usb1-480m",
            name: "USB-C External Drive",
            vendor: "Generic",
            busName: "USB 3.1 Bus (0x02000000)",
            protocolKind: .usbHost,
            negotiatedSpeedLabel: "480 Mb/s",
            negotiatedGbps: 0.48,
            portCeilingGbps: nil,
            depth: 1,
            modeDescription: "via external USB hub",
            verdict: .indeterminate,
            diagnosticDetail: "Negotiated at 480 Mb/s; cannot determine if cable/hub-limited without device max capability."
        )
        let captureCard = AttachedBusDevice(
            id: "demo-usb2-uvc",
            name: "StreamCapture 4K60 UVC",
            vendor: "Elgato",
            busName: "USB 3.1 Bus (0x01000000)",
            protocolKind: .usbHost,
            negotiatedSpeedLabel: "5 Gb/s",
            negotiatedGbps: 5.0,
            portCeilingGbps: nil,
            depth: 0,
            modeDescription: "direct host bus",
            verdict: .indeterminate,
            diagnosticDetail: "Negotiated at 5 Gb/s; cannot determine if cable/hub-limited without device max capability."
        )
        let usb1Receiver = AttachedBusDevice(
            id: "demo-usb1-12m",
            name: "USB 1.1 Full-Speed Receiver",
            vendor: "Generic",
            busName: "USB 3.1 Bus (0x01000000)",
            protocolKind: .usbHost,
            negotiatedSpeedLabel: "12 Mb/s",
            negotiatedGbps: 0.012,
            portCeilingGbps: nil,
            depth: 0,
            modeDescription: "direct host bus",
            capability: DeviceCapabilityDescriptor(usbInterfaceClasses: [3]),
            verdict: .lowSpeedPeripheral,
            diagnosticDetail: "Negotiated at 12 Mb/s (HID peripheral)."
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
                devices: [tbEnclosure]
            ),
            PhysicalPortController(
                id: "c2",
                title: "Thunderbolt / USB4 Bus 3",
                protocolKind: .thunderboltUSB4,
                maxRateLabel: "40 Gb/s",
                maxGbps: 40.0,
                negotiatedGbps: 0.0,
                isConnected: false,
                devices: []
            ),
            PhysicalPortController(
                id: "u1",
                title: "USB 3.1 Bus (0x02000000)",
                protocolKind: .usbHost,
                maxGbps: nil,
                negotiatedGbps: 10.0,
                isConnected: true,
                devices: [usb10GStorage, usb480Device]
            ),
            PhysicalPortController(
                id: "u2",
                title: "USB 3.1 Bus (0x01000000)",
                protocolKind: .usbHost,
                maxGbps: nil,
                negotiatedGbps: 5.0,
                isConnected: true,
                devices: [captureCard, usb1Receiver]
            )
        ]

        let snap = BusTopologySnapshot(
            capturedAt: now,
            controllers: controllers,
            devices: [tbEnclosure, usb10GStorage, usb480Device, captureCard, usb1Receiver],
            power: PowerDeliverySummary(powerSource: "USB-C PD", negotiatedWatts: 140, lowPowerMode: false)
        )
        return BusLensMonitor(snapshot: snap, isStaticPreview: true, autoRefreshSeconds: nil)
    }
}

public enum BusScreenshotExporter {
    @MainActor
    public static func exportMarketingScreenshots(
        to directory: URL,
        language: AppLanguage = .en
    ) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let monitor = BusLensMonitor.preview()
        let localizer = AppLocalizer(fixedLanguage: language)
        let suffix = (language == .zhHans) ? "-zh" : ""

        let mainView = BusDashboardView(monitor: monitor, localizer: localizer)
            .environment(\.locale, language.locale)
            .frame(width: 1060, height: 715)
            .environment(\.colorScheme, .light)
        try renderPNG(view: mainView, to: directory.appendingPathComponent("screenshot-main\(suffix).png"))

        let menuView = BusMenuBarView(
            monitor: monitor,
            localizer: localizer,
            onOpenWindow: {},
            onQuit: {}
        )
        .environment(\.locale, language.locale)
        .frame(width: 410, height: 444)
        .padding(14)
        .background(Color(red: 0.859, green: 0.851, blue: 0.824))
        .environment(\.colorScheme, .light)
        try renderPNG(view: menuView, to: directory.appendingPathComponent("screenshot-menubar\(suffix).png"))
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
