import Foundation

public struct BusCLIExecutionResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String = "", stderr: String = "") {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public struct BusCLITopologyJSONPayload: Codable, Equatable, Sendable {
    public struct PowerPayload: Codable, Equatable, Sendable {
        public let powerSource: String?
        public let localizedBadge: String
        public let negotiatedWatts: Int?
        public let lowPowerMode: Bool?
        public let lowPowerModeLabel: String

        enum CodingKeys: String, CodingKey {
            case powerSource, localizedBadge, negotiatedWatts, lowPowerMode, lowPowerModeLabel
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            if let powerSource {
                try c.encode(powerSource, forKey: .powerSource)
            } else {
                try c.encodeNil(forKey: .powerSource)
            }
            try c.encode(localizedBadge, forKey: .localizedBadge)
            if let negotiatedWatts {
                try c.encode(negotiatedWatts, forKey: .negotiatedWatts)
            } else {
                try c.encodeNil(forKey: .negotiatedWatts)
            }
            if let lowPowerMode {
                try c.encode(lowPowerMode, forKey: .lowPowerMode)
            } else {
                try c.encodeNil(forKey: .lowPowerMode)
            }
            try c.encode(lowPowerModeLabel, forKey: .lowPowerModeLabel)
        }
    }

    public struct ControllerPayload: Codable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let protocolKind: String
        public let ceilingGbps: Double?
        public let ceilingLabel: String
        public let negotiatedGbps: Double
        public let negotiatedSpeedLabel: String
        public let isConnected: Bool
        public let deviceCount: Int

        enum CodingKeys: String, CodingKey {
            case id, title, protocolKind, ceilingGbps, ceilingLabel
            case negotiatedGbps, negotiatedSpeedLabel, isConnected, deviceCount
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(title, forKey: .title)
            try c.encode(protocolKind, forKey: .protocolKind)
            if let ceilingGbps {
                try c.encode(ceilingGbps, forKey: .ceilingGbps)
            } else {
                try c.encodeNil(forKey: .ceilingGbps)
            }
            try c.encode(ceilingLabel, forKey: .ceilingLabel)
            try c.encode(negotiatedGbps, forKey: .negotiatedGbps)
            try c.encode(negotiatedSpeedLabel, forKey: .negotiatedSpeedLabel)
            try c.encode(isConnected, forKey: .isConnected)
            try c.encode(deviceCount, forKey: .deviceCount)
        }
    }

    public struct DevicePayload: Codable, Equatable, Sendable {
        public let id: String
        public let name: String
        public let vendor: String
        public let busName: String
        public let protocolKind: String
        public let negotiatedGbps: Double
        public let negotiatedSpeedLabel: String
        public let portCeilingGbps: Double?
        public let portCeilingLabel: String
        public let depth: Int
        public let behindExternalHub: Bool
        public let modeDescription: String
        public let verdict: String
        public let verdictLabel: String
        public let diagnosticDetail: String

        enum CodingKeys: String, CodingKey {
            case id, name, vendor, busName, protocolKind
            case negotiatedGbps, negotiatedSpeedLabel, portCeilingGbps, portCeilingLabel
            case depth, behindExternalHub, modeDescription, verdict, verdictLabel, diagnosticDetail
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(name, forKey: .name)
            try c.encode(vendor, forKey: .vendor)
            try c.encode(busName, forKey: .busName)
            try c.encode(protocolKind, forKey: .protocolKind)
            try c.encode(negotiatedGbps, forKey: .negotiatedGbps)
            try c.encode(negotiatedSpeedLabel, forKey: .negotiatedSpeedLabel)
            if let portCeilingGbps {
                try c.encode(portCeilingGbps, forKey: .portCeilingGbps)
            } else {
                try c.encodeNil(forKey: .portCeilingGbps)
            }
            try c.encode(portCeilingLabel, forKey: .portCeilingLabel)
            try c.encode(depth, forKey: .depth)
            try c.encode(behindExternalHub, forKey: .behindExternalHub)
            try c.encode(modeDescription, forKey: .modeDescription)
            try c.encode(verdict, forKey: .verdict)
            try c.encode(verdictLabel, forKey: .verdictLabel)
            try c.encode(diagnosticDetail, forKey: .diagnosticDetail)
        }
    }

