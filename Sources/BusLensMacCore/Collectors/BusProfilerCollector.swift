import Foundation

public enum BusProfilerCollector {

    private static let redactedKeys: Set<String> = [
        "serial_num",
        "device_serial",
        "USBDeviceKeySerialNumber",
        "domain_uuid_key",
        "switch_uid_key",
        "receptacle_upstream_ambiguous_tag"
    ]

    /// Recursively strips hardware serial numbers and UUID keys from parsed JSON dictionaries.
    public static func redactHardwareIdentifiers(_ raw: Any) -> Any {
        if let dict = raw as? [String: Any] {
            var cleaned: [String: Any] = [:]
            for (k, v) in dict {
                let lower = k.lowercased()
                if redactedKeys.contains(k) || lower.contains("serial") || lower.contains("uuid") || lower.contains("uid_key") {
                    continue
                }
                cleaned[k] = redactHardwareIdentifiers(v)
            }
            return cleaned
        }
        if let arr = raw as? [Any] {
            return arr.map { redactHardwareIdentifiers($0) }
        }
        return raw
    }

    public static func parseSystemProfilerJSON(_ data: Data, capturedAt: Date = Date()) -> BusTopologySnapshot {
        guard let rawObj = try? JSONSerialization.jsonObject(with: data),
              let root = redactHardwareIdentifiers(rawObj) as? [String: Any] else {
            return BusTopologySnapshot(
                capturedAt: capturedAt,
                controllers: [],
                devices: [],
                power: PowerDeliverySummary(powerSource: "Unknown")
            )
        }

        var controllers: [PhysicalPortController] = []
        var allDevices: [AttachedBusDevice] = []

        // 1. Parse SPThunderboltDataType
        if let tbArray = root["SPThunderboltDataType"] as? [[String: Any]] {
            let sortedTB = tbArray.sorted { (a, b) in
                String(describing: a["_name"] ?? "") < String(describing: b["_name"] ?? "")
            }
            for busDict in sortedTB {
                let rawName = (busDict["_name"] as? String) ?? "Thunderbolt Bus"
                let displayTitle = prettifyBusName(rawName)
                let rec = findFirstReceptacle(in: busDict)
                let speedStr = (rec?["current_speed_key"] as? String) ?? "Up to 40 Gb/s"
                let statusStr = (rec?["receptacle_status_key"] as? String) ?? ""
                let ceilingGbps = max(40.0, BottleneckDiagnoser.parseSpeedGbps(speedStr))
                let isConnected = statusStr == "receptacle_connected" || (busDict["_items"] as? [[String: Any]])?.isEmpty == false
                let negotiatedGbps = isConnected ? BottleneckDiagnoser.parseSpeedGbps(speedStr) : 0.0

                var busDevices: [AttachedBusDevice] = []
                if let children = busDict["_items"] as? [[String: Any]] {
                    walkThunderboltDevices(
                        items: children,
                        busTitle: displayTitle,
                        fallbackSpeedLabel: speedStr,
                        fallbackGbps: negotiatedGbps > 0 ? negotiatedGbps : ceilingGbps,
                        ceilingGbps: ceilingGbps,
                        depth: 0,
                        into: &busDevices
                    )
                }

                controllers.append(
                    PhysicalPortController(
                        id: "tb::\(rawName)",
                        title: displayTitle,
                        protocolKind: .thunderboltUSB4,
                        maxRateLabel: BottleneckDiagnoser.formatSpeedGbps(ceilingGbps),
                        maxGbps: ceilingGbps,
                        negotiatedGbps: negotiatedGbps,
                        isConnected: isConnected,
                        devices: busDevices
                    )
                )
                allDevices.append(contentsOf: busDevices)
            }
        }

        // 2. Parse SPUSBHostDataType (macOS 26+) or SPUSBDataType (macOS 14-15)
        let usbControllersRaw: [[String: Any]] = {
            if let hostArr = root["SPUSBHostDataType"] as? [[String: Any]], !hostArr.isEmpty {
                return hostArr
            }
            if let legacyArr = root["SPUSBDataType"] as? [[String: Any]], !legacyArr.isEmpty {
                return legacyArr
            }
            return []
        }()

        for (idx, usbBus) in usbControllersRaw.enumerated() {
            let rawBusTitle = (usbBus["_name"] as? String) ?? "USB Bus"
            let busTitle = "\(rawBusTitle) #\(idx + 1)"
            var usbDevices: [AttachedBusDevice] = []
            if let items = usbBus["_items"] as? [[String: Any]] {
                walkUSBDevices(
                    items: items,
                    busTitle: busTitle,
                    behindHub: false,
                    depth: 0,
                    into: &usbDevices
                )
            }
            let peak = usbDevices.map(\.negotiatedGbps).max() ?? 0.0
            if !usbDevices.isEmpty {
                controllers.append(
                    PhysicalPortController(
                        id: "usb::\(idx)::\(rawBusTitle)",
                        title: busTitle,
                        protocolKind: .usbHost,
                        maxRateLabel: "10 Gb/s",
                        maxGbps: 10.0,
                        negotiatedGbps: peak,
                        isConnected: true,
                        devices: usbDevices
                    )
                )
                allDevices.append(contentsOf: usbDevices)
            }
        }

        // 3. Parse SPPowerDataType
        let power = parsePower(root["SPPowerDataType"] as? [[String: Any]] ?? [])

        return BusTopologySnapshot(
            capturedAt: capturedAt,
            controllers: controllers,
            devices: allDevices,
            power: power
        )
    }

