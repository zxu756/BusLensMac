import Foundation
import Testing
@testable import BusLensMacCore

@Suite("Diagnoser Verification", .timeLimit(.minutes(1)))
struct DiagnoserTests {

    @Test("U2 / Row 4: Samsung T7 at 10 Gb/s and T5 at 5 Gb/s are NOT flagged as throttled and never suggest a 40 Gb/s cable")
    @MainActor
    func testSamsungT7Native10GbpsNotFlaggedAsBottleneck() throws {
        let json = """
        {
          "SPUSBHostDataType": [
            {
              "_name": "USB 3.1 Bus",
              "_items": [
                {
                  "_name": "Portable SSD T7",
                  "USBDeviceKeyLinkSpeed": "10 Gb/s",
                  "USBDeviceKeyVendorName": "Samsung"
                },
                {
                  "_name": "Samsung T5",
                  "USBDeviceKeyLinkSpeed": "5 Gb/s",
                  "USBDeviceKeyVendorName": "Samsung"
                }
              ]
            }
          ]
        }
        """
        let snap = BusProfilerCollector.parseSystemProfilerJSON(Data(json.utf8))
        #expect(snap.devices.count == 2)
        #expect(snap.bottleneckDevices.isEmpty)

        let enLocalizer = AppLocalizer(fixedLanguage: .en)
        let zhLocalizer = AppLocalizer(fixedLanguage: .zhHans)

        for dev in snap.devices {
            #expect(dev.verdict == .indeterminate)
            #expect(!dev.verdict.isWarning)
            let enDetail = dev.localizedDiagnosticDetail(enLocalizer)
            let zhDetail = dev.localizedDiagnosticDetail(zhLocalizer)
            #expect(!enDetail.contains("40 Gb/s"))
            #expect(!enDetail.lowercased().contains("replace"))
            #expect(!zhDetail.contains("40 Gb/s"))
            #expect(!zhDetail.contains("更换"))
            #expect(enDetail.contains("cannot determine"))
            #expect(zhDetail.contains("无法判断是否被限速"))
        }
    }

    @Test("U2: SanDisk Extreme PRO USB2 Drive and generic USB drives at 480 Mb/s are neither name-guessed as throttled nor misclassified as HID")
    @MainActor
    func testUSB2DrivesAreIndeterminateWithoutDeviceDescriptor() throws {
        let json = """
        {
          "SPUSBHostDataType": [
            {
              "_name": "USB 3.1 Bus",
              "_items": [
                {
                  "_name": "USB DISK 2.0",
                  "USBDeviceKeyLinkSpeed": "480 Mb/s",
                  "USBDeviceKeyVendorName": "Kingston"
                },
                {
                  "_name": "My Passport 25E2",
                  "USBDeviceKeyLinkSpeed": "480 Mb/s",
                  "USBDeviceKeyVendorName": "Western Digital"
                },
                {
                  "_name": "SanDisk Extreme PRO USB2 Drive",
                  "USBDeviceKeyLinkSpeed": "480 Mb/s",
                  "USBDeviceKeyVendorName": "SanDisk"
                }
              ]
            }
          ]
        }
        """
        let snap = BusProfilerCollector.parseSystemProfilerJSON(Data(json.utf8))
        #expect(snap.devices.count == 3)
        #expect(snap.bottleneckDevices.isEmpty)

        let enLocalizer = AppLocalizer(fixedLanguage: .en)
        let zhLocalizer = AppLocalizer(fixedLanguage: .zhHans)

        for dev in snap.devices {
            #expect(dev.verdict == .indeterminate)
            #expect(!dev.verdict.isWarning)
            #expect(dev.verdict.localizedLabel(enLocalizer) == "Indeterminate")
            #expect(dev.verdict.localizedLabel(zhLocalizer) == "无法判断是否被限速")
            #expect(dev.localizedDiagnosticDetail(enLocalizer) == "Negotiated at 480 Mb/s; cannot determine if cable/hub-limited without device max capability.")
            #expect(dev.localizedDiagnosticDetail(zhLocalizer) == "实际速率 480 Mb/s，无法判断是否被限速。")
        }
    }