    public let capturedAt: Date
    public let language: String
    public let isDemo: Bool
    public let peakNegotiatedGbps: Double
    public let peakNegotiatedLabel: String
    public let power: PowerPayload
    public let controllers: [ControllerPayload]
    public let devices: [DevicePayload]
}

public enum BusCLIRunner {
    public static let versionString = "0.2.0"

    public static func isHeadlessInvocation(arguments: [String]) -> Bool {
        let tail = Array(arguments.dropFirst())
        if tail.isEmpty { return false }

        var idx = 0
        while idx < tail.count {
            let arg = tail[idx]
            if arg == "--cli" || arg == "--help" || arg == "-h" || arg == "--version" || arg == "-v" || arg == "--export-screenshots" {
                return true
            }
            if arg == "--demo" {
                idx += 1
                continue
            }
            if arg == "--lang" {
                idx += 2
                continue
            }
            if arg.hasPrefix("--lang=") {
                idx += 1
                continue
            }
            if arg.hasPrefix("-psn_") || arg == "-NSDocumentRevisionsDebugMode" || arg == "-AppleLanguages" {
                if arg == "-NSDocumentRevisionsDebugMode" || arg == "-AppleLanguages" {
                    idx += 2
                } else {
                    idx += 1
                }
                continue
            }
            // Any unrecognized flag or positional argument on command line should fail fast in CLI rather than opening GUI
            return true
        }
        return false
    }

