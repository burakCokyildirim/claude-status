import AppKit

/// The pet panel's content view.
///
/// SwiftUI draws the pet; this view owns every event. `hitTest(_:)` never calls
/// `super`, so nothing added on the SwiftUI side — a background, a wider content
/// shape — can silently widen the clickable region and start eating clicks meant
/// for whatever is underneath.
final class PetContentView: NSView {

    weak var controller: PetWindowController?

    /// The rect that responds to the mouse, in this view's coordinates.
    /// Everything outside it is transparent and clicks through to the app below.
    var interactiveRect: NSRect = .zero

    /// How far the mouse may travel before a click becomes a drag. Small enough
    /// to feel immediate, large enough that a shaky click still counts as one.
    private static let dragThreshold: CGFloat = 4

    /// Mouse position on screen when the button went down, and where the pet was
    /// at that moment. Deltas are measured against these rather than per event:
    /// as the window moves under the cursor, per-event deltas feed back on
    /// themselves and the drag runs away.
    private var dragAnchor: NSPoint?
    private var dragOrigin: NSPoint?
    private var isDragging = false

    private var isHovered = false
    private var contextMenu: NSMenu?

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

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            showMenu(with: event)
            return
        }
        dragAnchor = screenPoint(for: event)
        dragOrigin = controller?.petScreenRect?.origin
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let anchor = dragAnchor, let origin = dragOrigin else { return }

        let current = screenPoint(for: event)
        let dx = current.x - anchor.x
        let dy = current.y - anchor.y

        if !isDragging {
            guard dx * dx + dy * dy >= Self.dragThreshold * Self.dragThreshold else { return }
            isDragging = true
            controller?.dragDidBegin()
        }
        controller?.movePet(to: NSPoint(x: origin.x + dx, y: origin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragAnchor = nil
            dragOrigin = nil
            isDragging = false
        }
        guard dragAnchor != nil else { return }
        if isDragging {
            controller?.dragDidEnd()
        } else {
            controller?.petWasClicked()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        showMenu(with: event)
    }

    /// The event's position in screen coordinates.
    ///
    /// `locationInWindow` is derived from the window's origin at event time, so
    /// converting it back yields the true global point even mid-drag.
    private func screenPoint(for event: NSEvent) -> NSPoint {
        window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
    }

    // MARK: - Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        // `.activeAlways` is the only option that delivers hover while the owning
        // app is inactive — which is the pet's entire use case. SwiftUI's
        // `.onHover` scopes its tracking to the key window and stays silent here.
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        updateHover(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        setHovered(false)
    }

    /// The tracking area is rectangular, so hover is refined against the sprite
    /// itself here — otherwise the bubble would appear from the empty corners.
    private func updateHover(with event: NSEvent) {
        setHovered(interactiveRect.contains(convert(event.locationInWindow, from: nil)))
    }

    private func setHovered(_ hovered: Bool) {
        guard hovered != isHovered else { return }
        isHovered = hovered
        controller?.hoverChanged(hovered)
    }

    // MARK: - Context Menu

    private func showMenu(with event: NSEvent) {
        guard let menu = controller?.makeContextMenu() else { return }
        menu.delegate = self
        contextMenu = menu
        // `popUp(positioning:at:in:)` rather than the context-menu call, which is
        // deprecated as of macOS 14. Neither activates the app; menus run their
        // own tracking loop at their own window level.
        menu.popUp(positioning: nil, at: convert(event.locationInWindow, from: nil), in: self)
    }
}

// MARK: - NSMenuDelegate

extension PetContentView: NSMenuDelegate {

    /// Menu tracking runs in its own event mode and swallows `mouseExited`, so
    /// hover is re-derived here rather than left stuck open behind the menu.
    func menuDidClose(_ menu: NSMenu) {
        contextMenu = nil
        let isOverPet = controller?.interactiveScreenRect?.contains(NSEvent.mouseLocation) ?? false
        setHovered(isOverPet)
    }
}
