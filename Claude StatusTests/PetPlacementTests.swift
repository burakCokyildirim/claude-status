import CoreGraphics
import Testing
@testable import Claude_Status

/// Where the pet may sit on a display, and where it goes when displays change.
@MainActor
struct PetPlacementTests {

    /// A 1512x982 laptop display under a 33pt menu bar.
    private static let laptopFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private static let petSize = CGSize(width: 80, height: 64)

    private func screen(_ id: UInt32, _ area: CGRect) -> PetScreen {
        PetScreen(displayUUID: "display-\(id)", displayID: id, name: "Display \(id)", workingArea: area)
    }

    /// The Dock seldom fills its edge, and the space beside it is where the pet
    /// is wanted; only the menu bar stays off-limits, on any display.
    @Test func theDockEdgeIsOpenButTheMenuBarIsNot() {
        let dockAtBottom = CGRect(x: 0, y: 70, width: 1512, height: 879)
        let dockOnLeft = CGRect(x: 80, y: 0, width: 1432, height: 949)
        let belowMenuBar = CGRect(x: 0, y: 0, width: 1512, height: 949)

        #expect(PetPlacement.workingArea(frame: Self.laptopFrame, visibleFrame: dockAtBottom) == belowMenuBar)
        #expect(PetPlacement.workingArea(frame: Self.laptopFrame, visibleFrame: dockOnLeft) == belowMenuBar)
        #expect(
            PetPlacement.workingArea(
                frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
                visibleFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1055)
            ) == CGRect(x: -1920, y: 0, width: 1920, height: 1055)
        )

        // Dropped in the Dock's row the pet stays there, but not over the menu bar.
        #expect(PetPlacement.clamp(CGPoint(x: 1400, y: 0), in: belowMenuBar, petSize: Self.petSize)
            == CGPoint(x: 1400, y: 0))
        #expect(PetPlacement.clamp(CGPoint(x: 100, y: 940), in: belowMenuBar, petSize: Self.petSize).y
            == belowMenuBar.maxY - Self.petSize.height)
    }

    /// Plugging a monitor into a Mac with one display is the only change that
    /// moves the pet on its own.
    @Test func onlyGoingFromOneDisplayToSeveralMovesThePet() {
        #expect(PetPlacement.movesToMainDisplay(fromDisplayCount: 1, to: 2))
        #expect(PetPlacement.movesToMainDisplay(fromDisplayCount: 1, to: 3))
        #expect(!PetPlacement.movesToMainDisplay(fromDisplayCount: 2, to: 3))
        #expect(!PetPlacement.movesToMainDisplay(fromDisplayCount: 2, to: 1))
        #expect(!PetPlacement.movesToMainDisplay(fromDisplayCount: 1, to: 1))
        // Before the pet has been placed at all there is nothing to move it from.
        #expect(!PetPlacement.movesToMainDisplay(fromDisplayCount: 0, to: 2))
    }

    /// On the main display the pet takes the corner it was left in, though that
    /// display is another size, or the default corner if it was never moved.
    /// Saved there, a later change finds the main display rather than pulling
    /// the pet back to where it came from.
    @Test func thePetKeepsItsCornerOnTheMainDisplay() {
        let laptop = screen(1, CGRect(x: 0, y: 0, width: 1512, height: 949))
        let monitor = screen(2, CGRect(x: 1512, y: -200, width: 2560, height: 1415))
        let bottomRight = CGPoint(x: laptop.workingArea.maxX - Self.petSize.width, y: laptop.workingArea.minY)
        let stored = PetPosition(petOrigin: bottomRight, petSize: Self.petSize, screen: laptop)

        let moved = PetPlacement.originOnMainDisplay(monitor, stored: stored, petSize: Self.petSize)

        #expect(moved == CGPoint(x: monitor.workingArea.maxX - Self.petSize.width, y: monitor.workingArea.minY))
        #expect(PetPlacement.originOnMainDisplay(monitor, stored: nil, petSize: Self.petSize)
            == PetPlacement.defaultOrigin(in: monitor.workingArea, petSize: Self.petSize))
        let saved = PetPosition(petOrigin: moved, petSize: Self.petSize, screen: monitor)
        #expect(PetPlacement.resolveScreen(for: saved, among: [laptop, monitor]) == monitor)
    }
}
