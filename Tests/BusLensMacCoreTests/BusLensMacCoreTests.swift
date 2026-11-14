import Foundation
import Testing
@testable import BusLensMacCore

@Suite("BusLensMacCore Verification Suite", .timeLimit(.minutes(1)))
struct BusLensMacCoreTests {

    @Test("Parses macOS Thunderbolt & USB link speed strings into Gbps")
    func testSpeedParsing() {
        #expect(BottleneckDiagnoser.parseSpeedGbps("Up to 40 Gb/s") == 40.0)
        #expect(BottleneckDiagnoser.parseSpeedGbps("80 Gb/sec") == 80.0)
        #expect(BottleneckDiagnoser.parseSpeedGbps("10 Gb/s") == 10.0)
        #expect(BottleneckDiagnoser.parseSpeedGbps("Up to 480 Mb/sec") == 0.48)
        #expect(BottleneckDiagnoser.parseSpeedGbps("12 Mb/s") == 0.012)
    }

    @Test("Evaluates negotiated link speeds honestly without guessing device capability from product names")
    func testBottleneckDiagnostics() {
        let usb2Drive = BottleneckDiagnoser.evaluateDevice(
            name: "Portable SSD X9 Pro",
            vendor: "Crucial",
            protocolKind: .usbHost,
            negotiatedGbps: 0.48,
            portCeilingGbps: nil,
            behindHub: false
        )
        #expect(usb2Drive.verdict == .indeterminate)
        #expect(usb2Drive.detail.contains("cannot determine"))

        let usb10GEnclosure = BottleneckDiagnoser.evaluateDevice(
            name: "ASM2464PD USB4 NVMe Enclosure",
            vendor: "ASMedia",
            protocolKind: .usbHost,
            negotiatedGbps: 10.0,
            portCeilingGbps: nil,
            behindHub: true
        )
        #expect(usb10GEnclosure.verdict == .indeterminate)
        #expect(usb10GEnclosure.detail.contains("cannot determine"))

        let fullTB = BottleneckDiagnoser.evaluateDevice(
            name: "TBU405Pro",
            vendor: "ACASIS",
            protocolKind: .thunderboltUSB4,
            negotiatedGbps: 40.0,
            portCeilingGbps: 40.0,
            behindHub: false
        )
        #expect(fullTB.verdict == .fullRate)

        let hidKB = BottleneckDiagnoser.evaluateDevice(
            name: "60HE Analog Keyboard",
            vendor: "Wooting",
            protocolKind: .usbHost,
            negotiatedGbps: 0.48,
            portCeilingGbps: nil,
            behindHub: true
        )
        #expect(hidKB.verdict == .lowSpeedPeripheral)
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
        #expect(snap.bottleneckDevices.isEmpty)
        let t7 = try #require(snap.devices.first { $0.name == "Portable SSD T7" })
        #expect(t7.verdict == .indeterminate)
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
        let store = InMemoryPreferenceStore()

        let localizer = AppLocalizer(
            arguments: [],
            preferenceStore: store,
            preferenceKey: AppLocalizer.defaultPreferenceKey,
            preferredLanguages: ["en-US"]
        )
        #expect(localizer.language == .en)
        #expect(LinkHealthVerdict.indeterminate.localizedLabel(localizer) == "Cannot determine if throttled")

        localizer.toggle()
        #expect(localizer.language == .zhHans)
        #expect(store.string(forKey: AppLocalizer.defaultPreferenceKey) == "zh-Hans")
        #expect(LinkHealthVerdict.indeterminate.localizedLabel(localizer) == "无法判断是否被限速")
        #expect(LinkHealthVerdict.fullRate.localizedLabel(localizer) == "满速")
        #expect(LinkHealthVerdict.lowSpeedPeripheral.localizedLabel(localizer) == "低速外设（正常）")

        let preview = BusLensMonitor.preview()
        let usb480 = preview.snapshot.indeterminateDevices.first { $0.negotiatedGbps <= 0.5 }!
        #expect(usb480.localizedDiagnosticDetail(localizer).contains("480 Mb/s"))
        #expect(usb480.localizedDiagnosticDetail(localizer).contains("无法判断是否被限速"))
        #expect(!usb480.localizedDiagnosticDetail(localizer).contains("40 Gb/s"))

        localizer.toggle()
        #expect(localizer.language == .en)
        #expect(store.string(forKey: AppLocalizer.defaultPreferenceKey) == "en")
    }

    @Test("Auto-detects Chinese system locale, respects preference store & --lang flag, and preserves EN screenshots")
    @MainActor
    func testChineseLocaleAutoDetectCLIFlagAndChineseScreenshots() throws {
        let store = InMemoryPreferenceStore()

        let autoZh = AppLocalizer(
            arguments: ["BusLensMac"],
            preferenceStore: store,
            preferenceKey: AppLocalizer.defaultPreferenceKey,
            preferredLanguages: ["zh-Hans-CN", "en-US"]
        )
        #expect(autoZh.language == .zhHans)
        #expect(autoZh.L("Rescan", "重新探测") == "重新探测")

        store.set("en", forKey: AppLocalizer.defaultPreferenceKey)
        let savedEn = AppLocalizer(
            arguments: ["BusLensMac"],
            preferenceStore: store,
            preferenceKey: AppLocalizer.defaultPreferenceKey,
            preferredLanguages: ["zh-Hans-CN"]
        )
        #expect(savedEn.language == .en)

        let cliZh = AppLocalizer(
            arguments: ["BusLensMac", "--lang", "zh"],
            preferenceStore: store,
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
