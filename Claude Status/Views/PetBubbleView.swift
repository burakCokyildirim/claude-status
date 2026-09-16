import SwiftUI

/// The pet's speech bubble: the sessions that are doing something, one line
/// each, the first nearest the pet. Lines are truncated — the popover is where
/// the detail lives.
///
/// Purely a renderer, like `PetView`: `PetBubbleContentView` owns the mouse and
/// tells it which row is under the pointer.
struct PetBubbleView: View {

    let rows: [PetBubbleRow]
    /// Whether the bubble sits above the pet, which puts its first row at the
    /// bottom. `PetLayout.bubbleRow(at:in:rows:isAbove:)` counts the same way.
    let isAbove: Bool
    /// The row under the pointer.
    let highlighted: Int?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(order, id: \.self) { index in
                line(rows[index], isHighlighted: index == highlighted)
            }
        }
        .padding(.vertical, PetLayout.bubblePadding)
        .frame(maxWidth: PetLayout.bubbleWidth)
        .fixedSize()
        .background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.background)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        )
        .padding(PetLayout.bubbleShadowInset)
    }

    private var order: [Int] {
        isAbove ? Array(rows.indices.reversed()) : Array(rows.indices)
    }

    /// A single line reads as a capsule, the way the one-line bubble always has.
    private var cornerRadius: CGFloat {
        rows.count == 1 ? PetLayout.bubbleHeight(rows: 1) / 2 - PetLayout.bubbleShadowInset : 11
    }

    private func line(_ row: PetBubbleRow, isHighlighted: Bool) -> some View {
        HStack(spacing: 5) {
            if let accent = row.accent {
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
            }
            Text(row.title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            // The state always reads in full; a long title is what gives way.
            if let stateLabel = row.stateLabel {
                Text(stateLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 9)
        .frame(height: PetLayout.bubbleRowHeight)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(isHighlighted ? 0.1 : 0))
                .padding(.horizontal, 3)
        )
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
