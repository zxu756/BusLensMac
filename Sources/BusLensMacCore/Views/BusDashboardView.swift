import SwiftUI

enum BenchTheme {
    // Anodized Aluminum Hardware Schematic + Teenage Engineering Signal Orange
    static let chassis = Color(red: 0.906, green: 0.898, blue: 0.875)      // #E7E5DF bead-blasted aluminum chassis
    static let deck = Color(red: 0.945, green: 0.941, blue: 0.922)         // #F1F0EB machined upper deck
    static let plate = Color(red: 0.980, green: 0.976, blue: 0.965)        // #FAF9F6 diagnostic bench plate
    static let recessed = Color(red: 0.859, green: 0.851, blue: 0.824)     // #DBD9D2 recessed segmented track
    static let seam = Color(red: 0.788, green: 0.776, blue: 0.741)         // #C9C6BD precision chassis seam
    static let hairline = Color(red: 0.882, green: 0.875, blue: 0.847)     // #E1DFD8 bench row rule

    // Physical dark-graphite USB-C / Thunderbolt I/O port housing
    static let portBay = Color(red: 0.102, green: 0.106, blue: 0.118)      // #1A1B1E dark anodized port module
    static let portCavity = Color(red: 0.055, green: 0.059, blue: 0.067)   // #0E0F11 deep USB-C receptacle cavity
    static let portRim = Color(red: 0.255, green: 0.267, blue: 0.294)      // #41444B machined port bevel
    static let portSilk = Color(red: 0.635, green: 0.651, blue: 0.686)     // #A2A6AF laser-etched port label

    // Silkscreen Typography & Signal Colors
    static let ink = Color(red: 0.082, green: 0.086, blue: 0.094)          // #151618 silkscreen black
    static let muted = Color(red: 0.341, green: 0.349, blue: 0.369)        // #57595E engraved graphite
    static let subtle = Color(red: 0.482, green: 0.494, blue: 0.522)       // #7B7E85 secondary spec ink

    static let cobalt = Color(red: 0.082, green: 0.341, blue: 0.690)       // #1557B0 Thunderbolt 40G tunnel
    static let ledBlue = Color(red: 0.365, green: 0.678, blue: 0.992)      // #5DADFD luminous LED on dark port bay
    static let ledMint = Color(red: 0.259, green: 0.839, blue: 0.616)      // #42D69D luminous USB3 LED on port bay
    static let ledOrange = Color(red: 1.000, green: 0.447, blue: 0.235)    // #FF723C luminous alert LED on port bay
    static let pine = Color(red: 0.075, green: 0.451, blue: 0.337)         // #137356 SuperSpeed optimal
    static let signalOrange = Color(red: 0.863, green: 0.271, blue: 0.094) // #DC4518 cable/hub bottleneck alert
}

public struct BusDashboardView: View {
    @ObservedObject var monitor: BusLensMonitor

    public init(monitor: BusLensMonitor) {
        self.monitor = monitor
    }

    public var body: some View {
        VStack(spacing: 0) {
            topHeaderBar
            Rectangle().fill(BenchTheme.seam).frame(height: 1)
            telemetryReadoutStrip
            Rectangle().fill(BenchTheme.seam).frame(height: 1)
            receptacleMatrixStrip
            Rectangle().fill(BenchTheme.seam).frame(height: 1)
            filterToolbar
            Rectangle().fill(BenchTheme.seam).frame(height: 1)
            benchColumnHeader
            Rectangle().fill(BenchTheme.hairline).frame(height: 1)
            deviceBenchSection
        }
        .background(BenchTheme.chassis)
        .foregroundStyle(BenchTheme.ink)
        .preferredColorScheme(.light)
    }

    // MARK: - Top Anodized Chassis Bar

    private var topHeaderBar: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(BenchTheme.portBay)
                    .frame(width: 28, height: 28)
                Image(systemName: "bolt.horizontal.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(BenchTheme.ledOrange)
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("BusLens Mac")
                    .font(.system(size: 17, weight: .bold))
                    .tracking(-0.35)
                    .foregroundStyle(BenchTheme.ink)
                Text("Thunderbolt, USB4 & USB-C physical link-rate schematic and cable bottleneck analyzer")
                    .font(.system(size: 12.5))
                    .foregroundStyle(BenchTheme.muted)
            }

            Spacer()

