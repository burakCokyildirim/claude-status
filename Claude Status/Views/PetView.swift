import SwiftUI

/// Draws the desktop pet inside the pet panel.
///
/// Purely a renderer: it takes no gestures and no hover. Every event is handled
/// by `PetContentView`, because SwiftUI's own gesture and hover machinery is
/// unreliable in a window that never becomes key.
struct PetView: View {

    let scale: CGFloat

    var body: some View {
        Canvas { context, _ in
            // Placeholder silhouette. The character sprites replace this.
            let sprite = PetLayout.spriteRect(scale: scale)
            context.fill(
                Path(roundedRect: sprite, cornerRadius: scale * 2),
                with: .color(.gray.opacity(0.85))
            )
        }
        .allowsHitTesting(false)
    }
}
