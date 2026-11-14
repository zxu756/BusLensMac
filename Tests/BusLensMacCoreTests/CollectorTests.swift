import Foundation
import Testing
@testable import BusLensMacCore

@Suite("Collector Verification", .timeLimit(.minutes(1)))
struct CollectorTests {

    private static var hostFixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("BusLensMacTests/Fixtures/host_macmini_scrubbed.json")
    }

    @Test("U1 / Row 3: Preserves receptacle_upstream_ambiguous_tag so 20 Gb/s TB device on 40 Gb/s bus reports 20 Gb/s while redacting UUIDs")
    func testThunderboltPerDeviceSpeedPreservedOn40GbpsBus() throws {
        let json = """
        {
          "SPThunderboltDataType": [
            {
              "_name": "thunderboltusb4_bus_0",
              "domain_uuid_key": "DOMAIN-UUID-SECRET-1111",
              "switch_uid_key": "0xAABBCCDDEEFF0011",
              "receptacle_1_tag": {
                "current_speed_key": "40 Gb/s",
                "receptacle_status_key": "receptacle_connected"
              },
              "_items": [
                {
                  "_name": "OWC Envoy NVMe",
                  "device_name_key": "OWC Envoy NVMe",
                  "vendor_name_key": "Acme",
                  "mode_key": "thunderbolt_three",
                  "switch_uid_key": "0x9988776655443322",
                  "receptacle_upstream_ambiguous_tag": {
                    "current_speed_key": "20 Gb/s",
                    "receptacle_status_key": "receptacle_connected"
                  }
                }
              ]
            }
          ]
        }
        """
        let rawData = Data(json.utf8)
        let rawObj = try JSONSerialization.jsonObject(with: rawData)
        let redactedBytes = try JSONSerialization.data(withJSONObject: BusProfilerCollector.redactHardwareIdentifiers(rawObj))
        let redactedString = String(decoding: redactedBytes, as: UTF8.self)
        #expect(!redactedString.contains("DOMAIN-UUID-SECRET-1111"))
        #expect(!redactedString.contains("0xAABBCCDDEEFF0011"))
        #expect(!redactedString.contains("0x9988776655443322"))
        #expect(redactedString.contains("receptacle_upstream_ambiguous_tag"))

        let snap = BusProfilerCollector.parseSystemProfilerJSON(rawData)
        #expect(snap.devices.count == 1)
        let dev = try #require(snap.devices.first)
        #expect(dev.name == "OWC Envoy NVMe")
        #expect(dev.negotiatedGbps == 20.0)
        #expect(dev.negotiatedSpeedLabel == "20 Gb/s")
        #expect(dev.verdict == .indeterminate)
    }

    @Test("U1: Daisy-chained Thunderbolt/USB4 devices each report their own negotiated speed instead of upstream 40 Gb/s")
    func testThunderboltDaisyChainPerDeviceSpeeds() throws {
        let json = """
        {
          "SPThunderboltDataType": [
            {
              "_name": "thunderboltusb4_bus_0",
              "receptacle_1_tag": {
                "current_speed_key": "40 Gb/s",
                "receptacle_status_key": "receptacle_connected"
              },
              "_items": [
                {
                  "_name": "USB4 Hub NVMe",
                  "device_name_key": "USB4 Hub NVMe",
                  "vendor_name_key": "Acme",
                  "mode_key": "usb4",
                  "receptacle_upstream_ambiguous_tag": {
                    "current_speed_key": "40 Gb/s",
                    "receptacle_status_key": "receptacle_connected"
                  },
                  "_items": [
                    {
                      "_name": "Samsung X5",
                      "device_name_key": "Samsung X5",
                      "vendor_name_key": "Acme",
                      "mode_key": "thunderbolt_three",
                      "receptacle_upstream_ambiguous_tag": {
                        "current_speed_key": "20 Gb/s",
                        "receptacle_status_key": "receptacle_connected"
                      }
                    }
                  ]
                }
              ]
            }
          ]
        }
        """
        let snap = BusProfilerCollector.parseSystemProfilerJSON(Data(json.utf8))
        #expect(snap.devices.count == 2)
        let upstream = try #require(snap.devices.first { $0.name == "USB4 Hub NVMe" })
        let downstream = try #require(snap.devices.first { $0.name == "Samsung X5" })
        #expect(upstream.negotiatedGbps == 40.0)
        #expect(upstream.negotiatedSpeedLabel == "40 Gb/s")
        #expect(upstream.verdict == .fullRate)
        #expect(downstream.negotiatedGbps == 20.0)
        #expect(downstream.negotiatedSpeedLabel == "20 Gb/s")
        #expect(downstream.verdict == .indeterminate)
        #expect(downstream.depth == 1)
    }

    @Test("U3: Unknown Thunderbolt and USB bus ceilings are nil and render as Unknown / 未知 instead of 40 Gb/s or 10 Gb/s")
    @MainActor
    func testUnknownBusCeilingsAreNotFabricated() throws {
        let tbNoCeilingJSON = """
        {
          "SPThunderboltDataType": [
            {
              "_name": "thunderboltusb4_bus_0",
              "receptacle_1_tag": {
                "current_speed_key": "10 Gb/s",
                "receptacle_status_key": "receptacle_connected"
              },
              "_items": [
                {
                  "_name": "Generic Display",
                  "device_name_key": "Generic Display",
                  "vendor_name_key": "X",
                  "mode_key": "usb4"
                }
              ]
            }
          ],
          "SPUSBHostDataType": [
            {
              "_name": "USB 3.1 Bus",
              "_items": [
                {
                  "_name": "Portable SSD T7",
                  "USBDeviceKeyLinkSpeed": "10 Gb/s",
                  "USBDeviceKeyVendorName": "Samsung"
                }
              ]
            }
          ]
        }
        """
        let snap = BusProfilerCollector.parseSystemProfilerJSON(Data(tbNoCeilingJSON.utf8))
        let en = AppLocalizer(fixedLanguage: .en)
        let zh = AppLocalizer(fixedLanguage: .zhHans)

        let tbCtrl = try #require(snap.controllers.first { $0.protocolKind == .thunderboltUSB4 })
        let usbCtrl = try #require(snap.controllers.first { $0.protocolKind == .usbHost })
        #expect(tbCtrl.maxGbps == nil)
        #expect(usbCtrl.maxGbps == nil)
        #expect(tbCtrl.localizedMaxRateLabel(en) == "Unknown")
        #expect(tbCtrl.localizedMaxRateLabel(zh) == "未知")
        #expect(usbCtrl.localizedMaxRateLabel(en) == "Unknown")
        #expect(usbCtrl.localizedMaxRateLabel(zh) == "未知")

        let tbDev = try #require(snap.devices.first { $0.name == "Generic Display" })
        let usbDev = try #require(snap.devices.first { $0.name == "Portable SSD T7" })
        #expect(tbDev.negotiatedGbps == 10.0)
        #expect(tbDev.portCeilingGbps == nil)
        #expect(tbDev.localizedPortCeilingLabel(en) == "Unknown")
        #expect(tbDev.localizedPortCeilingLabel(zh) == "未知")
        #expect(usbDev.portCeilingGbps == nil)
        #expect(usbDev.localizedPortCeilingLabel(en) == "Unknown")
        #expect(usbDev.localizedPortCeilingLabel(zh) == "未知")
    }

    @Test("U5 & Row 5: Scrubbed Mac mini host fixture parses 3 real devices, preserves speeds, and does NOT flag Apple Built-in hubs as external hubs")
    @MainActor
    func testRealHostMacMiniScrubbedFixtureAndInternalHubHandling() throws {
        let data = try Data(contentsOf: Self.hostFixtureURL)
        let snap = try BusProfilerCollector.parseSystemProfilerJSONValidated(data)
        let zh = AppLocalizer(fixedLanguage: .zhHans)

        #expect(snap.devices.count == 3)
        let tbDev = try #require(snap.devices.first { $0.name == "TBU405Pro" })
        let wooting = try #require(snap.devices.first { $0.name == "Wooting 60HE v2" })
        let ajazz = try #require(snap.devices.first { $0.name == "AJAZZ AJ159 APEX" })

        #expect(tbDev.negotiatedSpeedLabel == "40 Gb/s")
        #expect(tbDev.negotiatedGbps == 40.0)
        #expect(tbDev.portCeilingGbps == 40.0)
        #expect(tbDev.verdict == .fullRate)

        #expect(wooting.negotiatedSpeedLabel == "480 Mb/s")
        #expect(wooting.negotiatedGbps == 0.48)
        #expect(wooting.verdict == .lowSpeedPeripheral)
        #expect(wooting.depth == 0)
        #expect(wooting.behindExternalHub == false)
        #expect(!wooting.modeDescription.lowercased().contains("hub"))
        #expect(!wooting.localizedModeDescription(zh).contains("集线器"))

        #expect(ajazz.negotiatedSpeedLabel == "12 Mb/s")
        #expect(ajazz.negotiatedGbps == 0.012)
        #expect(ajazz.verdict == .lowSpeedPeripheral)
        #expect(ajazz.depth == 0)
        #expect(ajazz.behindExternalHub == false)
        #expect(!ajazz.modeDescription.lowercased().contains("hub"))
        #expect(!ajazz.localizedModeDescription(zh).contains("集线器"))

        for ctrl in snap.controllers {
            #expect(!ctrl.title.contains("#"))
        }
        #expect(snap.power.powerSource == "AC Line Power")
        #expect(snap.power.lowPowerMode == false)
    }

    @Test("U4 & U5: Parses legacy SPUSBDataType schema (synthetic fixture), scrubs serial_num, and distinguishes external hubs from Built-in_Device hubs")
    @MainActor
    func testLegacySPUSBDataTypeSchemaAndExternalHubDetection() throws {
        let legacyJSON = """
        {
          "SPUSBDataType": [
            {
              "_name": "USB31Bus",
              "host_controller": "AppleT8103USBXHCI",
              "_items": [
                {
                  "_name": "USB 2.0 Hub",
                  "Built-in_Device": "Yes",
                  "speed": "Up to 480 Mb/sec",
                  "_items": [
                    {
                      "_name": "NVMe Enclosure",
                      "manufacturer": "Acme",
                      "speed": "Up to 480 Mb/s",
                      "serial_num": "LEGACY-SECRET-SERIAL-01",
                      "vendor_id": "0x1234"
                    }
                  ]
                },
                {
                  "_name": "4-Port USB 3.0 Hub",
                  "speed": "Up to 5 Gb/s",
                  "_items": [
                    {
                      "_name": "Portable SSD",
                      "manufacturer": "Acme",
                      "speed": "Up to 10 Gb/s"
                    },
                    {
                      "_name": "Apple Keyboard",
                      "speed": "Up to 12 Mb/s"
                    }
                  ]
                }
              ]
            }
          ]
        }
        """
        let rawData = Data(legacyJSON.utf8)
        let rawObj = try JSONSerialization.jsonObject(with: rawData)
        let redacted = try JSONSerialization.data(withJSONObject: BusProfilerCollector.redactHardwareIdentifiers(rawObj))
        #expect(!String(decoding: redacted, as: UTF8.self).contains("LEGACY-SECRET-SERIAL-01"))

        let snap = try BusProfilerCollector.parseSystemProfilerJSONValidated(rawData)
        #expect(snap.devices.count == 3)

        let directEnclosure = try #require(snap.devices.first { $0.name == "NVMe Enclosure" })
        #expect(directEnclosure.negotiatedSpeedLabel == "480 Mb/s")
        #expect(directEnclosure.behindExternalHub == false)
        #expect(directEnclosure.depth == 0)
        #expect(directEnclosure.verdict == .indeterminate)

        let externalHubSSD = try #require(snap.devices.first { $0.name == "Portable SSD" })
        #expect(externalHubSSD.negotiatedSpeedLabel == "10 Gb/s")
        #expect(externalHubSSD.behindExternalHub == true)
        #expect(externalHubSSD.depth == 1)
        #expect(externalHubSSD.modeDescription == "via external USB hub")
        #expect(externalHubSSD.localizedModeDescription(AppLocalizer(fixedLanguage: .zhHans)) == "经由外接 USB 集线器")

        let externalHubKB = try #require(snap.devices.first { $0.name == "Apple Keyboard" })
        #expect(externalHubKB.negotiatedSpeedLabel == "12 Mb/s")
        #expect(externalHubKB.behindExternalHub == true)
        #expect(externalHubKB.verdict == .lowSpeedPeripheral)
    }

    @Test("U8: Low Power Mode accepts string ('Yes', '1', 'true', 'sppower_low_power_mode_enabled'), integer 1, and pmset fallback")
    func testLowPowerModeStringIntegerAndPmsetParsing() {
        let samples: [(String, Bool)] = [
            (#"{"SPPowerDataType":[{"AC Power":{"Current Power Source":"TRUE","LowPowerMode":"Yes"}}]}"#, true),
            (#"{"SPPowerDataType":[{"AC Power":{"Current Power Source":"TRUE","LowPowerMode":"1"}}]}"#, true),
            (#"{"SPPowerDataType":[{"AC Power":{"Current Power Source":"TRUE","LowPowerMode":"true"}}]}"#, true),
            (#"{"SPPowerDataType":[{"sppower_low_power_mode":"sppower_low_power_mode_enabled"}]}"#, true),
            (#"{"SPPowerDataType":[{"AC Power":{"Current Power Source":"TRUE","LowPowerMode":1}}]}"#, true),
            (#"{"SPPowerDataType":[{"AC Power":{"Current Power Source":"TRUE","LowPowerMode":"No"}}]}"#, false),
            (#"{"SPPowerDataType":[{"AC Power":{"Current Power Source":"TRUE","LowPowerMode":"0"}}]}"#, false),
            (#"{"SPPowerDataType":[{"AC Power":{"Current Power Source":"TRUE","LowPowerMode":0}}]}"#, false)
        ]
        for (raw, expected) in samples {
            let snap = BusProfilerCollector.parseSystemProfilerJSON(Data(raw.utf8))
            #expect(snap.power.lowPowerMode == expected)
        }

        let pmsetOn = """
        System-wide power settings:
        Currently in use:
         lowpowermode         1
         sleep                1
        """
        let pmsetOff = """
        System-wide power settings:
        Currently in use:
         lowpowermode         0
        """
        #expect(BusProfilerCollector.parsePmsetLowPowerMode(pmsetOn) == true)
        #expect(BusProfilerCollector.parsePmsetLowPowerMode(pmsetOff) == false)

        let fallbackSnap = BusProfilerCollector.parseSystemProfilerJSON(
            Data(#"{"SPPowerDataType":[{"AC Power":{"Current Power Source":"TRUE"}}]}"#.utf8),
            pmsetOutput: pmsetOn
        )
        #expect(fallbackSnap.power.lowPowerMode == true)
    }
}
