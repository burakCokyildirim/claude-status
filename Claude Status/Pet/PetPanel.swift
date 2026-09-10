import AppKit

/// The desktop pet's window: borderless, transparent, always on top, never key.
///
/// Follows the tooltip panel in `ProductivityBarView` with two deliberate
/// differences: the pet accepts mouse events, and it must stay visible while the
/// app is inactive — which, for a menu bar-only app, is nearly always.
final class PetPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // `isFloatingPanel` assigns `level` as a side effect, so it has to be set
        // before the explicit level below, not after.
        isFloatingPanel = true
        level = Self.windowLevel

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        // NSPanel defaults this to true, unlike NSWindow. This app is an
        // accessory that is almost never active, so the default would make the
        // pet vanish the moment the user clicks another app — and never return.
        hidesOnDeactivate = false

        becomesKeyOnlyIfNeeded = true
        worksWhenModal = false

        // Dragging is handled in `PetContentView` so the click/drag threshold
        // stays ours; AppKit's own window dragging would swallow the mouse-up.
        isMovable = false
        isMovableByWindowBackground = false

        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .none
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = false
        tabbingMode = .disallowed
        isExcludedFromWindowsMenu = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Placement is owned by `PetWindowController`, which clamps against the
    /// screen itself. AppKit's own constraining would fight that.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    /// `.floating` is the lowest level that sits above other apps' windows while
    /// still staying below the menu bar, open menus, and system modal alerts.
    ///
    /// The undocumented override exists so a "the pet is behind X on my machine"
    /// report can be diagnosed with a `defaults write` instead of a release.
    private static var windowLevel: NSWindow.Level {
        let override = UserDefaults.standard.integer(forKey: "petWindowLevelOverride")
        return override == 0 ? .floating : NSWindow.Level(rawValue: override)
    }
}
