import CoreGraphics
import Foundation

/// A display, reduced to the facts the pet's placement needs.
///
/// Placement math takes these rather than `NSScreen` so it can be exercised
/// without a real screen attached.
nonisolated struct PetScreen: Equatable {
    let displayUUID: String?
    let displayID: UInt32
    let name: String?
    /// Where the pet may go on this display, from `PetPlacement.workingArea`.
    let workingArea: CGRect
}

/// Where the user left the pet.
///
/// Stored as a fraction of the owning display's working area plus enough
/// identity to find that display again. Raw global coordinates would strand the
/// pet off-screen the moment a monitor is unplugged or its resolution changes.
nonisolated struct PetPosition: Codable, Equatable {

    /// Derived from the display's vendor, model, and serial, so it survives a
    /// reboot and a replug — unlike `displayID`, which the window server
    /// reassigns per session.
    var displayUUID: String?
    var displayID: UInt32
    var displayName: String?

    /// The working area at the time of saving, used to disambiguate displays.
    /// Named for the visible frame it once was, so saved positions still decode.
    var visibleWidth: Double
    var visibleHeight: Double

    /// Edge-preserving position of the pet's origin. `0` is flush against the
    /// left/bottom edge and `1` flush against the right/top edge on any display
    /// size, so a pet parked in a corner restores to that same corner.
    var fractionX: Double
    var fractionY: Double

    init(petOrigin: CGPoint, petSize: CGSize, screen: PetScreen) {
        displayUUID = screen.displayUUID
        displayID = screen.displayID
        displayName = screen.name
        visibleWidth = screen.workingArea.width
        visibleHeight = screen.workingArea.height

        let area = screen.workingArea
        let spanX = max(area.width - petSize.width, 1)
        let spanY = max(area.height - petSize.height, 1)
        fractionX = PetPlacement.clampUnit(Double((petOrigin.x - area.minX) / spanX))
        fractionY = PetPlacement.clampUnit(Double((petOrigin.y - area.minY) / spanY))
    }
}

/// Pure placement math: turning a stored position back into an on-screen origin,
/// and keeping the pet inside a visible area when displays change.
nonisolated enum PetPlacement {

    /// Gap between the pet and the screen edge when it has never been moved.
    static let defaultInset: CGFloat = 24

    /// The part of a display the pet may use: all of it but the menu bar.
    ///
    /// Unlike `visibleFrame`, this leaves the Dock's edge open. The Dock seldom
    /// fills that edge, and the space beside it is where a pet is least in the
    /// way. Dropped over the Dock itself, the pet sits beneath it, because the
    /// Dock draws above floating windows.
    static func workingArea(frame: CGRect, visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX,
            y: frame.minY,
            width: frame.width,
            height: max(visibleFrame.maxY - frame.minY, 0)
        )
    }

    /// Bottom-right corner of the working area.
    static func defaultOrigin(in area: CGRect, petSize: CGSize) -> CGPoint {
        clamp(
            CGPoint(
                x: area.maxX - defaultInset - petSize.width,
                y: area.minY + defaultInset
            ),
            in: area,
            petSize: petSize
        )
    }

    /// The on-screen origin a stored position maps to on a given working area.
    static func origin(
        for position: PetPosition,
        in area: CGRect,
        petSize: CGSize
    ) -> CGPoint {
        let spanX = max(area.width - petSize.width, 0)
        let spanY = max(area.height - petSize.height, 0)
        let point = CGPoint(
            x: area.minX + CGFloat(clampUnit(position.fractionX)) * spanX,
            y: area.minY + CGFloat(clampUnit(position.fractionY)) * spanY
        )
        return clamp(point, in: area, petSize: petSize)
    }

    /// Hard containment: the pet is never allowed outside the working area.
    static func clamp(_ origin: CGPoint, in area: CGRect, petSize: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(origin.x, area.minX), max(area.maxX - petSize.width, area.minX)),
            y: min(max(origin.y, area.minY), max(area.maxY - petSize.height, area.minY))
        )
    }

    /// Whether a display change takes the pet to the main display: the Mac went
    /// from one display to several, as when a monitor is plugged in.
    static func movesToMainDisplay(fromDisplayCount previous: Int, to current: Int) -> Bool {
        previous == 1 && current > 1
    }

    /// Where the pet lands on the main display: in the corner it was left in on
    /// whichever display that was, or the default corner if it was never moved.
    static func originOnMainDisplay(_ main: PetScreen, stored: PetPosition?, petSize: CGSize) -> CGPoint {
        guard let stored else { return defaultOrigin(in: main.workingArea, petSize: petSize) }
        return origin(for: stored, in: main.workingArea, petSize: petSize)
    }

    /// Finds the display a stored position belongs to.
    ///
    /// Tries the stable identifiers first and degrades to shape matching, because
    /// display IDs change across reboots and two identical monitors share a name.
    /// Returns `nil` when the display is simply gone; the caller then falls back
    /// to the main screen, which keeps the pet in the equivalent corner.
    static func resolveScreen(
        for position: PetPosition,
        among screens: [PetScreen]
    ) -> PetScreen? {
        let storedSize = CGSize(width: position.visibleWidth, height: position.visibleHeight)

        if let uuid = position.displayUUID {
            let matches = screens.filter { $0.displayUUID == uuid }
            if matches.count == 1 { return matches[0] }
            if matches.count > 1 {
                return matches.first { $0.workingArea.size == storedSize } ?? matches[0]
            }
        }

        if let match = screens.first(where: { $0.displayID == position.displayID }) {
            return match
        }

        if let name = position.displayName {
            let matches = screens.filter { $0.name == name && $0.workingArea.size == storedSize }
            if matches.count == 1 { return matches[0] }
        }

        let sameSize = screens.filter { $0.workingArea.size == storedSize }
        return sameSize.count == 1 ? sameSize[0] : nil
    }

    static func clampUnit(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
