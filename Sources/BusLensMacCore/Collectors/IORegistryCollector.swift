import Foundation

public struct IORegistryUSBDeviceRecord: Equatable, Sendable {
    public let locationID: UInt32
    public let name: String
    public let isInternalPort: Bool
    public let linkSpeedGbps: Double?
    public let hostPhysicalPortLabel: String?
    public let hostPortCeilingGbps: Double?
    public let capability: DeviceCapabilityDescriptor

    public init(
        locationID: UInt32,
        name: String,
        isInternalPort: Bool,
        linkSpeedGbps: Double?,
        hostPhysicalPortLabel: String? = nil,
        hostPortCeilingGbps: Double? = nil,
        capability: DeviceCapabilityDescriptor
    ) {
        self.locationID = locationID
        self.name = name
        self.isInternalPort = isInternalPort
        self.linkSpeedGbps = linkSpeedGbps
        self.hostPhysicalPortLabel = hostPhysicalPortLabel
        self.hostPortCeilingGbps = hostPortCeilingGbps
        self.capability = capability
    }
}

public struct IORegistryUSBPortRecord: Equatable, Sendable {
    public let locationID: UInt32
    public let portNumber: Int?
    public let physicalPortLabel: String?
    public let companionLocationID: UInt32?
    public let rawOwnCeilingGbps: Double?
    public var portCeilingGbps: Double?
    public let isHostPort: Bool

    public init(
        locationID: UInt32,
        portNumber: Int?,
        physicalPortLabel: String?,
        companionLocationID: UInt32?,
        rawOwnCeilingGbps: Double?,
        portCeilingGbps: Double?,
        isHostPort: Bool
    ) {
        self.locationID = locationID
        self.portNumber = portNumber
        self.physicalPortLabel = physicalPortLabel
        self.companionLocationID = companionLocationID
        self.rawOwnCeilingGbps = rawOwnCeilingGbps
        self.portCeilingGbps = portCeilingGbps
        self.isHostPort = isHostPort
    }
}

public struct IORegistryThunderboltBusRecord: Equatable, Sendable {
    public let routerID: Int
    public let socketID: String?
    public let physicalPortLabel: String?
    public let portCeilingGbps: Double?

    public init(
        routerID: Int,
        socketID: String?,
        physicalPortLabel: String?,
        portCeilingGbps: Double?
    ) {
        self.routerID = routerID
        self.socketID = socketID
        self.physicalPortLabel = physicalPortLabel
        self.portCeilingGbps = portCeilingGbps
    }
}

public struct IORegistryThunderboltDeviceRecord: Equatable, Sendable {
    public let routerID: Int
    public let routeString: String
    public let modelName: String
    public let negotiatedGbps: Double?
    public let capability: DeviceCapabilityDescriptor

    public init(
        routerID: Int,
        routeString: String,
        modelName: String,
        negotiatedGbps: Double?,
        capability: DeviceCapabilityDescriptor
    ) {
        self.routerID = routerID
        self.routeString = routeString
        self.modelName = modelName
        self.negotiatedGbps = negotiatedGbps
        self.capability = capability
    }
}

public struct IORegistrySnapshot: Equatable, Sendable {
    public var usbDevicesByLocation: [UInt32: IORegistryUSBDeviceRecord]
    public var usbPortsByLocation: [UInt32: IORegistryUSBPortRecord]
    public var thunderboltBusesByRouter: [Int: IORegistryThunderboltBusRecord]
    public var thunderboltDevices: [IORegistryThunderboltDeviceRecord]
    public var socketToPhysicalPort: [String: String]

    public static let empty = IORegistrySnapshot(
        usbDevicesByLocation: [:],
        usbPortsByLocation: [:],
        thunderboltBusesByRouter: [:],
        thunderboltDevices: [],
        socketToPhysicalPort: [:]
    )

