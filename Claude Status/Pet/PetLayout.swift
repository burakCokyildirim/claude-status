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
    /// than applied to them, so nothing lands outside the canvas.
    static let gridWidth = 20
    static let gridHeight = 16

    /// The pet's own box: the canvas at `scale`. This is what the user perceives
    /// as "the pet", what takes the mouse, and what stored positions refer to.
    static func petSize(scale: CGFloat) -> CGSize {
        CGSize(width: CGFloat(gridWidth) * scale, height: CGFloat(gridHeight) * scale)
    }

    /// The whole panel: the pet box, with room all round for the count badge,
    /// which sits up and to the left of the character and can reach past the box.
    static func panelSize(scale: CGFloat) -> CGSize {
        let pet = petSize(scale: scale)
        let margin = panelMargin(scale: scale)
        return CGSize(width: pet.width + margin * 2, height: pet.height + margin * 2)
    }

    /// The pet box inside the panel, centered.
    static func petRect(scale: CGFloat) -> CGRect {
        let margin = panelMargin(scale: scale)
        return CGRect(origin: CGPoint(x: margin, y: margin), size: petSize(scale: scale))
    }

    private static func panelMargin(scale: CGFloat) -> CGFloat {
        (badgeHeight(scale: scale) * 1.6).rounded(.up)
    }

    // MARK: - Badge

    /// The count badge's height: it grows a little with the pet, within the range
    /// a badge reads well in.
    static func badgeHeight(scale: CGFloat) -> CGFloat {
        min(max((scale * 3.5).rounded(), 20), 30)
    }

    /// The count's point size inside the badge.
    static func badgeFontSize(scale: CGFloat) -> CGFloat {
        (badgeHeight(scale: scale) * 0.62).rounded()
    }

    /// The badge inside the panel, as a pill wide enough for `digits`.
    ///
    /// Its bottom-right corner sits on `corner`, the character's own point in
    /// canvas cells, so the pill grows away from the character, never into it.
    static func badgeRect(scale: CGFloat, corner: CGPoint, digits: Int) -> CGRect {
        let height = badgeHeight(scale: scale)
        let width = height + CGFloat(max(digits - 1, 0)) * (height * 0.45).rounded()
        let end = badgeEnd(scale: scale, corner: corner)
        return CGRect(x: end.x - width, y: end.y - height, width: width, height: height)
    }

    /// The dot the badge draws in to while the bubble is open: the bubble's
    /// mouth, centered in the badge's right-hand end.
    static func badgeDotRect(scale: CGFloat, corner: CGPoint) -> CGRect {
        let height = badgeHeight(scale: scale)
        let side = (height * 0.45).rounded()
        let end = badgeEnd(scale: scale, corner: corner)
        let center = CGPoint(x: end.x - height / 2, y: end.y - height / 2)
        return CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
    }

    /// Whether the badge is drawn in to its dot: while the bubble's list is open,
    /// and when a single session leaves nothing to count but a bubble still needs
    /// somewhere to come from.
    static func isBadgeDot(count: Int, isBubbleOpen: Bool) -> Bool {
        isBubbleOpen || count < 2
    }

    /// The badge as it is drawn for `count` sessions: the pill, or its dot.
    static func badgeRect(scale: CGFloat, corner: CGPoint, count: Int, isBubbleOpen: Bool) -> CGRect {
        isBadgeDot(count: count, isBubbleOpen: isBubbleOpen)
            ? badgeDotRect(scale: scale, corner: corner)
            : badgeRect(scale: scale, corner: corner, digits: String(count).count)
    }

    private static func badgeEnd(scale: CGFloat, corner: CGPoint) -> CGPoint {
        let pet = petRect(scale: scale)
        return CGPoint(x: (pet.minX + corner.x * scale).rounded(), y: (pet.minY + corner.y * scale).rounded())
    }

    // MARK: - Screen Conversion

    /// The panel frame origin that places the pet box at `petOrigin` on screen.
    static func panelOrigin(forPetOrigin petOrigin: CGPoint, scale: CGFloat) -> CGPoint {
        let margin = panelMargin(scale: scale)
        return CGPoint(x: petOrigin.x - margin, y: petOrigin.y - margin)
    }

    /// The pet box's on-screen origin for a panel placed at `panelOrigin`.
    static func petOrigin(forPanelOrigin panelOrigin: CGPoint, scale: CGFloat) -> CGPoint {
        let margin = panelMargin(scale: scale)
        return CGPoint(x: panelOrigin.x + margin, y: panelOrigin.y + margin)
    }

    /// An in-panel rect in screen coordinates, for a panel whose frame is `panelFrame`.
    static func screenRect(_ rect: CGRect, inPanelAt panelFrame: CGRect) -> CGRect {
        CGRect(
            x: panelFrame.minX + rect.minX,
            y: panelFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    // MARK: - Speech Bubble

    /// The bubble's outline width, the same whatever it lists so it holds still as
    /// its lines change, and narrower than the session list; a long session name
    /// is what gives way.
    static let bubbleWidth: CGFloat = 220
    /// A line as the session list draws one: the name over the folder, and the
    /// state over how long ago the session did something.
    static let bubbleRowHeight: CGFloat = 38
    /// Inside the outline, before the first row and after the last.
    static let bubblePadding: CGFloat = 4
    static let bubbleCornerRadius: CGFloat = 12
    /// Transparent room around the outline for its shadow.
    static let bubbleShadowInset: CGFloat = 8
    /// The tail that points the bubble at the badge, long enough to lift the
    /// bubble clear of the pet's head.
    static let bubbleTailHeight: CGFloat = 14
    static let bubbleTailWidth: CGFloat = 18
    /// Where the tail sits along the outline when nothing pushes it, from the
    /// outline's left edge.
    static let bubbleTailInset: CGFloat = 26
    /// Between the tail's tip and the badge it points at.
    static let bubbleTailGap: CGFloat = 3
    /// Past this many sessions, the last row counts the rest instead.
    static let bubbleMaxRows = 8

    /// The bubble panel's height for `rows` rows, tail included.
    static func bubbleHeight(rows: Int) -> CGFloat {
        CGFloat(rows) * bubbleRowHeight + bubblePadding * 2 + bubbleTailHeight + bubbleShadowInset * 2
    }

    /// The bubble panel's size for `rows` rows, tail and shadow room included.
    static func bubbleSize(rows: Int) -> CGSize {
        CGSize(width: bubbleWidth + bubbleShadowInset * 2, height: bubbleHeight(rows: rows))
    }

    /// The row under `point` in a bubble panel of `size`, in the panel's flipped
    /// coordinates, or `nil` off the outline.
    ///
    /// Rows count outwards from the tail: the first sits nearest it, at the bottom
    /// of a bubble above the pet and at the top of one below. So the list grows
    /// out of the line the pet's own session is on.
    static func bubbleRow(at point: CGPoint, in size: CGSize, rows: Int, isAbove: Bool) -> Int? {
        var outline = CGRect(origin: .zero, size: size).insetBy(dx: bubbleShadowInset, dy: bubbleShadowInset)
        outline.size.height -= bubbleTailHeight
        if !isAbove {
            outline.origin.y += bubbleTailHeight
        }
        guard rows > 0, outline.contains(point) else { return nil }
        let slot = min(max(Int((point.y - outline.minY - bubblePadding) / bubbleRowHeight), 0), rows - 1)
        return isAbove ? rows - 1 - slot : slot
    }

    /// Where a bubble panel of `size` goes on screen, pointing at `target`.
    ///
    /// The tail's tip rests on the top of the badge when the working area has
    /// room above it, and on `below` — the bottom of the pet — otherwise. The
    /// bubble keeps inside the working area sideways, and its tail slides along
    /// the outline to keep pointing at the badge.
    static func bubblePlacement(
        size: CGSize,
        target: CGRect,
        below: CGFloat,
        in area: CGRect
    ) -> PetBubblePlacement {
        let aboveY = target.maxY + bubbleTailGap - bubbleShadowInset
        let belowY = below - bubbleTailGap + bubbleShadowInset - size.height
        let isAbove = aboveY + size.height <= area.maxY || belowY < area.minY
        let preferredX = target.midX - bubbleShadowInset - bubbleTailInset
        let x = min(max(preferredX, area.minX), max(area.maxX - size.width, area.minX)).rounded()
        let outlineWidth = size.width - bubbleShadowInset * 2
        let tailRoom = bubbleCornerRadius + bubbleTailWidth / 2
        let tailX = min(max(target.midX - x - bubbleShadowInset, tailRoom), max(outlineWidth - tailRoom, tailRoom))
        return PetBubblePlacement(
            frame: CGRect(x: x, y: (isAbove ? aboveY : belowY).rounded(), width: size.width, height: size.height),
            isAbove: isAbove,
            tailX: tailX.rounded()
        )
    }
}

/// A bubble panel's on-screen frame, which side of the pet it is on, and where
/// its tail meets the outline, from the outline's left edge.
nonisolated struct PetBubblePlacement: Equatable {
    let frame: CGRect
    let isAbove: Bool
    let tailX: CGFloat
}
