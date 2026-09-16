import SwiftUI

/// Draws the desktop pet: the character sprite, and the badge that says how many
/// sessions it is standing in for. The speech bubble has a panel of its own.
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

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Establishes the panel-sized coordinate space the offsets below use.
            Color.clear

            sprite
                .frame(width: petRect.width, height: petRect.height)
                .offset(x: petRect.minX, y: petRect.minY)

            if sessionCount > 1 {
                countBadge
                    .offset(x: badgeRect.minX, y: badgeRect.minY)
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
            .font(.system(size: badgeRect.height * 0.6, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: badgeRect.width, height: badgeRect.height)
            .background(Circle().fill(PetMood(state: state, isUnread: isUnread).accent))
            .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1))
    }

    // MARK: - Geometry

    private var petRect: CGRect { PetLayout.petRect(scale: scale) }
    private var badgeRect: CGRect { PetLayout.badgeRect(scale: scale) }
}
