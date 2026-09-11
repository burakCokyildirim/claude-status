import CoreGraphics
import Foundation

/// Geometry for the desktop pet's panel.
///
/// Pure math over the sprite grid, so it can be reasoned about without a window
/// or a screen. In-panel rects use a top-left origin to match SwiftUI and the
/// flipped content view; the screen-facing helpers convert to AppKit's
/// bottom-left origin.
nonisolated enum PetLayout {

    /// The sprite grid. Portrait, so the character has room for a head, a body,
    /// and vertical motion.
    static let gridWidth = 16
    static let gridHeight = 24

    /// Grid pixels of empty margin drawn around the sprite so hops and stretch
    /// are not clipped by the panel edge. Nothing is ever drawn here, so it
    /// stays fully transparent and clicks pass straight through it.
    static let overshoot = 4

    /// Space reserved above the pet for the speech bubble. Reserved whether or
    /// not the bubble is showing, so the pet never moves when it appears.
    static let bubbleHeight: CGFloat = 34
    static let bubbleWidth: CGFloat = 220
    static let bubbleGap: CGFloat = 6

    /// The pet's own box: the sprite plus its motion margin. This is what the
    /// user perceives as "the pet", and what stored positions refer to.
    static func petSize(scale: CGFloat) -> CGSize {
        CGSize(
            width: CGFloat(gridWidth + overshoot * 2) * scale,
            height: CGFloat(gridHeight + overshoot * 2) * scale
        )
    }

    /// The whole panel: the pet box with the bubble reserved above it.
    static func panelSize(scale: CGFloat) -> CGSize {
        let pet = petSize(scale: scale)
        return CGSize(
            width: max(pet.width, bubbleWidth),
            height: bubbleHeight + bubbleGap + pet.height
        )
    }

    /// The pet box inside the panel: flush with the bottom, horizontally centered.
    static func petRect(scale: CGFloat) -> CGRect {
        let panel = panelSize(scale: scale)
        let pet = petSize(scale: scale)
        return CGRect(
            x: ((panel.width - pet.width) / 2).rounded(),
            y: panel.height - pet.height,
            width: pet.width,
            height: pet.height
        )
    }

    /// The sprite itself, with the motion margin removed.
    ///
    /// This is the mouse target. It is deliberately fixed: if it tracked the
    /// animation, clicking a hopping pet would mean chasing a moving target.
    static func spriteRect(scale: CGFloat) -> CGRect {
        let margin = CGFloat(overshoot) * scale
        return petRect(scale: scale).insetBy(dx: margin, dy: margin)
    }

    /// The bubble's box inside the panel: top, spanning the full width.
    static func bubbleRect(scale: CGFloat) -> CGRect {
        CGRect(x: 0, y: 0, width: panelSize(scale: scale).width, height: bubbleHeight)
    }

    // MARK: - Screen Conversion

    /// The panel frame origin that places the pet box at `petOrigin` on screen.
    ///
    /// The pet box is flush with the panel's bottom edge, so only x needs an
    /// adjustment for the horizontal centering.
    static func panelOrigin(forPetOrigin petOrigin: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(x: petOrigin.x - petRect(scale: scale).minX, y: petOrigin.y)
    }

    /// The pet box's on-screen origin for a panel placed at `panelOrigin`.
    static func petOrigin(forPanelOrigin panelOrigin: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(x: panelOrigin.x + petRect(scale: scale).minX, y: panelOrigin.y)
    }
}