    @MainActor
    public static func execute(
        arguments: [String],
        preferredLanguages: [String] = Locale.preferredLanguages,
        liveCollector: () throws -> BusTopologySnapshot = { try BusProfilerCollector.collectLiveHostValidated() }
    ) -> BusCLIExecutionResult {
        let tail = Array(arguments.dropFirst())
        let fallbackLang = resolveDefaultLanguage(preferredLanguages: preferredLanguages)
        var resolvedLang = fallbackLang

        // First scan --lang to localize usage/option errors accurately, and validate --lang value if supplied
        var scanIdx = 0
        while scanIdx < tail.count {
            let token = tail[scanIdx]
            if token == "--lang" {
                guard scanIdx + 1 < tail.count else {
                    let loc = AppLocalizer(fixedLanguage: resolvedLang)
                    return BusCLIExecutionResult(
                        exitCode: 2,
                        stderr: loc.L(
                            "BusLensMac error: Missing value for '--lang' (expected 'en' or 'zh').\n",
                            "BusLensMac 错误：'--lang' 缺少语言参数（可选 'en' 或 'zh'）。\n"
                        )
                    )
                }
                let rawVal = tail[scanIdx + 1]
                guard let parsed = AppLanguage.parseCLI(rawVal) else {
                    let loc = AppLocalizer(fixedLanguage: resolvedLang)
                    return BusCLIExecutionResult(
                        exitCode: 2,
                        stderr: loc.L(
                            "BusLensMac error: Unsupported language '\(rawVal)' (expected 'en' or 'zh').\n",
                            "BusLensMac 错误：不支持的语言参数 '\(rawVal)'（可选 'en' 或 'zh'）。\n"
                        )
                    )
                }
                resolvedLang = parsed
                scanIdx += 2
                continue
            } else if token.hasPrefix("--lang=") {
                let rawVal = String(token.dropFirst("--lang=".count))
                guard let parsed = AppLanguage.parseCLI(rawVal) else {
                    let loc = AppLocalizer(fixedLanguage: resolvedLang)
                    return BusCLIExecutionResult(
                        exitCode: 2,
                        stderr: loc.L(
                            "BusLensMac error: Unsupported language '\(rawVal)' (expected 'en' or 'zh').\n",
                            "BusLensMac 错误：不支持的语言参数 '\(rawVal)'（可选 'en' 或 'zh'）。\n"
                        )
                    )
                }
                resolvedLang = parsed
            }
            scanIdx += 1
        }

        let localizer = AppLocalizer(fixedLanguage: resolvedLang)

        if tail.contains("--help") || tail.contains("-h") {
            return BusCLIExecutionResult(exitCode: 0, stdout: helpBanner(localizer))
        }

        if tail.contains("--version") || tail.contains("-v") {
            return BusCLIExecutionResult(exitCode: 0, stdout: "BusLens Mac \(versionString)\n")
        }

        if let exportIdx = tail.firstIndex(of: "--export-screenshots") {
            guard exportIdx + 1 < tail.count, !tail[exportIdx + 1].hasPrefix("-") else {
                return BusCLIExecutionResult(
                    exitCode: 2,
                    stderr: localizer.L(
                        "BusLensMac error: Missing output directory after '--export-screenshots'.\n",
                        "BusLensMac 错误：'--export-screenshots' 后缺少输出目录路径。\n"
                    )
                )
            }
            let rawOutPath = tail[exportIdx + 1]
            let outURL = URL(fileURLWithPath: rawOutPath)
            do {
                try BusScreenshotExporter.exportMarketingScreenshots(to: outURL, language: resolvedLang)
                return BusCLIExecutionResult(
                    exitCode: 0,
                    stdout: localizer.L(
                        "Exported 2x Retina [DEMO] screenshots (\(resolvedLang.rawValue)) to \(rawOutPath)\n",
                        "已导出 2x Retina [演示数据] 截图（\(resolvedLang.rawValue)）至 \(rawOutPath)\n"
                    )
                )
            } catch {
                return BusCLIExecutionResult(
                    exitCode: 1,
                    stderr: localizer.L(
                        "BusLensMac error: Failed to export screenshots: \(error.localizedDescription)\n",
                        "BusLensMac 错误：导出截图失败：\(error.localizedDescription)\n"
                    )
                )
            }
        }

        var sawCLI = false
        var subcommand: String?
        var jsonOutput = false
        var isDemo = false
        var inputPath: String?

        var i = 0
        while i < tail.count {
            let arg = tail[i]
            switch arg {
            case "--cli":
                sawCLI = true
                if i + 1 < tail.count, !tail[i + 1].hasPrefix("-") {
                    subcommand = tail[i + 1]
                    i += 2
                    continue
                }
                i += 1
            case "--json":
                jsonOutput = true
                i += 1
            case "--demo":
                isDemo = true
                i += 1
            case "--lang":
                i += 2
            case _ where arg.hasPrefix("--lang="):
                i += 1
            case "--input":
                guard i + 1 < tail.count, !tail[i + 1].hasPrefix("-") else {
                    return BusCLIExecutionResult(
                        exitCode: 2,
                        stderr: localizer.L(
                            "BusLensMac error: Missing file path after '--input'.\n",
                            "BusLensMac 错误：'--input' 后缺少 JSON 文件路径。\n"
                        )
                    )
                }
                inputPath = tail[i + 1]
                i += 2
            case _ where arg.hasPrefix("--input="):
                let val = String(arg.dropFirst("--input=".count))
                guard !val.isEmpty else {
                    return BusCLIExecutionResult(
                        exitCode: 2,
                        stderr: localizer.L(
                            "BusLensMac error: Missing file path after '--input='.\n",
                            "BusLensMac 错误：'--input=' 后缺少 JSON 文件路径。\n"
                        )
                    )
                }
                inputPath = val
                i += 1
            default:
                if arg.hasPrefix("-") {
                    return BusCLIExecutionResult(
                        exitCode: 2,
                        stderr: localizer.L(
                            "BusLensMac error: Unknown option '\(arg)'. Run with '--help' for usage.\n",
                            "BusLensMac 错误：未知选项 '\(arg)'。请使用 '--help' 查看用法。\n"
                        )
                    )
                } else if sawCLI && subcommand == nil {
                    subcommand = arg
                    i += 1
                } else {
                    return BusCLIExecutionResult(
                        exitCode: 2,
                        stderr: localizer.L(
                            "BusLensMac error: Unexpected argument '\(arg)'. Run with '--help' for usage.\n",
                            "BusLensMac 错误：多余或无法识别的参数 '\(arg)'。请使用 '--help' 查看用法。\n"
                        )
                    )
                }
            }
        }

        guard sawCLI else {
            return BusCLIExecutionResult(
                exitCode: 2,
                stderr: localizer.L(
                    "BusLensMac error: Pass '--cli topology' for command-line inspection, or '--help' for usage.\n",
                    "BusLensMac 错误：命令行模式请传入 '--cli topology'，或使用 '--help' 查看用法。\n"
                )
            )
        }

        let resolvedSub = subcommand ?? "topology"
        switch resolvedSub {
        case "topology":
            break
        case "bottlenecks":
            return BusCLIExecutionResult(
                exitCode: 1,
                stderr: localizer.L(
                    "BusLensMac error: Per-device bottleneck detection requires reading device capability descriptors from ioreg (scheduled for M1). Use '--cli topology' to inspect negotiated link speeds.\n",
                    "BusLensMac 错误：线材或集线器限速判定需从 ioreg 读取设备最高支持速率描述符（排在 M1）；请使用 '--cli topology' 查看当前协商速率。\n"
                )
            )
        default:
            return BusCLIExecutionResult(
                exitCode: 2,
                stderr: localizer.L(
                    "BusLensMac error: Unknown CLI subcommand '\(resolvedSub)'. Available subcommands: topology.\n",
                    "BusLensMac 错误：未知命令行子命令 '\(resolvedSub)'。可用子命令：topology。\n"
                )
            )
        }

        if isDemo && inputPath != nil {
            return BusCLIExecutionResult(
                exitCode: 2,
                stderr: localizer.L(
                    "BusLensMac error: Cannot combine '--demo' and '--input'.\n",
                    "BusLensMac 错误：不能同时指定 '--demo' 与 '--input'。\n"
                )
            )
        }

        let snapshot: BusTopologySnapshot
        do {
            if isDemo {
                snapshot = BusLensMonitor.preview().snapshot
            } else if let inputPath {
                let url = URL(fileURLWithPath: inputPath)
                guard let raw = try? Data(contentsOf: url) else {
                    throw BusCollectorError.unreadableInput(inputPath)
                }
                snapshot = try BusProfilerCollector.parseSystemProfilerJSONValidated(raw)
            } else {
                snapshot = try liveCollector()
            }
        } catch let err as BusCollectorError {
            return BusCLIExecutionResult(
                exitCode: 1,
                stderr: "BusLensMac: \(err.localizedMessage(localizer))\n"
            )
        } catch {
            return BusCLIExecutionResult(
                exitCode: 1,
                stderr: "BusLensMac: \(error.localizedDescription)\n"
            )
        }

        if jsonOutput {
            do {
                let jsonText = try renderTopologyJSON(snapshot: snapshot, localizer: localizer, isDemo: isDemo)
                return BusCLIExecutionResult(exitCode: 0, stdout: jsonText)
            } catch {
                return BusCLIExecutionResult(
                    exitCode: 1,
                    stderr: "BusLensMac: \(error.localizedDescription)\n"
                )
            }
        } else {
            let text = renderTopologyText(snapshot: snapshot, localizer: localizer, isDemo: isDemo)
            return BusCLIExecutionResult(exitCode: 0, stdout: text)
        }
    }

