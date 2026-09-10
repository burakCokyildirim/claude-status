import AppKit
import SwiftUI

/// Owns the desktop pet's panel: building it, placing it, driving its animation,
/// and tearing it down.
///
/// Created only while the pet is enabled. When the setting is switched off the
/// panel is destroyed rather than hidden, so a disabled pet holds no window, no
/// observers, and no timers.
@MainActor
final class PetWindowController: NSObject {

    private let settings: PetSettings

    /// Injected the way `AppDelegate` already wires the popover, so the
    /// controller needs no reference back to the app delegate.
    private let onFocus: (ClaudeSession) -> Void
    private let onShowSessionList: () -> Void
    private let onShowSettings: () -> Void
    private let onHide: () -> Void

    private var panel: PetPanel?
    private var contentView: PetContentView?
    private var hostingView: NSHostingView<PetView>?

    // MARK: Session state

    private var session: ClaudeSession?
    private var sessionCount = 0
    /// Suppresses the startle reaction on the very first update.
    private var hasApplied = false

    // MARK: Animation state

    private var restingAnimation: PetAnimation = .still
    private var oneShot: PetAnimation?
    private var oneShotStartedAt: Date = .distantPast
    private var loopStartedAt: Date = Date()
    private var frameTimer: Timer?
    private var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    /// Pixel art does not need a high frame rate, and the pet is on screen all day.
    private static let frameInterval: TimeInterval = 1.0 / 12.0

    /// Observers, kept per notification centre: `NSWorkspace` posts on its own,
    /// and removing from only one of them is a silent leak.
    private var workspaceObservers: [NSObjectProtocol] = []
    private var defaultObservers: [NSObjectProtocol] = []

    private var isHovered = false
    private var isDragging = false

    init(
        settings: PetSettings,
        onFocus: @escaping (ClaudeSession) -> Void,
        onShowSessionList: @escaping () -> Void,
        onShowSettings: @escaping () -> Void,
        onHide: @escaping () -> Void
    ) {
        self.settings = settings
        self.onFocus = onFocus
        self.onShowSessionList = onShowSessionList
        self.onShowSettings = onShowSettings
        self.onHide = onHide
        super.init()
    }

    // MARK: - Lifecycle

    func show() {
        guard panel == nil else { return }

        let scale = settings.size.scale
        let frame = NSRect(origin: .zero, size: PetLayout.panelSize(scale: scale))

        let content = PetContentView(frame: frame)
        content.interactiveRect = PetLayout.spriteRect(scale: scale)
        content.controller = self

        let hosting = NSHostingView(rootView: makeView())
        hosting.frame = frame
        hosting.autoresizingMask = [.width, .height]
        content.addSubview(hosting)

        let panel = PetPanel(contentRect: frame)
        panel.contentView = content
        content.wantsLayer = true

        self.panel = panel
        self.contentView = content
        self.hostingView = hosting

        applyStoredPosition()
        registerObservers()

        // `orderFrontRegardless` rather than `orderFront`, which an inactive app
        // can defer until it next activates — which may be never.
        panel.orderFrontRegardless()
        updateAnimationDriver()
    }

    /// Destroys the panel and everything it drives.
    func tearDown() {
        frameTimer?.invalidate()
        frameTimer = nil
        oneShot = nil

        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        for observer in defaultObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        workspaceObservers.removeAll()
        defaultObservers.removeAll()

        panel?.contentView = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        contentView = nil
        hostingView = nil
    }

    /// Rebuilds the panel when a setting that changes its geometry is edited.
    func settingsDidChange() {
        guard panel != nil else { return }
        // The session binding lives on the controller, so a rebuild keeps it.
        tearDown()
        show()
        updateVisibility()
    }

    // MARK: - Session Binding

    /// Points the pet at the highest-priority session.
    ///
    /// Called from the status item's existing one-second tick rather than a timer
    /// of its own, so an enabled pet adds no polling to the app.
    func apply(sessions: [ClaudeSession]) {
        let resolved = PetPresenter.resolve(from: sessions)
        let sessionChanged = resolved?.id != session?.id || resolved?.state != session?.state

        // The tick that feeds this fires every second whether or not anything
        // moved; without this the pet would rebuild its view once a second for
        // nothing, and would never be able to claim it is free when idle.
        guard sessionChanged || sessions.count != sessionCount || !hasApplied else { return }

        session = resolved
        sessionCount = sessions.count
        restingAnimation = PetAnimation.resting(for: resolved?.state)

        if sessionChanged, hasApplied, resolved != nil {
            startOneShot(.startle)
        }
        hasApplied = true

        updateVisibility()
        render()
        updateAnimationDriver()
    }

