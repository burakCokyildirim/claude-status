import Foundation
import Testing
@testable import Claude_Status

@MainActor
struct PetPresenterTests {

    /// Fixed reference date so timestamp ordering is explicit in each test.
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func session(
        id: String,
        state: SessionState,
        secondsAgo: TimeInterval = 0,
        isUnread: Bool? = nil
    ) -> ClaudeSession {
        ClaudeSession(
            sessionId: id,
            pid: 1,
            workingDirectory: "/tmp/\(id)",
            projectName: id,
            state: state,
            lastActivityAt: Self.now.addingTimeInterval(-secondsAgo),
            iTermSessionId: nil,
            tmuxPaneId: nil,
            tmuxSocket: nil,
            source: .terminal(app: "Terminal"),
            activity: "",
            sessionName: nil,
            profileName: nil,
            isUnread: isUnread
        )
    }

    /// A session blocked on the user outranks one that merely has something to
    /// read: the first cannot go on at all until they answer.
    @Test func waitingOutranksUnread() {
        let waiting = session(id: "waiting", state: .waiting)
        let unread = session(id: "unread", state: .idle, isUnread: true)

        #expect(PetPresenter.resolve(from: [waiting, unread])?.sessionId == "waiting")
        #expect(PetPresenter.resolve(from: [unread, waiting])?.sessionId == "waiting")
    }

    /// An answer nobody has read wants the user more than a session that is busy
    /// working, or one with nothing to show at all.
    @Test func unreadOutranksEveryStateBelowWaiting() {
        let unread = session(id: "unread", state: .idle, isUnread: true)
        for state in [SessionState.active, .compacting, .idle] {
            let other = session(id: "other", state: state)
            #expect(PetPresenter.resolve(from: [other, unread])?.sessionId == "unread")
            #expect(PetPresenter.resolve(from: [unread, other])?.sessionId == "unread")
        }
    }

    @Test func resolvesNilWithoutSessions() {
        #expect(PetPresenter.resolve(from: []) == nil)
    }

    @Test func resolvesTheOnlySession() {
        for state in [SessionState.active, .waiting, .compacting, .idle] {
            let only = session(id: "only", state: state)
            #expect(PetPresenter.resolve(from: [only])?.sessionId == "only")
        }
    }

    @Test func waitingOutranksActive() {
        let sessions = [
            session(id: "active", state: .active),
            session(id: "waiting", state: .waiting)
        ]
        #expect(PetPresenter.resolve(from: sessions)?.sessionId == "waiting")
        #expect(PetPresenter.resolve(from: sessions.reversed())?.sessionId == "waiting")
    }

    @Test func waitingOutranksEveryOtherState() {
        let sessions = [
            session(id: "idle", state: .idle),
            session(id: "compacting", state: .compacting),
            session(id: "active", state: .active),
            session(id: "waiting", state: .waiting)
        ]
        #expect(PetPresenter.resolve(from: sessions)?.sessionId == "waiting")
    }

    /// The pet follows the app's existing ordering (`SessionState.sortOrder`),
    /// where a working session outranks one that is compacting.
    @Test func activeOutranksCompacting() {
        let sessions = [
            session(id: "compacting", state: .compacting),
            session(id: "active", state: .active)
        ]
        #expect(PetPresenter.resolve(from: sessions)?.sessionId == "active")
        #expect(PetPresenter.resolve(from: sessions.reversed())?.sessionId == "active")
    }

    @Test func compactingOutranksIdle() {
        let sessions = [
            session(id: "idle", state: .idle),
            session(id: "compacting", state: .compacting)
        ]
        #expect(PetPresenter.resolve(from: sessions)?.sessionId == "compacting")
    }

    @Test func breaksStateTiesOnMostRecentActivity() {
        let sessions = [
            session(id: "stale", state: .active, secondsAgo: 600),
            session(id: "fresh", state: .active, secondsAgo: 5),
            session(id: "middle", state: .active, secondsAgo: 60)
        ]
        #expect(PetPresenter.resolve(from: sessions)?.sessionId == "fresh")
    }

    @Test func activityTiesBreakOnSessionId() {
        let sessions = [
            session(id: "ccc", state: .waiting),
            session(id: "aaa", state: .waiting),
            session(id: "bbb", state: .waiting)
        ]
        #expect(PetPresenter.resolve(from: sessions)?.sessionId == "aaa")
    }

