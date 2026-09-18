import AppKit

/// The desktop pet's windows: borderless, transparent, always on top, never key.
///
/// Follows the tooltip panel in `ProductivityBarView` with two deliberate
/// differences: the pet takes mouse events, and it must stay visible while the
/// app is inactive — which, for a menu bar-only app, is nearly always.
///
/// The pet is two of these, because one panel cannot let clicks through its
/// transparent margin and still take them on the sprite. With
/// `ignoresMouseEvents` set to false AppKit claims every click in the frame;
/// left unset, every click goes through, sprite included, since layer-backed
/// content is invisible to the window server's hit test. So the full-size panel
/// that draws the pet ignores the mouse, and a sprite-sized child panel takes it.
final class PetPanel: NSPanel {

    init(contentRect: NSRect, acceptsMouse: Bool) {
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
        ignoresMouseEvents = !acceptsMouse
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
