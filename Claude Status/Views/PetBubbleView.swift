import SwiftUI

/// The pet's speech bubble: the sessions that are doing something, one line
/// each, the first nearest the pet, with a tail pointing at the pet's badge.
///
/// Purely a renderer, like `PetView`: `PetBubbleContentView` owns the mouse and
/// tells it which row is under the pointer.
struct PetBubbleView: View {

    let rows: [PetBubbleRow]
    /// Whether the bubble sits above the pet, which puts its first row and its
    /// tail at the bottom. `PetLayout.bubbleRow(at:in:rows:isAbove:)` counts the
    /// same way.
    let isAbove: Bool
    /// The row under the pointer.
    let highlighted: Int?
    /// Where the tail meets the outline, from the outline's left edge.
    let tailX: CGFloat
    /// Whether the bubble is out. It bursts out of the badge as this turns on,
    /// and draws back in as it turns off; its size never changes, so the panel
    /// can be laid out before it shows.
    let isShown: Bool

    /// How long the bubble takes to draw back into the badge.
    static let drawInDuration: TimeInterval = 0.12

    var body: some View {
        VStack(spacing: 0) {
            ForEach(order, id: \.self) { index in
                line(rows[index], isHighlighted: index == highlighted)
            }
        }
        .padding(.vertical, PetLayout.bubblePadding)
        .padding(isAbove ? .bottom : .top, PetLayout.bubbleTailHeight)
        .frame(maxWidth: PetLayout.bubbleWidth)
        .fixedSize()
        .background(
            BubbleOutline(radius: PetLayout.bubbleCornerRadius(rows: rows.count), tailX: tailX, isTailAtBottom: isAbove)
                .fill(.background)
                .overlay(
                    BubbleOutline(radius: PetLayout.bubbleCornerRadius(rows: rows.count), tailX: tailX, isTailAtBottom: isAbove)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
        )
        .padding(PetLayout.bubbleShadowInset)
        // Grown from the tip of the tail, which sits on the badge.
        .visualEffect { [tailX, isAbove, isShown] content, proxy in
            let inset = PetLayout.bubbleShadowInset
            let size = CGSize(width: max(proxy.size.width, 1), height: max(proxy.size.height, 1))
            return content.scaleEffect(
                isShown ? 1 : 0.15,
                anchor: UnitPoint(
                    x: (inset + tailX) / size.width,
                    y: isAbove ? (size.height - inset) / size.height : inset / size.height
                )
            )
        }
        .opacity(isShown ? 1 : 0)
        .animation(
            isShown ? .spring(response: 0.34, dampingFraction: 0.66) : .easeIn(duration: Self.drawInDuration),
            value: isShown
        )
    }

    private var order: [Int] {
        isAbove ? Array(rows.indices.reversed()) : Array(rows.indices)
    }

    private func line(_ row: PetBubbleRow, isHighlighted: Bool) -> some View {
        HStack(spacing: 6) {
            if let accent = row.accent {
                Circle()
                    .fill(accent)
                    .frame(width: 7, height: 7)
            }
            RollingTitle(text: row.title, isRolling: isHighlighted && isShown)
            Spacer(minLength: 8)
            // The state always reads in full; a long title is what gives way.
            if let stateLabel = row.stateLabel {
                Text(stateLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .frame(height: PetLayout.bubbleRowHeight)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.primary.opacity(isHighlighted ? 0.1 : 0))
                .padding(.horizontal, 4)
        )
    }
}

/// A session name that ends in an ellipsis when it does not fit, and scrolls to
/// show the rest while its line is under the pointer.
private struct RollingTitle: View {

    let text: String
    let isRolling: Bool

    @State private var fullWidth: CGFloat = 0
    @State private var shownWidth: CGFloat = 0
    @State private var rollStart = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let font = Font.system(size: 13, weight: .medium)

    var body: some View {
        let overflow = max(fullWidth - shownWidth, 0)
        let rolls = isRolling && overflow > 1 && !reduceMotion
        Text(text)
            .font(Self.font)
            .lineLimit(1)
            .truncationMode(.tail)
            .opacity(rolls ? 0 : 1)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { shownWidth = $0 }
            .background(alignment: .leading) {
                // The whole name, measured but never drawn.
                Text(text)
                    .font(Self.font)
                    .fixedSize()
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { fullWidth = $0 }
            }
            .overlay(alignment: .leading) {
                if rolls {
                    TimelineView(.animation) { context in
                        Text(text)
                            .font(Self.font)
                            .fixedSize()
                            .offset(x: -overflow * Self.rollProgress(
                                elapsed: context.date.timeIntervalSince(rollStart),
                                overflow: overflow
                            ))
                    }
                    .frame(width: shownWidth, alignment: .leading)
                    .clipped()
                }
            }
            .onChange(of: rolls) { _, rolling in
                if rolling { rollStart = Date() }
            }
    }

    /// How far through the name the scroll is, from 0 to 1: it waits at the
    /// start, eases across at a reading pace, waits at the end, and comes back.
    static func rollProgress(elapsed: TimeInterval, overflow: CGFloat) -> CGFloat {
        let pause = 0.9
        let travel = max(Double(overflow) / 36, 0.4)
        let period = 2 * (pause + travel)
        let time = elapsed.truncatingRemainder(dividingBy: period)
        let linear: Double
        switch time {
        case ..<pause: linear = 0
        case ..<(pause + travel): linear = (time - pause) / travel
        case ..<(pause * 2 + travel): linear = 1
        default: linear = 1 - (time - pause * 2 - travel) / travel
        }
        return CGFloat(linear * linear * (3 - 2 * linear))
    }
}

/// The bubble's outline: a rounded rectangle with a tail, as one shape, so its
/// stroke does not cross the foot of the tail.
private struct BubbleOutline: Shape {

    let radius: CGFloat
    /// Where the tail meets the outline, from its left edge.
    let tailX: CGFloat
    let isTailAtBottom: Bool

    func path(in rect: CGRect) -> Path {
        let tail = PetLayout.bubbleTailHeight
        let body = CGRect(
            x: rect.minX,
            y: isTailAtBottom ? rect.minY : rect.minY + tail,
            width: rect.width,
            height: rect.height - tail
        )
        let half = PetLayout.bubbleTailWidth / 2
        let x = rect.minX + min(max(tailX, radius + half), max(rect.width - radius - half, radius + half))
        let foot = isTailAtBottom ? body.maxY - 1 : body.minY + 1
        let tip = isTailAtBottom ? rect.maxY : rect.minY
        var pointer = Path()
        pointer.move(to: CGPoint(x: x - half, y: foot))
        pointer.addQuadCurve(to: CGPoint(x: x, y: tip), control: CGPoint(x: x - half * 0.3, y: (foot + tip) / 2))
        pointer.addQuadCurve(to: CGPoint(x: x + half, y: foot), control: CGPoint(x: x + half * 0.3, y: (foot + tip) / 2))
        pointer.closeSubpath()
        return Path(roundedRect: body, cornerRadius: radius).union(pointer)
    }
}

/// One line of the speech bubble.
struct PetBubbleRow: Equatable {
    let title: String
    /// What the session is doing, or `nil` for a line that is not a session.
    let stateLabel: String?
    let accent: Color?
}

extension PetBubbleRow {

    init(session: ClaudeSession) {
        let mood = PetMood(state: session.state, isUnread: session.isUnread == true)
        self.init(title: session.sessionName ?? session.projectName, stateLabel: mood.label, accent: mood.accent)
    }

    /// The last line, standing in for the sessions there is no room to list.
    init(moreSessions count: Int) {
        self.init(title: "\(count) more\u{2026}", stateLabel: nil, accent: nil)
    }
}

extension PetMood {

    var label: String {
        switch self {
        case .active: "Active"
        case .waiting: "Waiting"
        case .unread: "Unread"
        case .compacting: "Compacting"
        case .idle: "Idle"
        case .resting: "No sessions"
        }
    }

    /// Mirrors the dot colours in `SessionRowView`, so the pet and the session
    /// list never disagree about what a state looks like.
    var accent: Color {
        switch self {
        case .active: .green
        case .waiting: .orange
        case .unread: SessionPalette.unread
        case .compacting: .blue
        case .idle, .resting: .gray
        }
    }
}
