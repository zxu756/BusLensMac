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
}
