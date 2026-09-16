import CoreGraphics
import Foundation

/// Geometry for the desktop pet's panel.
///
/// Pure math over the sprite grid, so it can be reasoned about without a window
/// or a screen. In-panel rects use a top-left origin to match SwiftUI and the
/// flipped content view; the screen-facing helpers convert to AppKit's
/// bottom-left origin.
nonisolated enum PetLayout {

    /// The canvas every frame is drawn on. Motion is drawn into the frames rather
    /// than applied to them, so nothing lands outside the canvas and it needs no
    /// margin around it.
    static let gridWidth = 20
    static let gridHeight = 16

    /// Space reserved above the pet for the speech bubble. Reserved whether or
    /// not the bubble is showing, so the pet never moves when it appears.
    static let bubbleHeight: CGFloat = 34
    static let bubbleWidth: CGFloat = 220
    static let bubbleGap: CGFloat = 6

    /// The pet's own box: the canvas at `scale`. This is what the user perceives
    /// as "the pet", what takes the mouse, and what stored positions refer to.
    static func petSize(scale: CGFloat) -> CGSize {
        CGSize(width: CGFloat(gridWidth) * scale, height: CGFloat(gridHeight) * scale)
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
