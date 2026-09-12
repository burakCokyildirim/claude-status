import Foundation
import Testing
@testable import Claude_Status

/// Sessions run by the Claude desktop app: reading its records, telling an
/// answer nobody has seen from an abandoned session, and the link that opens one.
@MainActor
struct ClaudeDesktopTests {

    private struct Record {
        let desktopId: String
        let cliId: String
        var lastActivityAt: Double = 1_000
        var lastFocusedAt: Double = 2_000
    }

    /// Lays out `<root>/<account>/<organization>/local_<id>.json` the way the
    /// Claude desktop app keeps its Claude Code sessions, under a throwaway root.
    private func makeSessionsRoot(_ records: [Record]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-desktop-\(UUID().uuidString)")
        let organization = root.appendingPathComponent("account/organization")
        try FileManager.default.createDirectory(at: organization, withIntermediateDirectories: true)
        for record in records {
            let json: [String: Any] = [
                "sessionId": record.desktopId,
                "cliSessionId": record.cliId,
                "lastActivityAt": record.lastActivityAt,
                "lastFocusedAt": record.lastFocusedAt
            ]
            try JSONSerialization.data(withJSONObject: json)
                .write(to: organization.appendingPathComponent("\(record.desktopId).json"))
        }
        return root
    }

    /// Epoch milliseconds as a `Date`, so a test can say "the scan ran here".
    private func at(_ milliseconds: Double) -> Date {
        Date(timeIntervalSince1970: milliseconds / 1_000)
    }

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "claude-desktop-tests-\(UUID().uuidString)")!
    }

    /// One session the user answered in and left, plus the one the app has up.
    /// The open session has spoken since its focus stamp, the way a session
    /// being read does while Claude keeps working in it.
    private func makeTwoSessionRoot() throws -> URL {
        try makeSessionsRoot([
            Record(desktopId: "local_away", cliId: "cli-away", lastActivityAt: 3_000, lastFocusedAt: 2_000),
            Record(desktopId: "local_open", cliId: "cli-open", lastActivityAt: 9_500, lastFocusedAt: 9_000)
        ])
    }

    @Test func findsTheDesktopRecordForAHookSession() throws {
        let root = try makeSessionsRoot([
            Record(desktopId: "local_1111-aaaa", cliId: "cli-one"),
            Record(desktopId: "local_2222-bbbb", cliId: "cli-two")
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        var store = ClaudeDesktopSessionStore(roots: [root], defaults: makeDefaults()) { false }
        store.refresh(force: true)

        #expect(store.session(forCLISession: "cli-two")?.sessionId == "local_2222-bbbb")
        #expect(store.session(forCLISession: "cli-nine") == nil)
    }

    @Test func survivesRootsThatAreNotThere() {
        var store = ClaudeDesktopSessionStore(
            roots: [URL(fileURLWithPath: "/nope/claude-code-sessions")],
            defaults: makeDefaults()
        ) { true }
        store.refresh(force: true)

        #expect(store.session(forCLISession: "cli-one") == nil)
        #expect(store.resolvedState(hookState: .idle, source: .claudeDesktop, cliSessionId: "cli-one") == .idle)
    }

    /// The case the rule exists for: Claude answered while the user was in
    /// another app, so nobody has seen it.
    @Test func anAnswerTheUserWasAwayForIsTheirMove() throws {
        let root = try makeTwoSessionRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var store = ClaudeDesktopSessionStore(roots: [root], defaults: makeDefaults()) { false }
        store.refresh(force: true, now: at(9_600))

        #expect(store.resolvedState(hookState: .idle, source: .claudeDesktop, cliSessionId: "cli-away") == .waiting)
        // A session still working, one running anywhere else, and one the app
        // has no record of all keep the state the hook reported.
        #expect(store.resolvedState(hookState: .active, source: .claudeDesktop, cliSessionId: "cli-away") == .active)
        #expect(store.resolvedState(hookState: .compacting, source: .claudeDesktop, cliSessionId: "cli-away") == .compacting)
        #expect(store.resolvedState(hookState: .idle, source: .terminal(app: "Terminal"), cliSessionId: "cli-away") == .idle)
        #expect(store.resolvedState(hookState: .idle, source: .claudeDesktop, cliSessionId: "cli-none") == .idle)
    }

    /// Sitting in a session must not turn it into a notice about itself, however
    /// old the app's own focus stamp has gone.
    @Test func aSessionBeingWatchedIsNotAMove() throws {
        let root = try makeTwoSessionRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var store = ClaudeDesktopSessionStore(roots: [root], defaults: makeDefaults()) { true }
        store.refresh(force: true, now: at(10_000))

        #expect(store.resolvedState(hookState: .idle, source: .claudeDesktop, cliSessionId: "cli-open") == .idle)
        // The session in the background is still the user's move.
        #expect(store.resolvedState(hookState: .idle, source: .claudeDesktop, cliSessionId: "cli-away") == .waiting)
    }

    /// Watching the answer arrive and then leaving the app must leave the
    /// session quiet: the stamp was taken while it was on screen.
    @Test func anAnswerWatchedLiveStaysQuietAfterLookingAway() throws {
        let root = try makeTwoSessionRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = makeDefaults()
        var inFront = true
        var store = ClaudeDesktopSessionStore(roots: [root], defaults: defaults) { inFront }
        store.refresh(force: true, now: at(10_000))  // read on screen

        inFront = false
        store.refresh(force: true, now: at(20_000))  // user moves to another app

        #expect(store.resolvedState(hookState: .idle, source: .claudeDesktop, cliSessionId: "cli-open") == .idle)
    }

    /// The stamps outlive the app, so a relaunch does not reannounce answers
    /// the user has already read.
    @Test func whatWasSeenIsRemembered() throws {
        let root = try makeTwoSessionRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = makeDefaults()
        var store = ClaudeDesktopSessionStore(roots: [root], defaults: defaults) { true }
        store.refresh(force: true, now: at(10_000))

        var relaunched = ClaudeDesktopSessionStore(roots: [root], defaults: defaults) { false }
        relaunched.refresh(force: true, now: at(20_000))

        #expect(relaunched.resolvedState(hookState: .idle, source: .claudeDesktop, cliSessionId: "cli-open") == .idle)
        #expect(relaunched.resolvedState(hookState: .idle, source: .claudeDesktop, cliSessionId: "cli-away") == .waiting)
    }

    /// The desktop app's link handler only accepts `local_` IDs, so anything
    /// else in a record must never make it into the URL.
    @Test func linksOnlyToLocalSessionIds() {
        #expect(
            SessionFocuser.claudeDesktopURL(forDesktopSession: "local_2222-bbbb")?.absoluteString
                == "claude://code/continue?session=local_2222-bbbb"
        )
        #expect(SessionFocuser.claudeDesktopURL(forDesktopSession: "cse_2222") == nil)
        #expect(SessionFocuser.claudeDesktopURL(forDesktopSession: "local_x&session=last") == nil)
    }

    @Test func desktopSessionsAreLabelledClaude() throws {
        #expect(SessionSource.claudeDesktop.label == "Claude")
        #expect(!SessionSource.claudeDesktop.isTerminal)

        let encoded = try JSONEncoder().encode(SessionSource.claudeDesktop)
        #expect(try JSONDecoder().decode(SessionSource.self, from: encoded) == .claudeDesktop)
    }
}
