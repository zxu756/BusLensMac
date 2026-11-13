import SwiftUI

public struct BusMenuBarView: View {
    @ObservedObject var monitor: BusLensMonitor
    @ObservedObject var localizer: AppLocalizer
    public var onOpenWindow: () -> Void
    public var onQuit: () -> Void

    @MainActor
    public init(
        monitor: BusLensMonitor,
        localizer: AppLocalizer? = nil,
        onOpenWindow: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.monitor = monitor
        self.localizer = localizer ?? .shared
        self.onOpenWindow = onOpenWindow
        self.onQuit = onQuit
    }

    public var body: some View {
        let warns = monitor.snapshot.bottleneckDevices.count

        VStack(alignment: .leading, spacing: 0) {
            // Anodized Header + Compact Mini Port Strip
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .center) {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.horizontal.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(BenchTheme.signalOrange)
                        Text("BusLens Mac")
                            .font(.system(size: 13.5, weight: .bold))
                            .tracking(-0.2)
                            .foregroundStyle(BenchTheme.ink)
                    }
                    Spacer()
                    LanguageTogglePill(localizer: localizer, compact: true)
                }

                HStack(alignment: .center) {
                    Text(localizer.L(
                        "\(monitor.snapshot.devices.count) attached · \(monitor.snapshot.power.localizedBadge(localizer))",
                        "已连接 \(monitor.snapshot.devices.count) 台 · \(monitor.snapshot.power.localizedBadge(localizer))"
                    ))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(BenchTheme.muted)
                    .fixedSize(horizontal: true, vertical: false)

                    Spacer()

                    Text(warns > 0
                         ? localizer.L(
                            "\(warns) bottleneck\(warns == 1 ? "" : "s")",
                            "\(warns) 处降速瓶颈"
                         )
                         : localizer.L("All optimal", "全部满速正常"))
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(warns > 0 ? .white : BenchTheme.pine)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .fixedSize(horizontal: true, vertical: false)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(warns > 0 ? BenchTheme.signalOrange : BenchTheme.pine.opacity(0.12))
                        )
                }

                // Mini 5-port dark graphite backplate preview
                HStack(spacing: 5) {
                    ForEach(Array(monitor.snapshot.controllers.prefix(5).enumerated()), id: \.element.id) { idx, ctrl in
                        let hasWarn = ctrl.devices.contains { $0.verdict == .cableOrHubBottleneck }
                        let led: Color = hasWarn
                            ? BenchTheme.ledOrange
                            : (ctrl.isConnected ? (ctrl.negotiatedGbps >= 40 ? BenchTheme.ledBlue : BenchTheme.ledMint) : BenchTheme.portRim)

                        VStack(spacing: 4) {
                            HStack(spacing: 3) {
                                Circle().fill(led).frame(width: 4.5, height: 4.5)
                                Text(verbatim: ctrl.protocolKind == .thunderboltUSB4 ? "TB\(idx)" : "U\(idx)")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(BenchTheme.portSilk)
                            }
                            Capsule()
                                .fill(BenchTheme.portCavity)
                                .frame(width: 24, height: 8)
                                .overlay(Capsule().strokeBorder(ctrl.isConnected ? led.opacity(0.8) : BenchTheme.portRim, lineWidth: 1))
                        }
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(BenchTheme.portBay))
                    }
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 11)
            .background(BenchTheme.chassis)

            Rectangle().fill(BenchTheme.seam).frame(height: 1)

            // Attached Device Rows
            VStack(alignment: .leading, spacing: 0) {
                ForEach(monitor.snapshot.devices.prefix(5)) { dev in
                    let isWarn = dev.verdict.isWarning
                    HStack(spacing: 9) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(dev.verdict.color)
                            .frame(width: 3, height: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dev.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(BenchTheme.ink)
                                .lineLimit(1)
                            Text("\(dev.vendor) · \(dev.verdict.localizedLabel(localizer))")
                                .font(.system(size: 10.5))
                                .foregroundStyle(isWarn ? BenchTheme.signalOrange : BenchTheme.muted)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(verbatim: dev.negotiatedSpeedLabel)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(isWarn ? BenchTheme.signalOrange : BenchTheme.ink)
                                .fixedSize(horizontal: true, vertical: false)
                            Text(localizer.L(
                                "max \(BottleneckDiagnoser.formatSpeedGbps(dev.portCeilingGbps))",
                                "上限 \(BottleneckDiagnoser.formatSpeedGbps(dev.portCeilingGbps))"
                            ))
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(BenchTheme.subtle)
                            .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 8)
                    .background(isWarn ? BenchTheme.signalOrange.opacity(0.055) : BenchTheme.plate)

                    Rectangle().fill(BenchTheme.hairline).frame(height: 1)
                }
            }

            Spacer(minLength: 0)

            Rectangle().fill(BenchTheme.seam).frame(height: 1)

            HStack(spacing: 8) {
                Button(action: onOpenWindow) {
                    Text(localizer.L("Open schematic", "打开端口面板"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5.5)
                        .fixedSize(horizontal: true, vertical: false)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(BenchTheme.portBay))
                }
                .buttonStyle(.plain)

                Button(action: { monitor.refresh() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text(localizer.L("Rescan", "重新扫描"))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(BenchTheme.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5.5)
                    .fixedSize(horizontal: true, vertical: false)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(BenchTheme.plate))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(BenchTheme.seam, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onQuit) {
                    Text(localizer.L("Quit", "退出"))
                        .font(.system(size: 12))
                        .foregroundStyle(BenchTheme.muted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 5)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
            .background(BenchTheme.chassis)
        }
        .background(BenchTheme.plate)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(BenchTheme.seam, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .environment(\.locale, localizer.language.locale)
        .preferredColorScheme(.light)
    }
}
