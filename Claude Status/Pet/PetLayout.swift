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

    /// The pet's own box: the canvas at `scale`. This is what the user perceives
    /// as "the pet", what takes the mouse, and what stored positions refer to.
    static func petSize(scale: CGFloat) -> CGSize {
        CGSize(width: CGFloat(gridWidth) * scale, height: CGFloat(gridHeight) * scale)
    }

    /// The whole panel: the pet box, with room either side for the count badge
    /// to hang past its edge.
    static func panelSize(scale: CGFloat) -> CGSize {
        let pet = petSize(scale: scale)
        return CGSize(width: pet.width + badgeOverhang(scale: scale) * 2, height: pet.height)
    }

    /// The pet box inside the panel: horizontally centered, filling its height.
    static func petRect(scale: CGFloat) -> CGRect {
        CGRect(origin: CGPoint(x: badgeOverhang(scale: scale), y: 0), size: petSize(scale: scale))
    }

    /// The count badge inside the panel, on the pet box's bottom-right corner and
    /// hanging a little past its right edge.
    static func badgeRect(scale: CGFloat) -> CGRect {
        let side = badgeSide(scale: scale)
        let pet = petRect(scale: scale)
        return CGRect(x: pet.maxX - side * 0.55, y: pet.maxY - side, width: side, height: side)
    }

    private static func badgeSide(scale: CGFloat) -> CGFloat {
        max(16, scale * 4.5)
    }

    /// How far the badge reaches past the pet box, its outline included.
    private static func badgeOverhang(scale: CGFloat) -> CGFloat {
        (badgeSide(scale: scale) * 0.45).rounded(.up) + 1
    }

    // MARK: - Screen Conversion

    /// The panel frame origin that places the pet box at `petOrigin` on screen.
    ///
    /// The pet box fills the panel's height, so only x needs an adjustment for
    /// the horizontal centering.
    static func panelOrigin(forPetOrigin petOrigin: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(x: petOrigin.x - petRect(scale: scale).minX, y: petOrigin.y)
    }

    /// The pet box's on-screen origin for a panel placed at `panelOrigin`.
    static func petOrigin(forPanelOrigin panelOrigin: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(x: panelOrigin.x + petRect(scale: scale).minX, y: panelOrigin.y)
    }

    // MARK: - Speech Bubble

    /// The widest the bubble's outline gets; a long session name is what gives way.
    static let bubbleWidth: CGFloat = 220
    static let bubbleRowHeight: CGFloat = 22
    /// Inside the outline, before the first row and after the last.
    static let bubblePadding: CGFloat = 4
    /// Transparent room around the outline for its shadow. It also stands as the
    /// gap to the pet, so the pointer crosses no dead space between the two.
    static let bubbleShadowInset: CGFloat = 6
    /// Past this many sessions, the last row counts the rest instead.
    static let bubbleMaxRows = 8

    /// The bubble panel's height for `rows` rows.
    static func bubbleHeight(rows: Int) -> CGFloat {
        CGFloat(rows) * bubbleRowHeight + (bubblePadding + bubbleShadowInset) * 2
    }

    /// The row under `point` in a bubble panel of `size`, in the panel's flipped
    /// coordinates, or `nil` over the shadow room.
    ///
    /// Rows count outwards from the pet: the first sits nearest it, at the bottom
    /// of a bubble above the pet and at the top of one below. So the list grows
    /// out of the line the pet's own session is on, and that line stays put under
    /// the pointer as the list opens.
    static func bubbleRow(at point: CGPoint, in size: CGSize, rows: Int, isAbove: Bool) -> Int? {
        let outline = CGRect(origin: .zero, size: size).insetBy(dx: bubbleShadowInset, dy: bubbleShadowInset)
        guard rows > 0, outline.contains(point) else { return nil }
        let slot = min(max(Int((point.y - outline.minY - bubblePadding) / bubbleRowHeight), 0), rows - 1)
        return isAbove ? rows - 1 - slot : slot
    }

    /// Where a bubble panel of `size` goes on screen for a pet box at `petRect`.
    ///
    /// Above the pet when the working area has room for it, below otherwise;
    /// centered on the pet, and kept inside the working area sideways.
    static func bubblePlacement(size: CGSize, petRect: CGRect, in area: CGRect) -> PetBubblePlacement {
        let isAbove = petRect.maxY + size.height <= area.maxY || petRect.minY - size.height < area.minY
        let centered = (petRect.midX - size.width / 2).rounded()
        let x = min(max(centered, area.minX), max(area.maxX - size.width, area.minX))
        let y = isAbove ? petRect.maxY : petRect.minY - size.height
        return PetBubblePlacement(frame: CGRect(origin: CGPoint(x: x, y: y), size: size), isAbove: isAbove)
    }
}

/// A bubble panel's on-screen frame, and which side of the pet it is on.
nonisolated struct PetBubblePlacement: Equatable {
    let frame: CGRect
    let isAbove: Bool
}