            Button(action: { monitor.refresh() }) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Rescan bus")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(BenchTheme.ink)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(BenchTheme.plate))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(BenchTheme.seam, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(BenchTheme.chassis)
    }

    // MARK: - 4-Column Hardware Readout Strip

    private var telemetryReadoutStrip: some View {
        HStack(alignment: .top, spacing: 0) {
            readoutCell(
                value: BottleneckDiagnoser.formatSpeedGbps(monitor.snapshot.peakNegotiatedGbps),
                label: "Peak negotiated link",
                detail: "Fastest active host lane",
                color: BenchTheme.cobalt
            )
            verticalSeam
            readoutCell(
                value: "\(monitor.snapshot.activeTunnelCount)",
                label: "Active 40G PCIe tunnels",
                detail: "Full USB4 / TB3 / TB4 lanes",
                color: BenchTheme.ink
            )
            verticalSeam
            readoutCell(
                value: "\(monitor.snapshot.bottleneckDevices.count)",
                label: "Cable or hub bottlenecks",
                detail: monitor.snapshot.bottleneckDevices.isEmpty
                    ? "All enclosures at link ceiling"
                    : "Below enclosure link ceiling",
                color: monitor.snapshot.bottleneckDevices.isEmpty ? BenchTheme.pine : BenchTheme.signalOrange
            )
            verticalSeam
            readoutCell(
                value: monitor.snapshot.power.displayBadge,
                label: "Host power delivery",
                detail: monitor.snapshot.power.lowPowerMode ? "Low Power Mode active" : "Full bus power budget",
                color: BenchTheme.ink
            )
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 13)
        .background(BenchTheme.deck)
    }

    private var verticalSeam: some View {
        Rectangle()
            .fill(BenchTheme.seam)
            .frame(width: 1, height: 44)
            .padding(.horizontal, 18)
    }

    private func readoutCell(value: String, label: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: value)
                .font(.system(size: 21, weight: .bold, design: .monospaced))
                .tracking(-0.5)
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(BenchTheme.ink.opacity(0.9))
            Text(detail)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(BenchTheme.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Signature Mac mini Rear-I/O Anodized Port Backplate

    private var receptacleMatrixStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Rear I/O controller port schematic")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BenchTheme.ink)
                Spacer()
                HStack(spacing: 14) {
                    legendPip(color: BenchTheme.ledBlue, text: "40 Gb/s tunnel")
                    legendPip(color: BenchTheme.ledMint, text: "USB3 SuperSpeed")
                    legendPip(color: BenchTheme.ledOrange, text: "Bottleneck downstream")
                }
            }

            HStack(spacing: 9) {
                ForEach(Array(monitor.snapshot.controllers.prefix(5).enumerated()), id: \.element.id) { idx, ctrl in
                    physicalPortModule(ctrl, index: idx)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(BenchTheme.chassis)
    }

    private func legendPip(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(BenchTheme.muted)
        }
    }

    private func physicalPortModule(_ ctrl: PhysicalPortController, index: Int) -> some View {
        let hasWarn = ctrl.devices.contains { $0.verdict == .cableOrHubBottleneck }
        let isTB = ctrl.protocolKind == .thunderboltUSB4
        let ledColor: Color = hasWarn
            ? BenchTheme.ledOrange
            : (ctrl.isConnected ? (ctrl.negotiatedGbps >= 40.0 ? BenchTheme.ledBlue : BenchTheme.ledMint) : BenchTheme.portRim)

        let shortBusCode = isTB ? "TB4 · P\(index)" : "USB · U\(index)"

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Circle()
                    .fill(ledColor)
                    .frame(width: 6, height: 6)
                Text(verbatim: shortBusCode)
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(BenchTheme.portSilk)
                Spacer()
                Text(verbatim: ctrl.isConnected ? BottleneckDiagnoser.formatSpeedGbps(ctrl.negotiatedGbps) : "OPEN")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(ctrl.isConnected ? ledColor : BenchTheme.portSilk.opacity(0.65))
            }

            // Machined USB-C physical stadium cutout with center tongue
            HStack {
                ZStack {
                    Capsule()
                        .fill(BenchTheme.portCavity)
                        .frame(width: 38, height: 13)
                        .overlay(
                            Capsule()
                                .strokeBorder(ctrl.isConnected ? ledColor.opacity(0.75) : BenchTheme.portRim, lineWidth: 1.5)
                        )
                    Capsule()
                        .fill(ctrl.isConnected ? ledColor.opacity(0.85) : BenchTheme.portRim.opacity(0.7))
                        .frame(width: 22, height: 3)
                }
                Spacer()
                if isTB {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(BenchTheme.portSilk.opacity(0.75))
                }
            }

            VStack(alignment: .leading, spacing: 1.5) {
                Text(ctrl.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.94))
                    .lineLimit(1)
                Text(verbatim: ctrl.isConnected ? "\(ctrl.devices.count) dev · max \(ctrl.maxRateLabel)" : "Idle · max \(ctrl.maxRateLabel)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(BenchTheme.portSilk)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(BenchTheme.portBay)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(hasWarn ? BenchTheme.signalOrange : Color.black.opacity(0.35), lineWidth: hasWarn ? 1.5 : 1)
        )
    }

    // MARK: - Segmented Filter Toolbar

    private var filterToolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(BusFilterMode.allCases) { mode in
                    let active = monitor.filterMode == mode
                    Button(action: { monitor.filterMode = mode }) {
                        HStack(spacing: 5) {
                            Text(mode.rawValue)
                                .font(.system(size: 12, weight: active ? .semibold : .regular))
                                .foregroundStyle(active ? BenchTheme.ink : BenchTheme.muted)
                            Text(verbatim: "\(count(for: mode))")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(
                                    mode == .bottlenecks && count(for: mode) > 0
                                        ? BenchTheme.signalOrange
                                        : (active ? BenchTheme.cobalt : BenchTheme.subtle)
                                )
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(active ? BenchTheme.plate : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(active ? BenchTheme.seam : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(BenchTheme.recessed)
            )

            Spacer()

            HStack(spacing: 5) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(BenchTheme.pine)
                Text("Serial numbers & Thunderbolt UUIDs scrubbed")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(BenchTheme.muted)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 8.5)
        .background(BenchTheme.deck)
    }

    private func count(for mode: BusFilterMode) -> Int {
        switch mode {
        case .all: return monitor.snapshot.devices.count
        case .bottlenecks: return monitor.snapshot.bottleneckDevices.count
        case .thunderbolt: return monitor.snapshot.devices.filter { $0.protocolKind == .thunderboltUSB4 }.count
        case .usbPeripherals: return monitor.snapshot.devices.filter { $0.protocolKind == .usbHost }.count
        }
    }

    // MARK: - Device Diagnostic Bench Header & Rows

    private var benchColumnHeader: some View {
        HStack(spacing: 12) {
            Text("Attached peripheral & diagnostic")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Controller topology")
                .frame(width: 196, alignment: .leading)
            Text("Link verdict")
                .frame(width: 162, alignment: .leading)
            Text("Negotiated vs port ceiling")
                .frame(width: 186, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(BenchTheme.muted)
        .padding(.horizontal, 22)
        .padding(.vertical, 7)
        .background(BenchTheme.deck.opacity(0.85))
    }

    @ViewBuilder
    private var deviceBenchSection: some View {
        if monitor.isStaticPreview {
            VStack(spacing: 0) {
                deviceRowsContent
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)
            .background(BenchTheme.plate)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    deviceRowsContent
                }
            }
            .frame(maxHeight: .infinity)
            .background(BenchTheme.plate)
        }
    }

    @ViewBuilder
    private var deviceRowsContent: some View {
        if monitor.filteredDevices.isEmpty {
            VStack(spacing: 6) {
                Text("No matching bus devices")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(BenchTheme.ink)
                Text("Connect a Thunderbolt, USB4, or USB-C device and click Rescan bus.")
                    .font(.system(size: 12))
                    .foregroundStyle(BenchTheme.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 44)
        } else {
            ForEach(monitor.filteredDevices) { dev in
                deviceDiagnosticRow(dev)
                Rectangle().fill(BenchTheme.hairline).frame(height: 1)
            }
        }
    }

    private func deviceDiagnosticRow(_ dev: AttachedBusDevice) -> some View {
        let isWarn = dev.verdict.isWarning
        return HStack(alignment: .center, spacing: 12) {
            // Device + Remediation Note
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(dev.name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(BenchTheme.ink)
                        .lineLimit(1)
                    Text(dev.vendor)
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(BenchTheme.subtle)
                }
                Text(dev.diagnosticDetail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(isWarn ? BenchTheme.signalOrange : BenchTheme.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Topology Path
            VStack(alignment: .leading, spacing: 2) {
                Text(dev.busName)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(BenchTheme.ink)
                    .lineLimit(1)
                Text(dev.modeDescription)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(dev.depth > 0 && isWarn ? BenchTheme.signalOrange : BenchTheme.subtle)
            }
            .frame(width: 196, alignment: .leading)

            // Verdict Indicator
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(dev.verdict.color)
                    .frame(width: 3.5, height: 14)
                Text(dev.verdict.rawValue)
                    .font(.system(size: 11.5, weight: isWarn ? .bold : .medium))
                    .foregroundStyle(dev.verdict.color)
                    .lineLimit(1)
            }
            .frame(width: 162, alignment: .leading)

            // Negotiated Speed + Segmented Lane Gauge
            VStack(alignment: .trailing, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(verbatim: dev.negotiatedSpeedLabel)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(isWarn ? BenchTheme.signalOrange : BenchTheme.ink)
                    Text(verbatim: "/ \(BottleneckDiagnoser.formatSpeedGbps(dev.portCeilingGbps))")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(BenchTheme.subtle)
                }

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(BenchTheme.recessed)
                        .frame(width: 148, height: 5)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(dev.verdict.color)
                        .frame(width: max(6, 148 * CGFloat(dev.utilizationFraction)), height: 5)
                }
            }
            .frame(width: 186, alignment: .trailing)
        }
        .padding(.leading, isWarn ? 18 : 22)
        .padding(.trailing, 22)
        .padding(.vertical, 11)
        .overlay(alignment: .leading) {
            if isWarn {
                Rectangle()
                    .fill(BenchTheme.signalOrange)
                    .frame(width: 4)
            }
        }
        .background(isWarn ? BenchTheme.signalOrange.opacity(0.055) : BenchTheme.plate)
    }
}
