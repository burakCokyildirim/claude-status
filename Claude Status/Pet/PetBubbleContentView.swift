import AppKit
import SwiftUI

/// Fills the speech bubble's panel: SwiftUI draws the rows, and this view owns
/// every mouse event over them.
///
/// For the same reason `PetContentView` owns the sprite's: SwiftUI's hover and
/// taps go quiet in a window that never becomes key while the app is inactive,
/// which is when the pet is used. `hitTest(_:)` claims every point, so the hosting
/// view underneath only ever draws.
final class PetBubbleContentView: NSView {

    weak var controller: PetWindowController?

    private let hostingView: NSHostingView<PetBubbleView>

    init(bubble: PetBubbleView) {
        hostingView = NSHostingView(rootView: bubble)
        super.init(frame: .zero)
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var bubble: PetBubbleView {
        get { hostingView.rootView }
        set { hostingView.rootView = newValue }
    }

    /// The width SwiftUI wants for the bubble as it stands.
    var bubbleWidth: CGFloat {
        hostingView.fittingSize.width
    }

    /// Top-left origin, matching SwiftUI and `PetLayout`.
    override var isFlipped: Bool { true }

    override var mouseDownCanMoveWindow: Bool { false }

    /// The first click on a row would otherwise be spent activating the app.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    // MARK: - Mouse

    /// Taken, so the matching mouse-up comes back here.
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        controller?.bubbleWasClicked(at: location(of: event))
    }

    // MARK: - Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        // `.activeAlways`, as on the sprite: nothing else reports hover while the
        // app is inactive.
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        controller?.bubblePointerDidMove(to: location(of: event))
    }

    override func mouseMoved(with event: NSEvent) {
        controller?.bubblePointerDidMove(to: location(of: event))
    }

    override func mouseExited(with event: NSEvent) {
        controller?.bubblePointerDidLeave()
    }

    private func location(of event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }
}
