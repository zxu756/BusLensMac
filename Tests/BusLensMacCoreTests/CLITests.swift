import Foundation
import MachO
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

    private static var host20261115SPURL: URL {
        repoRootURL.appendingPathComponent("Tests/BusLensMacTests/Fixtures/host_macmini_20261115_sp_scrubbed.json")
    }

    private static var host20261115IORegURL: URL {
        repoRootURL.appendingPathComponent("Tests/BusLensMacTests/Fixtures/host_macmini_20261115_ioreg_scrubbed.plist")
    }

    private static func resolveBuiltExecutableURL() throws -> URL {
        let fm = FileManager.default
        if let envBin = ProcessInfo.processInfo.environment["BUSLENS_BIN"],
           !envBin.isEmpty,
           fm.isExecutableFile(atPath: envBin) {
            return URL(fileURLWithPath: envBin)
        }

        var candidateSeeds: [URL] = Bundle.allBundles.map(\.bundleURL)
        for arg in CommandLine.arguments where arg.contains("/") {
            candidateSeeds.append(URL(fileURLWithPath: arg))
        }
        let imageCount = _dyld_image_count()
        for idx in 0..<imageCount {
            if let cPath = _dyld_get_image_name(idx) {
                let path = String(cString: cPath)
                if path.contains("BusLensMac") {
                    candidateSeeds.append(URL(fileURLWithPath: path))
                }
            }
        }

        for seed in candidateSeeds {
            var dir = seed.standardizedFileURL
            for _ in 0..<5 {
                dir = dir.deletingLastPathComponent()
                if dir.path == "/" || dir.path.isEmpty { break }
                let sibling = dir.appendingPathComponent("BusLensMac")
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: sibling.path, isDirectory: &isDir),
                   !isDir.boolValue,
                   fm.isExecutableFile(atPath: sibling.path) {
                    return sibling
                }
            }
        }

        throw NSError(
            domain: "BusLensMac.CLITests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate built BusLensMac binary in active SwiftPM products directory"]
        )
    }

    private static func runBinary(_ args: [String]) throws -> (code: Int32, stdout: String, stderr: String) {
        let proc = Process()
        proc.executableURL = try resolveBuiltExecutableURL()
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

    @Test("Rule 3 & M1: --cli bottlenecks requires ioreg descriptors when --input is used, and reports cable/hub/port bottlenecks when paired")
    @MainActor
    func testBottlenecksSubcommandAndInvalidInput() throws {
        // Without --ioreg-input, offline --input system_profiler JSON lacks USB capability descriptors -> exitCode 1
        let enNoIOReg = BusCLIRunner.execute(arguments: [
            "BusLensMac", "--cli", "bottlenecks", "--input", Self.hostFixtureURL.path, "--lang", "en"
        ])
        #expect(enNoIOReg.exitCode == 1)
        #expect(enNoIOReg.stdout.isEmpty)
        #expect(enNoIOReg.stderr.contains("--ioreg-input"))

        let zhNoIOReg = BusCLIRunner.execute(arguments: [
            "BusLensMac", "--cli", "bottlenecks", "--input", Self.hostFixtureURL.path, "--lang", "zh"
        ])
        #expect(zhNoIOReg.exitCode == 1)
        #expect(zhNoIOReg.stdout.isEmpty)
        #expect(zhNoIOReg.stderr.contains("--ioreg-input"))

        // Paired healthy 2026-11-15 Mac mini fixture -> exitCode 0, 0 throttled links
        let healthyEn = BusCLIRunner.execute(arguments: [
            "BusLensMac", "--cli", "bottlenecks",
            "--input", Self.host20261115SPURL.path,
            "--ioreg-input", Self.host20261115IORegURL.path,
            "--json", "--lang", "en"
        ])
        #expect(healthyEn.exitCode == 0)
        #expect(healthyEn.stderr.isEmpty)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let healthyPayload = try decoder.decode(BusCLITopologyJSONPayload.self, from: Data(healthyEn.stdout.utf8))
        #expect(healthyPayload.devices.isEmpty)

        // Synthetic throttled fixture (cable + hub + port bottlenecks) via --cli bottlenecks --json & text
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("buslens-cli-m1-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let spSyntheticURL = tmpDir.appendingPathComponent("synthetic_sp.json")
        let ioregSyntheticURL = tmpDir.appendingPathComponent("synthetic_ioreg.plist")

        let syntheticSP = """
        {
          "SPUSBHostDataType": [
            {
              "_name": "USB 3.1 Bus",
              "USBKeyLocationID": "0x01000000",
              "_items": [
                { "_name": "CableLimitedSSD", "USBKeyLocationID": "0x01110000", "USBDeviceKeyLinkSpeed": "480 Mb/s", "USBDeviceKeyVendorName": "Acme" },
                {
                  "_name": "USB2 Hub",
                  "USBKeyLocationID": "0x01120000",
                  "USBDeviceKeyLinkSpeed": "480 Mb/s",
                  "USBDeviceKeyVendorName": "Generic",
                  "_items": [
                    { "_name": "HubLimitedSSD", "USBKeyLocationID": "0x01121000", "USBDeviceKeyLinkSpeed": "480 Mb/s", "USBDeviceKeyVendorName": "Acme" }
                  ]
                },
                { "_name": "PortLimitedSSD", "USBKeyLocationID": "0x02100000", "USBDeviceKeyLinkSpeed": "480 Mb/s", "USBDeviceKeyVendorName": "Acme" }
              ]
            }
          ]
        }
        """
        try Data(syntheticSP.utf8).write(to: spSyntheticURL)

        let syntheticIOReg: [String: Any] = [
            "AppleUSBHostPort": [
                [
                    "IOObjectClass": "AppleUSB20XHCIARMPort",
                    "locationID": 0x01100000,
                    "UsbIOPort": "IOService:/AppleARMPE/Port-USB-C@1",
                    "UsbProtocol (2.0)": true,
                    "UsbProtocolCompanion (3.x)": "IOService:/usb-ss@01200000",
                    "IORegistryEntryChildren": [
                        ["IOObjectClass": "IOUSBHostDevice", "locationID": 0x01110000, "bcdUSB": 0x0210, "bDeviceClass": 0, "IORegistryEntryChildren": [["IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 8]]],
                        [
                            "IOObjectClass": "IOUSBHostDevice",
                            "locationID": 0x01120000,
                            "bcdUSB": 0x0200,
                            "bDeviceClass": 9,
                            "UsbLinkSpeed": 480_000_000,
                            "IORegistryEntryChildren": [
                                ["IOObjectClass": "IOUSBHostDevice", "locationID": 0x01121000, "bcdUSB": 0x0210, "bDeviceClass": 0, "IORegistryEntryChildren": [["IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 8]]]
                            ]
                        ]
                    ]
                ],
                [
                    "IOObjectClass": "AppleUSB20XHCIPort",
                    "locationID": 0x02100000,
                    "UsbIOPort": "IOService:/AppleARMPE/Port-USB-A@1",
                    "UsbProtocol (2.0)": true,
                    "IORegistryEntryChildren": [
                        ["IOObjectClass": "IOUSBHostDevice", "locationID": 0x02100000, "bcdUSB": 0x0210, "bDeviceClass": 0, "IORegistryEntryChildren": [["IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 8]]]
                    ]
                ]
            ]
        ]
        let ioregData = try PropertyListSerialization.data(fromPropertyList: syntheticIOReg, format: .xml, options: 0)
        try ioregData.write(to: ioregSyntheticURL)

        let throttledJSON = BusCLIRunner.execute(arguments: [
            "BusLensMac", "--cli", "bottlenecks",
            "--input", spSyntheticURL.path,
            "--ioreg-input", ioregSyntheticURL.path,
            "--json", "--lang", "en"
        ])
        #expect(throttledJSON.exitCode == 0)
        let throttledPayload = try decoder.decode(BusCLITopologyJSONPayload.self, from: Data(throttledJSON.stdout.utf8))
        #expect(throttledPayload.devices.count == 3)
        let byName = Dictionary(uniqueKeysWithValues: throttledPayload.devices.map { ($0.name, $0) })
        #expect(byName["CableLimitedSSD"]?.bottleneckSegment == "cable")
        #expect(byName["HubLimitedSSD"]?.bottleneckSegment == "hub")
        #expect(byName["PortLimitedSSD"]?.bottleneckSegment == "port")

        let throttledZh = BusCLIRunner.execute(arguments: [
            "BusLensMac", "--cli", "bottlenecks",
            "--input", spSyntheticURL.path,
            "--ioreg-input", ioregSyntheticURL.path,
            "--lang", "zh"
        ])
        #expect(throttledZh.exitCode == 0)
        #expect(throttledZh.stdout.contains("线缆限速"))
        #expect(throttledZh.stdout.contains("集线器限速"))
        #expect(throttledZh.stdout.contains("端口限速"))

        let missingInput = BusCLIRunner.execute(arguments: [
            "BusLensMac", "--cli", "topology", "--input", "/nonexistent/buslens-missing.json", "--lang", "en"
        ])
        #expect(missingInput.exitCode == 1)
        #expect(missingInput.stdout.isEmpty)
        #expect(missingInput.stderr.contains("Cannot read input file"))

        let missingIOReg = BusCLIRunner.execute(arguments: [
            "BusLensMac", "--cli", "topology",
            "--input", Self.host20261115SPURL.path,
            "--ioreg-input", "/nonexistent/buslens-missing.plist",
            "--lang", "en"
        ])
        #expect(missingIOReg.exitCode == 1)
        #expect(missingIOReg.stdout.isEmpty)
    }

    @Test("U6, U8, U14 & M1: CLI topology supports --json & --ioreg-input in EN & ZH, maps physical ports, and never truncates HID peripheral label")
    func testCLITopologyJSONAndNoLabelTruncation() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // 1. Pure system_profiler JSON (without --ioreg-input): 12 Mb/s without bInterfaceClass is Indeterminate (U14)
        let jsonPureEn = try Self.runBinary([
            "--cli", "topology",
            "--input", Self.hostFixtureURL.path,
            "--json",
            "--lang", "en"
        ])
        #expect(jsonPureEn.code == 0)
        #expect(jsonPureEn.stderr.isEmpty)
        let pureEn = try decoder.decode(BusCLITopologyJSONPayload.self, from: Data(jsonPureEn.stdout.utf8))
        #expect(pureEn.isDemo == false)
        #expect(pureEn.language == "en")
        #expect(pureEn.devices.count == 3)
        let pureAjazz = try #require(pureEn.devices.first { $0.name == "AJAZZ AJ159 APEX" })
        #expect(pureAjazz.verdict == "indeterminate")
        #expect(pureAjazz.verdictLabel == "Indeterminate")

        // 2. Paired 2026-11-15 real Mac mini system_profiler + ioreg fixture (EN & ZH)
        let jsonEn = try Self.runBinary([
            "--cli", "topology",
            "--input", Self.host20261115SPURL.path,
            "--ioreg-input", Self.host20261115IORegURL.path,
            "--json",
            "--lang", "en"
        ])
        #expect(jsonEn.code == 0)
        #expect(jsonEn.stderr.isEmpty)
        let payloadEn = try decoder.decode(BusCLITopologyJSONPayload.self, from: Data(jsonEn.stdout.utf8))
        #expect(payloadEn.devices.count == 2)
        let tbEn = try #require(payloadEn.devices.first { $0.name == "TBU405Pro" })
        #expect(tbEn.physicalPort == "Port-USB-C@2")
        #expect(tbEn.deviceMaxGbps == 40.0)
        #expect(tbEn.verdict == "full_rate")
        let ajazzEn = try #require(payloadEn.devices.first { $0.name == "AJAZZ AJ159 APEX" })
        #expect(ajazzEn.physicalPort == "Port-USB-C@6")
        #expect(ajazzEn.locationID == "0x02120000")
        #expect(ajazzEn.portCeilingGbps == 10.0)
        #expect(ajazzEn.behindExternalHub == false)
        #expect(ajazzEn.verdict == "low_speed_peripheral")
        #expect(ajazzEn.verdictLabel == "HID peripheral")

        let jsonZh = try Self.runBinary([
            "--cli", "topology",
            "--input", Self.host20261115SPURL.path,
            "--ioreg-input", Self.host20261115IORegURL.path,
            "--json",
            "--lang", "zh"
        ])
        #expect(jsonZh.code == 0)
        let payloadZh = try decoder.decode(BusCLITopologyJSONPayload.self, from: Data(jsonZh.stdout.utf8))
        #expect(payloadZh.language == "zh-Hans")
        let tbZh = try #require(payloadZh.devices.first { $0.name == "TBU405Pro" })
        #expect(tbZh.verdictLabel == "满速")
        let ajazzZh = try #require(payloadZh.devices.first { $0.name == "AJAZZ AJ159 APEX" })
        #expect(ajazzZh.verdictLabel == "HID / 低速外设")

        let textEn = try Self.runBinary([
            "--cli", "topology",
            "--input", Self.host20261115SPURL.path,
            "--ioreg-input", Self.host20261115IORegURL.path,
            "--lang", "en"
        ])
        #expect(textEn.code == 0)
        #expect(textEn.stdout.contains("[HID peripheral"))
        #expect(textEn.stdout.contains("[Port-USB-C@2]"))
        #expect(textEn.stdout.contains("[Port-USB-C@6]"))

        let textZh = try Self.runBinary([
            "--cli", "topology",
            "--input", Self.host20261115SPURL.path,
            "--ioreg-input", Self.host20261115IORegURL.path,
            "--lang", "zh"
        ])
        #expect(textZh.code == 0)
        #expect(textZh.stdout.contains("HID / 低速外设"))
        #expect(textZh.stdout.contains("[Port-USB-C@2]"))
        #expect(textZh.stdout.contains("[Port-USB-C@6]"))
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
