import SwiftUI

/// Draws the desktop pet: the character sprite, and the badge up at its top left
/// that counts the sessions it is standing in for. The speech bubble has a panel
/// of its own and points its tail at that badge.
///
/// Purely a renderer. It takes no gestures and no hover, because SwiftUI's
/// gesture and hover machinery is unreliable in a window that never becomes key;
/// `PetContentView` owns every event instead.
struct PetView: View {

    let character: PetCharacter
    /// The drawing to show, picked by `PetWindowController`.
    let frame: PetFrame
    /// The mood on screen, which the badge takes its colour from: the pet's own
    /// session, or the bubble line the pointer is on.
    let mood: PetMood
    let scale: CGFloat
    /// Sessions that are doing something, so the badge can say the pet is
    /// showing one of several. Idle sessions are left out: a machine can carry
    /// dozens of them for days without any of them wanting attention.
    let sessionCount: Int
    /// A bubble is up and points at the badge, so there has to be a badge even
    /// with nothing to count.
    let isBubbleShown: Bool
    /// The bubble's list is open: the badge draws in to a dot, the bubble's mouth.
    let isBubbleOpen: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Establishes the panel-sized coordinate space the offsets below use.
            Color.clear

            sprite
                .frame(width: petRect.width, height: petRect.height)
                .offset(x: petRect.minX, y: petRect.minY)

            if showsBadge {
                badge
                    .transition(.scale(scale: 0.2, anchor: dotCenter).combined(with: .opacity))
            }
        }
        .animation(Self.badgeSpring, value: showsBadge)
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

    private static let badgeSpring = Animation.spring(response: 0.3, dampingFraction: 0.72)

    private var showsBadge: Bool { sessionCount > 1 || isBubbleShown }

    /// Where the badge comes from and goes to, as a point of the whole panel.
    private var dotCenter: UnitPoint {
        let dot = PetLayout.badgeDotRect(scale: scale, corner: character.badgeCorner)
        let panel = PetLayout.panelSize(scale: scale)
        return UnitPoint(x: dot.midX / panel.width, y: dot.midY / panel.height)
    }

    /// A pill with the count, or the dot it draws in to.
    private var badge: some View {
        let isDot = PetLayout.isBadgeDot(count: sessionCount, isBubbleOpen: isBubbleOpen)
        let rect = PetLayout.badgeRect(
            scale: scale,
            corner: character.badgeCorner,
            count: sessionCount,
            isBubbleOpen: isBubbleOpen
        )
        return Capsule()
            .fill(mood.accent)
            .overlay(Capsule().stroke(Color.white.opacity(0.9), lineWidth: isDot ? 1 : 1.5))
            .overlay(
                Text("\(sessionCount)")
                    .font(.system(size: PetLayout.badgeFontSize(scale: scale), weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .fixedSize()
                    .opacity(isDot ? 0 : 1)
                    .scaleEffect(isDot ? 0.4 : 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .animation(Self.badgeSpring, value: isDot)
            .animation(.easeInOut(duration: 0.2), value: mood)
    }

    // MARK: - Geometry

    private var petRect: CGRect { PetLayout.petRect(scale: scale) }
}
