import AppKit
import BusLensMacCore
import Foundation
import SwiftUI

struct BusLensApp: App {
    @StateObject private var monitor: BusLensMonitor
    @StateObject private var localizer: AppLocalizer
    @Environment(\.openWindow) private var openWindow

    init() {
        let args = CommandLine.arguments
        let useDemo = args.contains("--demo")
        _monitor = StateObject(wrappedValue: useDemo ? BusLensMonitor.preview() : BusLensMonitor())
        _localizer = StateObject(wrappedValue: AppLocalizer(arguments: args))
    }

    var body: some Scene {
        Window(localizer.L("BusLens Mac — Thunderbolt & USB-C Link Inspector", "BusLens Mac — 雷雳与 USB-C 协商速率面板"), id: "main") {
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
}
