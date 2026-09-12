import SwiftUI

/// The pet's speech bubble: which session it is showing, and what that session
/// is doing. One line, truncated — the popover is where the detail lives.
struct PetBubbleView: View {

    let title: String
    let stateLabel: String
    let accent: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(accent)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            // The state always reads in full; a long title is what gives way.
            Text(stateLabel)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(.background)
                .overlay(
                    Capsule()
                        .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        )
    }
}
