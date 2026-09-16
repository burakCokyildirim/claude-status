import CoreGraphics
import Testing
@testable import Claude_Status

struct PetLayoutTests {

    /// The badge hangs past the pet's right edge, so the panel has to leave it
    /// room at every size the slider offers.
    @Test func badgeStaysInsideThePanelAtEverySize() {
        for points in PetSize.range {
            let scale = CGFloat(points)
            let panel = CGRect(origin: .zero, size: PetLayout.panelSize(scale: scale))
            #expect(panel.contains(PetLayout.badgeRect(scale: scale)))
            #expect(panel.contains(PetLayout.petRect(scale: scale)))
        }
    }

    /// Stored positions refer to the pet box, so the panel around it must map
    /// back to exactly the same spot.
    @Test func panelAndPetOriginsAreInverse() {
        let origin = CGPoint(x: 312, y: 88)
        for points in PetSize.range {
            let scale = CGFloat(points)
            let panel = PetLayout.panelOrigin(forPetOrigin: origin, scale: scale)
            #expect(PetLayout.petOrigin(forPanelOrigin: panel, scale: scale) == origin)
        }
    }

    /// Rows count outwards from the pet, so the list grows out of the line the
    /// pet's own session is on and that line stays under the pointer.
    @Test func bubbleRowsCountOutwardsFromThePet() {
        let size = CGSize(width: 180, height: PetLayout.bubbleHeight(rows: 3))
        let edge = PetLayout.bubbleShadowInset + PetLayout.bubblePadding
        let top = CGPoint(x: 90, y: edge + 2)
        let bottom = CGPoint(x: 90, y: size.height - edge - 2)

        #expect(PetLayout.bubbleRow(at: bottom, in: size, rows: 3, isAbove: true) == 0)
        #expect(PetLayout.bubbleRow(at: top, in: size, rows: 3, isAbove: true) == 2)
        #expect(PetLayout.bubbleRow(at: top, in: size, rows: 3, isAbove: false) == 0)
        #expect(PetLayout.bubbleRow(at: bottom, in: size, rows: 3, isAbove: false) == 2)
    }

    /// The transparent room kept for the shadow is not a row.
    @Test func bubbleShadowRoomIsNotARow() {
        let size = CGSize(width: 180, height: PetLayout.bubbleHeight(rows: 2))
        #expect(PetLayout.bubbleRow(at: CGPoint(x: 2, y: 20), in: size, rows: 2, isAbove: true) == nil)
        #expect(PetLayout.bubbleRow(at: CGPoint(x: 90, y: 1), in: size, rows: 2, isAbove: true) == nil)
        #expect(PetLayout.bubbleRow(at: CGPoint(x: 90, y: 20), in: size, rows: 0, isAbove: true) == nil)
    }

    /// Above the pet when there is room, below it when not, and never past the
    /// sides of the working area.
    @Test func bubbleSitsAboveThePetUnlessThereIsNoRoom() {
        let area = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let size = CGSize(width: 180, height: PetLayout.bubbleHeight(rows: 4))

        let middle = CGRect(x: 400, y: 300, width: 100, height: 80)
        let above = PetLayout.bubblePlacement(size: size, petRect: middle, in: area)
        #expect(above.isAbove)
        #expect(above.frame.minY == middle.maxY)
        #expect(abs(above.frame.midX - middle.midX) <= 0.5)

        let atTheTop = CGRect(x: 400, y: 720, width: 100, height: 80)
        let below = PetLayout.bubblePlacement(size: size, petRect: atTheTop, in: area)
        #expect(!below.isAbove)
        #expect(below.frame.maxY == atTheTop.minY)

        let atTheSide = CGRect(x: 950, y: 300, width: 100, height: 80)
        #expect(PetLayout.bubblePlacement(size: size, petRect: atTheSide, in: area).frame.maxX == area.maxX)
    }
}