    // MARK: - Formatting

    @MainActor
    public static func renderTopologyJSON(
        snapshot: BusTopologySnapshot,
        localizer: AppLocalizer,
        isDemo: Bool
    ) throws -> String {
        let payload = BusCLITopologyJSONPayload(
            capturedAt: snapshot.capturedAt,
            language: localizer.language.rawValue,
            isDemo: isDemo,
            peakNegotiatedGbps: snapshot.peakNegotiatedGbps,
            peakNegotiatedLabel: BottleneckDiagnoser.formatSpeedGbps(snapshot.peakNegotiatedGbps, localizer: localizer),
            power: .init(
                powerSource: snapshot.power.powerSource,
                localizedBadge: snapshot.power.localizedBadge(localizer),
                negotiatedWatts: snapshot.power.negotiatedWatts,
                lowPowerMode: snapshot.power.lowPowerMode,
                lowPowerModeLabel: snapshot.power.localizedLowPowerModeLabel(localizer)
            ),
            controllers: snapshot.controllers.map { ctrl in
                .init(
                    id: ctrl.id,
                    title: ctrl.localizedTitle(localizer),
                    protocolKind: ctrl.protocolKind.localizedTitle(localizer),
                    ceilingGbps: ctrl.maxGbps,
                    ceilingLabel: ctrl.localizedMaxRateLabel(localizer),
                    negotiatedGbps: ctrl.negotiatedGbps,
                    negotiatedSpeedLabel: BottleneckDiagnoser.formatSpeedGbps(ctrl.negotiatedGbps, localizer: localizer),
                    isConnected: ctrl.isConnected,
                    deviceCount: ctrl.devices.count
                )
            },
            devices: snapshot.devices.map { dev in
                .init(
                    id: dev.id,
                    name: dev.name,
                    vendor: dev.localizedVendor(localizer),
                    busName: dev.localizedBusName(localizer),
                    protocolKind: dev.protocolKind.localizedTitle(localizer),
                    negotiatedGbps: dev.negotiatedGbps,
                    negotiatedSpeedLabel: dev.negotiatedSpeedLabel,
                    portCeilingGbps: dev.portCeilingGbps,
                    portCeilingLabel: dev.localizedPortCeilingLabel(localizer),
                    depth: dev.depth,
                    behindExternalHub: dev.behindExternalHub,
                    modeDescription: dev.localizedModeDescription(localizer),
                    verdict: dev.verdict.jsonCode,
                    verdictLabel: dev.verdict.localizedLabel(localizer),
                    diagnosticDetail: dev.localizedDiagnosticDetail(localizer)
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    @MainActor
    public static func renderTopologyText(
        snapshot: BusTopologySnapshot,
        localizer: AppLocalizer,
        isDemo: Bool
    ) -> String {
        var lines: [String] = []
        if isDemo {
            lines.append(localizer.L(
                "[DEMO] Synthetic preview topology (BusLensMonitor.preview)",
                "[演示数据] 内置合成演示拓扑 (BusLensMonitor.preview)"
            ))
        }
        let peakStr = BottleneckDiagnoser.formatSpeedGbps(snapshot.peakNegotiatedGbps, localizer: localizer)
        let lpmLabel = snapshot.power.localizedLowPowerModeLabel(localizer)
        let lpmNote = localizer.L(
            " (Low Power Mode: \(lpmLabel))",
            "（低电量模式：\(lpmLabel)）"
        )
        lines.append(localizer.L(
            "Power: \(snapshot.power.localizedBadge(localizer))\(lpmNote) | Peak Negotiated Link: \(peakStr)",
            "供电状态：\(snapshot.power.localizedBadge(localizer))\(lpmNote) | 最高协商链路：\(peakStr)"
        ))

        if snapshot.devices.isEmpty {
            lines.append(localizer.L(
                "No external Thunderbolt, USB4, or USB devices attached.",
                "当前未连接雷雳、USB4 或外置 USB 设备。"
            ))
            return lines.joined(separator: "\n") + "\n"
        }

        let rateWidth = max(10, snapshot.devices.map { displayColumnWidth($0.negotiatedSpeedLabel) }.max() ?? 10)
        let verdictWidth = max(16, snapshot.devices.map { displayColumnWidth($0.verdict.localizedLabel(localizer)) }.max() ?? 16)

        for dev in snapshot.devices {
            let rate = padRightColumns(dev.negotiatedSpeedLabel, minColumns: rateWidth)
            let state = padRightColumns(dev.verdict.localizedLabel(localizer), minColumns: verdictWidth)
            let ceiling = dev.localizedPortCeilingLabel(localizer)
            let vendor = dev.localizedVendor(localizer)
            let bus = dev.localizedBusName(localizer)
            let detail = dev.localizedDiagnosticDetail(localizer)
            let ceilingTag = localizer.L("ceiling: \(ceiling)", "上限：\(ceiling)")
            lines.append("\(rate)  [\(state)]  \(dev.name) (\(vendor)) — \(bus) (\(ceilingTag)) — \(detail)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    @MainActor
    public static func helpBanner(_ localizer: AppLocalizer) -> String {
        if localizer.isChinese {
            return """
            BusLens Mac \(versionString) — 雷雳、USB4 与 USB-C 协商速率检视工具

            用法：
              BusLensMac [--lang zh|en] [--demo]
              BusLensMac --cli topology [--json] [--input <sp.json>] [--demo] [--lang zh|en]
              BusLensMac --export-screenshots <目录> [--lang zh|en]
              BusLensMac --help | --version

            子命令：
              topology    输出当前主机（或 --input 指定样本）的总线、设备与实际协商速率

            选项：
              --json              输出结构化 JSON
              --input <路径>       解析已保存的 system_profiler -json 文件（替代实时采集）
              --demo              显式加载内置演示数据（带 [演示数据] 标记）
              --lang <zh|en>      指定输出语言（默认跟随系统语言）
              --help, -h          显示本帮助信息
              --version, -v       显示版本号
            """ + "\n"
        }
        return """
        BusLens Mac \(versionString) — Thunderbolt, USB4 & USB-C negotiated link-speed inspector

        Usage:
          BusLensMac [--lang en|zh] [--demo]
          BusLensMac --cli topology [--json] [--input <sp.json>] [--demo] [--lang en|zh]
          BusLensMac --export-screenshots <dir> [--lang en|zh]
          BusLensMac --help | --version

        Subcommands:
          topology    Inspect attached controllers, devices, and negotiated link speeds

        Options:
          --json              Emit structured JSON output
          --input <path>      Parse a saved system_profiler -json file instead of live host
          --demo              Explicitly load built-in demo topology (tagged [DEMO])
          --lang <en|zh>      Select English or Simplified Chinese output
          --help, -h          Show this help message
          --version, -v       Show version
        """ + "\n"
    }

    private static func resolveDefaultLanguage(preferredLanguages: [String]) -> AppLanguage {
        if let first = preferredLanguages.first,
           first.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("zh") {
            return .zhHans
        }
        return .en
    }

    /// Computes terminal column width without ever truncating strings.
    public static func displayColumnWidth(_ text: String) -> Int {
        var width = 0
        for scalar in text.unicodeScalars {
            if isWideScalar(scalar) {
                width += 2
            } else {
                width += 1
            }
        }
        return width
    }

    public static func padRightColumns(_ text: String, minColumns: Int) -> String {
        let current = displayColumnWidth(text)
        guard current < minColumns else { return text }
        return text + String(repeating: " ", count: minColumns - current)
    }

    private static func isWideScalar(_ scalar: UnicodeScalar) -> Bool {
        let v = scalar.value
        return (0x1100...0x115F).contains(v)
            || (0x2E80...0xA4CF).contains(v)
            || (0xAC00...0xD7A3).contains(v)
            || (0xF900...0xFAFF).contains(v)
            || (0xFE10...0xFE19).contains(v)
            || (0xFE30...0xFE6F).contains(v)
            || (0xFF01...0xFF60).contains(v)
            || (0xFFE0...0xFFE6).contains(v)
            || (0x20000...0x3FFFD).contains(v)
    }
}
