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

    @Test("U11: Sibling Thunderbolt bus omitting speed reports nil / Unknown / 未知 instead of copying 'Up to 40 Gb/s' from another bus on the same host")
    @MainActor
    func testSiblingThunderboltBusDoesNotCopyCeiling() throws {
        let siblingJSON = """
        {
          "SPThunderboltDataType": [
            {
              "_name": "thunderboltusb4_bus_0",
              "vendor_name_key": "Apple Inc.",
              "device_name_key": "Mac mini",
              "receptacle_1_tag": {
                "current_speed_key": "Up to 40 Gb/s",
                "receptacle_status_key": "receptacle_no_devices_connected"
              }
            },
            {
              "_name": "thunderboltusb4_bus_1",
              "vendor_name_key": "Apple Inc.",
              "device_name_key": "Mac mini",
              "receptacle_1_tag": {
                "receptacle_status_key": "receptacle_no_devices_connected"
              }
            }
          ]
        }
        """
        let snap = try BusProfilerCollector.parseSystemProfilerJSONValidated(Data(siblingJSON.utf8))
        let en = AppLocalizer(fixedLanguage: .en)
        let zh = AppLocalizer(fixedLanguage: .zhHans)

        let bus0 = try #require(snap.controllers.first { $0.id == "tb::thunderboltusb4_bus_0" })
        let bus1 = try #require(snap.controllers.first { $0.id == "tb::thunderboltusb4_bus_1" })
        #expect(bus0.maxGbps == 40.0)
        #expect(bus0.localizedMaxRateLabel(en) == "40 Gb/s")
        #expect(bus1.maxGbps == nil)
        #expect(bus1.localizedMaxRateLabel(en) == "Unknown")
        #expect(bus1.localizedMaxRateLabel(zh) == "未知")
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
        #expect(tbDev.portCeilingGbps == nil)
        #expect(tbDev.verdict == .fullRate)

        #expect(wooting.negotiatedSpeedLabel == "480 Mb/s")
        #expect(wooting.negotiatedGbps == 0.48)
        #expect(wooting.verdict == .indeterminate)
        #expect(wooting.depth == 0)
        #expect(wooting.behindExternalHub == false)
        #expect(!wooting.modeDescription.lowercased().contains("hub"))
        #expect(!wooting.localizedModeDescription(zh).contains("集线器"))

        #expect(ajazz.negotiatedSpeedLabel == "12 Mb/s")
        #expect(ajazz.negotiatedGbps == 0.012)
        #expect(ajazz.verdict == .indeterminate)
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
                  "bDeviceClass": 9,
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
        #expect(externalHubKB.verdict == .indeterminate)
    }

    @Test("U10: Leaf USB devices containing 'hub' in name ('Hubble Backup Drive', empty 'Generic 4-Port Hub') are never hidden by product-name substring matching")
    @MainActor
    func testHubbleBackupDriveNotHiddenByHubSubstring() throws {
        let json = """
        {
          "SPUSBDataType": [
            {
              "_name": "USB 3.1 Bus",
              "host_controller_speed": "Up to 10 Gb/s",
              "_items": [
                {
                  "_name": "Hubble Backup Drive",
                  "manufacturer": "Acme Storage",
                  "speed": "Up to 480 Mb/s"
                },
                {
                  "_name": "Generic 4-Port Hub",
                  "manufacturer": "Generic",
                  "speed": "Up to 5 Gb/s"
                },
                {
                  "_name": "Anker USB-C Adapter",
                  "bDeviceClass": 9,
                  "manufacturer": "Anker",
                  "speed": "Up to 5 Gb/s",
                  "_items": [
                    {
                      "_name": "Downstream Flash Drive",
                      "manufacturer": "Acme",
                      "speed": "Up to 480 Mb/s"
                    }
                  ]
                }
              ]
            }
          ]
        }
        """
        let snap = try BusProfilerCollector.parseSystemProfilerJSONValidated(Data(json.utf8))
        let hubble = try #require(snap.devices.first { $0.name == "Hubble Backup Drive" })
        #expect(hubble.negotiatedSpeedLabel == "480 Mb/s")
        #expect(hubble.verdict == .indeterminate)
        #expect(hubble.behindExternalHub == false)
        #expect(hubble.depth == 0)

        let emptyHub = try #require(snap.devices.first { $0.name == "Generic 4-Port Hub" })
        #expect(emptyHub.negotiatedSpeedLabel == "5 Gb/s")
        #expect(emptyHub.verdict == .indeterminate)

        let downstream = try #require(snap.devices.first { $0.name == "Downstream Flash Drive" })
        #expect(downstream.behindExternalHub == true)
        #expect(downstream.depth == 1)

        let enText = BusCLIRunner.renderTopologyText(snapshot: snap, localizer: AppLocalizer(fixedLanguage: .en), isDemo: false)
        let zhText = BusCLIRunner.renderTopologyText(snapshot: snap, localizer: AppLocalizer(fixedLanguage: .zhHans), isDemo: false)
        #expect(enText.contains("Hubble Backup Drive"))
        #expect(zhText.contains("Hubble Backup Drive"))
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

    @Test("U12: Missing SPPowerDataType and empty pmset render Unknown / 未知 instead of defaulting to AC Power and Low Power Mode Off")
    @MainActor
    func testMissingPowerTelemetryReportsUnknownNotACPowerOrFalse() throws {
        let emptySnap = try BusProfilerCollector.parseSystemProfilerJSONValidated(
            Data(#"{"SPPowerDataType":[]}"#.utf8),
            pmsetOutput: nil
        )
        let en = AppLocalizer(fixedLanguage: .en)
        let zh = AppLocalizer(fixedLanguage: .zhHans)

        #expect(emptySnap.power.powerSource == nil)
        #expect(emptySnap.power.lowPowerMode == nil)
        #expect(emptySnap.power.lowPowerModeEnabled == nil)
        #expect(emptySnap.power.localizedBadge(en) == "Unknown")
        #expect(emptySnap.power.localizedBadge(zh) == "未知")
        #expect(emptySnap.power.localizedLowPowerModeLabel(en) == "Unknown")
        #expect(emptySnap.power.localizedLowPowerModeLabel(zh) == "未知")

        let enText = BusCLIRunner.renderTopologyText(snapshot: emptySnap, localizer: en, isDemo: false)
        let zhText = BusCLIRunner.renderTopologyText(snapshot: emptySnap, localizer: zh, isDemo: false)
        #expect(enText.contains("Power: Unknown (Low Power Mode: Unknown)"))
        #expect(!enText.contains("AC Power"))
        #expect(zhText.contains("供电状态：未知（低电量模式：未知）"))
        #expect(!zhText.contains("交流电源"))

        let enJSON = try BusCLIRunner.renderTopologyJSON(snapshot: emptySnap, localizer: en, isDemo: false)
        #expect(enJSON.contains(#""powerSource" : null"#))
        #expect(enJSON.contains(#""lowPowerMode" : null"#))
        #expect(enJSON.contains(#""localizedBadge" : "Unknown""#))

        let zhJSON = try BusCLIRunner.renderTopologyJSON(snapshot: emptySnap, localizer: zh, isDemo: false)
        #expect(zhJSON.contains(#""localizedBadge" : "未知""#))
    }

    @Test("U13: Only USB Device Class 9 (or built-in root hub) is hidden as hub container; 10 Gb/s composite/billboard docks with child devices remain visible")
    @MainActor
    func testU13NonHubClassDockWithChildRemainsVisible() throws {
        let syntheticDockJSON = """
        {
          "SPUSBHostDataType": [
            {
              "_name": "USB 3.1 Bus",
              "USBKeyLocationID": "0x02000000",
              "_items": [
                {
                  "_name": "Composite 10G Creator Dock",
                  "USBDeviceKeyVendorName": "Acme",
                  "USBDeviceKeyLinkSpeed": "10 Gb/s",
                  "bDeviceClass": 0,
                  "_items": [
                    {
                      "_name": "Downstream Card Reader",
                      "USBDeviceKeyVendorName": "Acme",
                      "USBDeviceKeyLinkSpeed": "5 Gb/s",
                      "bDeviceClass": 0
                    }
                  ]
                },
                {
                  "_name": "Billboard 10G Video Dock",
                  "USBDeviceKeyVendorName": "Acme",
                  "USBDeviceKeyLinkSpeed": "10 Gb/s",
                  "bDeviceClass": 17,
                  "_items": [
                    {
                      "_name": "Dock Audio Endpoint",
                      "USBDeviceKeyVendorName": "Acme",
                      "USBDeviceKeyLinkSpeed": "480 Mb/s",
                      "bDeviceClass": 0
                    }
                  ]
                },
                {
                  "_name": "Explicit Class-9 USB3 Hub",
                  "USBDeviceKeyVendorName": "Genesys",
                  "USBDeviceKeyLinkSpeed": "10 Gb/s",
                  "bDeviceClass": 9,
                  "_items": [
                    {
                      "_name": "Hub Child SSD",
                      "USBDeviceKeyVendorName": "Acme",
                      "USBDeviceKeyLinkSpeed": "5 Gb/s",
                      "bDeviceClass": 0
                    }
                  ]
                }
              ]
            }
          ]
        }
        """
        let snap = try BusProfilerCollector.parseSystemProfilerJSONValidated(Data(syntheticDockJSON.utf8))
        let names = snap.devices.map(\.name)
        #expect(names.contains("Composite 10G Creator Dock"))
        #expect(names.contains("Downstream Card Reader"))
        #expect(names.contains("Billboard 10G Video Dock"))
        #expect(names.contains("Dock Audio Endpoint"))
        #expect(!names.contains("Explicit Class-9 USB3 Hub"))
        #expect(names.contains("Hub Child SSD"))
    }

    @Test("M1 Items 1 & 3 (U5): Real 2026-11-15 Mac mini system_profiler + ioreg pair maps physical ports (Port-USB-C@2, Port-USB-C@6), companion ceilings, TB capability, and HID class")
    @MainActor
    func testM1Real20261115PairedFixtureAndPhysicalPortMapping() throws {
        let fixturesDir = Self.hostFixtureURL.deletingLastPathComponent()
        let spData = try Data(contentsOf: fixturesDir.appendingPathComponent("host_macmini_20261115_sp_scrubbed.json"))
        let ioregData = try Data(contentsOf: fixturesDir.appendingPathComponent("host_macmini_20261115_ioreg_scrubbed.plist"))

        let ioregSnap = try IORegistrySnapshot.parsePlistData(ioregData)
        let snap = try BusProfilerCollector.parseSystemProfilerJSONValidated(spData, ioregSnapshot: ioregSnap)

        #expect(snap.devices.count == 2)

        let tbEnclosure = try #require(snap.devices.first { $0.name == "TBU405Pro" })
        #expect(tbEnclosure.negotiatedGbps == 40.0)
        #expect(tbEnclosure.portCeilingGbps == 40.0)
        #expect(tbEnclosure.deviceMaxGbps == 40.0)
        #expect(tbEnclosure.physicalPort == "Port-USB-C@2")
        #expect(tbEnclosure.verdict == .fullRate)
        #expect(tbEnclosure.behindExternalHub == false)

        let receiver = try #require(snap.devices.first { $0.name == "AJAZZ AJ159 APEX" })
        #expect(receiver.negotiatedGbps == 0.012)
        #expect(receiver.portCeilingGbps == 10.0)
        #expect(receiver.physicalPort == "Port-USB-C@6")
        #expect(receiver.locationID == "0x02120000")
        #expect(receiver.behindExternalHub == false)
        #expect(receiver.capability?.bcdUSB == 512)
        #expect(receiver.capability?.usbInterfaceClasses == [3, 3, 3])
        #expect(receiver.verdict == .lowSpeedPeripheral)

        // Verify sibling devices under same 0x02000000 XHCI controller & built-in USB2 Hub map to distinct physical ports
        let twoFrontPortsSP = """
        {
          "SPUSBHostDataType": [
            {
              "_name": "USB 3.1 Bus",
              "USBKeyLocationID": "0x02000000",
              "_items": [
                {
                  "_name": "USB2 Hub",
                  "USBKeyHardwareType": "Built-in",
                  "USBKeyLocationID": "0x02100000",
                  "USBDeviceKeyLinkSpeed": "480 Mb/s",
                  "_items": [
                    {
                      "_name": "Front Left Keyboard",
                      "USBKeyLocationID": "0x02110000",
                      "USBDeviceKeyLinkSpeed": "480 Mb/s"
                    },
                    {
                      "_name": "External Hub On Front Right",
                      "USBKeyLocationID": "0x02120000",
                      "USBDeviceKeyLinkSpeed": "480 Mb/s",
                      "bDeviceClass": 9,
                      "_items": [
                        {
                          "_name": "Downstream Drive On Hub Port 3",
                          "USBKeyLocationID": "0x02123000",
                          "USBDeviceKeyLinkSpeed": "480 Mb/s"
                        }
                      ]
                    }
                  ]
                }
              ]
            }
          ]
        }
        """
        let twoFrontSnap = try BusProfilerCollector.parseSystemProfilerJSONValidated(
            Data(twoFrontPortsSP.utf8),
            ioregSnapshot: ioregSnap
        )
        let leftDev = try #require(twoFrontSnap.devices.first { $0.name == "Front Left Keyboard" })
        let rightChild = try #require(twoFrontSnap.devices.first { $0.name == "Downstream Drive On Hub Port 3" })
        #expect(leftDev.physicalPort == "Port-USB-C@5")
        #expect(leftDev.portCeilingGbps == 10.0)
        #expect(leftDev.behindExternalHub == false)

        #expect(rightChild.physicalPort == "Port-USB-C@6")
        #expect(rightChild.portCeilingGbps == 10.0)
        #expect(rightChild.behindExternalHub == true)
        #expect(rightChild.upstreamHubGbps == 0.48)
    }
}