    /// Fully tied candidates must resolve the same way regardless of scan order,
    /// otherwise the pet would flap between equal sessions on every refresh.
    @Test func resolutionIsIndependentOfInputOrder() {
        let sessions = [
            session(id: "ccc", state: .waiting),
            session(id: "aaa", state: .waiting),
            session(id: "bbb", state: .waiting),
            session(id: "zzz", state: .active, secondsAgo: 1)
        ]
        let expected = PetPresenter.resolve(from: sessions)?.sessionId
        #expect(expected == "aaa")
        #expect(PetPresenter.resolve(from: sessions.reversed())?.sessionId == expected)
        #expect(PetPresenter.resolve(from: sessions.shuffled())?.sessionId == expected)
    }
}

struct PetMotionTests {

    private static let all: [PetAnimation] = [.still, .breathe, .work, .sweep, .poke, .startle]

    /// Loops must not jump when they wrap, and one-shots must settle. Both fall
    /// out of every animation starting and ending on the identity transform.
    @Test func everyAnimationOpensAndClosesOnIdentity() {
        for animation in Self.all {
            #expect(PetMotion.transform(for: animation, phase: 0) == .identity)
            #expect(PetMotion.transform(for: animation, phase: 1) == .identity)
        }
    }

    @Test func phaseIsClampedOutsideTheUnitRange() {
        for animation in Self.all {
            #expect(PetMotion.transform(for: animation, phase: -3) == .identity)
            #expect(PetMotion.transform(for: animation, phase: 42) == .identity)
        }
    }

    @Test func loopingAnimationsActuallyMove() {
        for animation in [PetAnimation.breathe, .work, .sweep, .poke, .startle] {
            let moved = stride(from: 0.05, to: 1.0, by: 0.05).contains { phase in
                PetMotion.transform(for: animation, phase: phase) != .identity
            }
            #expect(moved, "\(animation) never leaves the identity transform")
        }
    }

    /// The pet is static when idle, which is what lets the driver run no timer.
    @Test func stillNeverMoves() {
        for phase in stride(from: 0.0, through: 1.0, by: 0.05) {
            #expect(PetMotion.transform(for: .still, phase: phase) == .identity)
        }
        #expect(!PetAnimation.still.isAnimated)
    }

    @Test func onlyReactionsAreOneShots() {
        #expect(PetAnimation.poke.duration != nil)
        #expect(PetAnimation.startle.duration != nil)
        for animation in [PetAnimation.still, .breathe, .work, .sweep] {
            #expect(animation.duration == nil)
        }
    }

    @Test func restingAnimationFollowsSessionState() {
        #expect(PetAnimation.resting(for: .active) == .work)
        #expect(PetAnimation.resting(for: .waiting) == .breathe)
        #expect(PetAnimation.resting(for: .compacting) == .sweep)
        #expect(PetAnimation.resting(for: .idle) == .still)
        #expect(PetAnimation.resting(for: nil) == .still)
    }

    /// Grid offsets stay whole so the pixel art never lands between grid lines.
    @Test func offsetsStayOnTheGrid() {
        for animation in Self.all {
            for phase in stride(from: 0.0, through: 1.0, by: 0.02) {
                let transform = PetMotion.transform(for: animation, phase: phase)
                #expect(transform.offsetX == transform.offsetX.rounded())
                #expect(transform.offsetY == transform.offsetY.rounded())
            }
        }
    }
}

struct PetCharacterTests {

    /// The renderer indexes rows and columns directly, so a mis-sized row would
    /// silently clip or crash rather than look wrong.
    @Test func everyCharacterIsAWellFormedGrid() {
        for id in PetCharacterID.allCases {
            let character = PetCharacter.character(for: id)
            #expect(character.body.count == PetLayout.gridHeight)
            for row in character.body {
                #expect(row.count == PetLayout.gridWidth)
            }
            for (index, row) in character.airborneRows {
                #expect(character.body.indices.contains(index))
                #expect(row.count == PetLayout.gridWidth)
            }
        }
    }

    @Test func composedSpritesKeepTheirShape() {
        for id in PetCharacterID.allCases {
            let character = PetCharacter.character(for: id)
            for state in [SessionState.active, .waiting, .compacting, .idle] {
                for airborne in [false, true] {
                    let sprite = character.sprite(for: state, airborne: airborne)
                    #expect(sprite.count == PetLayout.gridHeight)
                    for row in sprite {
                        #expect(row.count == PetLayout.gridWidth)
                    }
                }
            }
        }
    }

    /// Each state has to be distinguishable, or the pet conveys nothing.
    @Test func eachStateLooksDifferent() {
        let character = PetCharacter.character(for: .nibble)
        let sprites = [SessionState.active, .waiting, .compacting, .idle].map {
            character.sprite(for: $0, airborne: false)
        }
        for (index, sprite) in sprites.enumerated() {
            for other in sprites[(index + 1)...] {
                #expect(sprite != other)
            }
        }
    }
}
