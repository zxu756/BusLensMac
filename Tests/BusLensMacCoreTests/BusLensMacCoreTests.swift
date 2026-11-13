import Foundation
import Testing
@testable import BusLensMacCore

@Suite("BusLensMacCore Verification Suite")
struct BusLensMacCoreTests {

    @Test("Parses macOS Thunderbolt & USB link speed strings into Gbps")
    func testSpeedParsing() {
        #expect(BottleneckDiagnoser.parseSpeedGbps("Up to 40 Gb/s") == 40.0)
        #expect(BottleneckDiagnoser.parseSpeedGbps("80 Gb/sec") == 80.0)
        #expect(BottleneckDiagnoser.parseSpeedGbps("10 Gb/s") == 10.0)
        #expect(BottleneckDiagnoser.parseSpeedGbps("Up to 480 Mb/sec") == 0.48)
        #expect(BottleneckDiagnoser.parseSpeedGbps("12 Mb/s") == 0.012)
    }

    @Test("Flags NVMe SSD on USB 2.0 charge cable or 10G hub while passing HID keyboards")
    func testBottleneckDiagnostics() {
        let usb2Trap = BottleneckDiagnoser.evaluateDevice(
            name: "Portable SSD X9 Pro",
            vendor: "Crucial",
            protocolKind: .usbHost,
            negotiatedGbps: 0.48,
            portCeilingGbps: 40.0,
            behindHub: false
        )
        #expect(usb2Trap.verdict == .cableOrHubBottleneck)

        let hub10G = BottleneckDiagnoser.evaluateDevice(
            name: "ASM2464PD USB4 NVMe Enclosure",
            vendor: "ASMedia",
            protocolKind: .usbHost,
            negotiatedGbps: 10.0,
            portCeilingGbps: 40.0,
            behindHub: true
        )
        #expect(hub10G.verdict == .cableOrHubBottleneck)

        let fullTB = BottleneckDiagnoser.evaluateDevice(
            name: "TBU405Pro",
            vendor: "ACASIS",
            protocolKind: .thunderboltUSB4,
            negotiatedGbps: 40.0,
            portCeilingGbps: 40.0,
            behindHub: false
        )
        #expect(fullTB.verdict == .optimalTunnel)

        let hidKB = BottleneckDiagnoser.evaluateDevice(
            name: "60HE Analog Keyboard",
            vendor: "Wooting",
            protocolKind: .usbHost,
            negotiatedGbps: 0.48,
            portCeilingGbps: 10.0,
            behindHub: true
        )
        #expect(hidKB.verdict == .hidOptimal)
    }

    @Test("Parses SPThunderboltDataType & SPUSBHostDataType JSON and scrubs serials/UUIDs")
    func testSystemProfilerJSONAndRedaction() throws {
        let sampleJSON = """
        {
          "SPThunderboltDataType": [
            {
              "_name": "thunderboltusb4_bus_1",
              "domain_uuid_key": "SECRET-UUID-9999",
              "switch_uid_key": "0x0011223344556677",
              "receptacle_1_tag": {
                "current_speed_key": "40 Gb/s",
                "receptacle_status_key": "receptacle_connected"
              },
              "_items": [
                {
                  "_name": "TBU405Pro",
                  "device_name_key": "TBU405Pro",
                  "vendor_name_key": "ACASIS",
                  "mode_key": "thunderbolt_3"
                }
              ]
            }
          ],
          "SPUSBHostDataType": [
            {
              "_name": "USB 3.1 Bus",
              "_items": [
                {
                  "_name": "USB2 Hub",
                  "USBDeviceKeyLinkSpeed": "480 Mb/s",
                  "_items": [
                    {
                      "_name": "Portable SSD T7",
                      "USBDeviceKeyVendorName": "Samsung",
                      "USBDeviceKeyLinkSpeed": "480 Mb/s",
                      "USBDeviceKeySerialNumber": "S6XPNS0T123456"
                    }
                  ]
                }
              ]
            }
          ],
          "SPPowerDataType": [
            {
              "sppower_ac_charger_watts": "96"
            }
          ]
        }
        """
        let rawData = Data(sampleJSON.utf8)
        let rawObj = try JSONSerialization.jsonObject(with: rawData)
        let redactedData = try JSONSerialization.data(withJSONObject: BusProfilerCollector.redactHardwareIdentifiers(rawObj))
        let redactedText = String(decoding: redactedData, as: UTF8.self)
        #expect(!redactedText.contains("SECRET-UUID-9999"))
        #expect(!redactedText.contains("S6XPNS0T123456"))

        let snap = BusProfilerCollector.parseSystemProfilerJSON(rawData)
        #expect(snap.activeTunnelCount == 1)
        #expect(snap.bottleneckDevices.count == 1)
        #expect(snap.bottleneckDevices.first?.name == "Portable SSD T7")
        #expect(snap.power.negotiatedWatts == 96)
    }

