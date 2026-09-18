import CoreGraphics
import Testing
@testable import Clawde

struct PetLayoutTests {

    /// The badge hangs past the pet's top left, so the panel has to leave it
    /// room for every character at every size the slider offers.
    @Test func badgeStaysInsideThePanelAtEverySize() {
        for id in PetCharacterID.allCases {
            let corner = PetCharacter.character(for: id).badgeCorner
            for points in PetSize.range {
                let scale = CGFloat(points)
                let panel = CGRect(origin: .zero, size: PetLayout.panelSize(scale: scale))
                for digits in 1...3 {
                    #expect(panel.contains(PetLayout.badgeRect(scale: scale, corner: corner, digits: digits)))
                }
                #expect(panel.contains(PetLayout.badgeDotRect(scale: scale, corner: corner)))
                #expect(panel.contains(PetLayout.petRect(scale: scale)))
            }
        }
    }

    /// The badge sits in the air beside the character, not on it: in every mood
    /// but active, whose props are thrown about on purpose, no frame draws a
    /// cell within a few points of it.
    @Test func badgeKeepsClearOfTheCharacter() {
        let calmMoods = PetMood.allCases.filter { $0 != .active }
        for id in PetCharacterID.allCases {
            let character = PetCharacter.character(for: id)
            let frames = calmMoods.flatMap { mood in
                let routine = character.routine(for: mood)
                return (routine.enter ?? []) + routine.loop + (routine.exit ?? [])
            }
            for points in PetSize.range {
                let scale = CGFloat(points)
                let pet = PetLayout.petRect(scale: scale)
                for digits in 1...2 {
                    let air = PetLayout.badgeRect(scale: scale, corner: character.badgeCorner, digits: digits)
                        .insetBy(dx: -3, dy: -3)
                    let touching = frames.contains { frame in
                        frame.rows.enumerated().contains { row, line in
                            line.enumerated().contains { column, key in
                                key != "." && air.intersects(CGRect(
                                    x: pet.minX + CGFloat(column) * scale,
                                    y: pet.minY + CGFloat(row) * scale,
                                    width: scale,
                                    height: scale
                                ))
                            }
                        }
                    }
                    #expect(!touching, "\(id) at \(points) points, \(digits) digits")
                }
            }
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

    /// An in-panel rect counts down from the panel's top; the screen counts up.
    @Test func panelRectsConvertToTheScreen() {
        let panel = CGRect(x: 100, y: 200, width: 80, height: 60)
        let badge = CGRect(x: 10, y: 5, width: 20, height: 12)
        #expect(PetLayout.screenRect(badge, inPanelAt: panel) == CGRect(x: 110, y: 243, width: 20, height: 12))
    }

    /// Rows count outwards from the tail, so the list grows out of the line the
    /// pet's own session is on and that line stays nearest the badge.
    @Test func bubbleRowsCountOutwardsFromTheTail() {
        let size = CGSize(width: 180, height: PetLayout.bubbleHeight(rows: 3))
        let inset = PetLayout.bubbleShadowInset + PetLayout.bubblePadding
        let tail = PetLayout.bubbleTailHeight

        // Above the pet, the tail is at the bottom.
        let firstAbove = CGPoint(x: 90, y: size.height - inset - tail - 2)
        let lastAbove = CGPoint(x: 90, y: inset + 2)
        #expect(PetLayout.bubbleRow(at: firstAbove, in: size, rows: 3, isAbove: true) == 0)
        #expect(PetLayout.bubbleRow(at: lastAbove, in: size, rows: 3, isAbove: true) == 2)

        // Below it, at the top.
        let firstBelow = CGPoint(x: 90, y: inset + tail + 2)
        let lastBelow = CGPoint(x: 90, y: size.height - inset - 2)
        #expect(PetLayout.bubbleRow(at: firstBelow, in: size, rows: 3, isAbove: false) == 0)
        #expect(PetLayout.bubbleRow(at: lastBelow, in: size, rows: 3, isAbove: false) == 2)
    }

    /// The transparent room kept for the shadow is not a row, and nor is the
    /// strip the tail hangs in.
    @Test func bubbleShadowAndTailAreNotRows() {
        let size = CGSize(width: 180, height: PetLayout.bubbleHeight(rows: 2))
        let tailStrip = PetLayout.bubbleShadowInset + PetLayout.bubbleTailHeight / 2
        #expect(PetLayout.bubbleRow(at: CGPoint(x: 2, y: 20), in: size, rows: 2, isAbove: true) == nil)
        #expect(PetLayout.bubbleRow(at: CGPoint(x: 90, y: 1), in: size, rows: 2, isAbove: true) == nil)
        #expect(PetLayout.bubbleRow(at: CGPoint(x: 90, y: 20), in: size, rows: 0, isAbove: true) == nil)
        #expect(PetLayout.bubbleRow(at: CGPoint(x: 90, y: size.height - tailStrip), in: size, rows: 2, isAbove: true) == nil)
        #expect(PetLayout.bubbleRow(at: CGPoint(x: 90, y: tailStrip), in: size, rows: 2, isAbove: false) == nil)
    }

    /// The tail's tip rests just above the badge when there is room, and just
    /// below the pet when there is not, pointing at the badge's middle.
    @Test func bubblePointsItsTailAtTheBadge() {
        let area = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let size = PetLayout.bubbleSize(rows: 4)
        let inset = PetLayout.bubbleShadowInset
        let gap = PetLayout.bubbleTailGap

        let badge = CGRect(x: 400, y: 400, width: 20, height: 20)
        let above = PetLayout.bubblePlacement(size: size, target: badge, below: 330, in: area)
        #expect(above.isAbove)
        #expect(above.frame.minY + inset == badge.maxY + gap)
        #expect(above.frame.minX + inset + above.tailX == badge.midX)

        let atTheTop = CGRect(x: 400, y: 770, width: 20, height: 20)
        let below = PetLayout.bubblePlacement(size: size, target: atTheTop, below: 700, in: area)
        #expect(!below.isAbove)
        #expect(below.frame.maxY - inset == 700 - gap)
        #expect(below.frame.minX + inset + below.tailX == atTheTop.midX)
    }

    /// Near a side the bubble stops at the working area's edge, and its tail
    /// slides along the outline as far as the rounded corner lets it.
    @Test func bubbleKeepsInsideTheWorkingAreaSideways() {
        let area = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let size = PetLayout.bubbleSize(rows: 4)
        let outlineWidth = size.width - PetLayout.bubbleShadowInset * 2
        let tailRoom = PetLayout.bubbleCornerRadius + PetLayout.bubbleTailWidth / 2

        let right = PetLayout.bubblePlacement(
            size: size, target: CGRect(x: 985, y: 400, width: 10, height: 10), below: 330, in: area
        )
        #expect(right.frame.maxX == area.maxX)
        #expect(right.tailX == outlineWidth - tailRoom)

        let left = PetLayout.bubblePlacement(
            size: size, target: CGRect(x: 2, y: 400, width: 10, height: 10), below: 330, in: area
        )
        #expect(left.frame.minX == area.minX)
        #expect(left.tailX == tailRoom)
    }
}