    public init(
        usbDevicesByLocation: [UInt32: IORegistryUSBDeviceRecord],
        usbPortsByLocation: [UInt32: IORegistryUSBPortRecord],
        thunderboltBusesByRouter: [Int: IORegistryThunderboltBusRecord],
        thunderboltDevices: [IORegistryThunderboltDeviceRecord],
        socketToPhysicalPort: [String: String]
    ) {
        self.usbDevicesByLocation = usbDevicesByLocation
        self.usbPortsByLocation = usbPortsByLocation
        self.thunderboltBusesByRouter = thunderboltBusesByRouter
        self.thunderboltDevices = thunderboltDevices
        self.socketToPhysicalPort = socketToPhysicalPort
    }

    // MARK: - Lookup Helpers

    public func resolveUSBHostPort(for locationID: UInt32) -> IORegistryUSBPortRecord? {
        let masks: [UInt32] = [
            0xFFFF_FFFF,
            0xFFFF_FFF0,
            0xFFFF_FF00,
            0xFFFF_F000,
            0xFFFF_0000,
            0xFFF0_0000
        ]
        for mask in masks {
            let candidate = locationID & mask
            if let rec = usbPortsByLocation[candidate], rec.isHostPort {
                return rec
            }
        }
        return nil
    }

    public func resolveThunderboltDevice(routerID: Int?, routeString: String?, name: String) -> IORegistryThunderboltDeviceRecord? {
        let normalizedRoute = routeString.map(Self.normalizeRouteString)
        if let routerID, let normalizedRoute, !normalizedRoute.isEmpty {
            if let exact = thunderboltDevices.first(where: { $0.routerID == routerID && $0.routeString == normalizedRoute }) {
                return exact
            }
        }
        if let routerID {
            let candidates = thunderboltDevices.filter { $0.routerID == routerID && $0.modelName == name }
            if candidates.count == 1 {
                return candidates[0]
            }
        }
        if let normalizedRoute, !normalizedRoute.isEmpty {
            let candidates = thunderboltDevices.filter { $0.routeString == normalizedRoute && $0.modelName == name }
            if candidates.count == 1 {
                return candidates[0]
            }
        }
        return nil
    }

    public static func parseLocationID(_ raw: Any?) -> UInt32? {
        guard let raw else { return nil }
        if let u = raw as? UInt32 { return u }
        if let i = raw as? Int, i >= 0 { return UInt32(truncatingIfNeeded: i) }
        if let i64 = raw as? Int64, i64 >= 0 { return UInt32(truncatingIfNeeded: i64) }
        if let n = raw as? NSNumber { return n.uint32Value }
        if let s = raw as? String {
            let pattern = #"0x([0-9A-Fa-f]+)"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let m = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
               let r = Range(m.range(at: 1), in: s),
               let val = UInt32(s[r], radix: 16) {
                return val
            }
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if let dec = UInt32(trimmed) {
                return dec
            }
        }
        return nil
    }

    // MARK: - Parsing

    public static func parsePlistData(_ data: Data) throws -> IORegistrySnapshot {
        guard !data.isEmpty,
              let raw = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else {
            throw BusCollectorError.invalidIORegistryFormat
        }
        if let dict = raw as? [String: Any] {
            let usbArr = (dict["AppleUSBHostPort"] as? [[String: Any]]) ?? []
            let tbArr = (dict["IOThunderboltSwitch"] as? [[String: Any]]) ?? []
            return buildSnapshot(usbRoots: usbArr, tbRoots: tbArr)
        }
        if let arr = raw as? [[String: Any]] {
            var usbRoots: [[String: Any]] = []
            var tbRoots: [[String: Any]] = []
            for item in arr {
                let cls = (item["IOObjectClass"] as? String) ?? ""
                if cls.contains("Thunderbolt") {
                    tbRoots.append(item)
                } else {
                    usbRoots.append(item)
                }
            }
            return buildSnapshot(usbRoots: usbRoots, tbRoots: tbRoots)
        }
        throw BusCollectorError.invalidIORegistryFormat
    }

