import SwiftUI

/// Draws the desktop pet: the character sprite, its speech bubble, and the badge
/// that says how many sessions it is standing in for.
///
/// Purely a renderer. It takes no gestures and no hover, because SwiftUI's
/// gesture and hover machinery is unreliable in a window that never becomes key;
/// `PetContentView` owns every event instead.
struct PetView: View {

    let character: PetCharacter
    /// The drawing to show, picked by `PetWindowController`.
    let frame: PetFrame
    let state: SessionState?
    /// Claude has spoken here since the user last looked. Shown in its own
    /// colour rather than folded into `state`, because "there is something to
    /// read" is a different claim from "this session is blocked on you".
    let isUnread: Bool
    let scale: CGFloat
    /// Sessions that are doing something, so the badge can say the pet is
    /// showing one of several. Idle sessions are left out: a machine can carry
    /// dozens of them for days without any of them wanting attention.
    let sessionCount: Int
    /// The bubble's text, or `nil` when the bubble is hidden.
    let bubbleTitle: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Establishes the panel-sized coordinate space the offsets below use.
            Color.clear

            sprite
                .frame(width: petRect.width, height: petRect.height)
                .offset(x: petRect.minX, y: petRect.minY)

            if let bubbleTitle {
                PetBubbleView(
                    title: bubbleTitle,
                    stateLabel: stateLabel,
                    accent: accentColor
                )
                // Room for the capsule's shadow when a long title fills the width.
                .padding(.horizontal, 6)
                .frame(width: bubbleRect.width, height: bubbleRect.height)
                .offset(x: bubbleRect.minX, y: bubbleRect.minY)
            }

            if sessionCount > 1 {
                countBadge
                    .offset(x: petRect.maxX - badgeSize * 0.55, y: petRect.maxY - badgeSize)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Sprite

    private var sprite: some View {
        Canvas { context, _ in
            let pixel = scale
            for (row, line) in frame.rows.enumerated() {
                for (column, key) in line.enumerated() {
                    guard let color = character.color(for: key) else { continue }
                    let rect = CGRect(
                        x: CGFloat(column) * pixel,
                        y: CGFloat(row) * pixel,
                        width: pixel,
                        height: pixel
                    )
                    // Hard edges: anti-aliased, neighbouring cells would leave a
                    // hairline seam of backdrop between them.
                    context.fill(Path(rect), with: .color(color), style: FillStyle(antialiased: false))
                }
            }
        }
    }

    // MARK: - Badge

    private var countBadge: some View {
        Text("\(sessionCount)")
            .font(.system(size: badgeSize * 0.6, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: badgeSize, height: badgeSize)
            .background(Circle().fill(accentColor))
            .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1))
    }

    private var badgeSize: CGFloat { max(16, scale * 4.5) }

    // MARK: - Geometry

    private var petRect: CGRect { PetLayout.petRect(scale: scale) }
    private var bubbleRect: CGRect { PetLayout.bubbleRect(scale: scale) }

    private var stateLabel: String {
        guard let state else { return "No sessions" }
        return isUnread ? "Unread" : state.label
    }

    /// Mirrors the dot colours in `SessionRowView`, so the pet and the session
    /// list never disagree about what a state looks like.
    private var accentColor: Color {
        guard let state else { return .gray }
        if isUnread { return SessionPalette.unread }
        switch state {
        case .active: return .green
        case .waiting: return .orange
        case .compacting: return .blue
        case .idle: return .gray
        }
    }
}
