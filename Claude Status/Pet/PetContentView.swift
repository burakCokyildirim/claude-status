import AppKit

/// The pet panel's content view.
///
/// SwiftUI draws the pet; this view owns every event. `hitTest(_:)` never calls
/// `super`, so nothing added on the SwiftUI side — a background, a wider content
/// shape — can silently widen the clickable region and start eating clicks meant
/// for whatever is underneath.
final class PetContentView: NSView {

    /// The rect that responds to the mouse, in this view's coordinates.
    /// Everything outside it is transparent and clicks through to the app below.
    var interactiveRect: NSRect = .zero

    /// Top-left origin, matching SwiftUI and `PetLayout`.
    override var isFlipped: Bool { true }

    /// AppKit would otherwise start its own window drag from a transparent,
    /// layer-backed subview and swallow the mouse-up that resolves click vs drag.
    override var mouseDownCanMoveWindow: Bool { false }

    /// Without this the first click on the pet is consumed as an activation
    /// click, because the app is inactive whenever the pet is interesting.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard interactiveRect.contains(local) else { return nil }
        return self
    }
}
