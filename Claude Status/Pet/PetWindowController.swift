import AppKit
import SwiftUI

/// Owns the desktop pet's panel: building it, placing it, driving its animation,
/// and tearing it down.
///
/// Created only while the pet is enabled. When the setting is switched off the
/// panel is destroyed rather than hidden, so a disabled pet holds no window, no
/// observers, and no timers.
@MainActor
final class PetWindowController {

    private let settings: PetSettings

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

    init(settings: PetSettings) {
        self.settings = settings
    }

    // MARK: - Lifecycle

    func show() {
        guard panel == nil else { return }

        let scale = settings.size.scale
        let frame = NSRect(origin: .zero, size: PetLayout.panelSize(scale: scale))

        let content = PetContentView(frame: frame)
        content.interactiveRect = PetLayout.spriteRect(scale: scale)

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
        guard settings.bubbleMode == .always, let session else { return nil }
        return session.sessionName ?? session.projectName
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

    // MARK: - Placement

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
