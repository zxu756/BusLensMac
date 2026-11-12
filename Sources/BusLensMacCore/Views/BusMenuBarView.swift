import SwiftUI

public struct BusMenuBarView: View {
    @ObservedObject var monitor: BusLensMonitor
    public var onOpenWindow: () -> Void
    public var onQuit: () -> Void

    public init(
        monitor: BusLensMonitor,
        onOpenWindow: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.monitor = monitor
        self.onOpenWindow = onOpenWindow
        self.onQuit = onQuit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("BusLens Mac")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BenchTheme.chalk)
                    Text("\(monitor.snapshot.devices.count) attached devices, \(monitor.snapshot.power.displayBadge)")
                        .font(.system(size: 11))
                        .foregroundStyle(BenchTheme.slate)
                }
                Spacer()
                let warns = monitor.snapshot.bottleneckDevices.count
                Text(verbatim: warns > 0 ? "\(warns) warning\(warns == 1 ? "" : "s")" : "Optimal")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(warns > 0 ? BenchTheme.coral : BenchTheme.emerald)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(BenchTheme.panel)

            Divider().overlay(BenchTheme.trace)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(monitor.snapshot.devices.prefix(5)) { dev in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(dev.verdict.color)
                            .frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dev.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(BenchTheme.chalk)
                                .lineLimit(1)
                            Text(dev.verdict.rawValue)
                                .font(.system(size: 10.5))
                                .foregroundStyle(dev.verdict.isWarning ? BenchTheme.coral : BenchTheme.slate)
                        }
                        Spacer()
                        Text(verbatim: dev.negotiatedSpeedLabel)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(dev.verdict.isWarning ? BenchTheme.coral : BenchTheme.chalk)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    Divider().overlay(BenchTheme.trace.opacity(0.65))
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button(action: onOpenWindow) {
                    Text("Open bench")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(BenchTheme.chalk)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(BenchTheme.slot))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(BenchTheme.trace, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button(action: { monitor.refresh() }) {
                    Text("Rescan")
                        .font(.system(size: 12))
                        .foregroundStyle(BenchTheme.slate)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onQuit) {
                    Text("Quit")
                        .font(.system(size: 12))
                        .foregroundStyle(BenchTheme.slate)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(BenchTheme.panel)
        }
        .background(BenchTheme.chassis)
    }
}