    /// Plays a one-shot reaction. Ignored under reduced motion.
    func startOneShot(_ animation: PetAnimation) {
        guard !reduceMotion, animation.duration != nil else { return }
        oneShot = animation
        oneShotStartedAt = Date()
        updateAnimationDriver()
    }

    /// Shows or hides the panel for the "no sessions running" setting.
    private func updateVisibility() {
        guard let panel else { return }
        let shouldShow = session != nil || settings.emptyBehavior == .rest
        if shouldShow {
            if !panel.isVisible { panel.orderFrontRegardless() }
        } else if panel.isVisible {
            panel.orderOut(nil)
        }
    }

    // MARK: - Rendering

    private func render() {
        hostingView?.rootView = makeView()
    }

    private func makeView() -> PetView {
        PetView(
            character: PetCharacter.character(for: settings.character),
            state: session?.state,
            transform: currentTransform,
            scale: settings.size.scale,
            sessionCount: sessionCount,
            bubbleTitle: bubbleTitle
        )
    }

    private var bubbleTitle: String? {
        guard !isDragging, let session else { return nil }
        switch settings.bubbleMode {
        case .always: return session.sessionName ?? session.projectName
        case .hover: return isHovered ? (session.sessionName ?? session.projectName) : nil
        case .never: return nil
        }
    }

    /// The transform for right now: a one-shot while it is running, otherwise the
    /// state's resting loop.
    private var currentTransform: PetTransform {
        guard !reduceMotion else { return .identity }

        if let oneShot, let duration = oneShot.duration {
            let elapsed = Date().timeIntervalSince(oneShotStartedAt)
            if elapsed < duration {
                return PetMotion.transform(for: oneShot, phase: elapsed / duration)
            }
        }

        guard restingAnimation.isAnimated else { return .identity }
        let period = restingAnimation.period
        let elapsed = Date().timeIntervalSince(loopStartedAt).truncatingRemainder(dividingBy: period)
        return PetMotion.transform(for: restingAnimation, phase: elapsed / period)
    }

    // MARK: - Animation Driver

