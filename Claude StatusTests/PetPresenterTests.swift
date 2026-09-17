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

    /// The bubble lists what is doing something or holding an answer, in the pet's
    /// own order, so its first line is the session the pet stands for, and then
    /// the idle session that did something last.
    @Test func bubbleListsBusySessionsInThePetsOrder() {
        let sessions = [
            session(id: "older-idle", state: .idle, secondsAgo: 60),
            session(id: "idle", state: .idle, secondsAgo: 30),
            session(id: "active", state: .active, secondsAgo: 5),
            session(id: "unread", state: .idle, isUnread: true),
            session(id: "waiting", state: .waiting),
            session(id: "compacting", state: .compacting),
            session(id: "newer-active", state: .active, secondsAgo: 1)
        ]
        let listed = PetPresenter.listed(from: sessions).map(\.sessionId)

        #expect(listed == ["waiting", "unread", "newer-active", "active", "compacting", "idle"])
        #expect(listed.first == PetPresenter.resolve(from: sessions)?.sessionId)
    }

    /// With nothing busy, the bubble lists the three idle sessions that did
    /// something last, the pet's own first.
    @Test func bubbleFallsBackToTheLatestIdleSessions() {
        let sessions = [
            session(id: "oldest", state: .idle, secondsAgo: 90),
            session(id: "older", state: .idle, secondsAgo: 60),
            session(id: "newer", state: .idle),
            session(id: "old", state: .idle, secondsAgo: 30)
        ]
        let listed = PetPresenter.listed(from: sessions).map(\.sessionId)

        #expect(listed == ["newer", "old", "older"])
        #expect(listed.first == PetPresenter.resolve(from: sessions)?.sessionId)
        #expect(PetPresenter.listed(from: []).isEmpty)
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