    public static func parseSeparatePlists(usbPlist: Data?, thunderboltPlist: Data?) -> IORegistrySnapshot {
        var usbRoots: [[String: Any]] = []
        var tbRoots: [[String: Any]] = []
        if let usbPlist, !usbPlist.isEmpty,
           let arr = (try? PropertyListSerialization.propertyList(from: usbPlist, options: [], format: nil)) as? [[String: Any]] {
            usbRoots = arr
        }
        if let thunderboltPlist, !thunderboltPlist.isEmpty,
           let arr = (try? PropertyListSerialization.propertyList(from: thunderboltPlist, options: [], format: nil)) as? [[String: Any]] {
            tbRoots = arr
        }
        return buildSnapshot(usbRoots: usbRoots, tbRoots: tbRoots)
    }

    /// Strictly read-only execution of `/usr/sbin/ioreg` for `AppleUSBHostPort` and `IOThunderboltSwitch`.
    public static func collectLiveReadOnly() -> IORegistrySnapshot? {
        let path = "/usr/sbin/ioreg"
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let usbData = runReadOnlyIOReg(className: "AppleUSBHostPort")
        let tbData = runReadOnlyIOReg(className: "IOThunderboltSwitch")
        if usbData == nil && tbData == nil {
            return nil
        }
        return parseSeparatePlists(usbPlist: usbData, thunderboltPlist: tbData)
    }

