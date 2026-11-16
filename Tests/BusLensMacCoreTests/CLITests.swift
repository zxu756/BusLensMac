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
          "SPThunderboltDataType": [
            {
              "_name": "thunderboltusb4_bus_0",
              "receptacle_1_tag": {
                "current_speed_key": "40 Gb/s",
                "receptacle_id_key": "1",
                "receptacle_status_key": "receptacle_connected"
              },
              "_items": [
                {
                  "_name": "CableLimitedTBSSD",
                  "device_name_key": "CableLimitedTBSSD",
                  "vendor_name_key": "Acme",
                  "mode_key": "thunderbolt_three",
                  "route_string_key": "1",
                  "receptacle_upstream_ambiguous_tag": {
                    "current_speed_key": "20 Gb/s",
                    "receptacle_status_key": "receptacle_connected"
                  }
                }
              ]
            }
          ],
          "SPUSBHostDataType": [
            {
              "_name": "USB 3.1 Bus",
              "USBKeyLocationID": "0x01000000",
              "_items": [
                { "_name": "UnknownCeilingSSD", "USBKeyLocationID": "0x01110000", "USBDeviceKeyLinkSpeed": "480 Mb/s", "USBDeviceKeyVendorName": "Acme" },
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
            ],
            "IOThunderboltSwitch": [
                [
                    "IOObjectClass": "IOThunderboltSwitchType5",
                    "Router ID": 0,
                    "Depth": 0,
                    "Route String": 0,
                    "IORegistryEntryChildren": [
                        [
                            "IOObjectClass": "IOThunderboltPort",
                            "Socket ID": "1",
                            "Supported Link Speed": 12,
                            "Supported Link Width": 2,
                            "Link Bandwidth": 200,
                            "IORegistryEntryChildren": [
                                [
                                    "IOObjectClass": "IOThunderboltPort",
                                    "Supported Link Speed": 12,
                                    "Supported Link Width": 2,
                                    "Link Bandwidth": 200,
                                    "IORegistryEntryChildren": [
                                        [
                                            "IOObjectClass": "IOThunderboltSwitchType3",
                                            "Depth": 1,
                                            "Route String": 1,
                                            "Device Model Name": "CableLimitedTBSSD"
                                        ]
                                    ]
                                ]
                            ]
                        ]
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
        #expect(throttledPayload.devices.count == 4)
        let byName = Dictionary(uniqueKeysWithValues: throttledPayload.devices.map { ($0.name, $0) })
        #expect(byName["CableLimitedTBSSD"]?.bottleneckSegment == "cable")
        #expect(byName["UnknownCeilingSSD"]?.bottleneckSegment == "cable_or_port_indeterminate")
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
        #expect(throttledZh.stdout.contains("无法判断是线还是口"))
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
        #expect(ajazzEn.portCeilingGbps == nil)
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

    @Test("UR5: README verification row states 1 machine, 3 devices, enumeration & negotiated speed only (throttling unverified), and bcdUSB-inferred conclusions carry 'inferred' / '推断' across CLI, JSON, and GUI")
    @MainActor
    func testUR5BcdUSBInferredConclusionsAndReadmeVerificationScope() throws {
        // 1. Verify README.md and README.zh-CN.md verification rows
        let readmeEn = try String(contentsOf: Self.repoRootURL.appendingPathComponent("README.md"), encoding: .utf8)
        let readmeZh = try String(contentsOf: Self.repoRootURL.appendingPathComponent("README.zh-CN.md"), encoding: .utf8)

        let verifiedRowEn = try #require(
            readmeEn.components(separatedBy: .newlines).first { $0.contains("**Verified on real hardware**") }
        )
        #expect(verifiedRowEn.contains("1 machine"))
        #expect(verifiedRowEn.contains("3 attached devices"))
        #expect(verifiedRowEn.lowercased().contains("only"))
        #expect(verifiedRowEn.lowercased().contains("negotiated"))

        let throttlingRowEn = readmeEn.components(separatedBy: .newlines).first {
            $0.lowercased().contains("throttl") && $0.contains("Unverified on real hardware")
        }
        #expect(throttlingRowEn != nil)

        let verifiedRowZh = try #require(
            readmeZh.components(separatedBy: .newlines).first { $0.contains("**已在真机验证**") }
        )
        #expect(verifiedRowZh.contains("1 台"))
        #expect(verifiedRowZh.contains("3 台"))
        #expect(verifiedRowZh.contains("仅核对"))
        #expect(verifiedRowZh.contains("协商速率"))

        let throttlingRowZh = readmeZh.components(separatedBy: .newlines).first {
            $0.contains("限速判断") && $0.contains("未在真机验证")
        }
        #expect(throttlingRowZh != nil)

        // 2. Verify bcdUSB-inferred conclusions carry 'inferred' / '推断' in CLI text, CLI JSON, and GUI model details
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("buslens-ur5-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let spURL = tmpDir.appendingPathComponent("synthetic_ur5_sp.json")
        let ioregURL = tmpDir.appendingPathComponent("synthetic_ur5_ioreg.plist")

        let syntheticSP = """
        {
          "SPThunderboltDataType": [
            {
              "_name": "thunderboltusb4_bus_0",
              "receptacle_1_tag": {
                "current_speed_key": "40 Gb/s",
                "receptacle_id_key": "1",
                "receptacle_status_key": "receptacle_connected"
              },
              "_items": [
                {
                  "_name": "ExplicitTBThrottled",
                  "device_name_key": "ExplicitTBThrottled",
                  "vendor_name_key": "Acme",
                  "mode_key": "thunderbolt_three",
                  "route_string_key": "1",
                  "receptacle_upstream_ambiguous_tag": {
                    "current_speed_key": "20 Gb/s",
                    "receptacle_status_key": "receptacle_connected"
                  }
                }
              ]
            },
            {
              "_name": "thunderboltusb4_bus_1",
              "receptacle_1_tag": {
                "current_speed_key": "20 Gb/s",
                "receptacle_id_key": "2",
                "receptacle_status_key": "receptacle_connected"
              },
              "_items": [
                {
                  "_name": "ExplicitTBPortLimited",
                  "device_name_key": "ExplicitTBPortLimited",
                  "vendor_name_key": "Acme",
                  "mode_key": "thunderbolt_three",
                  "route_string_key": "1",
                  "receptacle_upstream_ambiguous_tag": {
                    "current_speed_key": "20 Gb/s",
                    "receptacle_status_key": "receptacle_connected"
                  }
                }
              ]
            }
          ],
          "SPUSBHostDataType": [
            {
              "_name": "USB 3.1 Bus",
              "USBKeyLocationID": "0x01000000",
              "_items": [
                { "_name": "BcdUSBThrottledDrive", "USBKeyLocationID": "0x01110000", "USBDeviceKeyLinkSpeed": "480 Mb/s", "USBDeviceKeyVendorName": "Acme" },
                { "_name": "BcdUSBNormal10GDrive", "USBKeyLocationID": "0x01210000", "USBDeviceKeyLinkSpeed": "10 Gb/s", "USBDeviceKeyVendorName": "Acme" },
                { "_name": "VerifiedHIDMouse", "USBKeyLocationID": "0x01120000", "USBDeviceKeyLinkSpeed": "12 Mb/s", "USBDeviceKeyVendorName": "Acme" }
              ]
            }
          ]
        }
        """
        try Data(syntheticSP.utf8).write(to: spURL)

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
                        ["IOObjectClass": "IOUSBHostDevice", "locationID": 0x01120000, "bcdUSB": 0x0200, "bDeviceClass": 0, "IORegistryEntryChildren": [["IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 3]]]
                    ]
                ],
                [
                    "IOObjectClass": "AppleUSB30XHCIARMPort",
                    "locationID": 0x01200000,
                    "UsbIOPort": "IOService:/AppleARMPE/Port-USB-C@1",
                    "UsbProtocol (3.x)": true,
                    "IORegistryEntryChildren": [
                        ["IOObjectClass": "IOUSBHostDevice", "locationID": 0x01210000, "bcdUSB": 0x0310, "bDeviceClass": 0, "IORegistryEntryChildren": [["IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 8]]]
                    ]
                ]
            ],
            "IOThunderboltSwitch": [
                [
                    "IOObjectClass": "IOThunderboltSwitchType5",
                    "Router ID": 0,
                    "Depth": 0,
                    "Route String": 0,
                    "IORegistryEntryChildren": [
                        [
                            "IOObjectClass": "IOThunderboltPort",
                            "Socket ID": "1",
                            "Supported Link Speed": 12,
                            "Supported Link Width": 2,
                            "Link Bandwidth": 200,
                            "IORegistryEntryChildren": [
                                [
                                    "IOObjectClass": "IOThunderboltPort",
                                    "Supported Link Speed": 12,
                                    "Supported Link Width": 2,
                                    "Link Bandwidth": 200,
                                    "IORegistryEntryChildren": [
                                        [
                                            "IOObjectClass": "IOThunderboltSwitchType3",
                                            "Depth": 1,
                                            "Route String": 1,
                                            "Device Model Name": "ExplicitTBThrottled"
                                        ]
                                    ]
                                ]
                            ]
                        ]
                    ]
                ],
                [
                    "IOObjectClass": "IOThunderboltSwitchType5",
                    "Router ID": 1,
                    "Depth": 0,
                    "Route String": 0,
                    "IORegistryEntryChildren": [
                        [
                            "IOObjectClass": "IOThunderboltPort",
                            "Socket ID": "2",
                            "Supported Link Speed": 8,
                            "Supported Link Width": 2,
                            "Link Bandwidth": 200,
                            "IORegistryEntryChildren": [
                                [
                                    "IOObjectClass": "IOThunderboltPort",
                                    "Supported Link Speed": 12,
                                    "Supported Link Width": 2,
                                    "Link Bandwidth": 200,
                                    "IORegistryEntryChildren": [
                                        [
                                            "IOObjectClass": "IOThunderboltSwitchType3",
                                            "Depth": 1,
                                            "Route String": 1,
                                            "Device Model Name": "ExplicitTBPortLimited"
                                        ]
                                    ]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]
        let ioregData = try PropertyListSerialization.data(fromPropertyList: syntheticIOReg, format: .xml, options: 0)
        try ioregData.write(to: ioregURL)

        let jsonZhRes = BusCLIRunner.execute(arguments: [
            "BusLensMac", "--cli", "topology", "--input", spURL.path, "--ioreg-input", ioregURL.path, "--json", "--lang", "zh"
        ])
        #expect(jsonZhRes.exitCode == 0)
        let rootZh = try #require(JSONSerialization.jsonObject(with: Data(jsonZhRes.stdout.utf8)) as? [String: Any])
        let devsZh = try #require(rootZh["devices"] as? [[String: Any]])
        let byNameZh = Dictionary(uniqueKeysWithValues: devsZh.compactMap { d -> (String, [String: Any])? in
            guard let n = d["name"] as? String else { return nil }
            return (n, d)
        })

        #expect((byNameZh["BcdUSBThrottledDrive"]?["isInferred"] as? Bool) == true)
        #expect((byNameZh["BcdUSBThrottledDrive"]?["verdictLabel"] as? String) == "被限速（推断）")
        #expect((byNameZh["BcdUSBThrottledDrive"]?["diagnosticDetail"] as? String)?.contains("推断") == true)

        #expect((byNameZh["BcdUSBNormal10GDrive"]?["isInferred"] as? Bool) == true)
        #expect((byNameZh["BcdUSBNormal10GDrive"]?["verdictLabel"] as? String) == "正常（推断）")
        #expect((byNameZh["BcdUSBNormal10GDrive"]?["diagnosticDetail"] as? String)?.contains("推断") == true)

        #expect((byNameZh["ExplicitTBThrottled"]?["isInferred"] as? Bool) == true)
        #expect((byNameZh["ExplicitTBThrottled"]?["verdictLabel"] as? String) == "被限速（推断）")
        #expect((byNameZh["ExplicitTBPortLimited"]?["isInferred"] as? Bool) == false)
        #expect((byNameZh["ExplicitTBPortLimited"]?["verdictLabel"] as? String) == "被限速")
        #expect((byNameZh["VerifiedHIDMouse"]?["isInferred"] as? Bool) == false)
        #expect((byNameZh["VerifiedHIDMouse"]?["verdictLabel"] as? String) == "HID / 低速外设")

        let jsonEnRes = BusCLIRunner.execute(arguments: [
            "BusLensMac", "--cli", "topology", "--input", spURL.path, "--ioreg-input", ioregURL.path, "--json", "--lang", "en"
        ])
        #expect(jsonEnRes.exitCode == 0)
        let rootEn = try #require(JSONSerialization.jsonObject(with: Data(jsonEnRes.stdout.utf8)) as? [String: Any])
        let devsEn = try #require(rootEn["devices"] as? [[String: Any]])
        let byNameEn = Dictionary(uniqueKeysWithValues: devsEn.compactMap { d -> (String, [String: Any])? in
            guard let n = d["name"] as? String else { return nil }
            return (n, d)
        })
        #expect((byNameEn["BcdUSBThrottledDrive"]?["isInferred"] as? Bool) == true)
        #expect((byNameEn["BcdUSBThrottledDrive"]?["verdictLabel"] as? String) == "Throttled (inferred)")
        #expect((byNameEn["BcdUSBNormal10GDrive"]?["isInferred"] as? Bool) == true)
        #expect((byNameEn["BcdUSBNormal10GDrive"]?["verdictLabel"] as? String) == "Normal (inferred)")
        #expect((byNameEn["ExplicitTBThrottled"]?["isInferred"] as? Bool) == true)
        #expect((byNameEn["ExplicitTBPortLimited"]?["isInferred"] as? Bool) == false)
        #expect((byNameEn["VerifiedHIDMouse"]?["isInferred"] as? Bool) == false)

        let textZhRes = BusCLIRunner.execute(arguments: [
            "BusLensMac", "--cli", "topology", "--input", spURL.path, "--ioreg-input", ioregURL.path, "--lang", "zh"
        ])
        #expect(textZhRes.stdout.contains("被限速（推断）"))
        #expect(textZhRes.stdout.contains("正常（推断）"))

        let textEnRes = BusCLIRunner.execute(arguments: [
            "BusLensMac", "--cli", "topology", "--input", spURL.path, "--ioreg-input", ioregURL.path, "--lang", "en"
        ])
        #expect(textEnRes.stdout.contains("Throttled (inferred)"))
        #expect(textEnRes.stdout.contains("Normal (inferred)"))

        let botZhRes = BusCLIRunner.execute(arguments: [
            "BusLensMac", "--cli", "bottlenecks", "--input", spURL.path, "--ioreg-input", ioregURL.path, "--lang", "zh"
        ])
        #expect(botZhRes.stdout.contains("无法判断是线还是口（推断）"))
        #expect(botZhRes.stdout.contains("推断"))

        let botEnRes = BusCLIRunner.execute(arguments: [
            "BusLensMac", "--cli", "bottlenecks", "--input", spURL.path, "--ioreg-input", ioregURL.path, "--lang", "en"
        ])
        #expect(botEnRes.stdout.contains("Cannot determine if cable or port (inferred)"))

        // Also verify GUI model methods used by BusDashboardView & BusMenuBarView device rows
        let ioregSnap = try IORegistrySnapshot.parsePlistData(ioregData)
        let snap = try BusProfilerCollector.parseSystemProfilerJSONValidated(Data(syntheticSP.utf8), ioregSnapshot: ioregSnap)
        let enLoc = AppLocalizer(fixedLanguage: .en)
        let zhLoc = AppLocalizer(fixedLanguage: .zhHans)
        let guiByName = Dictionary(uniqueKeysWithValues: snap.devices.map { ($0.name, $0) })
        #expect(guiByName["BcdUSBThrottledDrive"]?.localizedVerdictLabel(enLoc) == "Throttled (inferred)")
        #expect(guiByName["BcdUSBThrottledDrive"]?.localizedVerdictLabel(zhLoc) == "被限速（推断）")
        #expect(guiByName["BcdUSBNormal10GDrive"]?.localizedVerdictLabel(enLoc) == "Normal (inferred)")
        #expect(guiByName["BcdUSBNormal10GDrive"]?.localizedVerdictLabel(zhLoc) == "正常（推断）")
        #expect(guiByName["ExplicitTBThrottled"]?.localizedVerdictLabel(zhLoc) == "被限速（推断）")
        #expect(guiByName["ExplicitTBPortLimited"]?.localizedVerdictLabel(zhLoc) == "被限速")
        #expect(guiByName["VerifiedHIDMouse"]?.localizedVerdictLabel(zhLoc) == "HID / 低速外设")
    }

    @Test("UR6: Menu bar throttled count and dashboard physical ports carry 'inferred' / '推断' when displaying inferred conclusions, and m1-differential.sh Row 1 states what it checked and same-source ioreg keys")
    @MainActor
    func testUR6MenuBarCountDashboardPhysicalPortsAndRow1SameSourceDisclosure() throws {
        // 1. m1-differential.sh Row 1 output must disclose what it actually checked & same-source ioreg keys
        let diffScript = try String(
            contentsOf: Self.repoRootURL.appendingPathComponent("Scripts/acceptance/m1-differential.sh"),
            encoding: .utf8
        )
        let row1Idx = try #require(diffScript.range(of: "[PASS] Row 1"))
        let row1Tail = String(diffScript[row1Idx.lowerBound...].prefix(900))
        #expect(row1Tail.contains("只核对") || row1Tail.lowercased().contains("checked only"))
        #expect(row1Tail.contains("同一批 ioreg 键") || row1Tail.lowercased().contains("same ioreg keys"))
        #expect(row1Tail.contains("未验证限速") || row1Tail.lowercased().contains("0 throttled") || row1Tail.lowercased().contains("no throttling"))

        // 2. Dashboard physical port line on paired 2026-11-15 fixture:
        //    - TBU405Pro physical port comes from cross-bus Socket ID -> PortNumber inference -> carries '推断' / 'inferred'
        //    - AJAZZ AJ159 APEX physical port comes directly from AppleUSBHostPort UsbIOPort and HID class 3 -> NOT inferred
        let enLoc = AppLocalizer(fixedLanguage: .en)
        let zhLoc = AppLocalizer(fixedLanguage: .zhHans)
        let spRaw = try Data(contentsOf: Self.host20261115SPURL)
        let ioRaw = try Data(contentsOf: Self.host20261115IORegURL)
        let ioSnap = try IORegistrySnapshot.parsePlistData(ioRaw)
        let hostSnap = try BusProfilerCollector.parseSystemProfilerJSONValidated(spRaw, ioregSnapshot: ioSnap)

        let tbDev = try #require(hostSnap.devices.first { $0.name == "TBU405Pro" })
        #expect(BusDashboardView.topologyPortLine(for: tbDev, localizer: zhLoc).contains("Port-USB-C@2（推断）"))
        #expect(BusDashboardView.topologyPortLine(for: tbDev, localizer: enLoc).contains("Port-USB-C@2 (inferred)"))

        let ajazzDev = try #require(hostSnap.devices.first { $0.name == "AJAZZ AJ159 APEX" })
        #expect(BusDashboardView.topologyPortLine(for: ajazzDev, localizer: zhLoc).contains("Port-USB-C@6"))
        #expect(!BusDashboardView.topologyPortLine(for: ajazzDev, localizer: zhLoc).contains("推断"))

        // 3. Dashboard physical port line on bcdUSB-inferred USB device carries '推断' / 'inferred'
        let bcdEval = BottleneckDiagnoser.evaluate(
            protocolKind: .usbHost,
            negotiatedGbps: 0.48,
            portCeilingGbps: nil,
            behindExternalHub: false,
            capability: DeviceCapabilityDescriptor(bcdUSB: 0x0210, usbDeviceClass: 0, usbInterfaceClasses: [8])
        )
        let inferredUSBDev = AttachedBusDevice(
            id: "ur6-usb-inferred",
            name: "InferredDrive",
            vendor: "Acme",
            busName: "USB 3.1 Bus",
            physicalPort: "Port-USB-C@1",
            protocolKind: .usbHost,
            negotiatedSpeedLabel: "480 Mb/s",
            negotiatedGbps: 0.48,
            portCeilingGbps: nil,
            deviceMaxGbps: bcdEval.deviceMaxGbps,
            capability: DeviceCapabilityDescriptor(bcdUSB: 0x0210, usbDeviceClass: 0, usbInterfaceClasses: [8]),
            bottleneckSegment: bcdEval.bottleneckSegment,
            isInferred: bcdEval.isInferred,
            verdict: bcdEval.verdict,
            diagnosticDetail: bcdEval.detail
        )
        #expect(BusDashboardView.topologyPortLine(for: inferredUSBDev, localizer: zhLoc).contains("Port-USB-C@1（推断）"))
        #expect(BusDashboardView.topologyPortLine(for: inferredUSBDev, localizer: enLoc).contains("Port-USB-C@1 (inferred)"))

        // 4. Menu bar throttled badge and dashboard physical port module mark inferred conclusions
        let explicitTBThrottled = AttachedBusDevice(
            id: "ur6-tb-explicit",
            name: "ExplicitTBDrive",
            vendor: "Acme",
            busName: "Thunderbolt / USB4 Bus 0",
            physicalPort: "Port-USB-C@2",
            protocolKind: .thunderboltUSB4,
            negotiatedSpeedLabel: "20 Gb/s",
            negotiatedGbps: 20.0,
            portCeilingGbps: 20.0,
            deviceMaxGbps: 40.0,
            capability: DeviceCapabilityDescriptor(tbSupportedLinkGbps: 40.0),
            bottleneckSegment: .port,
            isInferred: false,
            isPhysicalPortInferred: true,
            verdict: .throttled,
            diagnosticDetail: "Throttled (port-limited)"
        )

        let snapPureInferred = BusTopologySnapshot(
            capturedAt: Date(),
            controllers: [
                PhysicalPortController(
                    id: "usb-c0",
                    title: "USB 3.1 Bus",
                    protocolKind: .usbHost,
                    maxGbps: nil,
                    negotiatedGbps: 0.48,
                    isConnected: true,
                    devices: [inferredUSBDev]
                )
            ],
            devices: [inferredUSBDev],
            power: PowerDeliverySummary()
        )
        #expect(BusMenuBarView.statusBadgeText(for: snapPureInferred, localizer: zhLoc) == "1 台被限速（推断）")
        #expect(BusMenuBarView.statusBadgeText(for: snapPureInferred, localizer: enLoc) == "1 throttled (inferred)")
        #expect(BusDashboardView.physicalPortModuleSubtitle(for: snapPureInferred.controllers[0], localizer: zhLoc).contains("限速（推断）"))
        #expect(BusDashboardView.physicalPortModuleSubtitle(for: snapPureInferred.controllers[0], localizer: enLoc).contains("throttled (inferred)"))

        let snapMixed = BusTopologySnapshot(
            capturedAt: Date(),
            controllers: [],
            devices: [inferredUSBDev, explicitTBThrottled],
            power: PowerDeliverySummary()
        )
        #expect(BusMenuBarView.statusBadgeText(for: snapMixed, localizer: zhLoc) == "2 台被限速（含 1 台推断）")
        #expect(BusMenuBarView.statusBadgeText(for: snapMixed, localizer: enLoc) == "2 throttled (1 inferred)")

        let snapExplicitOnly = BusTopologySnapshot(
            capturedAt: Date(),
            controllers: [
                PhysicalPortController(
                    id: "tb-b0",
                    title: "Thunderbolt / USB4 Bus 0",
                    protocolKind: .thunderboltUSB4,
                    maxGbps: 40.0,
                    negotiatedGbps: 20.0,
                    isConnected: true,
                    devices: [explicitTBThrottled]
                )
            ],
            devices: [explicitTBThrottled],
            power: PowerDeliverySummary()
        )
        #expect(BusMenuBarView.statusBadgeText(for: snapExplicitOnly, localizer: zhLoc) == "1 台被限速")
        #expect(!BusDashboardView.physicalPortModuleSubtitle(for: snapExplicitOnly.controllers[0], localizer: zhLoc).contains("推断"))
        #expect(!BusMenuBarView.statusBadgeText(for: hostSnap, localizer: zhLoc).contains("推断"))
    }

    @Test("S4 Item 5: README.zh-CN.md and docs/SPEC.md have clean single parentheses on unverified rows without nested '（尚未在真机上验证（仅合成样本测试））'")
    func testS4ChineseReadmeAndSpecHaveNoNestedUnverifiedParentheses() throws {
        let readmeZh = try String(contentsOf: Self.repoRootURL.appendingPathComponent("README.zh-CN.md"), encoding: .utf8)
        let specMd = try String(contentsOf: Self.repoRootURL.appendingPathComponent("docs/SPEC.md"), encoding: .utf8)

        #expect(!readmeZh.contains("（尚未在真机上验证（仅合成样本测试））"))
        #expect(!specMd.contains("（尚未在真机上验证（仅合成样本测试））"))
        #expect(readmeZh.contains("**未在真机验证（仅合成样本测试）**"))
    }
}
