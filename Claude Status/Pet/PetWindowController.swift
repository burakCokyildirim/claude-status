import AppKit
import SwiftUI

/// Owns the desktop pet's panel: building it, placing it, and tearing it down.
///
/// Created only while the pet is enabled. When the setting is switched off the
/// panel is destroyed rather than hidden, so a disabled pet costs nothing.
@MainActor
final class PetWindowController {

    private let settings: PetSettings

    private var panel: PetPanel?
    private var contentView: PetContentView?
    private var hostingView: NSHostingView<PetView>?

    init(settings: PetSettings) {
        self.settings = settings
    }

    // MARK: - Lifecycle

    func show() {
        guard panel == nil else { return }

        let scale = settings.size.scale
        let size = PetLayout.panelSize(scale: scale)
        let frame = NSRect(origin: .zero, size: size)

        let content = PetContentView(frame: frame)
        content.interactiveRect = PetLayout.spriteRect(scale: scale)

        let hosting = NSHostingView(rootView: PetView(scale: scale))
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

        // `orderFrontRegardless` rather than `orderFront`, which an inactive app
        // can defer until it next activates — which may be never.
        panel.orderFrontRegardless()
    }

    /// Destroys the panel and everything it drives.
    func tearDown() {
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
        tearDown()
        show()
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