    public static func collectLiveHost() -> BusTopologySnapshot {
        let out = runSystemProfiler()
        return parseSystemProfilerJSON(out, capturedAt: Date())
    }

    // MARK: - Helpers

    private static func walkThunderboltDevices(
        items: [[String: Any]],
        busTitle: String,
        fallbackSpeedLabel: String,
        fallbackGbps: Double,
        ceilingGbps: Double,
        depth: Int,
        into out: inout [AttachedBusDevice]
    ) {
        for (idx, item) in items.enumerated() {
            let name = (item["device_name_key"] as? String)
                ?? (item["_name"] as? String)
                ?? "Thunderbolt Device"
            let vendor = (item["vendor_name_key"] as? String) ?? "Thunderbolt Vendor"
            let mode = (item["mode_key"] as? String) ?? "thunderbolt_3"
            let rec = findFirstReceptacle(in: item)
            let speedLabel = (rec?["current_speed_key"] as? String) ?? fallbackSpeedLabel
            let gbps = {
                let parsed = BottleneckDiagnoser.parseSpeedGbps(speedLabel)
                return parsed > 0 ? parsed : fallbackGbps
            }()

            let eval = BottleneckDiagnoser.evaluateDevice(
                name: name,
                vendor: vendor,
                protocolKind: .thunderboltUSB4,
                negotiatedGbps: gbps,
                portCeilingGbps: ceilingGbps,
                behindHub: depth > 0
            )

            out.append(
                AttachedBusDevice(
                    id: "tb-dev::\(busTitle)::\(depth)::\(idx)::\(name)",
                    name: name,
                    vendor: vendor,
                    busName: busTitle,
                    protocolKind: .thunderboltUSB4,
                    negotiatedSpeedLabel: BottleneckDiagnoser.formatSpeedGbps(gbps),
                    negotiatedGbps: gbps,
                    portCeilingGbps: ceilingGbps,
                    depth: depth,
                    modeDescription: mode.replacingOccurrences(of: "_", with: " "),
                    verdict: eval.verdict,
                    diagnosticDetail: eval.detail
                )
            )

            if let nested = item["_items"] as? [[String: Any]] {
                walkThunderboltDevices(
                    items: nested,
                    busTitle: busTitle,
                    fallbackSpeedLabel: speedLabel,
                    fallbackGbps: gbps,
                    ceilingGbps: ceilingGbps,
                    depth: depth + 1,
                    into: &out
                )
            }
        }
    }