    private static func runReadOnlyIOReg(className: String) -> Data? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        proc.arguments = ["-a", "-r", "-c", className, "-l"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0, !data.isEmpty else { return nil }
            return data
        } catch {
            return nil
        }
    }

    // MARK: - Internal Tree Builders

    private static func buildSnapshot(
        usbRoots: [[String: Any]],
        tbRoots: [[String: Any]]
    ) -> IORegistrySnapshot {
        var usbPorts: [UInt32: IORegistryUSBPortRecord] = [:]
        var rawDeviceNodes: [(node: [String: Any], ancestorHostLoc: UInt32?)] = []
        var socketToPort: [String: String] = [:]

        for root in usbRoots {
            walkUSBRegistryNode(
                root,
                parentHubIsInternal: true,
                currentHostPortLoc: nil,
                usbPorts: &usbPorts,
                rawDeviceNodes: &rawDeviceNodes,
                socketToPort: &socketToPort
            )
        }

        // Cross-propagate companion USB 3.x port ceilings onto USB 2.0 companion ports sharing the same physical receptacle
        // only when the companion port itself exposes a concrete ceiling; otherwise leave nil (unknown).
        let initialPorts = usbPorts
        for (loc, var portRec) in initialPorts {
            if let compLoc = portRec.companionLocationID {
                let compCeiling = initialPorts[compLoc]?.rawOwnCeilingGbps
                if let compCeiling, compCeiling > (portRec.portCeilingGbps ?? 0) {
                    portRec.portCeilingGbps = compCeiling
                    usbPorts[loc] = portRec
                } else if compCeiling == nil, portRec.portCeilingGbps != nil {
                    portRec.portCeilingGbps = nil
                    usbPorts[loc] = portRec
                }
            }
        }

        // Build finalized USB device records with resolved host physical port and companion ceiling
        var usbDevices: [UInt32: IORegistryUSBDeviceRecord] = [:]
        for (devNode, ancestorHostLoc) in rawDeviceNodes {
            guard let loc = parseLocationID(devNode["locationID"]) else { continue }
            let name = (devNode["kUSBProductString"] as? String)
                ?? (devNode["USB Product Name"] as? String)
                ?? (devNode["IORegistryEntryName"] as? String)
                ?? "USB Device"
            let portType = parseInt(devNode["USBPortType"])
            // kIOUSBHostPortTypeCaptive == 1, kIOUSBHostPortTypeInternal == 2
            let isInternal = (portType == 1 || portType == 2)
            let linkSpeedGbps: Double? = {
                if let bps = parseInt64(devNode["UsbLinkSpeed"]), bps > 0 {
                    return Double(bps) / 1_000_000_000.0
                }
                return nil
            }()

            var ifaceClasses: [Int] = []
            collectInterfaceClasses(in: devNode, into: &ifaceClasses)

            let bcdUSB = parseInt(devNode["bcdUSB"])
            let devClass = parseInt(devNode["bDeviceClass"])

            let resolvedHostPort: IORegistryUSBPortRecord? = {
                if let ancestorHostLoc, let p = usbPorts[ancestorHostLoc] {
                    return p
                }
                for mask: UInt32 in [0xFFFF_FFFF, 0xFFFF_FFF0, 0xFFFF_FF00, 0xFFFF_F000, 0xFFFF_0000, 0xFFF0_0000] {
                    if let p = usbPorts[loc & mask], p.isHostPort {
                        return p
                    }
                }
                return nil
            }()

            let cap = DeviceCapabilityDescriptor(
                bcdUSB: bcdUSB,
                usbDeviceClass: devClass,
                usbInterfaceClasses: ifaceClasses
            )
            usbDevices[loc] = IORegistryUSBDeviceRecord(
                locationID: loc,
                name: name,
                isInternalPort: isInternal,
                linkSpeedGbps: linkSpeedGbps,
                hostPhysicalPortLabel: resolvedHostPort?.physicalPortLabel,
                hostPortCeilingGbps: resolvedHostPort?.portCeilingGbps,
                capability: cap
            )
        }

        // Parse Thunderbolt switch & port trees
        var tbBuses: [Int: IORegistryThunderboltBusRecord] = [:]
        var tbDevices: [IORegistryThunderboltDeviceRecord] = []

        for tbRoot in tbRoots {
            let cls = (tbRoot["IOObjectClass"] as? String) ?? ""
            guard cls.contains("IOThunderboltSwitch") else { continue }
            let depth = parseInt(tbRoot["Depth"]) ?? 0
            guard depth == 0, let routerID = parseInt(tbRoot["Router ID"]) else { continue }

            var hostSocketID: String?
            var hostCeilingGbps: Double?
            if let children = tbRoot["IORegistryEntryChildren"] as? [[String: Any]] {
                for ch in children where ((ch["IOObjectClass"] as? String) ?? "").contains("IOThunderboltPort") {
                    if let sid = stringFromAny(ch["Socket ID"]), !sid.isEmpty {
                        hostSocketID = sid
                        if let ceil = decodeThunderboltSupportedMaxGbps(portNode: ch) {
                            hostCeilingGbps = max(hostCeilingGbps ?? 0, ceil)
                        }
                    }
                }
                for ch in children {
                    walkThunderboltSubtree(
                        node: ch,
                        routerID: routerID,
                        parentPortNode: nil,
                        into: &tbDevices
                    )
                }
            }

            let portLabel: String? = {
                guard let sid = hostSocketID else { return nil }
                return socketToPort[sid]
            }()

            tbBuses[routerID] = IORegistryThunderboltBusRecord(
                routerID: routerID,
                socketID: hostSocketID,
                physicalPortLabel: portLabel,
                portCeilingGbps: hostCeilingGbps
            )
        }

        return IORegistrySnapshot(
            usbDevicesByLocation: usbDevices,
            usbPortsByLocation: usbPorts,
            thunderboltBusesByRouter: tbBuses,
            thunderboltDevices: tbDevices,
            socketToPhysicalPort: socketToPort
        )
    }

    private static func walkUSBRegistryNode(
        _ node: [String: Any],
        parentHubIsInternal: Bool,
        currentHostPortLoc: UInt32?,
        usbPorts: inout [UInt32: IORegistryUSBPortRecord],
        rawDeviceNodes: inout [(node: [String: Any], ancestorHostLoc: UInt32?)],
        socketToPort: inout [String: String]
    ) {
        let cls = (node["IOObjectClass"] as? String) ?? ""
        var nextInternal = parentHubIsInternal
        var nextHostPortLoc = currentHostPortLoc

        if cls.contains("USB") && cls.hasSuffix("Port"), let loc = parseLocationID(node["locationID"]) {
            let ioPortPath = node["UsbIOPort"] as? String
            let portNum = parseInt(node["PortNumber"])
            let label = extractPhysicalPortLabel(usbIOPort: ioPortPath, portNumber: portNum)
            if let portNum, let label {
                socketToPort[String(portNum)] = label
            }

            // A port is a physical host port if it sits at root XHCI or under an internal Apple companion hub
            // AND exposes either a physical UsbIOPort / PortNumber or root XHCI protocol properties.
            let isHostPort = parentHubIsInternal && (
                label != nil
                || cls.contains("XHCIPort")
                || cls.contains("XHCIARMPort")
            )
            let companionStr = node["UsbProtocolCompanion (3.x)"] as? String
            let companionLoc: UInt32? = {
                guard let companionStr else { return nil }
                if let atIdx = companionStr.lastIndex(of: "@") {
                    let hexPart = String(companionStr[companionStr.index(after: atIdx)...])
                    if let parsed = UInt32(hexPart, radix: 16) {
                        return parsed
                    }
                }
                return 0 // Sentinel indicating a 3.x companion exists even without an @location suffix
            }()

            let ownCeiling = computeOwnUSBPortCeilingGbps(portNode: node)
            usbPorts[loc] = IORegistryUSBPortRecord(
                locationID: loc,
                portNumber: portNum,
                physicalPortLabel: label,
                companionLocationID: companionLoc,
                rawOwnCeilingGbps: ownCeiling,
                portCeilingGbps: ownCeiling,
                isHostPort: isHostPort
            )
            if isHostPort {
                nextHostPortLoc = loc
            }
        } else if cls == "IOUSBHostDevice" {
            rawDeviceNodes.append((node: node, ancestorHostLoc: currentHostPortLoc))
            let portType = parseInt(node["USBPortType"])
            let isInternalDev = (portType == 1 || portType == 2)
            nextInternal = isInternalDev
        }

        if let children = node["IORegistryEntryChildren"] as? [[String: Any]] {
            for ch in children {
                walkUSBRegistryNode(
                    ch,
                    parentHubIsInternal: nextInternal,
                    currentHostPortLoc: nextHostPortLoc,
                    usbPorts: &usbPorts,
                    rawDeviceNodes: &rawDeviceNodes,
                    socketToPort: &socketToPort
                )
            }
        }
    }

    private static func computeOwnUSBPortCeilingGbps(
        portNode: [String: Any]
    ) -> Double? {
        if parseBool(portNode["UsbProtocol (3.x)"]) == true {
            return nil
        }
        if portNode["UsbProtocolCompanion (3.x)"] != nil {
            return nil
        }
        if parseBool(portNode["UsbProtocol (2.0)"]) == true {
            return 0.48
        }
        if parseBool(portNode["UsbProtocol (1.x)"]) == true {
            return 0.012
        }
        return nil
    }

    private static func collectInterfaceClasses(in deviceNode: [String: Any], into out: inout [Int]) {
        guard let children = deviceNode["IORegistryEntryChildren"] as? [[String: Any]] else { return }
        for ch in children {
            let cls = (ch["IOObjectClass"] as? String) ?? ""
            if cls == "IOUSBHostInterface", let ic = parseInt(ch["bInterfaceClass"]) {
                out.append(ic)
            }
        }
    }

    private static func walkThunderboltSubtree(
        node: [String: Any],
        routerID: Int,
        parentPortNode: [String: Any]?,
        into out: inout [IORegistryThunderboltDeviceRecord]
    ) {
        let cls = (node["IOObjectClass"] as? String) ?? ""
        var nextParentPort = parentPortNode
        if cls.contains("IOThunderboltPort") {
            nextParentPort = node
        } else if cls.contains("IOThunderboltSwitch") {
            let depth = parseInt(node["Depth"]) ?? 0
            if depth >= 1 {
                let rawRoute = stringFromAny(node["Route String"]) ?? ""
                let route = normalizeRouteString(rawRoute)
                let model = (node["Device Model Name"] as? String)
                    ?? (node["IORegistryEntryName"] as? String)
                    ?? ""
                let explicitMax = parentPortNode.flatMap(decodeThunderboltSupportedMaxGbps)
                let negotiated: Double? = {
                    if let parentPortNode, let bw = parseInt(parentPortNode["Link Bandwidth"]), bw > 0 {
                        return Double(bw) / 10.0
                    }
                    return nil
                }()
                out.append(
                    IORegistryThunderboltDeviceRecord(
                        routerID: routerID,
                        routeString: route,
                        modelName: model,
                        negotiatedGbps: negotiated,
                        capability: DeviceCapabilityDescriptor(tbSupportedLinkGbps: explicitMax)
                    )
                )
            }
        }

        if let children = node["IORegistryEntryChildren"] as? [[String: Any]] {
            for ch in children {
                walkThunderboltSubtree(
                    node: ch,
                    routerID: routerID,
                    parentPortNode: nextParentPort,
                    into: &out
                )
            }
        }
    }

    private static func decodeThunderboltSupportedMaxGbps(portNode: [String: Any]) -> Double? {
        guard let speedMask = parseInt(portNode["Supported Link Speed"]), speedMask > 0 else {
            return nil
        }
        let widthRaw = parseInt(portNode["Supported Link Width"]) ?? 2
        let lanes: Double = (widthRaw >= 2) ? 2.0 : 1.0

        // Apple IOThunderboltPort Supported Link Speed bitmask:
        // 0x08 (8) = 10 Gb/s per lane (Gen 2 CIO), 0x04 (4) = 20 Gb/s per lane (Gen 3 CIO),
        // 0x02 (2) = 40 Gb/s per lane (Gen 4 / TB5, unverified on TB4 hardware).
        let laneGbps: Double
        if (speedMask & 0x02) != 0 {
            laneGbps = 40.0
        } else if (speedMask & 0x04) != 0 {
            laneGbps = 20.0
        } else if (speedMask & 0x08) != 0 {
            laneGbps = 10.0
        } else {
            return nil
        }
        return laneGbps * lanes
    }

    private static func extractPhysicalPortLabel(usbIOPort: String?, portNumber: Int?) -> String? {
        _ = portNumber
        if let usbIOPort, !usbIOPort.isEmpty {
            if let last = usbIOPort.split(separator: "/").last, !last.isEmpty {
                return String(last)
            }
        }
        return nil
    }

    private static func normalizeRouteString(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.hasPrefix("0x") {
            s = String(s.dropFirst(2))
        }
        return s
    }

    private static func stringFromAny(_ raw: Any?) -> String? {
        guard let raw else { return nil }
        if let s = raw as? String { return s }
        if let i = raw as? Int { return String(i) }
        if let n = raw as? NSNumber { return n.stringValue }
        return nil
    }

    private static func parseInt(_ raw: Any?) -> Int? {
        guard let raw else { return nil }
        if let i = raw as? Int { return i }
        if let n = raw as? NSNumber { return n.intValue }
        if let s = raw as? String {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if trimmed.hasPrefix("0x"), let v = Int(trimmed.dropFirst(2), radix: 16) {
                return v
            }
            return Int(trimmed)
        }
        return nil
    }

    private static func parseInt64(_ raw: Any?) -> Int64? {
        guard let raw else { return nil }
        if let i64 = raw as? Int64 { return i64 }
        if let i = raw as? Int { return Int64(i) }
        if let n = raw as? NSNumber { return n.int64Value }
        if let s = raw as? String, let v = Int64(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return v
        }
        return nil
    }

    private static func parseBool(_ raw: Any?) -> Bool? {
        guard let raw else { return nil }
        if let b = raw as? Bool { return b }
        if let n = raw as? NSNumber { return n.boolValue }
        return nil
    }
}
