import SwiftUI

public enum BenchTheme {
    // Anodized Aluminum Hardware Schematic + Teenage Engineering Signal Orange
    public static let chassis = Color(red: 0.906, green: 0.898, blue: 0.875)      // #E7E5DF bead-blasted aluminum chassis
    public static let deck = Color(red: 0.945, green: 0.941, blue: 0.922)         // #F1F0EB machined upper deck
    public static let plate = Color(red: 0.980, green: 0.976, blue: 0.965)        // #FAF9F6 diagnostic bench plate
    public static let recessed = Color(red: 0.859, green: 0.851, blue: 0.824)     // #DBD9D2 recessed segmented track
    public static let seam = Color(red: 0.788, green: 0.776, blue: 0.741)         // #C9C6BD precision chassis seam
    public static let hairline = Color(red: 0.882, green: 0.875, blue: 0.847)     // #E1DFD8 bench row rule

    // Physical dark-graphite USB-C / Thunderbolt I/O port housing
    public static let portBay = Color(red: 0.102, green: 0.106, blue: 0.118)      // #1A1B1E dark anodized port module
    public static let portCavity = Color(red: 0.055, green: 0.059, blue: 0.067)   // #0E0F11 deep USB-C receptacle cavity
    public static let portRim = Color(red: 0.255, green: 0.267, blue: 0.294)      // #41444B machined port bevel
    public static let portSilk = Color(red: 0.635, green: 0.651, blue: 0.686)     // #A2A6AF laser-etched port label

    // Silkscreen Typography & Signal Colors
    public static let ink = Color(red: 0.082, green: 0.086, blue: 0.094)          // #151618 silkscreen black
    public static let muted = Color(red: 0.341, green: 0.349, blue: 0.369)        // #57595E engraved graphite
    public static let subtle = Color(red: 0.482, green: 0.494, blue: 0.522)       // #7B7E85 secondary spec ink

    public static let cobalt = Color(red: 0.082, green: 0.341, blue: 0.690)       // #1557B0 Thunderbolt 40G tunnel
    public static let ledBlue = Color(red: 0.365, green: 0.678, blue: 0.992)      // #5DADFD luminous LED on dark port bay
    public static let ledMint = Color(red: 0.259, green: 0.839, blue: 0.616)      // #42D69D luminous USB3 LED on port bay
    public static let ledOrange = Color(red: 1.000, green: 0.447, blue: 0.235)    // #FF723C luminous alert LED on port bay
    public static let pine = Color(red: 0.075, green: 0.451, blue: 0.337)         // #137356 SuperSpeed optimal
    public static let signalOrange = Color(red: 0.863, green: 0.271, blue: 0.094) // #DC4518 cable/hub bottleneck alert
}

public struct BusDashboardView: View {
    @ObservedObject var monitor: BusLensMonitor
    @ObservedObject var localizer: AppLocalizer

    @MainActor
    public init(monitor: BusLensMonitor, localizer: AppLocalizer? = nil) {
        self.monitor = monitor
        self.localizer = localizer ?? .shared
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
        .environment(\.locale, localizer.language.locale)
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
                Text(localizer.L(
                    "Thunderbolt, USB4 & USB-C physical link-rate schematic and cable bottleneck analyzer",
                    "雷雳、USB4 与 USB-C 物理协商速率面板及线材降速瓶颈诊断仪"
                ))
                .font(.system(size: 12.5))
                .foregroundStyle(BenchTheme.muted)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }

            Spacer(minLength: 12)

            LanguageTogglePill(localizer: localizer)

            Button(action: { monitor.refresh() }) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                    Text(localizer.L("Rescan bus", "重新扫描总线"))
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
        let peakVal = BottleneckDiagnoser.formatSpeedGbps(monitor.snapshot.peakNegotiatedGbps, localizer: localizer)
        let peakHasCJK = localizer.isChinese && monitor.snapshot.peakNegotiatedGbps <= 0
        let pdBadge = monitor.snapshot.power.localizedBadge(localizer)
        let pdHasCJK = localizer.isChinese && monitor.snapshot.power.negotiatedWatts == nil

