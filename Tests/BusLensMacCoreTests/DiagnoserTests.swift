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

    @Test("U9: 480 Mb/s 'Groups Backup Drive', 'Hidden Disk', and 'Wooting 60HE' on 10 Gb/s bus are Indeterminate; only verified HID class 3 at 1.5/12 Mb/s is HID peripheral")
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
                  "_name": "USB 1.0 HID Keypad",
                  "manufacturer": "Generic",
                  "speed": "Up to 1.5 Mb/s",
                  "bInterfaceClass": 3
                },
                {
                  "_name": "USB 1.1 Unclassified Device",
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

        let usb1LowHID = try #require(snap.devices.first { $0.name == "USB 1.0 HID Keypad" })
        #expect(usb1LowHID.negotiatedGbps == 0.0015)
        #expect(usb1LowHID.negotiatedSpeedLabel == "1.5 Mb/s")
        #expect(usb1LowHID.verdict == .lowSpeedPeripheral)
        #expect(usb1LowHID.verdict.localizedLabel(en) == "HID peripheral")
        #expect(usb1LowHID.verdict.localizedLabel(zh) == "HID / 低速外设")

        let usb1Unclassified = try #require(snap.devices.first { $0.name == "USB 1.1 Unclassified Device" })
        #expect(usb1Unclassified.negotiatedGbps == 0.012)
        #expect(usb1Unclassified.negotiatedSpeedLabel == "12 Mb/s")
        #expect(usb1Unclassified.verdict == .indeterminate)
    }

    @Test("U2, U9 & U14: Without capability descriptors, non-ceiling links are Indeterminate; verified HID class 3 is HID peripheral")
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

        let hidCap = DeviceCapabilityDescriptor(bcdUSB: 0x0200, usbDeviceClass: 0, usbInterfaceClasses: [3])
        for gbps in [0.0015, 0.012] {
            let res = BottleneckDiagnoser.evaluateDevice(
                name: "Generic HID",
                vendor: "Vendor",
                protocolKind: .usbHost,
                negotiatedGbps: gbps,
                portCeilingGbps: nil,
                behindHub: false,
                capability: hidCap
            )
            #expect(res.verdict == .lowSpeedPeripheral)
            #expect(res.verdict.localizedLabel(en) == "HID peripheral")
            #expect(res.verdict.localizedLabel(zh) == "HID / 低速外设")
        }
    }

    @Test("U14: 12 Mb/s Mass Storage disk (bInterfaceClass == 8) is never mislabeled HID / Low-speed peripheral; only verified HID (class == 3) gets HID peripheral label")
    @MainActor
    func testU14TwelveMbpsMassStorageIsNeverLabeledLowSpeedPeripheral() throws {
        let syntheticMassStorage12M = """
        {
          "SPUSBHostDataType": [
            {
              "_name": "USB 3.1 Bus",
              "_items": [
                {
                  "_name": "ThumbDrive NoDesc",
                  "USBDeviceKeyVendorName": "Generic",
                  "USBDeviceKeyLinkSpeed": "12 Mb/s",
                  "bDeviceClass": 0,
                  "bInterfaceClass": 8
                },
                {
                  "_name": "ThumbDrive USB3At12M",
                  "USBDeviceKeyVendorName": "Generic",
                  "USBDeviceKeyLinkSpeed": "12 Mb/s",
                  "bcdUSB": "0x0210",
                  "bDeviceClass": 0,
                  "bInterfaceClass": 8
                },
                {
                  "_name": "Optical Mouse",
                  "USBDeviceKeyVendorName": "Generic",
                  "USBDeviceKeyLinkSpeed": "12 Mb/s",
                  "bcdUSB": "0x0200",
                  "bDeviceClass": 0,
                  "bInterfaceClass": 3
                }
              ]
            }
          ]
        }
        """
        let snap = try BusProfilerCollector.parseSystemProfilerJSONValidated(Data(syntheticMassStorage12M.utf8))
        let diskNoDesc = try #require(snap.devices.first { $0.name == "ThumbDrive NoDesc" })
        #expect(diskNoDesc.negotiatedSpeedLabel == "12 Mb/s")
        #expect(diskNoDesc.verdict == .indeterminate)

        let diskUSB3 = try #require(snap.devices.first { $0.name == "ThumbDrive USB3At12M" })
        #expect(diskUSB3.negotiatedSpeedLabel == "12 Mb/s")
        #expect(diskUSB3.verdict == .throttled)
        #expect(diskUSB3.bottleneckSegment == .cable)

        let mouse = try #require(snap.devices.first { $0.name == "Optical Mouse" })
        #expect(mouse.negotiatedSpeedLabel == "12 Mb/s")
        #expect(mouse.verdict == .lowSpeedPeripheral)
    }

    @Test("M1 Row 4: All 16 synthetic hardware scenarios paired with ioreg XML descriptors match expected verdicts and cable/hub/port bottleneck segments in EN & ZH")
    @MainActor
    func testM1SixteenSyntheticScenariosWithIORegistryDescriptors() throws {
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
                  "_name": "OWC Envoy NVMe",
                  "device_name_key": "OWC Envoy NVMe",
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
                "current_speed_key": "Up to 40 Gb/s",
                "receptacle_id_key": "2",
                "receptacle_status_key": "receptacle_connected"
              },
              "_items": [
                {
                  "_name": "USB4 Hub NVMe",
                  "device_name_key": "USB4 Hub NVMe",
                  "vendor_name_key": "Acme",
                  "mode_key": "usb4",
                  "route_string_key": "1",
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
                      "route_string_key": "301",
                      "receptacle_upstream_ambiguous_tag": {
                        "current_speed_key": "20 Gb/s",
                        "receptacle_status_key": "receptacle_connected"
                      }
                    }
                  ]
                }
              ]
            },
            {
              "_name": "thunderboltusb4_bus_2",
              "receptacle_1_tag": {
                "current_speed_key": "Up to 80 Gb/s",
                "receptacle_id_key": "3",
                "receptacle_status_key": "receptacle_connected"
              },
              "_items": [
                {
                  "_name": "TB5 Dock",
                  "device_name_key": "TB5 Dock",
                  "vendor_name_key": "Acme",
                  "mode_key": "usb4",
                  "route_string_key": "1",
                  "receptacle_upstream_ambiguous_tag": {
                    "current_speed_key": "80 Gb/s",
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
                { "_name": "ASM2464PD 480M", "USBKeyLocationID": "0x01110000", "USBDeviceKeyLinkSpeed": "480 Mb/s", "USBDeviceKeyVendorName": "ASMedia" },
                { "_name": "ASM2464PD 10G", "USBKeyLocationID": "0x01210000", "USBDeviceKeyLinkSpeed": "10 Gb/s", "USBDeviceKeyVendorName": "ASMedia" },
                { "_name": "Wooting 60HE", "USBKeyLocationID": "0x01120000", "USBDeviceKeyLinkSpeed": "480 Mb/s", "USBDeviceKeyVendorName": "Wooting" },
                { "_name": "USB Optical Mouse", "USBKeyLocationID": "0x01130000", "USBDeviceKeyLinkSpeed": "12 Mb/s", "USBDeviceKeyVendorName": "Vendor" },
                { "_name": "2.4G Wireless Receiver", "USBKeyLocationID": "0x01140000", "USBDeviceKeyLinkSpeed": "12 Mb/s", "USBDeviceKeyVendorName": "Vendor" },
                { "_name": "Logitech Unifying Receiver", "USBKeyLocationID": "0x01150000", "USBDeviceKeyLinkSpeed": "12 Mb/s", "USBDeviceKeyVendorName": "Logitech" },
                { "_name": "USB DISK 2.0", "USBKeyLocationID": "0x01160000", "USBDeviceKeyLinkSpeed": "480 Mb/s", "USBDeviceKeyVendorName": "Kingston" },
                { "_name": "My Passport 25E2", "USBKeyLocationID": "0x01170000", "USBDeviceKeyLinkSpeed": "480 Mb/s", "USBDeviceKeyVendorName": "Western Digital" },
                { "_name": "SanDisk Extreme PRO USB2 Drive", "USBKeyLocationID": "0x01180000", "USBDeviceKeyLinkSpeed": "480 Mb/s", "USBDeviceKeyVendorName": "SanDisk" },
                {
                  "_name": "External USB2 Hub",
                  "USBKeyLocationID": "0x01190000",
                  "USBDeviceKeyLinkSpeed": "480 Mb/s",
                  "USBDeviceKeyVendorName": "Generic",
                  "_items": [
                    { "_name": "Portable SSD T7 Behind USB2 Hub", "USBKeyLocationID": "0x01191000", "USBDeviceKeyLinkSpeed": "480 Mb/s", "USBDeviceKeyVendorName": "Samsung" }
                  ]
                },
                { "_name": "Portable SSD T7 Native 10G", "USBKeyLocationID": "0x01220000", "USBDeviceKeyLinkSpeed": "10 Gb/s", "USBDeviceKeyVendorName": "Samsung" },
                { "_name": "Samsung T5", "USBKeyLocationID": "0x01230000", "USBDeviceKeyLinkSpeed": "5 Gb/s", "USBDeviceKeyVendorName": "Samsung" },
                { "_name": "CalDigit TS4 Dock", "USBKeyLocationID": "0x011a0000", "USBDeviceKeyLinkSpeed": "480 Mb/s", "USBDeviceKeyVendorName": "CalDigit" },
                {
                  "_name": "External USB3 Gen2 Hub",
                  "USBKeyLocationID": "0x01240000",
                  "USBDeviceKeyLinkSpeed": "10 Gb/s",
                  "USBDeviceKeyVendorName": "Genesys",
                  "_items": [
                    { "_name": "Elements SE", "USBKeyLocationID": "0x01241000", "USBDeviceKeyLinkSpeed": "5 Gb/s", "USBDeviceKeyVendorName": "WD" }
                  ]
                },
                { "_name": "SuperSpeed Drive On USB2 Host Port", "USBKeyLocationID": "0x04100000", "USBDeviceKeyLinkSpeed": "480 Mb/s", "USBDeviceKeyVendorName": "Acme" }
              ]
            }
          ]
        }
        """

        let ioregDict: [String: Any] = [
            "AppleUSBHostPort": [
                // USB-C Port 1..10 with USB 3.x companion (10 Gb/s ceiling)
                [
                    "IOObjectClass": "AppleUSB20XHCIARMPort",
                    "locationID": 0x01100000,
                    "UsbIOPort": "IOService:/AppleARMPE/Port-USB-C@1",
                    "UsbProtocol (2.0)": true,
                    "UsbProtocolCompanion (3.x)": "IOService:/usb-ss@01200000",
                    "IORegistryEntryChildren": [
                        ["IOObjectClass": "IOUSBHostDevice", "locationID": 0x01110000, "bcdUSB": 0x0210, "bDeviceClass": 0, "IORegistryEntryChildren": [["IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 8]]],
                        ["IOObjectClass": "IOUSBHostDevice", "locationID": 0x01120000, "bcdUSB": 0x0200, "bDeviceClass": 0, "IORegistryEntryChildren": [["IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 3]]],
                        ["IOObjectClass": "IOUSBHostDevice", "locationID": 0x01130000, "bcdUSB": 0x0200, "bDeviceClass": 0, "IORegistryEntryChildren": [["IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 3]]],
                        ["IOObjectClass": "IOUSBHostDevice", "locationID": 0x01140000, "bcdUSB": 0x0200, "bDeviceClass": 0, "IORegistryEntryChildren": [["IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 3]]],
                        ["IOObjectClass": "IOUSBHostDevice", "locationID": 0x01150000, "bcdUSB": 0x0200, "bDeviceClass": 0, "IORegistryEntryChildren": [["IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 3]]],
                        ["IOObjectClass": "IOUSBHostDevice", "locationID": 0x01160000, "bcdUSB": 0x0200, "bDeviceClass": 0, "IORegistryEntryChildren": [["IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 8]]],
                        ["IOObjectClass": "IOUSBHostDevice", "locationID": 0x01170000, "bcdUSB": 0x0210, "bDeviceClass": 0, "IORegistryEntryChildren": [["IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 8]]],
                        ["IOObjectClass": "IOUSBHostDevice", "locationID": 0x01180000, "bcdUSB": 0x0200, "bDeviceClass": 0, "IORegistryEntryChildren": [["IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 8]]],
                        [
                            "IOObjectClass": "IOUSBHostDevice",
                            "locationID": 0x01190000,
                            "bcdUSB": 0x0200,
                            "bDeviceClass": 9,
                            "USBPortType": 0,
                            "UsbLinkSpeed": 480_000_000,
                            "IORegistryEntryChildren": [
                                [
                                    "IOObjectClass": "AppleUSB20HubPort",
                                    "locationID": 0x01191000,
                                    "IORegistryEntryChildren": [
                                        ["IOObjectClass": "IOUSBHostDevice", "locationID": 0x01191000, "bcdUSB": 0x0210, "bDeviceClass": 0, "IORegistryEntryChildren": [["IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 8]]]
                                    ]
                                ]
                            ]
                        ],
                        ["IOObjectClass": "IOUSBHostDevice", "locationID": 0x011a0000, "bcdUSB": 0x0201, "bDeviceClass": 17]
                    ]
                ],
                [
                    "IOObjectClass": "AppleUSB30XHCIARMPort",
                    "locationID": 0x01200000,
                    "UsbIOPort": "IOService:/AppleARMPE/Port-USB-C@1",
                    "UsbProtocol (3.x)": true,
                    "IORegistryEntryChildren": [
                        ["IOObjectClass": "IOUSBHostDevice", "locationID": 0x01210000, "bcdUSB": 0x0320, "bDeviceClass": 0, "IORegistryEntryChildren": [["IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 8]]],
                        ["IOObjectClass": "IOUSBHostDevice", "locationID": 0x01220000, "bcdUSB": 0x0310, "bDeviceClass": 0, "IORegistryEntryChildren": [["IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 8]]],
                        ["IOObjectClass": "IOUSBHostDevice", "locationID": 0x01230000, "bcdUSB": 0x0300, "bDeviceClass": 0, "IORegistryEntryChildren": [["IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 8]]],
                        [
                            "IOObjectClass": "IOUSBHostDevice",
                            "locationID": 0x01240000,
                            "bcdUSB": 0x0320,
                            "bDeviceClass": 9,
                            "USBPortType": 0,
                            "UsbLinkSpeed": 10_000_000_000,
                            "IORegistryEntryChildren": [
                                [
                                    "IOObjectClass": "AppleUSB30HubPort",
                                    "locationID": 0x01241000,
                                    "IORegistryEntryChildren": [
                                        ["IOObjectClass": "IOUSBHostDevice", "locationID": 0x01241000, "bcdUSB": 0x0300, "bDeviceClass": 0, "IORegistryEntryChildren": [["IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 8]]]
                                    ]
                                ]
                            ]
                        ]
                    ]
                ],
                // Dedicated USB 2.0-only physical port (no 3.x companion -> 480 Mb/s port ceiling)
                [
                    "IOObjectClass": "AppleUSB20XHCIPort",
                    "locationID": 0x04100000,
                    "UsbIOPort": "IOService:/AppleARMPE/Port-USB-A@1",
                    "UsbProtocol (2.0)": true,
                    "IORegistryEntryChildren": [
                        ["IOObjectClass": "IOUSBHostDevice", "locationID": 0x04100000, "bcdUSB": 0x0210, "bDeviceClass": 0, "IORegistryEntryChildren": [["IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 8]]]
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
                            "Current Link Speed": 8,
                            "Current Link Width": 2,
                            "Link Bandwidth": 200,
                            "IORegistryEntryChildren": [
                                [
                                    "IOObjectClass": "IOThunderboltPort",
                                    "Supported Link Speed": 12,
                                    "Supported Link Width": 2,
                                    "Current Link Speed": 8,
                                    "Current Link Width": 2,
                                    "Link Bandwidth": 200,
                                    "IORegistryEntryChildren": [
                                        [
                                            "IOObjectClass": "IOThunderboltSwitchType3",
                                            "Depth": 1,
                                            "Route String": 1,
                                            "Device Model Name": "OWC Envoy NVMe"
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
                            "Supported Link Speed": 12,
                            "Supported Link Width": 2,
                            "Current Link Speed": 4,
                            "Current Link Width": 2,
                            "Link Bandwidth": 400,
                            "IORegistryEntryChildren": [
                                [
                                    "IOObjectClass": "IOThunderboltPort",
                                    "Supported Link Speed": 12,
                                    "Supported Link Width": 2,
                                    "Current Link Speed": 4,
                                    "Current Link Width": 2,
                                    "Link Bandwidth": 400,
                                    "IORegistryEntryChildren": [
                                        [
                                            "IOObjectClass": "IOThunderboltSwitchType5",
                                            "Depth": 1,
                                            "Route String": 1,
                                            "Device Model Name": "USB4 Hub NVMe",
                                            "IORegistryEntryChildren": [
                                                [
                                                    "IOObjectClass": "IOThunderboltPort",
                                                    "Supported Link Speed": 12,
                                                    "Supported Link Width": 2,
                                                    "Current Link Speed": 8,
                                                    "Current Link Width": 2,
                                                    "Link Bandwidth": 200,
                                                    "IORegistryEntryChildren": [
                                                        [
                                                            "IOObjectClass": "IOThunderboltPort",
                                                            "Supported Link Speed": 12,
                                                            "Supported Link Width": 2,
                                                            "Current Link Speed": 8,
                                                            "Current Link Width": 2,
                                                            "Link Bandwidth": 200,
                                                            "IORegistryEntryChildren": [
                                                                [
                                                                    "IOObjectClass": "IOThunderboltSwitchType3",
                                                                    "Depth": 2,
                                                                    "Route String": "301",
                                                                    "Device Model Name": "Samsung X5"
                                                                ]
                                                            ]
                                                        ]
                                                    ]
                                                ]
                                            ]
                                        ]
                                    ]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let plistData = try PropertyListSerialization.data(fromPropertyList: ioregDict, format: .xml, options: 0)
        let ioregSnap = try IORegistrySnapshot.parsePlistData(plistData)
        let snap = try BusProfilerCollector.parseSystemProfilerJSONValidated(Data(syntheticSP.utf8), ioregSnapshot: ioregSnap)

        // External Class-9 USB2 & USB3 hubs must be hidden as hub containers
        let byName = Dictionary(uniqueKeysWithValues: snap.devices.map { ($0.name, $0) })
        #expect(byName["External USB2 Hub"] == nil)
        #expect(byName["External USB3 Gen2 Hub"] == nil)

        // 1. ASM2464PD 480M (bcdUSB 0x0210 on 10G port) -> Throttled (cable)
        #expect(byName["ASM2464PD 480M"]?.verdict == .throttled)
        #expect(byName["ASM2464PD 480M"]?.bottleneckSegment == .cable)
        // 2. ASM2464PD 10G (bcdUSB 0x0320 without SSP sublink attribute) -> Indeterminate
        #expect(byName["ASM2464PD 10G"]?.verdict == .indeterminate)
        // 3. Wooting 60HE (bcdUSB 0x0200 at 480M) -> Normal
        #expect(byName["Wooting 60HE"]?.verdict == .normal)
        // 4-6. 12 Mb/s HID Class 3 peripherals -> HID peripheral
        #expect(byName["USB Optical Mouse"]?.verdict == .lowSpeedPeripheral)
        #expect(byName["2.4G Wireless Receiver"]?.verdict == .lowSpeedPeripheral)
        #expect(byName["Logitech Unifying Receiver"]?.verdict == .lowSpeedPeripheral)
        // 7. USB DISK 2.0 (bcdUSB 0x0200 at 480M) -> Normal
        #expect(byName["USB DISK 2.0"]?.verdict == .normal)
        // 8. My Passport 25E2 (bcdUSB 0x0210 at 480M) -> Throttled (cable)
        #expect(byName["My Passport 25E2"]?.verdict == .throttled)
        #expect(byName["My Passport 25E2"]?.bottleneckSegment == .cable)
        // 9. SanDisk Extreme PRO USB2 Drive (bcdUSB 0x0200 at 480M) -> Normal (never keyword-guessed!)
        #expect(byName["SanDisk Extreme PRO USB2 Drive"]?.verdict == .normal)
        // 10. Portable SSD T7 Behind USB2 Hub -> Throttled (hub)
        #expect(byName["Portable SSD T7 Behind USB2 Hub"]?.verdict == .throttled)
        #expect(byName["Portable SSD T7 Behind USB2 Hub"]?.bottleneckSegment == .hub)
        // 11. Portable SSD T7 Native 10G (bcdUSB 0x0310 at 10G) -> Normal
        #expect(byName["Portable SSD T7 Native 10G"]?.verdict == .normal)
        // 12. Samsung T5 (bcdUSB 0x0300 at 5G) -> Normal
        #expect(byName["Samsung T5"]?.verdict == .normal)
        // 13. CalDigit TS4 Dock (bDeviceClass 17 Billboard at 480M) -> Normal
        #expect(byName["CalDigit TS4 Dock"]?.verdict == .normal)
        // 14. Elements SE (bcdUSB 0x0300 at 5G behind 10G hub) -> Normal
        #expect(byName["Elements SE"]?.verdict == .normal)
        // 15. OWC Envoy NVMe (40G TB3 switch at 20G on 40G bus) -> Throttled (cable)
        #expect(byName["OWC Envoy NVMe"]?.verdict == .throttled)
        #expect(byName["OWC Envoy NVMe"]?.bottleneckSegment == .cable)
        // 16. Daisy-chained USB4 Hub NVMe (40G -> fullRate) + Samsung X5 (40G capable at 20G -> Throttled cable)
        #expect(byName["USB4 Hub NVMe"]?.verdict == .fullRate)
        #expect(byName["USB4 Hub NVMe"]?.negotiatedGbps == 40.0)
        #expect(byName["Samsung X5"]?.verdict == .throttled)
        #expect(byName["Samsung X5"]?.negotiatedGbps == 20.0)
        #expect(byName["Samsung X5"]?.bottleneckSegment == .cable)
        // Extra: SuperSpeed Drive On USB2 Host Port (bcdUSB 0x0210 on 480M port) -> Throttled (port)
        #expect(byName["SuperSpeed Drive On USB2 Host Port"]?.verdict == .throttled)
        #expect(byName["SuperSpeed Drive On USB2 Host Port"]?.bottleneckSegment == .port)
        // Extra: TB5 Dock (80G on 80G bus) -> Full bus rate
        #expect(byName["TB5 Dock"]?.verdict == .fullRate)

        let zh = AppLocalizer(fixedLanguage: .zhHans)
        #expect(byName["ASM2464PD 480M"]?.localizedDiagnosticDetail(zh).contains("线缆限速") == true)
        #expect(byName["Portable SSD T7 Behind USB2 Hub"]?.localizedDiagnosticDetail(zh).contains("集线器限速") == true)
        #expect(byName["SuperSpeed Drive On USB2 Host Port"]?.localizedDiagnosticDetail(zh).contains("端口限速") == true)
    }

    @Test("M1 Row 4 (Pure system_profiler without ioreg): All 14 raw harness JSON cases never guess by product name and return Indeterminate or FullRate")
    func testM1FourteenRawSystemProfilerHarnessCasesWithoutIOReg() throws {
        let rawCases: [(String, String, [(String, Double, LinkHealthVerdict)])] = [
            ("c1_nvme_480", #"{"SPUSBHostDataType":[{"_name":"USB 3.1 Bus","_items":[{"_name":"ASM2464PD NVMe Enclosure","USBDeviceKeyLinkSpeed":"480 Mb/s","USBDeviceKeyVendorName":"ASMedia"}]}]}"#, [("ASM2464PD NVMe Enclosure", 0.48, .indeterminate)]),
            ("c2_nvme_10G", #"{"SPUSBHostDataType":[{"_name":"USB 3.1 Bus","_items":[{"_name":"ASM2464PD NVMe Enclosure","USBDeviceKeyLinkSpeed":"10 Gb/s","USBDeviceKeyVendorName":"ASMedia"}]}]}"#, [("ASM2464PD NVMe Enclosure", 10.0, .indeterminate)]),
            ("c3_hid", #"{"SPUSBHostDataType":[{"_name":"USB 3.1 Bus","_items":[{"_name":"Wooting 60HE","USBDeviceKeyLinkSpeed":"480 Mb/s","USBDeviceKeyVendorName":"Wooting"},{"_name":"USB Optical Mouse","USBDeviceKeyLinkSpeed":"12 Mb/s","USBDeviceKeyVendorName":"Vendor"},{"_name":"2.4G Wireless Receiver","USBDeviceKeyLinkSpeed":"12 Mb/s","USBDeviceKeyVendorName":"Vendor"},{"_name":"Logitech Unifying Receiver","USBDeviceKeyLinkSpeed":"12 Mb/s","USBDeviceKeyVendorName":"Logitech"}]}]}"#, [
                ("Wooting 60HE", 0.48, .indeterminate),
                ("USB Optical Mouse", 0.012, .indeterminate),
                ("2.4G Wireless Receiver", 0.012, .indeterminate),
                ("Logitech Unifying Receiver", 0.012, .indeterminate),
            ]),
            ("c4_usbdisk2", #"{"SPUSBHostDataType":[{"_name":"USB 3.1 Bus","_items":[{"_name":"USB DISK 2.0","USBDeviceKeyLinkSpeed":"480 Mb/s","USBDeviceKeyVendorName":"Kingston"},{"_name":"My Passport 25E2","USBDeviceKeyLinkSpeed":"480 Mb/s","USBDeviceKeyVendorName":"Western Digital"},{"_name":"SanDisk Extreme PRO USB2 Drive","USBDeviceKeyLinkSpeed":"480 Mb/s","USBDeviceKeyVendorName":"SanDisk"}]}]}"#, [
                ("USB DISK 2.0", 0.48, .indeterminate),
                ("My Passport 25E2", 0.48, .indeterminate),
                ("SanDisk Extreme PRO USB2 Drive", 0.48, .indeterminate),
            ]),
            ("c5_behind_usb2hub", #"{"SPUSBHostDataType":[{"_name":"USB 3.1 Bus","_items":[{"_name":"USB2 Hub","USBDeviceKeyLinkSpeed":"480 Mb/s","USBDeviceKeyVendorName":"Apple","_items":[{"_name":"Portable SSD T7","USBDeviceKeyLinkSpeed":"480 Mb/s","USBDeviceKeyVendorName":"Samsung"}]}]}]}"#, [
                ("USB2 Hub", 0.48, .indeterminate),
                ("Portable SSD T7", 0.48, .indeterminate),
            ]),
            ("c6_t7_native10", #"{"SPUSBHostDataType":[{"_name":"USB 3.1 Bus","_items":[{"_name":"Portable SSD T7","USBDeviceKeyLinkSpeed":"10 Gb/s","USBDeviceKeyVendorName":"Samsung"},{"_name":"Samsung T5","USBDeviceKeyLinkSpeed":"5 Gb/s","USBDeviceKeyVendorName":"Samsung"}]}]}"#, [
                ("Portable SSD T7", 10.0, .indeterminate),
                ("Samsung T5", 5.0, .indeterminate),
            ]),
            ("c7_dock", #"{"SPUSBHostDataType":[{"_name":"USB 3.1 Bus","_items":[{"_name":"CalDigit TS4 Dock","USBDeviceKeyLinkSpeed":"480 Mb/s","USBDeviceKeyVendorName":"CalDigit"},{"_name":"USB3 Gen2 Hub","bDeviceClass":9,"USBDeviceKeyLinkSpeed":"10 Gb/s","USBDeviceKeyVendorName":"Genesys","_items":[{"_name":"Elements SE","USBDeviceKeyLinkSpeed":"5 Gb/s","USBDeviceKeyVendorName":"WD"}]}]}]}"#, [
                ("CalDigit TS4 Dock", 0.48, .indeterminate),
                ("Elements SE", 5.0, .indeterminate),
            ]),
            ("e1_empty", #"{"SPUSBHostDataType":[{"_name":"USB 3.1 Bus"}],"SPThunderboltDataType":[{"_name":"thunderboltusb4_bus_0","receptacle_1_tag":{"current_speed_key":"Up to 40 Gb/s","receptacle_status_key":"receptacle_no_devices_connected"}}],"SPPowerDataType":[]}"#, []),
            ("l1_legacy_nvme_480", #"{"SPUSBDataType":[{"_name":"USB31Bus","host_controller":"AppleT8103USBXHCI","_items":[{"_name":"NVMe Enclosure","manufacturer":"Acme","speed":"Up to 480 Mb/s","serial_num":"LEGACYSER1","vendor_id":"0x1234"}]}]}"#, [
                ("NVMe Enclosure", 0.48, .indeterminate)
            ]),
            ("l2_legacy_nvme_10G_hub_kb", #"{"SPUSBDataType":[{"_name":"USB31Bus","host_controller":"AppleT8103USBXHCI","_items":[{"_name":"4-Port USB 3.0 Hub","bDeviceClass":9,"speed":"Up to 5 Gb/s","_items":[{"_name":"Portable SSD","manufacturer":"Acme","speed":"Up to 10 Gb/s"},{"_name":"Apple Keyboard","speed":"Up to 12 Mb/s"}]}]}]}"#, [
                ("Portable SSD", 10.0, .indeterminate),
                ("Apple Keyboard", 0.012, .indeterminate),
            ]),
            ("t1_tb_dev_20G_on_40bus", #"{"SPThunderboltDataType":[{"_name":"thunderboltusb4_bus_0","receptacle_1_tag":{"current_speed_key":"40 Gb/s","receptacle_status_key":"receptacle_connected"},"_items":[{"_name":"OWC Envoy NVMe","device_name_key":"OWC Envoy NVMe","vendor_name_key":"Acme","mode_key":"thunderbolt_three","receptacle_upstream_ambiguous_tag":{"current_speed_key":"20 Gb/s","receptacle_status_key":"receptacle_connected"}}]}]}"#, [
                ("OWC Envoy NVMe", 20.0, .indeterminate)
            ]),
            ("t2_tb5_80", #"{"SPThunderboltDataType":[{"_name":"thunderboltusb4_bus_0","receptacle_1_tag":{"current_speed_key":"Up to 80 Gb/s","receptacle_status_key":"receptacle_connected"},"_items":[{"_name":"TB5 Dock","device_name_key":"TB5 Dock","vendor_name_key":"Acme","mode_key":"usb4","receptacle_upstream_ambiguous_tag":{"current_speed_key":"80 Gb/s","receptacle_status_key":"receptacle_connected"}}]}]}"#, [
                ("TB5 Dock", 80.0, .fullRate)
            ]),
            ("t3_usb4_and_daisy", #"{"SPThunderboltDataType":[{"_name":"thunderboltusb4_bus_0","receptacle_1_tag":{"current_speed_key":"40 Gb/s","receptacle_status_key":"receptacle_connected"},"_items":[{"_name":"USB4 Hub NVMe","device_name_key":"USB4 Hub NVMe","vendor_name_key":"Acme","mode_key":"usb4","receptacle_upstream_ambiguous_tag":{"current_speed_key":"40 Gb/s","receptacle_status_key":"receptacle_connected"},"_items":[{"_name":"Samsung X5","device_name_key":"Samsung X5","vendor_name_key":"Acme","mode_key":"thunderbolt_three","receptacle_upstream_ambiguous_tag":{"current_speed_key":"20 Gb/s","receptacle_status_key":"receptacle_connected"}}]}]}]}"#, [
                ("USB4 Hub NVMe", 40.0, .fullRate),
                ("Samsung X5", 20.0, .indeterminate),
            ]),
            ("t4_tb_dev_nospeed_on_10bus", #"{"SPThunderboltDataType":[{"_name":"thunderboltusb4_bus_0","receptacle_1_tag":{"current_speed_key":"10 Gb/s","receptacle_status_key":"receptacle_connected"},"_items":[{"_name":"Generic Display","device_name_key":"Generic Display","vendor_name_key":"X","mode_key":"usb4"}]}]}"#, [
                ("Generic Display", 10.0, .indeterminate)
            ]),
        ]

        for (caseID, jsonStr, expected) in rawCases {
            let snap = try BusProfilerCollector.parseSystemProfilerJSONValidated(Data(jsonStr.utf8))
            #expect(snap.devices.count == expected.count, "Mismatch count for \(caseID)")
            for (idx, (expName, expGbps, expVerdict)) in expected.enumerated() where idx < snap.devices.count {
                #expect(snap.devices[idx].name == expName, "\(caseID)[\(idx)] name")
                #expect(abs(snap.devices[idx].negotiatedGbps - expGbps) < 0.0001, "\(caseID)[\(idx)] speed")
                #expect(snap.devices[idx].verdict == expVerdict, "\(caseID)[\(idx)] verdict")
            }
        }
    }

    @Test("UR1: Unverified keys absent from real host ioreg/system_profiler (UsbDeviceMaxSpeedGbps, SuperSpeedPlusMaxSpeedGbps, Usb3LinkPreferred, hasDeviceQualifier, UsbBillboardAltModeFailed, UsbHostPortLinkSpeedLimit, MaxSpeedGbps, device_max_speed) do not affect collection or diagnostics")
    @MainActor
    func testUR1UnverifiedKeysAreIgnored() throws {
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
                  "_name": "TB_MaxSpeedGbps_Only",
                  "device_name_key": "TB_MaxSpeedGbps_Only",
                  "vendor_name_key": "Acme",
                  "mode_key": "thunderbolt_three",
                  "route_string_key": "1",
                  "receptacle_upstream_ambiguous_tag": {
                    "current_speed_key": "20 Gb/s",
                    "receptacle_status_key": "receptacle_connected"
                  }
                },
                {
                  "_name": "TB_device_max_speed_Only",
                  "device_name_key": "TB_device_max_speed_Only",
                  "vendor_name_key": "Acme",
                  "mode_key": "thunderbolt_three",
                  "route_string_key": "9",
                  "device_max_speed": "40 Gb/s",
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
                {
                  "_name": "USB_IOReg_UsbDeviceMaxSpeedGbps",
                  "USBKeyLocationID": "0x01110000",
                  "USBDeviceKeyLinkSpeed": "10 Gb/s",
                  "USBDeviceKeyVendorName": "Acme"
                },
                {
                  "_name": "USB_Inline_UsbDeviceMaxSpeedGbps",
                  "USBKeyLocationID": "0x01120000",
                  "USBDeviceKeyLinkSpeed": "10 Gb/s",
                  "USBDeviceKeyVendorName": "Acme",
                  "bcdUSB": "0x0320",
                  "UsbDeviceMaxSpeedGbps": 20
                },
                {
                  "_name": "USB_SuperSpeedPlusMaxSpeedGbps",
                  "USBKeyLocationID": "0x01130000",
                  "USBDeviceKeyLinkSpeed": "10 Gb/s",
                  "USBDeviceKeyVendorName": "Acme"
                },
                {
                  "_name": "USB_device_max_speed",
                  "USBKeyLocationID": "0x01140000",
                  "USBDeviceKeyLinkSpeed": "10 Gb/s",
                  "USBDeviceKeyVendorName": "Acme",
                  "bcdUSB": "0x0320",
                  "device_max_speed": "20 Gb/s"
                },
                {
                  "_name": "USB_Usb3LinkPreferred",
                  "USBKeyLocationID": "0x01150000",
                  "USBDeviceKeyLinkSpeed": "480 Mb/s",
                  "USBDeviceKeyVendorName": "Acme",
                  "Usb3LinkPreferred": true
                },
                {
                  "_name": "USB_hasDeviceQualifier",
                  "USBKeyLocationID": "0x01160000",
                  "USBDeviceKeyLinkSpeed": "12 Mb/s",
                  "USBDeviceKeyVendorName": "Acme",
                  "hasDeviceQualifier": true
                },
                {
                  "_name": "USB_UsbBillboardAltModeFailed",
                  "USBKeyLocationID": "0x01170000",
                  "USBDeviceKeyLinkSpeed": "480 Mb/s",
                  "USBDeviceKeyVendorName": "Acme",
                  "UsbBillboardAltModeFailed": true
                },
                {
                  "_name": "USB_PortLimit_Only",
                  "USBKeyLocationID": "0x02110000",
                  "USBDeviceKeyLinkSpeed": "480 Mb/s",
                  "USBDeviceKeyVendorName": "Acme"
                }
              ]
            }
          ]
        }
        """

        let ioregDict: [String: Any] = [
            "AppleUSBHostPort": [
                [
                    "IOObjectClass": "AppleUSB30XHCIARMPort",
                    "locationID": 0x01100000,
                    "UsbIOPort": "IOService:/AppleARMPE/Port-USB-C@1",
                    "UsbProtocol (3.x)": true,
                    "IORegistryEntryChildren": [
                        [
                            "IOObjectClass": "IOUSBHostDevice",
                            "locationID": 0x01110000,
                            "bcdUSB": 0x0320,
                            "bDeviceClass": 0,
                            "UsbDeviceMaxSpeedGbps": 20,
                            "IORegistryEntryChildren": [["IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 8]]
                        ],
                        [
                            "IOObjectClass": "IOUSBHostDevice",
                            "locationID": 0x01130000,
                            "bcdUSB": 0x0320,
                            "bDeviceClass": 0,
                            "SuperSpeedPlusMaxSpeedGbps": 20,
                            "IORegistryEntryChildren": [["IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 8]]
                        ],
                        [
                            "IOObjectClass": "IOUSBHostDevice",
                            "locationID": 0x01150000,
                            "bcdUSB": 0x0200,
                            "bDeviceClass": 0,
                            "Usb3LinkPreferred": true,
                            "IORegistryEntryChildren": [["IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 8]]
                        ],
                        [
                            "IOObjectClass": "IOUSBHostDevice",
                            "locationID": 0x01160000,
                            "bcdUSB": 0x0200,
                            "bDeviceClass": 0,
                            "hasDeviceQualifier": true,
                            "IORegistryEntryChildren": [["IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 8]]
                        ],
                        [
                            "IOObjectClass": "IOUSBHostDevice",
                            "locationID": 0x01170000,
                            "bcdUSB": 0x0201,
                            "bDeviceClass": 17,
                            "UsbBillboardAltModeFailed": true
                        ]
                    ]
                ],
                [
                    "IOObjectClass": "AppleUSB30XHCIARMPort",
                    "locationID": 0x02100000,
                    "UsbIOPort": "IOService:/AppleARMPE/Port-USB-C@2",
                    "UsbHostPortLinkSpeedLimit": 5,
                    "IORegistryEntryChildren": [
                        [
                            "IOObjectClass": "IOUSBHostDevice",
                            "locationID": 0x02110000,
                            "bcdUSB": 0x0200,
                            "bDeviceClass": 0,
                            "IORegistryEntryChildren": [["IOObjectClass": "IOUSBHostInterface", "bInterfaceClass": 8]]
                        ]
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
                            "IORegistryEntryChildren": [
                                [
                                    "IOObjectClass": "IOThunderboltSwitchType3",
                                    "Depth": 1,
                                    "Route String": 1,
                                    "Device Model Name": "TB_MaxSpeedGbps_Only",
                                    "MaxSpeedGbps": 40
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let plistData = try PropertyListSerialization.data(fromPropertyList: ioregDict, format: .xml, options: 0)
        let ioregSnap = try IORegistrySnapshot.parsePlistData(plistData)
        let snap = try BusProfilerCollector.parseSystemProfilerJSONValidated(Data(syntheticSP.utf8), ioregSnapshot: ioregSnap)
        let byName = Dictionary(uniqueKeysWithValues: snap.devices.map { ($0.name, $0) })

        // 1. MaxSpeedGbps (TB ioreg)
        let tbMaxKeyDev = try #require(byName["TB_MaxSpeedGbps_Only"])
        #expect(tbMaxKeyDev.deviceMaxGbps == nil)
        #expect(tbMaxKeyDev.verdict == .indeterminate)

        // 2. device_max_speed (TB & USB SP JSON)
        let tbSpMaxDev = try #require(byName["TB_device_max_speed_Only"])
        #expect(tbSpMaxDev.deviceMaxGbps == nil)
        #expect(tbSpMaxDev.verdict == .indeterminate)

        let usbSpMaxDev = try #require(byName["USB_device_max_speed"])
        #expect(usbSpMaxDev.deviceMaxGbps == nil)
        #expect(usbSpMaxDev.verdict == .indeterminate)

        // 3. UsbDeviceMaxSpeedGbps (ioreg & SP JSON)
        let usbMaxIoreg = try #require(byName["USB_IOReg_UsbDeviceMaxSpeedGbps"])
        #expect(usbMaxIoreg.deviceMaxGbps == nil)
        #expect(usbMaxIoreg.verdict == .indeterminate)

        let usbMaxInline = try #require(byName["USB_Inline_UsbDeviceMaxSpeedGbps"])
        #expect(usbMaxInline.deviceMaxGbps == nil)
        #expect(usbMaxInline.verdict == .indeterminate)

        // 4. SuperSpeedPlusMaxSpeedGbps (ioreg)
        let sspDev = try #require(byName["USB_SuperSpeedPlusMaxSpeedGbps"])
        #expect(sspDev.deviceMaxGbps == nil)
        #expect(sspDev.verdict == .indeterminate)

        // 5. Usb3LinkPreferred (ioreg & SP JSON)
        let prefDrive = try #require(byName["USB_Usb3LinkPreferred"])
        #expect(prefDrive.verdict == .normal)

        // 6. hasDeviceQualifier (ioreg & SP JSON)
        let qualDrive = try #require(byName["USB_hasDeviceQualifier"])
        #expect(qualDrive.verdict == .indeterminate)

        // 7. UsbBillboardAltModeFailed (ioreg & SP JSON)
        let billboard = try #require(byName["USB_UsbBillboardAltModeFailed"])
        #expect(billboard.verdict == .normal)

        // 8. UsbHostPortLinkSpeedLimit (ioreg port)
        let limitPortDev = try #require(byName["USB_PortLimit_Only"])
        #expect(limitPortDev.portCeilingGbps == nil)
        #expect(limitPortDev.verdict == .normal)
    }
}
