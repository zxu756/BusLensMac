import Foundation
import Testing
@testable import BusLensMacCore

@Suite("CLI Verification", .timeLimit(.minutes(1)))
struct CLITests {

    private static var repoRootURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static var hostFixtureURL: URL {
        repoRootURL.appendingPathComponent("Tests/BusLensMacTests/Fixtures/host_macmini_scrubbed.json")
    }

    private static var debugBinaryURL: URL {
        repoRootURL.appendingPathComponent(".build/debug/BusLensMac")
    }

    private static func runBinary(_ args: [String]) throws -> (code: Int32, stdout: String, stderr: String) {
        let proc = Process()
        proc.executableURL = debugBinaryURL
        proc.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        try proc.run()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return (
            proc.terminationStatus,
            String(decoding: outData, as: UTF8.self),
            String(decoding: errData, as: UTF8.self)
        )
    }

    @Test("U6 / Row 2: Unknown CLI subcommand and invalid options exit with code 2 and empty stdout in EN and ZH")
    func testUnknownSubcommandAndOptionsExitWithCode2() throws {
        let en = try Self.runBinary(["--cli", "bogus", "--lang", "en"])
        #expect(en.code == 2)
        #expect(en.stdout.isEmpty)
        #expect(en.stderr.contains("Unknown CLI subcommand 'bogus'"))

        let zh = try Self.runBinary(["--cli", "bogus", "--lang", "zh"])
        #expect(zh.code == 2)
        #expect(zh.stdout.isEmpty)
        #expect(zh.stderr.contains("未知命令行子命令 'bogus'"))

        let badOpt = try Self.runBinary(["--cli", "topology", "--nosuchflag", "--lang", "en"])
        #expect(badOpt.code == 2)
        #expect(badOpt.stdout.isEmpty)
        #expect(badOpt.stderr.contains("--nosuchflag"))

        let badLang = try Self.runBinary(["--cli", "topology", "--lang", "martian"])
        #expect(badLang.code == 2)
        #expect(badLang.stdout.isEmpty)
    }

    @Test("Rule 3: Unimplemented --cli bottlenecks and unreadable/corrupt --input return exit code 1 with honest error")
    @MainActor
    func testUnimplementedBottlenecksAndInvalidInputReturnExitCode1() {
        let enBottlenecks = BusCLIRunner.execute(arguments: ["BusLensMac", "--cli", "bottlenecks", "--lang", "en"])
        #expect(enBottlenecks.exitCode == 1)
        #expect(enBottlenecks.stdout.isEmpty)
        #expect(enBottlenecks.stderr.contains("ioreg"))
        #expect(enBottlenecks.stderr.contains("M1"))

        let zhBottlenecks = BusCLIRunner.execute(arguments: ["BusLensMac", "--cli", "bottlenecks", "--lang", "zh"])
        #expect(zhBottlenecks.exitCode == 1)
        #expect(zhBottlenecks.stdout.isEmpty)
        #expect(zhBottlenecks.stderr.contains("ioreg"))
        #expect(zhBottlenecks.stderr.contains("M1"))

        let missingInput = BusCLIRunner.execute(arguments: [
            "BusLensMac", "--cli", "topology", "--input", "/nonexistent/buslens-missing.json", "--lang", "en"
        ])
        #expect(missingInput.exitCode == 1)
        #expect(missingInput.stdout.isEmpty)
        #expect(missingInput.stderr.contains("Cannot read input file"))
    }

    @Test("U6 & U8: CLI topology supports --json in EN & ZH and never truncates HID / low-latency peripheral label")
    func testCLITopologyJSONAndNoLabelTruncation() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let jsonEn = try Self.runBinary([
            "--cli", "topology",
            "--input", Self.hostFixtureURL.path,
            "--json",
            "--lang", "en"
        ])
        #expect(jsonEn.code == 0)
        #expect(jsonEn.stderr.isEmpty)
        let payloadEn = try decoder.decode(BusCLITopologyJSONPayload.self, from: Data(jsonEn.stdout.utf8))
        #expect(payloadEn.isDemo == false)
        #expect(payloadEn.language == "en")
        #expect(payloadEn.devices.count == 3)
        let wootingEn = try #require(payloadEn.devices.first { $0.name == "Wooting 60HE v2" })
        #expect(wootingEn.portCeilingGbps == nil)
        #expect(wootingEn.portCeilingLabel == "Unknown")
        #expect(wootingEn.behindExternalHub == false)
        #expect(wootingEn.verdictLabel == "HID / low-latency peripheral")

        let jsonZh = try Self.runBinary([
            "--cli", "topology",
            "--input", Self.hostFixtureURL.path,
            "--json",
            "--lang", "zh"
        ])
        #expect(jsonZh.code == 0)
        let payloadZh = try decoder.decode(BusCLITopologyJSONPayload.self, from: Data(jsonZh.stdout.utf8))
        #expect(payloadZh.language == "zh-Hans")
        let wootingZh = try #require(payloadZh.devices.first { $0.name == "Wooting 60HE v2" })
        #expect(wootingZh.portCeilingLabel == "未知")
        #expect(wootingZh.verdictLabel == "低速外设（正常）")

        let textEn = try Self.runBinary([
            "--cli", "topology",
            "--input", Self.hostFixtureURL.path,
            "--lang", "en"
        ])
        #expect(textEn.code == 0)
        #expect(textEn.stdout.contains("[HID / low-latency peripheral]"))
        #expect(!textEn.stdout.contains("HID / low-latenc]"))
        #expect(textEn.stdout.contains("ceiling: Unknown"))

        let textZh = try Self.runBinary([
            "--cli", "topology",
            "--input", Self.hostFixtureURL.path,
            "--lang", "zh"
        ])
        #expect(textZh.code == 0)
        #expect(textZh.stdout.contains("低速外设（正常）"))
        #expect(textZh.stdout.contains("上限：未知"))
    }

    @Test("Rule 2: Explicit --demo marks CLI text and JSON outputs with [DEMO] / [演示数据], help & version exit 0")
    @MainActor
    func testExplicitDemoAndHelpVersion() throws {
        let demoEn = BusCLIRunner.execute(arguments: ["BusLensMac", "--cli", "topology", "--demo", "--lang", "en"])
        #expect(demoEn.exitCode == 0)
        #expect(demoEn.stdout.hasPrefix("[DEMO]"))

        let demoZh = BusCLIRunner.execute(arguments: ["BusLensMac", "--cli", "topology", "--demo", "--lang", "zh"])
        #expect(demoZh.exitCode == 0)
        #expect(demoZh.stdout.hasPrefix("[演示数据]"))

        let demoJSON = BusCLIRunner.execute(arguments: ["BusLensMac", "--cli", "topology", "--demo", "--json", "--lang", "en"])
        #expect(demoJSON.exitCode == 0)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let parsed = try decoder.decode(BusCLITopologyJSONPayload.self, from: Data(demoJSON.stdout.utf8))
        #expect(parsed.isDemo == true)

        let helpEn = BusCLIRunner.execute(arguments: ["BusLensMac", "--help", "--lang", "en"])
        #expect(helpEn.exitCode == 0)
        #expect(helpEn.stdout.contains("--cli topology"))

        let helpZh = BusCLIRunner.execute(arguments: ["BusLensMac", "--help", "--lang", "zh"])
        #expect(helpZh.exitCode == 0)
        #expect(helpZh.stdout.contains("子命令"))

        let ver = BusCLIRunner.execute(arguments: ["BusLensMac", "--version"])
        #expect(ver.exitCode == 0)
        #expect(ver.stdout.contains("0.2.0"))
    }
}