        return HStack(alignment: .top, spacing: 0) {
            readoutCell(
                value: peakVal,
                label: localizer.L("Peak negotiated link", "最高协商链路速率"),
                detail: localizer.L("Fastest active host lane", "当前最快活跃主机通道"),
                color: BenchTheme.cobalt,
                valueHasCJK: peakHasCJK
            )
            verticalSeam
            readoutCell(
                value: "\(monitor.snapshot.activeTunnelCount)",
                label: localizer.L("Active 40G PCIe tunnels", "活跃 40G PCIe 隧道"),
                detail: localizer.L("Full USB4 / TB3 / TB4 lanes", "满速 USB4 / 雷雳 3 / 雷雳 4 通道"),
                color: BenchTheme.ink
            )
            verticalSeam
            readoutCell(
                value: "\(monitor.snapshot.bottleneckDevices.count)",
                label: localizer.L("Cable or hub bottlenecks", "线材或扩展坞瓶颈"),
                detail: monitor.snapshot.bottleneckDevices.isEmpty
                    ? localizer.L("All enclosures at link ceiling", "所有外设均达物理速率上限")
                    : localizer.L("Below enclosure link ceiling", "低于外设物理速率上限"),
                color: monitor.snapshot.bottleneckDevices.isEmpty ? BenchTheme.pine : BenchTheme.signalOrange
            )
            verticalSeam
            readoutCell(
                value: pdBadge,
                label: localizer.L("Host power delivery", "主机供电功率 (PD)"),
                detail: monitor.snapshot.power.lowPowerMode
                    ? localizer.L("Low Power Mode active", "已开启低电量模式")
                    : localizer.L("Full bus power budget", "总线供电功率充足"),
                color: BenchTheme.ink,
                valueHasCJK: pdHasCJK
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

    private func readoutCell(
        value: String,
        label: String,
        detail: String,
        color: Color,
        valueHasCJK: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: value)
                .font(.system(size: 21, weight: .bold, design: .monospaced))
                .tracking(valueHasCJK ? 0 : -0.5)
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(BenchTheme.ink.opacity(0.9))
                .lineLimit(1)
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
                Text(localizer.L("Rear I/O controller port schematic", "机身 I/O 控制器物理端口示意图"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BenchTheme.ink)
                Spacer()
                HStack(spacing: 14) {
                    legendPip(color: BenchTheme.ledBlue, text: localizer.L("40 Gb/s tunnel", "40 Gb/s 满速隧道"))
                    legendPip(color: BenchTheme.ledMint, text: localizer.L("USB3 SuperSpeed", "USB3 超高速"))
                    legendPip(color: BenchTheme.ledOrange, text: localizer.L("Bottleneck downstream", "下游存在降速瓶颈"))
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
                .fixedSize(horizontal: true, vertical: false)
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
                Text(ctrl.isConnected
                     ? BottleneckDiagnoser.formatSpeedGbps(ctrl.negotiatedGbps)
                     : localizer.L("OPEN", "空闲"))
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
                Text(ctrl.localizedTitle(localizer))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.94))
                    .lineLimit(1)
                Text(ctrl.isConnected
                     ? localizer.L(
                        "\(ctrl.devices.count) dev · max \(ctrl.maxRateLabel)",
                        "\(ctrl.devices.count) 台设备 · 上限 \(ctrl.maxRateLabel)"
                     )
                     : localizer.L(
                        "Idle · max \(ctrl.maxRateLabel)",
                        "未连接 · 上限 \(ctrl.maxRateLabel)"
                     ))
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
                            Text(mode.localizedTitle(localizer))
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
            .fixedSize(horizontal: true, vertical: false)

            Spacer()

            HStack(spacing: 5) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(BenchTheme.pine)
                Text(localizer.L(
                    "Serial numbers & Thunderbolt UUIDs scrubbed",
                    "硬件序列号与雷雳 UUID 已自动脱敏"
                ))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(BenchTheme.muted)
                .fixedSize(horizontal: true, vertical: false)
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
            Text(localizer.L("Attached peripheral & diagnostic", "已连接外设与链路诊断建议"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(localizer.L("Controller topology", "控制器拓扑路径"))
                .frame(width: 186, alignment: .leading)
            Text(localizer.L("Link verdict", "链路健康判定"))
                .frame(width: 158, alignment: .leading)
            Text(localizer.L("Negotiated vs port ceiling", "协商速率 / 端口上限"))
                .frame(width: 178, alignment: .trailing)
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
                Text(localizer.L("No matching bus devices", "未找到匹配的总线外设"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(BenchTheme.ink)
                Text(localizer.L(
                    "Connect a Thunderbolt, USB4, or USB-C device and click Rescan bus.",
                    "请连接雷雳、USB4 或 USB-C 外设后点击「重新扫描总线」。"
                ))
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
                Text(dev.localizedDiagnosticDetail(localizer))
                    .font(.system(size: 11.5))
                    .foregroundStyle(isWarn ? BenchTheme.signalOrange : BenchTheme.muted)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Topology Path
            VStack(alignment: .leading, spacing: 2) {
                Text(dev.localizedBusName(localizer))
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(BenchTheme.ink)
                    .lineLimit(1)
                Text(dev.localizedModeDescription(localizer))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(dev.depth > 0 && isWarn ? BenchTheme.signalOrange : BenchTheme.subtle)
                    .lineLimit(1)
            }
            .frame(width: 186, alignment: .leading)

            // Verdict Indicator
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(dev.verdict.color)
                    .frame(width: 3.5, height: 14)
                Text(dev.verdict.localizedLabel(localizer))
                    .font(.system(size: 11.5, weight: isWarn ? .bold : .medium))
                    .foregroundStyle(dev.verdict.color)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(width: 158, alignment: .leading)

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
            .frame(width: 178, alignment: .trailing)
        }
        .padding(.leading, isWarn ? 18 : 22)
        .padding(.trailing, 22)
        .padding(.vertical, 10.5)
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
