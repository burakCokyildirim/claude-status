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
    /// The speech bubble, a child window of `panel` too: unlike the pet's drawing
    /// it takes the mouse, and it grows and shrinks with the list it shows.
    private var bubblePanel: PetPanel?
    private var bubbleView: PetBubbleContentView?
    private var hostingView: NSHostingView<PetView>?

    // MARK: Session state

    private var session: ClaudeSession?
    /// What the session the pet stands for is doing, whatever row of the bubble
    /// the pointer has the pet showing instead.
    private var sessionMood = PetMood.resting
    /// The sessions the bubble lists when it opens, in the pet's order.
    private var listed: [ClaudeSession] = []
    private var sessionCount = 0
    /// The first update starts the pet in its mood rather than moving it there.
    private var hasApplied = false

    // MARK: Animation state

    private var playback: PetPlayback
    /// Fires when the frame on screen is due to change, and at no other time.
    private var frameTimer: Timer?
    private var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    /// Frames are timed on the uptime clock, which a change to the system clock
    /// cannot send backwards and strand the pet on one frame.
    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// Observers, kept per notification centre: `NSWorkspace` posts on its own,
    /// and removing from only one of them is a silent leak.
    private var workspaceObservers: [NSObjectProtocol] = []
    private var defaultObservers: [NSObjectProtocol] = []

    private var isHovered = false
    private var isDragging = false
    private var isPointerOverBubble = false
    /// The bubble row under the pointer.
    private var hoveredRow: Int?
    /// Whether the bubble shows the whole list, rather than the pet's own line or
    /// nothing, depending on the setting.
    private var isBubbleOpen = false
    /// Which side of the pet the bubble was last placed on.
    private var isBubbleAbove = true
    /// Where its tail meets the outline, from the outline's left edge.
    private var bubbleTailX: CGFloat = PetLayout.bubbleTailInset
    /// Whether the bubble is out of the badge, as opposed to drawn in to it — on
    /// its way up or down, or waiting to be taken down.
    private var isBubbleOut = false
    /// The lines the bubble draws: the last it was laid out with, so it can draw
    /// back into the badge with them after the list they stood for is gone.
    private var drawnBubbleRows: [PetBubbleRow] = []
    /// Bumped on every pointer change, so a close still waiting out its grace
    /// period drops out when the pointer comes back.
    private var bubbleCloseGeneration = 0
    /// Bumped whenever the bubble is laid out or put away, so a burst or a
    /// take-down scheduled for an earlier one drops out.
    private var bubbleShowGeneration = 0

    /// Long enough to cross from the pet to its bubble, or to stray off the
    /// bubble for a moment.
    private static let bubbleGracePeriod: TimeInterval = 0.3

    /// The scale the current panel was laid out for, so a settings change knows
    /// whether the geometry actually needs rebuilding.
    private var builtScale: CGFloat = 0
    /// Bumped on every screen-parameter notification so superseded and
    /// post-teardown re-clamps drop out.
    private var screenChangeGeneration = 0
    /// How many displays there were when the pet was last placed, to tell a
    /// monitor being plugged into a one-display Mac from any other change.
    private var settledDisplayCount = 0

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
        playback = PetPlayback(
            character: PetCharacter.character(for: settings.character),
            mood: .resting,
            now: Self.now
        )
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
        let spriteFrame = NSRect(origin: .zero, size: PetLayout.petSize(scale: scale))
        let content = PetContentView(frame: spriteFrame)
        content.interactiveRect = spriteFrame
        content.controller = self
        let hitPanel = PetPanel(contentRect: spriteFrame, acceptsMouse: true)
        hitPanel.contentView = content

        // Sized and attached when there is something to say.
        let bubbleView = PetBubbleContentView(bubble: makeBubble())
        bubbleView.controller = self
        let bubblePanel = PetPanel(contentRect: .zero, acceptsMouse: true)
        bubblePanel.contentView = bubbleView

        self.panel = panel
        self.hitPanel = hitPanel
        self.bubblePanel = bubblePanel
        self.bubbleView = bubbleView
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
        layoutBubble()
        playDisplayedMood()
        render()
        updateAnimationDriver()
    }

    /// Destroys both panels and everything they drive.
    func tearDown() {
        frameTimer?.invalidate()
        frameTimer = nil
        // Interaction state belongs to the view that is about to go away. Left
        // set, a rebuild triggered while the mouse is over the pet would leave
        // the bubble stuck open until the new tracking area saw an exit.
        isHovered = false
        isDragging = false
        isPointerOverBubble = false
        hoveredRow = nil
        isBubbleOpen = false
        isBubbleOut = false
        drawnBubbleRows = []
        bubbleCloseGeneration += 1
        bubbleShowGeneration += 1
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
        if let bubblePanel {
            panel?.removeChildWindow(bubblePanel)
            bubblePanel.contentView = nil
            bubblePanel.close()
        }
        bubblePanel = nil
        bubbleView = nil
        panel?.contentView = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        hostingView = nil
    }

    /// Applies a fresh settings snapshot, rebuilding only if the geometry moved.
    func update(settings: PetSettings) {
        if settings.character != self.settings.character {
            playback = PetPlayback(
                character: PetCharacter.character(for: settings.character),
                mood: playback.target,
                now: Self.now
            )
        }
        self.settings = settings
        guard panel != nil else { return }

        // Only the size changes the panel's geometry. Rebuilding for a bubble or
        // character change would drop hover state and flicker for nothing.
        if builtScale != settings.size.scale {
            // The session binding lives on the controller, so a rebuild keeps it.
            tearDown()
            show()
            updateVisibility()
            layoutBubble()
            return
        }

        updateVisibility()
        layoutBubble()
        playDisplayedMood()
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
        let mood = PetMood(state: resolved?.state, isUnread: resolved?.isUnread == true)
        let listed = PetPresenter.listed(from: sessions)
        let sessionChanged = resolved?.id != session?.id || mood != sessionMood
            || !Self.drawSameBubble(listed, self.listed)

        // Idle sessions are not what the badge is for: it says how many sessions
        // are doing something behind the one the pet stands for. An unread one
        // counts — the hook calls it idle, but it is holding an answer.
        let busyCount = sessions.count { $0.state != .idle || $0.isUnread == true }
        // Kept up to date even when nothing on screen changes, so a click and the
        // bubble's times go by the session as it is now.
        session = resolved
        self.listed = listed

        // The tick that feeds this fires every second whether or not anything
        // moved; without this the pet would rebuild its view once a second for
        // nothing.
        guard sessionChanged || busyCount != sessionCount || !hasApplied else {
            // A line's "2m ago" moves on while nothing else does.
            if !bubbleRows.isEmpty, bubbleRows != drawnBubbleRows {
                layoutBubble()
            }
            return
        }

        sessionMood = mood
        sessionCount = busyCount

        if !hasApplied {
            playback = PetPlayback(character: playback.character, mood: mood, now: Self.now)
        }
        hasApplied = true

        updateVisibility()
        layoutBubble()
        playDisplayedMood()
        render()
        updateAnimationDriver()
    }

    /// Whether two lists of sessions would draw the same bubble.
    private static func drawSameBubble(_ lhs: [ClaudeSession], _ rhs: [ClaudeSession]) -> Bool {
        lhs.map(\.sessionId) == rhs.map(\.sessionId)
            && lhs.map(PetBubbleRow.init(session:)) == rhs.map(PetBubbleRow.init(session:))
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
        let isBubbleShown = !bubbleRows.isEmpty
        return PetView(
            character: playback.character,
            frame: reduceMotion ? playback.character.still(for: playback.target) : playback.frame,
            // The bubble and the badge follow the mood at once, while the drawing
            // may still be playing an exit or an entrance on its way there. On
            // purpose: they are the exact part, and a second of the character
            // catching up reads as it reacting.
            mood: displayedMood,
            scale: settings.size.scale,
            sessionCount: sessionCount,
            isBubbleShown: isBubbleShown,
            isBubbleOpen: isBubbleShown && isBubbleOpen
        )
    }

    // MARK: - Speech Bubble

    /// The sessions the bubble shows right now: the whole list while it is open,
    /// the pet's own session alone when the setting keeps a line up anyway, and
    /// none otherwise.
    private var bubbleSessions: [ClaudeSession] {
        guard !isDragging, let session, settings.bubbleMode != .never else { return [] }
        if isBubbleOpen { return listed }
        return settings.bubbleMode == .always ? [session] : []
    }

    /// The bubble's lines. Sessions past its room fold into a last line that
    /// counts them.
    private var bubbleRows: [PetBubbleRow] {
        let sessions = bubbleSessions
        guard sessions.count > PetLayout.bubbleMaxRows else {
            return sessions.map(PetBubbleRow.init(session:))
        }
        let shown = sessions.prefix(PetLayout.bubbleMaxRows - 1)
        return shown.map(PetBubbleRow.init(session:)) + [PetBubbleRow(moreSessions: sessions.count - shown.count)]
    }

    /// The session on the row under the pointer, if that row is one.
    private var hoveredSession: ClaudeSession? {
        guard isPointerOverBubble, let hoveredRow else { return nil }
        let sessions = bubbleSessions
        let isCountingLine = sessions.count > PetLayout.bubbleMaxRows && hoveredRow == PetLayout.bubbleMaxRows - 1
        return sessions.indices.contains(hoveredRow) && !isCountingLine ? sessions[hoveredRow] : nil
    }

    /// The mood the pet shows: the hovered session's while the pointer is on its
    /// row, and the pet's own otherwise.
    private var displayedMood: PetMood {
        guard let hoveredSession else { return sessionMood }
        return PetMood(state: hoveredSession.state, isUnread: hoveredSession.isUnread == true)
    }

    /// Sends the drawing towards `displayedMood`, through the same entrances and
    /// exits a real change of state plays.
    private func playDisplayedMood() {
        let mood = displayedMood
        guard mood != playback.target else { return }
        playback.play(mood, now: Self.now)
    }

    private func makeBubble() -> PetBubbleView {
        PetBubbleView(
            rows: drawnBubbleRows,
            isAbove: isBubbleAbove,
            highlighted: isPointerOverBubble ? hoveredRow : nil,
            tailX: bubbleTailX,
            isShown: isBubbleOut
        )
    }

    /// Fills, sizes, and places the bubble, bursting it out of the badge if it was
    /// not already out, or puts it away when it has nothing to show.
    private func layoutBubble() {
        guard let panel, let bubblePanel, let bubbleView else { return }
        let rows = bubbleRows
        guard !rows.isEmpty, panel.isVisible, let pet = petScreenRect else {
            // A panel taken down under the pointer never reports it leaving.
            isPointerOverBubble = false
            hoveredRow = nil
            putBubbleAway()
            return
        }

        bubbleShowGeneration += 1
        let wasOut = isBubbleOut && bubblePanel.parent === panel && bubblePanel.isVisible
        isBubbleOut = wasOut
        drawnBubbleRows = rows
        bubbleView.bubble = makeBubble()

        // The tail points at the badge as it is drawn: its dot while the list is open.
        let badge = PetLayout.badgeRect(
            scale: settings.size.scale,
            corner: playback.character.badgeCorner,
            count: sessionCount,
            isBubbleOpen: isBubbleOpen
        )
        let area = Self.screen(holding: pet, among: Self.currentScreens())?.workingArea ?? pet
        let placement = PetLayout.bubblePlacement(
            size: PetLayout.bubbleSize(rows: rows.count),
            target: PetLayout.screenRect(badge, inPanelAt: panel.frame),
            below: pet.minY,
            in: area
        )
        if placement.isAbove != isBubbleAbove || placement.tailX != bubbleTailX {
            isBubbleAbove = placement.isAbove
            bubbleTailX = placement.tailX
            bubbleView.bubble = makeBubble()
        }
        if bubblePanel.frame != placement.frame {
            bubblePanel.setFrame(placement.frame, display: true)
        }
        if bubblePanel.parent !== panel || !bubblePanel.isVisible {
            panel.addChildWindow(bubblePanel, ordered: .above)
        }
        guard !wasOut else { return }

        // Out of the badge on the next turn of the run loop, once the panel is up
        // at its final size with the bubble still drawn in, for SwiftUI to
        // animate from.
        let generation = bubbleShowGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.bubbleShowGeneration == generation else { return }
            self.isBubbleOut = true
            self.bubbleView?.bubble = self.makeBubble()
        }
    }

    /// Draws the bubble back into the badge with the lines it last showed, then
    /// takes its panel down.
    private func putBubbleAway() {
        guard let panel, let bubblePanel, let bubbleView,
              bubblePanel.parent != nil || bubblePanel.isVisible else { return }
        bubbleShowGeneration += 1
        let generation = bubbleShowGeneration
        if isBubbleOut {
            isBubbleOut = false
            bubbleView.bubble = makeBubble()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + PetBubbleView.drawInDuration) { [weak self] in
            guard let self, self.bubbleShowGeneration == generation, let bubblePanel = self.bubblePanel else { return }
            if bubblePanel.parent != nil { panel.removeChildWindow(bubblePanel) }
            bubblePanel.orderOut(nil)
        }
    }

    /// The pointer came onto, moved across, or left the pet or its bubble.
    private func pointerDidChange() {
        bubbleCloseGeneration += 1
        let wasOpen = isBubbleOpen
        if isHovered || isPointerOverBubble {
            isBubbleOpen = true
        } else if isBubbleOpen {
            // Not at once: the pointer leaves the pet a moment before it reaches
            // the bubble.
            let generation = bubbleCloseGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.bubbleGracePeriod) { [weak self] in
                guard let self, self.bubbleCloseGeneration == generation else { return }
                self.isBubbleOpen = false
                self.bubbleDidChange(resized: true)
            }
        }
        bubbleDidChange(resized: isBubbleOpen != wasOpen)
    }

    /// Redraws the bubble — laying it out again when it opened, closed, or
    /// changed size — along with the badge, and moves the drawing to the mood
    /// now on screen.
    private func bubbleDidChange(resized: Bool) {
        if resized {
            layoutBubble()
        } else {
            bubbleView?.bubble = makeBubble()
        }
        let before = playback.target
        playDisplayedMood()
        let moodChanged = playback.target != before
        // The badge draws in or out when the list opens or closes, and takes the
        // colour of whatever mood is now on screen.
        guard resized || moodChanged else { return }
        render()
        if moodChanged {
            updateAnimationDriver()
        }
    }

    // MARK: - Animation Driver

    /// The single place that decides whether the pet costs any CPU.
    ///
    /// Everything that can change the answer calls back into here, so "no timer
    /// while hidden, covered, disabled, or holding still for Reduce Motion" is one
    /// condition to audit rather than a property spread across the class. When a
    /// timer does run it wakes once per frame, when that frame is due, rather
    /// than on a fixed beat: most frames stay up for a few hundred milliseconds.
    private func updateAnimationDriver() {
        frameTimer?.invalidate()
        frameTimer = nil

        let isOnScreen = panel?.isVisible == true
            && panel?.occlusionState.contains(.visible) == true
        guard let delay = Self.frameTimerDelay(
            isOnScreen: isOnScreen,
            reduceMotion: reduceMotion,
            nextFrameAt: playback.nextFrameAt,
            now: Self.now
        ) else { return }

        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            // Added to the main run loop below, so it always fires on the main thread.
            MainActor.assumeIsolated { self?.frameDidEnd() }
        }
        timer.tolerance = min(delay / 10, 0.02)
        // `.common` so the pet keeps moving while a menu is being tracked.
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
    }

    private func frameDidEnd() {
        frameTimer = nil
        if playback.advance(now: Self.now) {
            render()
        }
        updateAnimationDriver()
    }

    /// How long until the frame timer should fire, or `nil` for no timer at all:
    /// the pet is hidden or covered, or holding still for Reduce Motion.
    nonisolated static func frameTimerDelay(
        isOnScreen: Bool,
        reduceMotion: Bool,
        nextFrameAt: TimeInterval,
        now: TimeInterval
    ) -> TimeInterval? {
        guard isOnScreen, !reduceMotion else { return nil }
        return max(nextFrameAt - now, 0)
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

        workspaceObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.activeSpaceDidChange() }
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

    /// The active Space changed. Leaving a full-screen Space brings the Dock back
    /// over a pet that was dropped while it was hidden, and entering one lets
    /// that pet return to its place. The Dock takes a moment to come and go, so
    /// the pet is placed once quickly and again after it has settled.
    private func activeSpaceDidChange() {
        screenChangeGeneration += 1
        let generation = screenChangeGeneration
        for delay in [0.35, 1.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.screenChangeGeneration == generation, !self.isDragging else { return }
                self.reclampIntoVisibleArea()
            }
        }
    }

    /// Brings the pet back into a working area.
    ///
    /// A monitor plugged into a Mac that had one display takes the pet to the
    /// main display, in the corner it was left in, and saves that so the next
    /// change does not pull it back. Anything else deliberately does not save: if
    /// a re-clamp overwrote the stored position, unplugging an external display
    /// would permanently destroy where the user had put the pet on it.
    private func reclampIntoVisibleArea() {
        guard panel != nil, let rect = petScreenRect else { return }
        let screens = Self.currentScreens()
        let previousDisplayCount = settledDisplayCount
        settledDisplayCount = screens.count

        if PetPlacement.movesToMainDisplay(fromDisplayCount: previousDisplayCount, to: screens.count),
           let main = screens.first {
            let moved = PetSettings.savedPosition()?.onDisplay(main)
                ?? PetPosition(
                    petOrigin: PetPlacement.defaultOrigin(in: main.clearOfDock, petSize: rect.size),
                    petSize: rect.size,
                    screen: main
                )
            PetSettings.savePosition(moved)
            movePet(to: PetPlacement.origin(
                for: moved, on: main, dockShown: Self.isDockShown(on: main), petSize: rect.size
            ))
            return
        }

        if let stored = PetSettings.savedPosition(),
           let screen = PetPlacement.resolveScreen(for: stored, among: screens) {
            movePet(to: PetPlacement.origin(
                for: stored, on: screen, dockShown: Self.isDockShown(on: screen), petSize: rect.size
            ))
            return
        }

        // Never moved: the default corner is clear of the Dock, and stays so.
        let area = Self.screen(holding: rect, among: screens)?.clearOfDock
            ?? screens.first?.clearOfDock
            ?? .zero
        movePet(to: PetPlacement.clamp(rect.origin, in: area, petSize: rect.size))
    }

    private func reduceMotionDidChange() {
        let value = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard value != reduceMotion else { return }
        reduceMotion = value
        if !reduceMotion {
            // Out of the still into the mood's loop, rather than resuming an
            // entrance or exit that was never shown.
            playback = PetPlayback(character: playback.character, mood: playback.target, now: Self.now)
        }
        render()
        updateAnimationDriver()
    }

    // MARK: - Interaction

    /// A click that stayed put: focus the session the pet stands for.
    func petWasClicked() {
        guard let session else { return }
        onFocus(session)
    }

    func hoverChanged(_ hovered: Bool) {
        guard hovered != isHovered else { return }
        isHovered = hovered
        pointerDidChange()
    }

    /// The pointer is at `point` in the bubble panel's flipped coordinates.
    func bubblePointerDidMove(to point: CGPoint) {
        let row = bubbleRow(at: point)
        guard !isPointerOverBubble || row != hoveredRow else { return }
        isPointerOverBubble = true
        hoveredRow = row
        pointerDidChange()
    }

    func bubblePointerDidLeave() {
        guard isPointerOverBubble else { return }
        isPointerOverBubble = false
        hoveredRow = nil
        pointerDidChange()
    }

    /// A click on a line: focus that session, or open the session list from the
    /// line counting the ones that did not fit.
    func bubbleWasClicked(at point: CGPoint) {
        guard let row = bubbleRow(at: point) else { return }
        let sessions = bubbleSessions
        if sessions.count > PetLayout.bubbleMaxRows, row == PetLayout.bubbleMaxRows - 1 {
            DispatchQueue.main.async { [weak self] in self?.onShowSessionList() }
        } else if sessions.indices.contains(row) {
            onFocus(sessions[row])
        }
    }

    private func bubbleRow(at point: CGPoint) -> Int? {
        guard let bubblePanel else { return nil }
        return PetLayout.bubbleRow(
            at: point,
            in: bubblePanel.frame.size,
            rows: bubbleRows.count,
            isAbove: isBubbleAbove
        )
    }

    func dragDidBegin() {
        isDragging = true
        bubbleDidChange(resized: true)
    }

    /// Persists where the pet was dropped. Apart from a monitor being plugged into
    /// a one-display Mac, this is the only place a position is written:
    /// re-clamping after any other display change must never overwrite it.
    func dragDidEnd() {
        isDragging = false
        defer { bubbleDidChange(resized: true) }

        guard let rect = petScreenRect,
              let screen = Self.screen(holding: rect, among: Self.currentScreens()) else { return }

        let clamped = PetPlacement.clamp(rect.origin, in: screen.workingArea, petSize: rect.size)
        movePet(to: clamped)
        PetSettings.savePosition(PetPosition(
            petOrigin: clamped, petSize: rect.size, screen: screen, dockHidden: !Self.isDockShown(on: screen)
        ))
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
        let area = Self.currentScreens().first?.clearOfDock ?? .zero
        movePet(to: PetPlacement.defaultOrigin(in: area, petSize: petSize))
    }

    // MARK: - Placement

    /// The sprite's on-screen rect — the part that actually responds to the mouse.
    var interactiveScreenRect: NSRect? {
        guard let panel else { return nil }
        let scale = settings.size.scale
        let sprite = PetLayout.petRect(scale: scale)
        let panelHeight = PetLayout.panelSize(scale: scale).height
        // `petRect` is in the flipped panel space; screen coordinates count up.
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
            overlap(rect, lhs.workingArea) < overlap(rect, rhs.workingArea)
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
        // The bubble is a child panel too, and can be dropped the same way.
        if let bubblePanel, !bubbleRows.isEmpty, bubblePanel.parent !== panel || !bubblePanel.isVisible {
            layoutBubble()
        }
    }

    /// Moves the pet box so its origin sits at `origin` in screen coordinates.
    func movePet(to origin: CGPoint) {
        guard let panel else { return }
        let scale = settings.size.scale
        panel.setFrameOrigin(PetLayout.panelOrigin(forPetOrigin: origin, scale: scale))
        // The bubble rides along as a child window, but near an edge it may have
        // to change sides. Not mid-drag, when it is down anyway.
        if !isDragging {
            layoutBubble()
        }
    }

    /// Places the pet where the user last dropped it, or in the default corner.
    private func applyStoredPosition() {
        let scale = settings.size.scale
        let petSize = PetLayout.petSize(scale: scale)
        let screens = Self.currentScreens()
        settledDisplayCount = screens.count

        guard let stored = PetSettings.savedPosition() else {
            let area = screens.first?.clearOfDock ?? .zero
            movePet(to: PetPlacement.defaultOrigin(in: area, petSize: petSize))
            return
        }

        // A stored display that is gone falls back to the main screen, which puts
        // the pet in the equivalent corner rather than nowhere.
        guard let screen = PetPlacement.resolveScreen(for: stored, among: screens) ?? screens.first else { return }
        movePet(to: PetPlacement.origin(
            for: stored, on: screen, dockShown: Self.isDockShown(on: screen), petSize: petSize
        ))
    }

    /// The attached displays, reduced to what placement needs. The first is the
    /// main display — the one System Settings says holds the menu bar — which
    /// `NSScreen.main` is not: that is whichever screen has the key window.
    static func currentScreens() -> [PetScreen] {
        NSScreen.screens.map { screen in
            let displayID = (screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber)?.uint32Value ?? 0
            return PetScreen(
                displayUUID: displayUUID(for: displayID),
                displayID: displayID,
                name: screen.localizedName,
                workingArea: PetPlacement.workingArea(frame: screen.frame, visibleFrame: screen.visibleFrame),
                clearOfDock: screen.visibleFrame
            )
        }
    }

    /// Whether the Dock is showing on a display right now.
    ///
    /// `NSScreen` cannot say: an app in the background is still given the Dock's
    /// room in `visibleFrame` while a full-screen Space hides it. The Dock's own
    /// window can, since it leaves the screen then. Reading the window list needs
    /// no permission. Without a Dock to find, the answer is that it shows, which
    /// only ever keeps the pet clear of where the Dock would be.
    private static func isDockShown(on screen: PetScreen) -> Bool {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first,
              let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return true
        }
        let windows = list.compactMap { info -> PetWindow? in
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else {
                return nil
            }
            return PetWindow(ownerPID: pid, layer: layer, bounds: rect)
        }
        return PetPlacement.dockShows(
            on: CGDisplayBounds(screen.displayID),
            among: windows,
            dockPID: dock.processIdentifier,
            dockLevel: Int(CGWindowLevelForKey(.dockWindow))
        )
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