    private static func walkUSBDevices(
        items: [[String: Any]],
        busTitle: String,
        behindHub: Bool,
        depth: Int,
        into out: inout [AttachedBusDevice]
    ) {
        for (idx, item) in items.enumerated() {
            let name = (item["_name"] as? String) ?? "USB Device"
            let vendor = (item["USBDeviceKeyVendorName"] as? String)
                ?? (item["manufacturer"] as? String)
                ?? "USB Peripheral"
            let rawSpeed = (item["USBDeviceKeyLinkSpeed"] as? String)
                ?? (item["link_speed"] as? String)
                ?? (item["speed"] as? String)
                ?? "480 Mb/s"
            let gbps = BottleneckDiagnoser.parseSpeedGbps(rawSpeed)
            let isHub = name.lowercased().contains("hub")

            if !isHub {
                let eval = BottleneckDiagnoser.evaluateDevice(
                    name: name,
                    vendor: vendor,
                    protocolKind: .usbHost,
                    negotiatedGbps: gbps,
                    portCeilingGbps: 40.0,
                    behindHub: behindHub
                )
                out.append(
                    AttachedBusDevice(
                        id: "usb-dev::\(busTitle)::\(depth)::\(idx)::\(name)",
                        name: name,
                        vendor: vendor,
                        busName: busTitle,
                        protocolKind: .usbHost,
                        negotiatedSpeedLabel: BottleneckDiagnoser.formatSpeedGbps(gbps),
                        negotiatedGbps: gbps,
                        portCeilingGbps: 10.0,
                        depth: depth,
                        modeDescription: behindHub ? "via USB hub" : "direct root port",
                        verdict: eval.verdict,
                        diagnosticDetail: eval.detail
                    )
                )
            }

            if let children = item["_items"] as? [[String: Any]] {
                walkUSBDevices(
                    items: children,
                    busTitle: busTitle,
                    behindHub: behindHub || isHub,
                    depth: depth + 1,
                    into: &out
                )
            }
        }
    }

    private static func parsePower(_ powerItems: [[String: Any]]) -> PowerDeliverySummary {
        var source = "AC Power"
        var watts: Int?
        var lowPower = false

        for entry in powerItems {
            if let w = entry["sppower_ac_charger_watts"] as? String, let parsed = Int(w) {
                watts = parsed
            } else if let wInt = entry["sppower_ac_charger_watts"] as? Int {
                watts = wInt
            }
            if let ac = entry["AC Power"] as? [String: Any] {
                if let cur = ac["Current Power Source"] as? String, cur == "TRUE" {
                    source = "AC Line Power"
                }
                if let lpm = ac["LowPowerMode"] as? Int, lpm == 1 {
                    lowPower = true
                }
            }
        }
        return PowerDeliverySummary(powerSource: source, negotiatedWatts: watts, lowPowerMode: lowPower)
    }

    private static func findFirstReceptacle(in dict: [String: Any]) -> [String: Any]? {
        for (k, v) in dict where k.hasPrefix("receptacle_") && k.hasSuffix("_tag") {
            if let sub = v as? [String: Any] {
                return sub
            }
        }
        return nil
    }

    private static func prettifyBusName(_ raw: String) -> String {
        if let last = raw.split(separator: "_").last, let idx = Int(last) {
            return "Thunderbolt / USB4 Bus \(idx)"
        }
        return raw
    }

    private static func runSystemProfiler() -> Data {
        let path = "/usr/sbin/system_profiler"
        guard FileManager.default.isExecutableFile(atPath: path) else { return Data() }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = [
            "SPThunderboltDataType",
            "SPUSBHostDataType",
            "SPUSBDataType",
            "SPPowerDataType",
            "-json"
        ]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            return data
        } catch {
            return Data()
        }
    }
}