    @Test("Renders 2x Retina marketing screenshots cleanly")
    @MainActor
    func testScreenshotExport() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("BusLensShots-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: dir) }

        try BusScreenshotExporter.exportMarketingScreenshots(to: dir)
        let mainBytes = try Data(contentsOf: dir.appendingPathComponent("screenshot-main.png"))
        let menuBytes = try Data(contentsOf: dir.appendingPathComponent("screenshot-menubar.png"))
        #expect(mainBytes.count > 25_000)
        #expect(menuBytes.count > 10_000)
    }

    @Test("Toggles live between zh-Hans and en and localizes link verdicts & cable diagnostics")
    @MainActor
    func testLiveLanguageToggleAndDiagnostics() {
        let suiteName = "BusLensMacTests.Toggle.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let localizer = AppLocalizer(
            arguments: [],
            userDefaults: defaults,
            preferenceKey: AppLocalizer.defaultPreferenceKey,
            preferredLanguages: ["en-US"]
        )
        #expect(localizer.language == .en)
        #expect(LinkHealthVerdict.cableOrHubBottleneck.localizedLabel(localizer) == "Cable or hub bottleneck")

        localizer.toggle()
        #expect(localizer.language == .zhHans)
        #expect(defaults.string(forKey: AppLocalizer.defaultPreferenceKey) == "zh-Hans")
        #expect(LinkHealthVerdict.cableOrHubBottleneck.localizedLabel(localizer) == "线材或扩展坞瓶颈")
        #expect(LinkHealthVerdict.optimalTunnel.localizedLabel(localizer) == "满速 PCIe / USB4 隧道")

        let preview = BusLensMonitor.preview()
        let throttled = preview.snapshot.bottleneckDevices.first { $0.negotiatedGbps <= 0.5 }!
        #expect(throttled.localizedDiagnosticDetail(localizer).contains("USB 2.0 (480 Mb/s)"))
        #expect(throttled.localizedDiagnosticDetail(localizer).contains("40 Gb/s"))

        localizer.toggle()
        #expect(localizer.language == .en)
        #expect(defaults.string(forKey: AppLocalizer.defaultPreferenceKey) == "en")
    }

    @Test("Auto-detects Chinese system locale, respects UserDefaults & --lang flag, and preserves EN screenshots")
    @MainActor
    func testChineseLocaleAutoDetectCLIFlagAndChineseScreenshots() throws {
        let suiteName = "BusLensMacTests.Locale.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let autoZh = AppLocalizer(
            arguments: ["BusLensMac"],
            userDefaults: defaults,
            preferenceKey: AppLocalizer.defaultPreferenceKey,
            preferredLanguages: ["zh-Hans-CN", "en-US"]
        )
        #expect(autoZh.language == .zhHans)
        #expect(autoZh.L("Rescan", "重新探测") == "重新探测")

        defaults.set("en", forKey: AppLocalizer.defaultPreferenceKey)
        let savedEn = AppLocalizer(
            arguments: ["BusLensMac"],
            userDefaults: defaults,
            preferenceKey: AppLocalizer.defaultPreferenceKey,
            preferredLanguages: ["zh-Hans-CN"]
        )
        #expect(savedEn.language == .en)

        let cliZh = AppLocalizer(
            arguments: ["BusLensMac", "--lang", "zh"],
            userDefaults: defaults,
            preferenceKey: AppLocalizer.defaultPreferenceKey,
            preferredLanguages: ["en-US"]
        )
        #expect(cliZh.language == .zhHans)
        #expect(AppLocalizer.resolveCLILanguage(from: ["BusLensMac", "--lang=en"]) == .en)

        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("BusLensZhShots-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let sentinel = Data("sentinel-en".utf8)
        let enPath = dir.appendingPathComponent("screenshot-main.png")
        try sentinel.write(to: enPath)

        try BusScreenshotExporter.exportMarketingScreenshots(to: dir, language: .zhHans)
        let zhMain = try Data(contentsOf: dir.appendingPathComponent("screenshot-main-zh.png"))
        let zhMenu = try Data(contentsOf: dir.appendingPathComponent("screenshot-menubar-zh.png"))
        let preservedEn = try Data(contentsOf: enPath)
        #expect(zhMain.count > 25_000)
        #expect(zhMenu.count > 10_000)
        #expect(preservedEn == sentinel)
    }
}
