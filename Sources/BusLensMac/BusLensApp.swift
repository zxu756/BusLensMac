import AppKit
import BusLensMacCore
import Foundation
import SwiftUI

@main
struct BusLensApp: App {
    @StateObject private var monitor: BusLensMonitor
    @Environment(\.openWindow) private var openWindow

    init() {
        let args = CommandLine.arguments

        if let idx = args.firstIndex(of: "--export-screenshots"), idx + 1 < args.count {
            let outURL = URL(fileURLWithPath: args[idx + 1])
            do {
                try MainActor.assumeIsolated {
                    try BusScreenshotExporter.exportMarketingScreenshots(to: outURL)
                }
                print("Exported 2x Retina screenshots to \(outURL.path)")
                exit(0)
            } catch {
                fputs("Failed to export screenshots: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }

        if let idx = args.firstIndex(of: "--cli") {
            let sub = (idx + 1 < args.count) ? args[idx + 1] : "topology"
            Self.runHeadlessCLI(subcmd: sub)
            exit(0)
        }

        _monitor = StateObject(wrappedValue: BusLensMonitor())
    }

    var body: some Scene {
        Window("BusLens Mac", id: "main") {
            BusDashboardView(monitor: monitor)
        }
        .defaultSize(width: 980, height: 700)

        MenuBarExtra {
            BusMenuBarView(
                monitor: monitor,
                onOpenWindow: {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                },
                onQuit: {
                    NSApplication.shared.terminate(nil)
                }
            )
            .frame(width: 380, height: 416)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cable.connector.horizontal")
                Text(monitor.menuBarLabelText)
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }

    private static func runHeadlessCLI(subcmd: String) {
        let snap = BusProfilerCollector.collectLiveHost()
        if subcmd == "bottlenecks" {
            if snap.bottleneckDevices.isEmpty {
                print("No USB-C / Thunderbolt cable or hub bottlenecks detected.")
                return
            }
            for dev in snap.bottleneckDevices {
                print("[WARN] \(dev.negotiatedSpeedLabel)  \(dev.name) (\(dev.busName)) — \(dev.diagnosticDetail)")
            }
            return
        }

        print("Power: \(snap.power.displayBadge) | Peak Negotiated Link: \(BottleneckDiagnoser.formatSpeedGbps(snap.peakNegotiatedGbps))")
        for dev in snap.devices {
            let rate = dev.negotiatedSpeedLabel.padding(toLength: 10, withPad: " ", startingAt: 0)
            let state = dev.verdict.rawValue.padding(toLength: 25, withPad: " ", startingAt: 0)
            print("\(rate)  [\(state)]  \(dev.name) (\(dev.vendor)) — \(dev.busName)")
        }
    }
}