    @Test("U9: 480 Mb/s 'Groups Backup Drive', 'Hidden Disk', and 'Wooting 60HE' on 10 Gb/s bus are Indeterminate; only 1.5 Mb/s and 12 Mb/s USB 1.x links are Low-speed peripheral")
    @MainActor
    func testNoNameGuessingForBackupDrivesAndKeyboardsAt480Mbps() throws {
        let json = """
        {
          "SPUSBDataType": [
            {
              "_name": "USB 3.1 Bus",
              "host_controller_speed": "Up to 10 Gb/s",
              "_items": [
                {
                  "_name": "Groups Backup Drive",
                  "manufacturer": "Acme Storage",
                  "speed": "Up to 480 Mb/s"
                },
                {
                  "_name": "Hidden Disk",
                  "manufacturer": "Acme Storage",
                  "speed": "Up to 480 Mb/s"
                },
                {
                  "_name": "Wooting 60HE",
                  "manufacturer": "Wooting",
                  "speed": "Up to 480 Mb/s"
                },
                {
                  "_name": "USB 1.0 Device",
                  "manufacturer": "Generic",
                  "speed": "Up to 1.5 Mb/s"
                },
                {
                  "_name": "USB 1.1 Receiver",
                  "manufacturer": "Generic",
                  "speed": "Up to 12 Mb/s"
                }
              ]
            }
          ]
        }
        """
        let snap = try BusProfilerCollector.parseSystemProfilerJSONValidated(Data(json.utf8))
        #expect(snap.devices.count == 5)

        let en = AppLocalizer(fixedLanguage: .en)
        let zh = AppLocalizer(fixedLanguage: .zhHans)

        for name in ["Groups Backup Drive", "Hidden Disk", "Wooting 60HE"] {
            let dev = try #require(snap.devices.first { $0.name == name })
            #expect(dev.negotiatedSpeedLabel == "480 Mb/s")
            #expect(dev.portCeilingGbps == 10.0)
            #expect(dev.verdict == .indeterminate)
            #expect(dev.verdict.localizedLabel(en) == "Indeterminate")
            #expect(dev.verdict.localizedLabel(zh) == "无法判断是否被限速")
            #expect(dev.localizedDiagnosticDetail(zh).contains("无法判断"))
        }

        let usb1Low = try #require(snap.devices.first { $0.name == "USB 1.0 Device" })
        #expect(usb1Low.negotiatedGbps == 0.0015)
        #expect(usb1Low.negotiatedSpeedLabel == "1.5 Mb/s")
        #expect(usb1Low.verdict == .lowSpeedPeripheral)
        #expect(usb1Low.verdict.localizedLabel(en) == "Low-speed peripheral")
        #expect(usb1Low.verdict.localizedLabel(zh).contains("低速外设"))

        let usb1Full = try #require(snap.devices.first { $0.name == "USB 1.1 Receiver" })
        #expect(usb1Full.negotiatedGbps == 0.012)
        #expect(usb1Full.negotiatedSpeedLabel == "12 Mb/s")
        #expect(usb1Full.verdict == .lowSpeedPeripheral)
        #expect(usb1Full.verdict.localizedLabel(en) == "Low-speed peripheral")
        #expect(usb1Full.verdict.localizedLabel(zh).contains("低速外设"))
    }

    @Test("U2 & U9: Only the 3 honest M0 verdicts exist across Full-rate TB, USB 1.x Low-speed peripheral, and Indeterminate links")
    @MainActor
    func testThreeHonestVerdictsInEnglishAndChinese() {
        let en = AppLocalizer(fixedLanguage: .en)
        let zh = AppLocalizer(fixedLanguage: .zhHans)

        let full40 = BottleneckDiagnoser.evaluateDevice(
            name: "TBU405Pro",
            vendor: "ACASIS",
            protocolKind: .thunderboltUSB4,
            negotiatedGbps: 40.0,
            portCeilingGbps: 40.0,
            behindHub: false
        )
        #expect(full40.verdict == .fullRate)
        #expect(full40.verdict.localizedLabel(en) == "Full bus rate")
        #expect(full40.verdict.localizedLabel(zh) == "满速")

        let tb20On40 = BottleneckDiagnoser.evaluateDevice(
            name: "OWC Envoy NVMe",
            vendor: "Acme",
            protocolKind: .thunderboltUSB4,
            negotiatedGbps: 20.0,
            portCeilingGbps: 40.0,
            behindHub: false
        )
        #expect(tb20On40.verdict == .indeterminate)

        let usb2Keyboard = BottleneckDiagnoser.evaluateDevice(
            name: "Wooting 60HE",
            vendor: "Wooting",
            protocolKind: .usbHost,
            negotiatedGbps: 0.48,
            portCeilingGbps: 10.0,
            behindHub: false
        )
        #expect(usb2Keyboard.verdict == .indeterminate)

        let usb1Items: [(String, String, Double)] = [
            ("Generic Low-Speed Device", "Vendor", 0.0015),
            ("Generic Full-Speed Device", "Vendor", 0.012)
        ]
        for (name, vendor, gbps) in usb1Items {
            let res = BottleneckDiagnoser.evaluateDevice(
                name: name,
                vendor: vendor,
                protocolKind: .usbHost,
                negotiatedGbps: gbps,
                portCeilingGbps: nil,
                behindHub: false
            )
            #expect(res.verdict == .lowSpeedPeripheral)
            #expect(res.verdict.localizedLabel(en) == "Low-speed peripheral")
            #expect(res.verdict.localizedLabel(zh) == "低速外设（USB 1.x）")
        }
    }
}
