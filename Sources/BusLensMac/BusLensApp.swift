import AppKit
import BusLensMacCore
import Foundation
import SwiftUI

@main
struct BusLensApp: App {
    @StateObject private var monitor: BusLensMonitor
    @StateObject private var localizer: AppLocalizer
    @Environment(\.openWindow) private var openWindow

    init() {
        let args = CommandLine.arguments

        if let idx = args.firstIndex(of: "--export-screenshots"), idx + 1 < args.count {
            let outURL = URL(fileURLWithPath: args[idx + 1])
            let exportLang = AppLocalizer.resolveCLILanguage(from: args) ?? .en
            do {
                try MainActor.assumeIsolated {
                    try BusScreenshotExporter.exportMarketingScreenshots(to: outURL, language: exportLang)
                }
                print("Exported 2x Retina screenshots (\(exportLang.rawValue)) to \(outURL.path)")
                exit(0)
            } catch {
                fputs("Failed to export screenshots: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }

        if let idx = args.firstIndex(of: "--cli") {
            let sub = (idx + 1 < args.count && !args[idx + 1].hasPrefix("--")) ? args[idx + 1] : "topology"
            MainActor.assumeIsolated {
                Self.runHeadlessCLI(subcmd: sub, localizer: AppLocalizer.shared)
            }
            exit(0)
        }

        _monitor = StateObject(wrappedValue: BusLensMonitor())
        _localizer = StateObject(wrappedValue: AppLocalizer.shared)
    }

    var body: some Scene {
        Window(localizer.L("BusLens Mac — Thunderbolt & USB-C Schematic", "BusLens Mac — 雷雳与 USB-C 端口诊断面板"), id: "main") {
            BusDashboardView(monitor: monitor, localizer: localizer)
        }
        .defaultSize(width: 1060, height: 715)
        .commands {
            CommandMenu(localizer.L("Language", "语言")) {
                Button("切换语言 / Toggle Language") {
                    localizer.toggle()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Divider()

                ForEach(AppLanguage.allCases) { lang in
                    Button {
                        localizer.language = lang
                    } label: {
                        HStack {
                            Text("\(lang.displayName) (\(lang.badge))")
                            if localizer.language == lang {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        }

        MenuBarExtra {
            BusMenuBarView(
                monitor: monitor,
                localizer: localizer,
                onOpenWindow: {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                },
                onQuit: {
                    NSApplication.shared.terminate(nil)
                }
            )
            .frame(width: 410, height: 444)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cable.connector.horizontal")
                Text(monitor.localizedMenuBarLabel(localizer))
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }

    @MainActor
    private static func runHeadlessCLI(subcmd: String, localizer: AppLocalizer) {
        let snap = BusProfilerCollector.collectLiveHost()
        if subcmd == "bottlenecks" {
            if snap.bottleneckDevices.isEmpty {
                print(localizer.L(
                    "No USB-C / Thunderbolt cable or hub bottlenecks detected.",
                    "未检测到 USB-C / 雷雳线材或集线器降速瓶颈。"
                ))
                return
            }
            for dev in snap.bottleneckDevices {
                let tag = localizer.L("[WARN]", "[瓶颈]")
                print("\(tag) \(dev.negotiatedSpeedLabel)  \(dev.name) (\(dev.localizedBusName(localizer))) — \(dev.localizedDiagnosticDetail(localizer))")
            }
            return
        }

        let peakStr = BottleneckDiagnoser.formatSpeedGbps(snap.peakNegotiatedGbps, localizer: localizer)
        print(localizer.L(
            "Power: \(snap.power.localizedBadge(localizer)) | Peak Negotiated Link: \(peakStr)",
            "供电状态：\(snap.power.localizedBadge(localizer)) | 最高协商链路：\(peakStr)"
        ))
        for dev in snap.devices {
            let rate = dev.negotiatedSpeedLabel.padding(toLength: 10, withPad: " ", startingAt: 0)
            let state = dev.verdict.localizedLabel(localizer).padding(toLength: 16, withPad: " ", startingAt: 0)
            print("\(rate)  [\(state)]  \(dev.name) (\(dev.vendor)) — \(dev.localizedBusName(localizer))")
        }
    }
}
