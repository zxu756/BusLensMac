import SwiftUI

enum BenchTheme {
    static let chassis = Color(red: 0.043, green: 0.055, blue: 0.067)     // #0B0E11
    static let panel = Color(red: 0.071, green: 0.090, blue: 0.114)       // #12171D
    static let slot = Color(red: 0.098, green: 0.125, blue: 0.157)        // #192028
    static let trace = Color(red: 0.133, green: 0.173, blue: 0.220)       // #222C38
    static let chalk = Color(red: 0.941, green: 0.961, blue: 0.980)       // #F0F5FA
    static let slate = Color(red: 0.545, green: 0.620, blue: 0.706)       // #8B9EB4
    static let cobalt = Color(red: 0.376, green: 0.647, blue: 0.980)      // #60A5FA
    static let emerald = Color(red: 0.204, green: 0.827, blue: 0.600)     // #34D399
    static let coral = Color(red: 0.984, green: 0.443, blue: 0.522)       // #FB7185
}

public struct BusDashboardView: View {
    @ObservedObject var monitor: BusLensMonitor

    public init(monitor: BusLensMonitor) {
        self.monitor = monitor
    }

    public var body: some View {
        VStack(spacing: 0) {
            topHeaderBar
            Divider().overlay(BenchTheme.trace)
            receptacleMatrixStrip
            Divider().overlay(BenchTheme.trace)
            filterToolbar
            Divider().overlay(BenchTheme.trace)
            deviceBenchSection
        }
        .background(BenchTheme.chassis)
        .foregroundStyle(BenchTheme.chalk)
    }

    // MARK: - Top Hardware Telemetry Bar

