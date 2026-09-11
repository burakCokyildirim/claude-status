import SwiftUI

/// Draws the desktop pet: the character sprite, its speech bubble, and the badge
/// that says how many sessions it is standing in for.
///
/// Purely a renderer. It takes no gestures and no hover, because SwiftUI's
/// gesture and hover machinery is unreliable in a window that never becomes key;
/// `PetContentView` owns every event instead.
struct PetView: View {

    let character: PetCharacter
    let state: SessionState?
    let transform: PetTransform
    let scale: CGFloat
    /// Total live sessions, so the badge can say the pet is showing one of many.
    let sessionCount: Int
    /// The bubble's text, or `nil` when the bubble is hidden.
    let bubbleTitle: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Establishes the panel-sized coordinate space the offsets below use.
            Color.clear

            // The whole panel rather than the pet box: at the top of a hop the
            // stretched body rises past the box, into the room kept for the bubble.
            sprite
                .frame(width: panelSize.width, height: panelSize.height)

            // After the sprite, so a hop that reaches the bubble passes behind it.
            if let bubbleTitle {
                PetBubbleView(
                    title: bubbleTitle,
                    stateLabel: state?.label ?? "No sessions",
                    accent: accentColor
                )
                // Room for the capsule's shadow when a long title fills the width.
                .padding(.horizontal, 6)
                .frame(width: bubbleRect.width, height: bubbleRect.height)
                .offset(x: bubbleRect.minX, y: bubbleRect.minY)
            }

            if sessionCount > 1 {
                countBadge
                    .offset(x: spriteRect.maxX - badgeSize * 0.55, y: spriteRect.maxY - badgeSize)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Sprite

    private var sprite: some View {
        Canvas { context, _ in
            let rows = character.sprite(for: state ?? .idle, airborne: transform.isAirborne)
            let pixel = scale
            let margin = CGFloat(PetLayout.overshoot) * scale
            let spriteWidth = CGFloat(PetLayout.gridWidth) * pixel
            let spriteHeight = CGFloat(PetLayout.gridHeight) * pixel

            // The canvas spans the panel; the sprite is laid out in the pet box.
            let box = petRect
            context.translateBy(x: box.minX, y: box.minY)

            // Anchor squash and stretch at the feet: a body compresses into the
            // ground, it does not shrink around its middle.
            let anchor = CGPoint(x: box.width / 2, y: margin + spriteHeight)
            context.translateBy(x: anchor.x, y: anchor.y)
            context.scaleBy(x: transform.scaleX, y: transform.scaleY)
            context.translateBy(x: -anchor.x, y: -anchor.y)
            // Grid offsets are whole pixels, and y is inverted because the view's
            // origin is at the top while the motion layer measures upward.
            context.translateBy(x: transform.offsetX * pixel, y: -transform.offsetY * pixel)

            let originX = ((box.width - spriteWidth) / 2).rounded()
            for (row, line) in rows.enumerated() {
                for (column, value) in line.enumerated() {
                    guard let color = character.color(for: value, accent: accentColor) else { continue }
                    let rect = CGRect(
                        x: originX + CGFloat(column) * pixel,
                        y: margin + CGFloat(row) * pixel,
                        width: pixel,
                        height: pixel
                    )
                    // Hard edges: anti-aliased, squash and stretch would leave a
                    // seam of backdrop between every pair of neighbouring cells.
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

    private var panelSize: CGSize { PetLayout.panelSize(scale: scale) }
    private var petRect: CGRect { PetLayout.petRect(scale: scale) }
    private var spriteRect: CGRect { PetLayout.spriteRect(scale: scale) }
    private var bubbleRect: CGRect { PetLayout.bubbleRect(scale: scale) }

    /// Mirrors the dot colours in `SessionRowView`, so the pet and the session
    /// list never disagree about what a state looks like.
    private var accentColor: Color {
        guard let state else { return .gray }
        switch state {
        case .active: return .green
        case .waiting: return .orange
        case .compacting: return .blue
        case .idle: return .gray
        }
    }
}
