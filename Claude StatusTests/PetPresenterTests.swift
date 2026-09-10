import Foundation
import Testing
@testable import Claude_Status

struct PetPresenterTests {

    /// Fixed reference date so timestamp ordering is explicit in each test.
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func session(
        id: String,
        state: SessionState,
        secondsAgo: TimeInterval = 0
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
            sessionName: nil
        )
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