    /// The single place that decides whether the pet costs any CPU.
    ///
    /// Everything that can change the answer calls back into here, so "no timers
    /// when idle, hidden, or disabled" is one condition to audit rather than a
    /// property spread across the class.
    private func updateAnimationDriver() {
        let isOnScreen = panel?.isVisible == true
            && panel?.occlusionState.contains(.visible) == true
        let needsFrames = !reduceMotion && isOnScreen
            && (oneShot != nil || restingAnimation.isAnimated)

        guard needsFrames else {
            frameTimer?.invalidate()
            frameTimer = nil
            return
        }
        guard frameTimer == nil else { return }

        let timer = Timer(timeInterval: Self.frameInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // `.common` so the pet keeps moving while a menu is being tracked.
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
    }

    private func tick() {
        if let oneShot, let duration = oneShot.duration,
           Date().timeIntervalSince(oneShotStartedAt) >= duration {
            self.oneShot = nil
            updateAnimationDriver()
        }
        render()
    }

    // MARK: - Observers

    private func registerObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.reduceMotionDidChange() }
        })

        defaultObservers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.updateAnimationDriver() }
        })
    }

    private func reduceMotionDidChange() {
        let value = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard value != reduceMotion else { return }
        reduceMotion = value
        if reduceMotion { oneShot = nil }
        render()
        updateAnimationDriver()
    }

    // MARK: - Interaction

    /// A click that stayed put: react, then focus the session it stands for.
    func petWasClicked() {
        startOneShot(.poke)
        guard let session else { return }
        onFocus(session)
    }

    func hoverChanged(_ hovered: Bool) {
        guard hovered != isHovered else { return }
        isHovered = hovered
        render()
    }

    func dragDidBegin() {
        isDragging = true
        render()
    }

    /// Persists where the pet was dropped. This is the only place a position is
    /// written: re-clamping after a display change must never overwrite it.
    func dragDidEnd() {
        isDragging = false
        defer { render() }

        guard let rect = petScreenRect,
              let screen = Self.screen(holding: rect, among: Self.currentScreens()) else { return }

        let clamped = PetPlacement.clamp(rect.origin, in: screen.visibleFrame, petSize: rect.size)
        movePet(to: clamped)
        settings.savePosition(
            PetPosition(petOrigin: clamped, petSize: rect.size, screen: screen)
        )
    }

    // MARK: - Context Menu

    func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(menuItem("Show Session List", #selector(showSessionList)))
        menu.addItem(menuItem("Reset Position", #selector(resetPosition)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Hide Pet", #selector(hidePet)))
        menu.addItem(menuItem("Settings\u{2026}", #selector(showSettings)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Claude Status", #selector(quitApp)))
        return menu
    }

    private func menuItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        // The target has to be explicit. With a nil target AppKit walks the
        // responder chain, which does not reach here from a non-key panel in an
        // inactive app, and every item would come up disabled.
        item.target = self
        item.isEnabled = true
        return item
    }

    @objc private func showSessionList() {
        onShowSessionList()
    }

    @objc private func showSettings() {
        onShowSettings()
    }

    @objc private func hidePet() {
        onHide()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    /// Recovery for a pet that ended up somewhere unreachable. There is no Dock
    /// icon and no window list, so without this there would be no way back.
    @objc private func resetPosition() {
        settings.clearPosition()
        let petSize = PetLayout.petSize(scale: settings.size.scale)
        let visible = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        movePet(to: PetPlacement.defaultOrigin(in: visible, petSize: petSize))
    }

    // MARK: - Placement

    /// The sprite's on-screen rect — the part that actually responds to the mouse.
    var interactiveScreenRect: NSRect? {
        guard let panel else { return nil }
        let scale = settings.size.scale
        let sprite = PetLayout.spriteRect(scale: scale)
        let panelHeight = PetLayout.panelSize(scale: scale).height
        // `spriteRect` is in the flipped panel space; screen coordinates count up.
        return NSRect(
            x: panel.frame.minX + sprite.minX,
            y: panel.frame.minY + (panelHeight - sprite.maxY),
            width: sprite.width,
            height: sprite.height
        )
    }

    /// The display holding most of `rect`, so a drop across a boundary is
    /// attributed to the screen the pet actually landed on.
    private static func screen(holding rect: NSRect, among screens: [PetScreen]) -> PetScreen? {
        let best = screens.max { lhs, rhs in
            overlap(rect, lhs.visibleFrame) < overlap(rect, rhs.visibleFrame)
        }
        return best ?? screens.first
    }

    private static func overlap(_ lhs: NSRect, _ rhs: NSRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return intersection.isNull || intersection.isEmpty ? 0 : intersection.width * intersection.height
    }

    /// The pet box's current on-screen rect, or `nil` when there is no panel.
    var petScreenRect: NSRect? {
        guard let panel else { return nil }
        let scale = settings.size.scale
        let origin = PetLayout.petOrigin(forPanelOrigin: panel.frame.origin, scale: scale)
        return NSRect(origin: origin, size: PetLayout.petSize(scale: scale))
    }

    /// Moves the pet box so its origin sits at `origin` in screen coordinates.
    func movePet(to origin: CGPoint) {
        guard let panel else { return }
        let scale = settings.size.scale
        panel.setFrameOrigin(PetLayout.panelOrigin(forPetOrigin: origin, scale: scale))
    }

    /// Places the pet where the user last dropped it, or in the default corner.
    private func applyStoredPosition() {
        let scale = settings.size.scale
        let petSize = PetLayout.petSize(scale: scale)
        let screens = Self.currentScreens()

        guard let stored = settings.savedPosition else {
            let visible = NSScreen.main?.visibleFrame ?? screens.first?.visibleFrame ?? .zero
            movePet(to: PetPlacement.defaultOrigin(in: visible, petSize: petSize))
            return
        }

        // A stored display that is gone falls back to the main screen, which puts
        // the pet in the equivalent corner rather than nowhere.
        let visible = PetPlacement.resolveScreen(for: stored, among: screens)?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? .zero
        movePet(to: PetPlacement.origin(for: stored, in: visible, petSize: petSize))
    }

    /// The attached displays, reduced to what placement needs.
    static func currentScreens() -> [PetScreen] {
        NSScreen.screens.map { screen in
            let displayID = (screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber)?.uint32Value ?? 0
            return PetScreen(
                displayUUID: displayUUID(for: displayID),
                displayID: displayID,
                name: screen.localizedName,
                visibleFrame: screen.visibleFrame
            )
        }
    }

    /// The display's stable UUID string. Unlike the display ID, this survives a
    /// reboot and an unplug/replug because it is derived from the hardware.
    private static func displayUUID(for displayID: UInt32) -> String? {
        guard displayID != 0,
              let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
              let string = CFUUIDCreateString(nil, uuid) else {
            return nil
        }
        return string as String
    }
}