    private var topHeaderBar: some View {
        HStack(alignment: .center) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(BenchTheme.cobalt.opacity(0.16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(BenchTheme.cobalt.opacity(0.48), lineWidth: 1)
                        )
                        .frame(width: 30, height: 30)
                    Image(systemName: "cable.connector.horizontal")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BenchTheme.cobalt)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("BusLens Mac")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(BenchTheme.chalk)
                    Text("Thunderbolt, USB4 & USB-C negotiated link-rate and cable bottleneck analyzer")
                        .font(.system(size: 12))
                        .foregroundStyle(BenchTheme.slate)
                }
            }

            Spacer()

            HStack(spacing: 20) {
                statBlock(
                    value: BottleneckDiagnoser.formatSpeedGbps(monitor.snapshot.peakNegotiatedGbps),
                    label: "Peak negotiated link",
                    color: BenchTheme.cobalt
                )
                statBlock(
                    value: "\(monitor.snapshot.activeTunnelCount)",
                    label: "40G+ PCIe tunnels",
                    color: BenchTheme.emerald
                )
                statBlock(
                    value: "\(monitor.snapshot.bottleneckDevices.count)",
                    label: "Cable bottlenecks",
                    color: monitor.snapshot.bottleneckDevices.isEmpty ? BenchTheme.slate : BenchTheme.coral
                )
                statBlock(
                    value: monitor.snapshot.power.displayBadge,
                    label: "Power delivery",
                    color: BenchTheme.chalk
                )

                Button(action: { monitor.refresh() }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Rescan")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(BenchTheme.slot))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(BenchTheme.trace, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(BenchTheme.panel)
    }

    private func statBlock(value: String, label: String, color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(verbatim: value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(BenchTheme.slate)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Signature Physical Port Receptacle Matrix

    private var receptacleMatrixStrip: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Host controller receptacles")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(BenchTheme.slate)

            HStack(spacing: 10) {
                ForEach(monitor.snapshot.controllers.prefix(5)) { ctrl in
                    let hasWarn = ctrl.devices.contains { $0.verdict == .cableOrHubBottleneck }
                    let borderCol: Color = hasWarn
                        ? BenchTheme.coral.opacity(0.6)
                        : (ctrl.isConnected ? BenchTheme.cobalt.opacity(0.55) : BenchTheme.trace)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            // Stylized USB-C oval receptacle pill
                            Capsule()
                                .strokeBorder(ctrl.isConnected ? BenchTheme.cobalt : BenchTheme.slate.opacity(0.45), lineWidth: 1.5)
                                .background(Capsule().fill(ctrl.isConnected ? BenchTheme.cobalt.opacity(0.18) : Color.clear))
                                .frame(width: 20, height: 8)
                            Spacer()
                            Text(verbatim: ctrl.isConnected ? BottleneckDiagnoser.formatSpeedGbps(ctrl.negotiatedGbps) : "Open")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(hasWarn ? BenchTheme.coral : (ctrl.isConnected ? BenchTheme.emerald : BenchTheme.slate))
                        }

                        Text(ctrl.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(BenchTheme.chalk)
                            .lineLimit(1)

                        Text(verbatim: ctrl.isConnected ? "\(ctrl.devices.count) attached / max \(ctrl.maxRateLabel)" : "Ready / up to \(ctrl.maxRateLabel)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(BenchTheme.slate)
                            .lineLimit(1)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(ctrl.isConnected ? BenchTheme.slot : BenchTheme.panel)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(borderCol, lineWidth: 1)
                    )
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .background(BenchTheme.panel.opacity(0.6))
    }

    // MARK: - Filter Toolbar

    private var filterToolbar: some View {
        HStack(spacing: 8) {
            ForEach(BusFilterMode.allCases) { mode in
                let active = monitor.filterMode == mode
                Button(action: { monitor.filterMode = mode }) {
                    HStack(spacing: 5) {
                        Text(mode.rawValue)
                            .font(.system(size: 12, weight: active ? .semibold : .regular))
                        Text(verbatim: "\(count(for: mode))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(active ? BenchTheme.cobalt : BenchTheme.slate)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(active ? BenchTheme.cobalt.opacity(0.16) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(active ? BenchTheme.cobalt.opacity(0.5) : BenchTheme.trace, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("Hardware serials & Thunderbolt UUIDs scrubbed")
                .font(.system(size: 11))
                .foregroundStyle(BenchTheme.slate.opacity(0.8))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(BenchTheme.chassis)
    }

    private func count(for mode: BusFilterMode) -> Int {
        switch mode {
        case .all: return monitor.snapshot.devices.count
        case .bottlenecks: return monitor.snapshot.bottleneckDevices.count
        case .thunderbolt: return monitor.snapshot.devices.filter { $0.protocolKind == .thunderboltUSB4 }.count
        case .usbPeripherals: return monitor.snapshot.devices.filter { $0.protocolKind == .usbHost }.count
        }
    }

    // MARK: - Device Diagnostic Bench

    @ViewBuilder
    private var deviceBenchSection: some View {
        if monitor.isStaticPreview {
            VStack(spacing: 10) {
                deviceCardsContent
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    deviceCardsContent
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var deviceCardsContent: some View {
        if monitor.filteredDevices.isEmpty {
            VStack(spacing: 6) {
                Text("No matching bus devices")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(BenchTheme.chalk)
                Text("Connect a Thunderbolt, USB4, or USB-C device and click Rescan.")
                    .font(.system(size: 12))
                    .foregroundStyle(BenchTheme.slate)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 44)
        } else {
            ForEach(monitor.filteredDevices) { dev in
                deviceDiagnosticRow(dev)
            }
        }
    }

    private func deviceDiagnosticRow(_ dev: AttachedBusDevice) -> some View {
        let isWarn = dev.verdict.isWarning
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle()
                    .fill(dev.verdict.color)
                    .frame(width: 8, height: 8)

                Text(dev.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(BenchTheme.chalk)

                Text(dev.vendor)
                    .font(.system(size: 12))
                    .foregroundStyle(BenchTheme.slate)

                Text("\(dev.busName) (\(dev.modeDescription))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(BenchTheme.slate.opacity(0.85))

                Spacer()

                Text(dev.verdict.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(dev.verdict.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(dev.verdict.color.opacity(0.15))
                    )

                Text(verbatim: dev.negotiatedSpeedLabel)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(isWarn ? BenchTheme.coral : BenchTheme.chalk)
                    .frame(width: 82, alignment: .trailing)
            }

            HStack(spacing: 14) {
                Text(dev.diagnosticDetail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(isWarn ? BenchTheme.coral.opacity(0.95) : BenchTheme.slate)
                    .lineLimit(1)

                Spacer()

                // Negotiated vs Ceiling lane gauge
                HStack(spacing: 7) {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(BenchTheme.chassis)
                            .frame(width: 140, height: 6)
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(dev.verdict.color)
                            .frame(width: max(5, 140 * CGFloat(dev.utilizationFraction)), height: 6)
                    }
                    Text(verbatim: "of \(BottleneckDiagnoser.formatSpeedGbps(dev.portCeilingGbps))")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(BenchTheme.slate)
                        .frame(width: 68, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isWarn ? BenchTheme.coral.opacity(0.07) : BenchTheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isWarn ? BenchTheme.coral.opacity(0.45) : BenchTheme.trace, lineWidth: 1)
        )
    }
}
