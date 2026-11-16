import Foundation

public enum BusCollectorError: Error, Equatable, Sendable {
    case unreadableInput(String)
    case invalidJSONFormat
    case invalidIORegistryFormat
    case systemProfilerFailed(Int32)

    @MainActor
    public func localizedMessage(_ localizer: AppLocalizer) -> String {
        switch self {
        case .unreadableInput(let path):
            return localizer.L(
                "Cannot read input file '\(path)'.",
                "无法读取输入文件 '\(path)'。"
            )
        case .invalidJSONFormat:
            return localizer.L(
                "Input is not a valid system_profiler JSON object.",
                "输入内容不是有效的 system_profiler JSON 对象。"
            )
        case .invalidIORegistryFormat:
            return localizer.L(
                "Input is not a valid ioreg XML property list.",
                "输入内容不是有效的 ioreg XML 属性列表。"
            )
        case .systemProfilerFailed(let code):
            return localizer.L(
                "/usr/sbin/system_profiler failed with exit code \(code).",
                "/usr/sbin/system_profiler 执行失败（退出码 \(code)）。"
            )
        }
    }
}

public enum BusProfilerCollector {

    private static let redactedKeys: Set<String> = [
        // Legacy SPUSBDataType serial key from public samples (unverified on the author's machine; new SPUSBHostDataType uses USBDeviceKeySerialNumber).
        "serial_num",
        "USBDeviceKeySerialNumber",
        "domain_uuid_key",
        "switch_uid_key"
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

    public static func parseSystemProfilerJSON(
        _ data: Data,
        capturedAt: Date = Date(),
        pmsetOutput: String? = nil,
        ioregSnapshot: IORegistrySnapshot? = nil
    ) -> BusTopologySnapshot {
        if let snap = try? parseSystemProfilerJSONValidated(
            data,
            capturedAt: capturedAt,
            pmsetOutput: pmsetOutput,
            ioregSnapshot: ioregSnapshot
        ) {
            return snap
        }
        return BusTopologySnapshot(
            capturedAt: capturedAt,
            controllers: [],
            devices: [],
            power: PowerDeliverySummary()
        )
    }

    public static func parseSystemProfilerJSONValidated(
        _ data: Data,
        capturedAt: Date = Date(),
        pmsetOutput: String? = nil,
        ioregSnapshot: IORegistrySnapshot? = nil
    ) throws -> BusTopologySnapshot {
        guard !data.isEmpty,
              let rawObj = try? JSONSerialization.jsonObject(with: data),
              let root = redactHardwareIdentifiers(rawObj) as? [String: Any] else {
            throw BusCollectorError.invalidJSONFormat
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
                let routerID = extractTrailingInteger(from: rawName)
                let tbBusRecord = routerID.flatMap { ioregSnapshot?.thunderboltBusesByRouter[$0] }
                let displayTitle = prettifyBusName(rawName)
                let rec = findFirstReceptacle(in: busDict)
                let speedStr = rec?["current_speed_key"] as? String
                let statusStr = (rec?["receptacle_status_key"] as? String) ?? ""
                let isConnected = statusStr == "receptacle_connected"
                    || (busDict["_items"] as? [[String: Any]])?.isEmpty == false
                let negotiatedGbps = (isConnected && speedStr != nil)
                    ? BottleneckDiagnoser.parseSpeedGbps(speedStr!)
                    : 0.0

                let ceilingGbps = explicitReceptacleCeilingGbps(in: rec) ?? tbBusRecord?.portCeilingGbps
                let busPhysicalPort: String? = {
                    if let mapped = tbBusRecord?.physicalPortLabel {
                        return mapped
                    }
                    if let rid = rec?["receptacle_id_key"] as? String,
                       !rid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let trimmed = rid.trimmingCharacters(in: .whitespacesAndNewlines)
                        return ioregSnapshot?.socketToPhysicalPort[trimmed]
                    }
                    return nil
                }()

                var busDevices: [AttachedBusDevice] = []
                if let children = busDict["_items"] as? [[String: Any]] {
                    walkThunderboltDevices(
                        items: children,
                        busTitle: displayTitle,
                        routerID: routerID,
                        physicalPort: busPhysicalPort,
                        fallbackSpeedLabel: speedStr,
                        fallbackGbps: negotiatedGbps,
                        ceilingGbps: ceilingGbps,
                        ioregSnapshot: ioregSnapshot,
                        depth: 0,
                        into: &busDevices
                    )
                }

                controllers.append(
                    PhysicalPortController(
                        id: "tb::\(rawName)",
                        title: displayTitle,
                        protocolKind: .thunderboltUSB4,
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

        var rawTitleCounts: [String: Int] = [:]
        for usbBus in usbControllersRaw {
            let t = (usbBus["_name"] as? String) ?? "USB Bus"
            rawTitleCounts[t, default: 0] += 1
        }

        for (idx, usbBus) in usbControllersRaw.enumerated() {
            let rawBusTitle = (usbBus["_name"] as? String) ?? "USB Bus"
            let busTitle = formatUSBControllerTitle(
                rawTitle: rawBusTitle,
                usbBus: usbBus,
                index: idx,
                duplicateCount: rawTitleCounts[rawBusTitle] ?? 1
            )
            let controllerCeilingGbps = explicitUSBControllerCeilingGbps(in: usbBus)

            var usbDevices: [AttachedBusDevice] = []
            if let items = usbBus["_items"] as? [[String: Any]] {
                walkUSBDevices(
                    items: items,
                    busTitle: busTitle,
                    controllerCeilingGbps: controllerCeilingGbps,
                    ancestorPhysicalPort: nil,
                    ioregSnapshot: ioregSnapshot,
                    behindExternalHub: false,
                    depth: 0,
                    into: &usbDevices
                )
            }
            let peak = usbDevices.map(\.negotiatedGbps).max() ?? 0.0
            let resolvedControllerCeiling = controllerCeilingGbps ?? usbDevices.compactMap(\.portCeilingGbps).max()
            if !usbDevices.isEmpty {
                controllers.append(
                    PhysicalPortController(
                        id: "usb::\(idx)::\(busTitle)",
                        title: busTitle,
                        protocolKind: .usbHost,
                        maxGbps: resolvedControllerCeiling,
                        negotiatedGbps: peak,
                        isConnected: true,
                        devices: usbDevices
                    )
                )
                allDevices.append(contentsOf: usbDevices)
            }
        }

        // 3. Parse SPPowerDataType (+ optional pmset fallback)
        let power = parsePower(root["SPPowerDataType"] as? [[String: Any]] ?? [], pmsetOutput: pmsetOutput)

        return BusTopologySnapshot(
            capturedAt: capturedAt,
            controllers: controllers,
            devices: allDevices,
            power: power
        )
    }

    public static func collectLiveHost() -> BusTopologySnapshot {
        if let snap = try? collectLiveHostValidated() {
            return snap
        }
        return BusTopologySnapshot(
            capturedAt: Date(),
            controllers: [],
            devices: [],
            power: PowerDeliverySummary()
        )
    }

    public static func collectLiveHostValidated() throws -> BusTopologySnapshot {
        let group = DispatchGroup()
        let lock = NSLock()
        var spResult: Result<Data, Error>?
        var pmsetOutput: String?
        var ioregSnapshot: IORegistrySnapshot?

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let res = Result { try runSystemProfilerValidated() }
            lock.lock()
            spResult = res
            lock.unlock()
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let pm = runPmsetOptional()
            lock.lock()
            pmsetOutput = pm
            lock.unlock()
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let io = IORegistrySnapshot.collectLiveReadOnly()
            lock.lock()
            ioregSnapshot = io
            lock.unlock()
            group.leave()
        }

        group.wait()
        let out = try (spResult ?? .failure(BusCollectorError.systemProfilerFailed(-1))).get()
        return try parseSystemProfilerJSONValidated(
            out,
            capturedAt: Date(),
            pmsetOutput: pmsetOutput,
            ioregSnapshot: ioregSnapshot
        )
    }

    // MARK: - Helpers

    private static func explicitReceptacleCeilingGbps(in rec: [String: Any]?) -> Double? {
        guard let rec else { return nil }
        if let curRaw = rec["current_speed_key"] as? String,
           curRaw.lowercased().contains("up to") {
            let val = BottleneckDiagnoser.parseSpeedGbps(curRaw)
            if val > 0 { return val }
        }
        return nil
    }

    private static func explicitUSBControllerCeilingGbps(in usbBus: [String: Any]) -> Double? {
        _ = usbBus
        return nil
    }

    private static func formatUSBControllerTitle(
        rawTitle: String,
        usbBus: [String: Any],
        index: Int,
        duplicateCount: Int
    ) -> String {
        // `location_id`: legacy SPUSBDataType key from public samples (e.g. "0x01140000 / 3"); unverified on the author's machine (new SPUSBHostDataType uses `USBKeyLocationID`).
        if let rawLoc = (usbBus["USBKeyLocationID"] as? String) ?? (usbBus["location_id"] as? String),
           let hexLoc = extractHexToken(from: rawLoc) {
            return "\(rawTitle) (\(hexLoc))"
        }
        if duplicateCount > 1 {
            return "\(rawTitle) (bus \(index + 1))"
        }
        return rawTitle
    }

    private static func extractHexToken(from raw: String) -> String? {
        let pattern = #"0x[0-9A-Fa-f]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let range = Range(match.range, in: raw) else {
            return nil
        }
        return String(raw[range]).lowercased()
    }

    private static func extractTrailingInteger(from raw: String) -> Int? {
        if let last = raw.split(separator: "_").last, let val = Int(last) {
            return val
        }
        return nil
    }

    private static func walkThunderboltDevices(
        items: [[String: Any]],
        busTitle: String,
        routerID: Int?,
        physicalPort: String?,
        fallbackSpeedLabel: String?,
        fallbackGbps: Double,
        ceilingGbps: Double?,
        ioregSnapshot: IORegistrySnapshot?,
        depth: Int,
        into out: inout [AttachedBusDevice]
    ) {
        for (idx, item) in items.enumerated() {
            let name = (item["device_name_key"] as? String)
                ?? (item["_name"] as? String)
                ?? "Thunderbolt Device"
            let vendor = (item["vendor_name_key"] as? String) ?? "Unknown vendor"
            let mode = (item["mode_key"] as? String) ?? "thunderbolt_3"
            let routeStr = item["route_string_key"] as? String
            let rec = findDeviceReceptacle(in: item)
            let itemSpeedStr = rec?["current_speed_key"] as? String
            let tbRecord = ioregSnapshot?.resolveThunderboltDevice(
                routerID: routerID,
                routeString: routeStr,
                name: name
            )
            let gbps: Double = {
                if let itemSpeedStr {
                    let parsed = BottleneckDiagnoser.parseSpeedGbps(itemSpeedStr)
                    if parsed > 0 { return parsed }
                }
                if let ioNeg = tbRecord?.negotiatedGbps, ioNeg > 0 {
                    return ioNeg
                }
                return fallbackGbps
            }()

            let capability = tbRecord?.capability

            let eval = BottleneckDiagnoser.evaluate(
                protocolKind: .thunderboltUSB4,
                negotiatedGbps: gbps,
                portCeilingGbps: ceilingGbps,
                behindExternalHub: false,
                capability: capability
            )

            out.append(
                AttachedBusDevice(
                    id: "tb-dev::\(busTitle)::\(depth)::\(idx)::\(name)",
                    name: name,
                    vendor: vendor,
                    busName: busTitle,
                    physicalPort: physicalPort,
                    locationID: routeStr.map { "route:\($0)" },
                    protocolKind: .thunderboltUSB4,
                    negotiatedSpeedLabel: gbps > 0 ? BottleneckDiagnoser.formatSpeedGbps(gbps) : "Unknown",
                    negotiatedGbps: gbps,
                    portCeilingGbps: ceilingGbps,
                    deviceMaxGbps: eval.deviceMaxGbps,
                    depth: depth,
                    behindExternalHub: false,
                    modeDescription: mode.replacingOccurrences(of: "_", with: " "),
                    capability: capability,
                    bottleneckSegment: eval.bottleneckSegment,
                    isInferred: eval.isInferred,
                    isPhysicalPortInferred: physicalPort != nil,
                    verdict: eval.verdict,
                    diagnosticDetail: eval.detail
                )
            )

            if let nested = item["_items"] as? [[String: Any]] {
                walkThunderboltDevices(
                    items: nested,
                    busTitle: busTitle,
                    routerID: routerID,
                    physicalPort: physicalPort,
                    fallbackSpeedLabel: itemSpeedStr ?? fallbackSpeedLabel,
                    fallbackGbps: gbps,
                    ceilingGbps: ceilingGbps,
                    ioregSnapshot: ioregSnapshot,
                    depth: depth + 1,
                    into: &out
                )
            }
        }
    }

    private static func isBuiltInUSBNode(_ item: [String: Any]) -> Bool {
        if let hwType = item["USBKeyHardwareType"] as? String,
           hwType.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("Built-in") == .orderedSame {
            return true
        }
        // `Built-in_Device`: legacy SPUSBDataType hub item key from public XML samples (value "Yes"); JSON key name unconfirmed and unverified on the author's machine.
        if parseBoolFlag(item["Built-in_Device"]) == true {
            return true
        }
        return false
    }

    private static func isExplicitUSBHubClass(_ item: [String: Any]) -> Bool {
        if let clsInt = item["bDeviceClass"] as? Int, clsInt == 9 {
            return true
        }
        if let clsStr = item["bDeviceClass"] as? String {
            let normalized = clsStr.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalized == "9" || normalized == "0x09" || normalized == "0x9" || normalized == "hub" {
                return true
            }
        }
        return false
    }

    private static func extractInlineUSBDescriptor(_ item: [String: Any]) -> DeviceCapabilityDescriptor? {
        let bcd = parseFlexibleInt(item["bcdUSB"])
        let devClass = parseFlexibleInt(item["bDeviceClass"])
        var ifaceClasses: [Int] = []
        if let singleIface = parseFlexibleInt(item["bInterfaceClass"]) {
            ifaceClasses.append(singleIface)
        }
        if bcd == nil && devClass == nil && ifaceClasses.isEmpty {
            return nil
        }
        return DeviceCapabilityDescriptor(
            bcdUSB: bcd,
            usbDeviceClass: devClass,
            usbInterfaceClasses: ifaceClasses
        )
    }

    private static func parseFlexibleInt(_ raw: Any?) -> Int? {
        guard let raw else { return nil }
        if let i = raw as? Int { return i }
        if let n = raw as? NSNumber { return n.intValue }
        if let s = raw as? String {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if trimmed.hasPrefix("0x"), let hex = Int(trimmed.dropFirst(2), radix: 16) {
                return hex
            }
            if let dec = Int(trimmed) {
                return dec
            }
        }
        return nil
    }

    private static func mergeDescriptors(
        ioregCap: DeviceCapabilityDescriptor?,
        inlineCap: DeviceCapabilityDescriptor?
    ) -> DeviceCapabilityDescriptor? {
        guard ioregCap != nil || inlineCap != nil else { return nil }
        return DeviceCapabilityDescriptor(
            bcdUSB: inlineCap?.bcdUSB ?? ioregCap?.bcdUSB,
            usbDeviceClass: inlineCap?.usbDeviceClass ?? ioregCap?.usbDeviceClass,
            usbInterfaceClasses: !(inlineCap?.usbInterfaceClasses.isEmpty ?? true)
                ? (inlineCap?.usbInterfaceClasses ?? [])
                : (ioregCap?.usbInterfaceClasses ?? []),
            tbSupportedLinkGbps: inlineCap?.tbSupportedLinkGbps ?? ioregCap?.tbSupportedLinkGbps
        )
    }

    private static func walkUSBDevices(
        items: [[String: Any]],
        busTitle: String,
        controllerCeilingGbps: Double?,
        ancestorPhysicalPort: String?,
        ioregSnapshot: IORegistrySnapshot?,
        behindExternalHub: Bool,
        upstreamHubGbps: Double? = nil,
        depth: Int,
        into out: inout [AttachedBusDevice]
    ) {
        for (idx, item) in items.enumerated() {
            let name = (item["_name"] as? String) ?? "USB Device"
            let vendor: String = {
                if let v = (item["USBDeviceKeyVendorName"] as? String) ?? (item["manufacturer"] as? String),
                   !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return v.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                // `vendor_id`: legacy SPUSBDataType key from public samples; unverified on the author's machine (new SPUSBHostDataType uses `USBDeviceKeyVendorID`).
                if let vid = (item["USBDeviceKeyVendorID"] as? String) ?? (item["vendor_id"] as? String),
                   let hexVid = extractHexToken(from: vid) {
                    return "VID \(hexVid)"
                }
                return "Unknown vendor"
            }()

            // `location_id`: legacy SPUSBDataType key from public samples (e.g. "0x01140000 / 3"); unverified on the author's machine (new SPUSBHostDataType uses `USBKeyLocationID`).
            let rawLocStr = (item["USBKeyLocationID"] as? String) ?? (item["location_id"] as? String)
            let locUInt = IORegistrySnapshot.parseLocationID(rawLocStr)
            let normalizedLocHex = locUInt.map { String(format: "0x%08x", $0) }
            let ioregDev = locUInt.flatMap { ioregSnapshot?.usbDevicesByLocation[$0] }
            let ioregHostPort = locUInt.flatMap { ioregSnapshot?.resolveUSBHostPort(for: $0) }

            let parsedGbps: Double = {
                if let hostSpeed = item["USBDeviceKeyLinkSpeed"] as? String {
                    return BottleneckDiagnoser.parseSpeedGbps(hostSpeed)
                }
                // `device_speed`: legacy SPUSBDataType key from public samples (values such as `full_speed`, `high_speed`); unverified on the author's machine.
                if let legacySpeed = item["device_speed"] as? String {
                    return BottleneckDiagnoser.parseLegacyUSBDeviceSpeedGbps(legacySpeed)
                }
                return 0.0
            }()
            let gbps = parsedGbps > 0 ? parsedGbps : (ioregDev?.linkSpeedGbps ?? 0.0)
            let children = (item["_items"] as? [[String: Any]]) ?? []
            let isBuiltIn = isBuiltInUSBNode(item) || (ioregDev?.isInternalPort == true)
            let mergedCap = mergeDescriptors(ioregCap: ioregDev?.capability, inlineCap: extractInlineUSBDescriptor(item))
            let isHubContainer = isBuiltIn || isExplicitUSBHubClass(item) || (mergedCap?.usbDeviceClass == 9)

            let resolvedPhysicalPort = ioregDev?.hostPhysicalPortLabel
                ?? ioregHostPort?.physicalPortLabel
                ?? ancestorPhysicalPort
            let effectivePortCeiling = controllerCeilingGbps
                ?? ioregDev?.hostPortCeilingGbps
                ?? ioregHostPort?.portCeilingGbps

            if !isHubContainer {
                let eval = BottleneckDiagnoser.evaluate(
                    protocolKind: .usbHost,
                    negotiatedGbps: gbps,
                    portCeilingGbps: effectivePortCeiling,
                    behindExternalHub: behindExternalHub,
                    upstreamHubGbps: upstreamHubGbps,
                    capability: mergedCap
                )
                out.append(
                    AttachedBusDevice(
                        id: "usb-dev::\(busTitle)::\(depth)::\(idx)::\(name)",
                        name: name,
                        vendor: vendor,
                        busName: busTitle,
                        physicalPort: resolvedPhysicalPort,
                        locationID: normalizedLocHex,
                        protocolKind: .usbHost,
                        negotiatedSpeedLabel: gbps > 0 ? BottleneckDiagnoser.formatSpeedGbps(gbps) : "Unknown",
                        negotiatedGbps: gbps,
                        portCeilingGbps: effectivePortCeiling,
                        deviceMaxGbps: eval.deviceMaxGbps,
                        upstreamHubGbps: upstreamHubGbps,
                        depth: depth,
                        behindExternalHub: behindExternalHub,
                        modeDescription: behindExternalHub ? "via external USB hub" : "direct host bus",
                        capability: mergedCap,
                        bottleneckSegment: eval.bottleneckSegment,
                        isInferred: eval.isInferred,
                        verdict: eval.verdict,
                        diagnosticDetail: eval.detail
                    )
                )
            }

            if !children.isEmpty {
                let childBehindExternalHub = behindExternalHub || !isBuiltIn
                let childDepth = isBuiltIn ? depth : (depth + 1)
                let childUpstreamHubGbps: Double? = {
                    if isBuiltIn { return upstreamHubGbps }
                    guard gbps > 0 else { return upstreamHubGbps }
                    if let existing = upstreamHubGbps, existing > 0 {
                        return min(existing, gbps)
                    }
                    return gbps
                }()
                walkUSBDevices(
                    items: children,
                    busTitle: busTitle,
                    controllerCeilingGbps: controllerCeilingGbps,
                    ancestorPhysicalPort: resolvedPhysicalPort,
                    ioregSnapshot: ioregSnapshot,
                    behindExternalHub: childBehindExternalHub,
                    upstreamHubGbps: childUpstreamHubGbps,
                    depth: childDepth,
                    into: &out
                )
            }
        }
    }

    public static func parsePower(_ powerItems: [[String: Any]], pmsetOutput: String? = nil) -> PowerDeliverySummary {
        var source: String?
        var watts: Int?
        var explicitLowPower: Bool?

        for entry in powerItems {
            // `sppower_ac_charger_watts`: present in /System/Library/SystemProfiler/SPPowerReporter.spreporter string table (emitted only on Macs with AC charger information); unverified on the author's machine (absent on this Mac mini).
            if let w = entry["sppower_ac_charger_watts"] as? String, let parsed = Int(w.trimmingCharacters(in: .whitespacesAndNewlines)) {
                watts = parsed
            } else if let wInt = entry["sppower_ac_charger_watts"] as? Int {
                watts = wInt
            }

            if let parsed = parseBoolFlag(entry["LowPowerMode"]) {
                explicitLowPower = parsed
            }

            if let ac = entry["AC Power"] as? [String: Any] {
                let isCurrent = parseBoolFlag(ac["Current Power Source"]) ?? false
                if isCurrent {
                    source = "AC Line Power"
                    if let parsed = extractLowPowerFlag(from: ac) {
                        explicitLowPower = parsed
                    }
                } else if explicitLowPower == nil, let parsed = extractLowPowerFlag(from: ac) {
                    explicitLowPower = parsed
                }
            }
        }

        let lowPower: Bool? = {
            if let explicitLowPower {
                return explicitLowPower
            }
            if let pmsetOutput, let pmsetVal = parsePmsetLowPowerMode(pmsetOutput) {
                return pmsetVal
            }
            return nil
        }()

        return PowerDeliverySummary(powerSource: source, negotiatedWatts: watts, lowPowerMode: lowPower)
    }

    public static func parsePmsetLowPowerMode(_ output: String) -> Bool? {
        for line in output.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if parts.count >= 2 && parts[0].lowercased() == "lowpowermode" {
                return parseBoolFlag(String(parts[1]))
            }
        }
        return nil
    }

