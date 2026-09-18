import SwiftUI

/// A stacked horizontal bar showing time-in-state breakdown.
/// On hover, displays a floating tooltip panel with the legend.
struct ProductivityBarView: View {
    let stats: ProductivityStats

    @State private var tooltipPanel: NSPanel?

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                barSegment(width: geo.size.width * stats.activePercent, color: .green)
                barSegment(width: geo.size.width * stats.waitingPercent, color: .orange)
                barSegment(width: geo.size.width * stats.compactingPercent, color: .blue)
                barSegment(width: geo.size.width * stats.idlePercent, color: .gray)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .background(
                GeometryReader { barGeo in
                    Color.clear
                        .onAppear {} // force geometry evaluation
                        .preference(key: BarFrameKey.self, value: barGeo.frame(in: .global))
                }
            )
        }
        .frame(height: 6)
        // Expand the hover hit area vertically so the thin bar is easy to target
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                showTooltip()
            } else {
                hideTooltip()
            }
        }
    }

    @ViewBuilder
    private func barSegment(width: CGFloat, color: Color) -> some View {
        if width > 0 {
            Rectangle()
                .fill(color)
                .frame(width: max(width, 2))
        }
    }

    private func showTooltip() {
        guard tooltipPanel == nil else { return }

        let content = NSHostingView(rootView: tooltipContent)
        content.frame.size = content.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: content.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .popUpMenu
        panel.hasShadow = false
        panel.contentView = content
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true

        // Position below the mouse cursor
        let mouseLocation = NSEvent.mouseLocation
        panel.setFrameOrigin(NSPoint(
            x: mouseLocation.x - content.fittingSize.width / 2,
            y: mouseLocation.y - content.fittingSize.height - 16
        ))
        panel.orderFront(nil)
        tooltipPanel = panel
    }

    private func hideTooltip() {
        tooltipPanel?.close()
        tooltipPanel = nil
    }

    private var tooltipContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            legendRow(color: .green, label: "\(Int(stats.activePercent * 100))% active")
            legendRow(color: .orange, label: "\(Int(stats.waitingPercent * 100))% wait")
            legendRow(color: .blue, label: "\(Int(stats.compactingPercent * 100))% compact")
            legendRow(color: .gray, label: "\(Int(stats.idlePercent * 100))% idle")
        }
        .font(.system(size: 11))
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        )
    }

    private func legendRow(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
        }
    }
}

private struct BarFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
