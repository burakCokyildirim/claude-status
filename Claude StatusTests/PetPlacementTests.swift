import CoreGraphics
import Foundation
import Testing
@testable import Claude_Status

/// Where the pet may sit on a display, and where it goes when displays change.
@MainActor
struct PetPlacementTests {

    /// A 1512x982 laptop display under a 33pt menu bar.
    private static let laptopFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private static let petSize = CGSize(width: 80, height: 64)

    private func screen(_ id: UInt32, _ area: CGRect, clearOfDock: CGRect? = nil) -> PetScreen {
        PetScreen(
            displayUUID: "display-\(id)", displayID: id, name: "Display \(id)",
            workingArea: area, clearOfDock: clearOfDock ?? area
        )
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
    /// display is another size. Filed there, a later change finds the main
    /// display rather than pulling the pet back to where it came from.
    @Test func thePetKeepsItsCornerOnTheMainDisplay() {
        let laptop = screen(1, CGRect(x: 0, y: 0, width: 1512, height: 949))
        let monitor = screen(2, CGRect(x: 1512, y: -200, width: 2560, height: 1415))
        let bottomRight = CGPoint(x: laptop.workingArea.maxX - Self.petSize.width, y: laptop.workingArea.minY)
        let stored = PetPosition(petOrigin: bottomRight, petSize: Self.petSize, screen: laptop, dockHidden: true)

        let moved = stored.onDisplay(monitor)

        #expect(PetPlacement.origin(for: moved, on: monitor, dockShown: false, petSize: Self.petSize)
            == CGPoint(x: monitor.workingArea.maxX - Self.petSize.width, y: monitor.workingArea.minY))
        #expect(moved.droppedWhileDockHidden == true)
        #expect(PetPlacement.resolveScreen(for: moved, among: [laptop, monitor]) == monitor)
    }

    /// Dropped in a full-screen Space, where the Dock hides, a pet at the bottom
    /// would end up under the Dock once it comes back. It is lifted clear while
    /// the Dock shows and returns when it hides; its stored place never moves.
    @Test func aPetDroppedWhileTheDockHidIsLiftedClearOfIt() {
        let laptop = screen(
            1, CGRect(x: 0, y: 0, width: 1512, height: 949),
            clearOfDock: CGRect(x: 0, y: 58, width: 1512, height: 890)
        )
        let bottom = CGPoint(x: 700, y: 0)
        let droppedInFullScreen = PetPosition(petOrigin: bottom, petSize: Self.petSize, screen: laptop, dockHidden: true)
        let droppedBesideDock = PetPosition(petOrigin: bottom, petSize: Self.petSize, screen: laptop, dockHidden: false)

        #expect(PetPlacement.origin(for: droppedInFullScreen, on: laptop, dockShown: true, petSize: Self.petSize)
            == CGPoint(x: 700, y: 58))
        #expect(PetPlacement.origin(for: droppedInFullScreen, on: laptop, dockShown: false, petSize: Self.petSize)
            == bottom)
        // Put beside a Dock the user could see, it stays put.
        #expect(PetPlacement.origin(for: droppedBesideDock, on: laptop, dockShown: true, petSize: Self.petSize)
            == bottom)
    }

    /// Positions saved before the Dock was recorded still decode, and stay put.
    @Test func positionsSavedBeforeTheDockWasRecordedStayPut() throws {
        let json = """
        {"displayUUID":"display-1","displayID":1,"displayName":"Display 1","visibleWidth":1512,
         "visibleHeight":949,"fractionX":0.5,"fractionY":0}
        """
        let saved = try JSONDecoder().decode(PetPosition.self, from: Data(json.utf8))
        let laptop = screen(
            1, CGRect(x: 0, y: 0, width: 1512, height: 949),
            clearOfDock: CGRect(x: 0, y: 58, width: 1512, height: 890)
        )

        #expect(saved.droppedWhileDockHidden == nil)
        #expect(PetPlacement.origin(for: saved, on: laptop, dockShown: true, petSize: Self.petSize).y == 0)
    }

    /// The Dock's window is on screen while it shows and leaves in a full-screen
    /// Space. Other levels are the Dock's passing effects, and a Dock on another
    /// display does not cover this one.
    @Test func theDockShowsWhileItsWindowIsOnScreen() {
        let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let dockWindow = PetWindow(ownerPID: 500, layer: 20, bounds: display)
        let fullScreenApp = PetWindow(ownerPID: 900, layer: 0, bounds: CGRect(x: 0, y: 33, width: 1512, height: 949))

        #expect(PetPlacement.dockShows(on: display, among: [fullScreenApp, dockWindow], dockPID: 500, dockLevel: 20))
        #expect(!PetPlacement.dockShows(on: display, among: [fullScreenApp], dockPID: 500, dockLevel: 20))
        #expect(!PetPlacement.dockShows(
            on: display, among: [PetWindow(ownerPID: 500, layer: 27, bounds: display)], dockPID: 500, dockLevel: 20
        ))
        #expect(!PetPlacement.dockShows(
            on: display,
            among: [PetWindow(ownerPID: 500, layer: 20, bounds: CGRect(x: 1512, y: -200, width: 2560, height: 1440))],
            dockPID: 500, dockLevel: 20
        ))
    }
}
