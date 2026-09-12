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

    /// A value snapshot, replaced wholesale by `update(settings:)`.
    private var settings: PetSettings

    /// Injected the way `AppDelegate` already wires the popover, so the
    /// controller needs no reference back to the app delegate.
    private let onFocus: (ClaudeSession) -> Void
    private let onShowSessionList: () -> Void
    private let onShowSettings: () -> Void
    private let onHide: () -> Void

    /// Draws the pet and lets every click through to the windows underneath.
    private var panel: PetPanel?
    /// Takes the mouse over the sprite only; a child window of `panel`.
    private var hitPanel: PetPanel?
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
    /// The scale the current panel was laid out for, so a settings change knows
    /// whether the geometry actually needs rebuilding.
    private var builtScale: CGFloat = 0
    /// Bumped on every screen-parameter notification so superseded and
    /// post-teardown re-clamps drop out.
    private var screenChangeGeneration = 0

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
        builtScale = scale
        let frame = NSRect(origin: .zero, size: PetLayout.panelSize(scale: scale))

        let hosting = NSHostingView(rootView: makeView())
        hosting.frame = frame
        hosting.autoresizingMask = [.width, .height]

        let panel = PetPanel(contentRect: frame, acceptsMouse: false)
        panel.contentView = hosting

        // Sprite-sized, so the sprite is the only thing that takes the mouse.
        let spriteFrame = NSRect(origin: .zero, size: PetLayout.spriteRect(scale: scale).size)
        let content = PetContentView(frame: spriteFrame)
        content.interactiveRect = spriteFrame
        content.controller = self
        let hitPanel = PetPanel(contentRect: spriteFrame, acceptsMouse: true)
        hitPanel.contentView = content

        self.panel = panel
        self.hitPanel = hitPanel
        self.hostingView = hosting

        applyStoredPosition()
        // Attached once it sits over the sprite: from then on it moves, hides,
        // and follows Spaces along with the panel.
        if let sprite = interactiveScreenRect {
            hitPanel.setFrame(sprite, display: false)
        }
        panel.addChildWindow(hitPanel, ordered: .above)
        registerObservers()

        // `orderFrontRegardless` rather than `orderFront`, which an inactive app
        // can defer until it next activates — which may be never.
        panel.orderFrontRegardless()
        updateAnimationDriver()
    }

    /// Destroys both panels and everything they drive.
    func tearDown() {
        frameTimer?.invalidate()
        frameTimer = nil
        oneShot = nil
        // Interaction state belongs to the view that is about to go away. Left
        // set, a rebuild triggered while the mouse is over the pet would leave
        // the bubble stuck open until the new tracking area saw an exit.
        isHovered = false
        isDragging = false
        // Drops any re-clamp still waiting out its debounce.
        screenChangeGeneration += 1

        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        for observer in defaultObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        workspaceObservers.removeAll()
        defaultObservers.removeAll()

        if let hitPanel {
            panel?.removeChildWindow(hitPanel)
            hitPanel.contentView = nil
            hitPanel.close()
        }
        hitPanel = nil
        panel?.contentView = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        hostingView = nil
    }

    /// Applies a fresh settings snapshot, rebuilding only if the geometry moved.
    func update(settings: PetSettings) {
        self.settings = settings
        guard panel != nil else { return }

        // Only the size changes the panel's geometry. Rebuilding for a bubble or
        // character change would drop hover state and flicker for nothing.
        if builtScale != settings.size.scale {
            // The session binding lives on the controller, so a rebuild keeps it.
            tearDown()
            show()
            updateVisibility()
            return
        }

        updateVisibility()
        render()
        updateAnimationDriver()
    }

    // MARK: - Session Binding

    /// Points the pet at the highest-priority session.
    ///
    /// Called from the status item's existing one-second tick rather than a timer
    /// of its own, so an enabled pet adds no polling to the app.
    func apply(sessions: [ClaudeSession]) {
        syncHitPanel()
        let resolved = PetPresenter.resolve(from: sessions)
        let sessionChanged = resolved?.id != session?.id || resolved?.state != session?.state

        // The tick that feeds this fires every second whether or not anything
        // moved; without this the pet would rebuild its view once a second for
        // nothing, and would never be able to claim it is free when idle.
        // Idle sessions are not what the badge is for: it says how many sessions
        // are doing something behind the one the pet stands for. An unread one
        // counts — the hook calls it idle, but it is holding an answer.
        let busyCount = sessions.count { $0.state != .idle || $0.isUnread == true }
        guard sessionChanged || busyCount != sessionCount || !hasApplied else { return }

        session = resolved
        sessionCount = busyCount
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
            isUnread: session?.isUnread == true,
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
            // Added to the main run loop below, so it always fires on the main thread.
            MainActor.assumeIsolated { self?.tick() }
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

        defaultObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.screenParametersDidChange() }
        })
    }

    /// Displays changed: a monitor was plugged or unplugged, a resolution or
    /// arrangement changed, or the Dock or menu bar changed the working area.
    private func screenParametersDidChange() {
        // These arrive in a burst while the configuration settles, and the early
        // ones describe an arrangement that is not final.
        screenChangeGeneration += 1
        let generation = screenChangeGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.screenChangeGeneration == generation else { return }
            self.reclampIntoVisibleArea()
        }
    }

    /// Brings the pet back into a visible working area.
    ///
    /// Deliberately does not save: if a re-clamp overwrote the stored position,
    /// unplugging an external display would permanently destroy where the user
    /// had put the pet on it. Leaving it alone means replugging restores it.
    private func reclampIntoVisibleArea() {
        guard panel != nil, let rect = petScreenRect else { return }
        let screens = Self.currentScreens()

        if let stored = PetSettings.savedPosition(),
           let screen = PetPlacement.resolveScreen(for: stored, among: screens) {
            movePet(to: PetPlacement.origin(for: stored, in: screen.visibleFrame, petSize: rect.size))
            return
        }

        let visible = Self.screen(holding: rect, among: screens)?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? .zero
        movePet(to: PetPlacement.clamp(rect.origin, in: visible, petSize: rect.size))
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
        PetSettings.savePosition(
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

    // These run to the next turn of the run loop rather than inside the menu's
    // own tracking loop: showing a window from there is unreliable, and "Hide
    // Pet" destroys the very view that is still tracking the menu.
    @objc private func showSessionList() {
        DispatchQueue.main.async { [weak self] in self?.onShowSessionList() }
    }

    @objc private func showSettings() {
        DispatchQueue.main.async { [weak self] in self?.onShowSettings() }
    }

    @objc private func hidePet() {
        DispatchQueue.main.async { [weak self] in self?.onHide() }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    /// Recovery for a pet that ended up somewhere unreachable. There is no Dock
    /// icon and no window list, so without this there would be no way back.
    @objc private func resetPosition() {
        PetSettings.clearPosition()
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

    /// Keeps the hit panel attached to the panel and over the sprite.
    ///
    /// The window server can drop a child window — after the display sleeps, for
    /// one — which leaves the pet drawn but unclickable, because the panel it is
    /// drawn in lets every click through. Re-asserting it costs a frame compare,
    /// so it rides the tick rather than waiting for the session to change.
    private func syncHitPanel() {
        guard let panel, let hitPanel, panel.isVisible else { return }
        if let sprite = interactiveScreenRect, hitPanel.frame != sprite {
            hitPanel.setFrame(sprite, display: false)
        }
        if hitPanel.parent !== panel || !hitPanel.isVisible {
            panel.addChildWindow(hitPanel, ordered: .above)
        }
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

        guard let stored = PetSettings.savedPosition() else {
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