    private static func extractLowPowerFlag(from dict: [String: Any]) -> Bool? {
        parseBoolFlag(dict["LowPowerMode"])
    }

    private static func parseBoolFlag(_ raw: Any?) -> Bool? {
        guard let raw else { return nil }
        if let b = raw as? Bool {
            return b
        }
        if let i = raw as? Int {
            return i != 0
        }
        if let s = raw as? String {
            let lower = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch lower {
            case "1", "yes", "true", "on", "enabled":
                return true
            case "0", "no", "false", "off", "disabled":
                return false
            default:
                return nil
            }
        }
        if let n = raw as? NSNumber {
            return n.intValue != 0
        }
        return nil
    }

    private static func findFirstReceptacle(in dict: [String: Any]) -> [String: Any]? {
        let receptacleKeys = dict.keys
            .filter { $0.hasPrefix("receptacle_") && $0.hasSuffix("_tag") && $0 != "receptacle_upstream_ambiguous_tag" }
            .sorted()
        for k in receptacleKeys {
            if let sub = dict[k] as? [String: Any],
               (sub["receptacle_status_key"] as? String) == "receptacle_connected" {
                return sub
            }
        }
        for k in receptacleKeys {
            if let sub = dict[k] as? [String: Any] {
                return sub
            }
        }
        if let upstream = dict["receptacle_upstream_ambiguous_tag"] as? [String: Any] {
            return upstream
        }
        return nil
    }

    private static func findDeviceReceptacle(in dict: [String: Any]) -> [String: Any]? {
        if let upstream = dict["receptacle_upstream_ambiguous_tag"] as? [String: Any] {
            return upstream
        }
        return findFirstReceptacle(in: dict)
    }

    private static func prettifyBusName(_ raw: String) -> String {
        if let last = raw.split(separator: "_").last, let idx = Int(last) {
            return "Thunderbolt / USB4 Bus \(idx)"
        }
        return raw
    }

    private static func runSystemProfilerValidated() throws -> Data {
        let path = "/usr/sbin/system_profiler"
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw BusCollectorError.unreadableInput(path)
        }
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
        try proc.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw BusCollectorError.systemProfilerFailed(proc.terminationStatus)
        }
        return data
    }

    private static func runPmsetOptional() -> String? {
        let path = "/usr/bin/pmset"
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = ["-g"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return nil }
            return String(decoding: data, as: UTF8.self)
        } catch {
            return nil
        }
    }
}
