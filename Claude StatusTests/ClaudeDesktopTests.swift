import Foundation
import Testing
@testable import Claude_Status

/// Sessions run by the Claude desktop app: reading its records, spotting the
/// ones the user has not looked at, and the link that opens them.
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

    private func makeStore(_ records: [Record]) throws -> (ClaudeDesktopSessionStore, URL) {
        let root = try makeSessionsRoot(records)
        var store = ClaudeDesktopSessionStore(roots: [root])
        store.refresh(force: true)
        return (store, root)
    }

    /// A session in the background that Claude has spoken in since it was last
    /// looked at, plus the session on screen — the newest focus stamp of the two.
    private func makeTwoSessionStore() throws -> (ClaudeDesktopSessionStore, URL) {
        try makeStore([
            Record(desktopId: "local_unread", cliId: "cli-unread", lastActivityAt: 3_000, lastFocusedAt: 2_000),
            Record(desktopId: "local_open", cliId: "cli-open", lastActivityAt: 9_500, lastFocusedAt: 9_000)
        ])
    }

    @Test func findsTheDesktopRecordForAHookSession() throws {
        let (store, root) = try makeStore([
            Record(desktopId: "local_1111-aaaa", cliId: "cli-one"),
            Record(desktopId: "local_2222-bbbb", cliId: "cli-two")
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(store.session(forCLISession: "cli-two")?.sessionId == "local_2222-bbbb")
        #expect(store.session(forCLISession: "cli-nine") == nil)
    }

    @Test func survivesRootsThatAreNotThere() {
        var store = ClaudeDesktopSessionStore(roots: [URL(fileURLWithPath: "/nope/claude-code-sessions")])
        store.refresh(force: true)

        #expect(store.session(forCLISession: "cli-one") == nil)
        #expect(store.resolvedState(hookState: .idle, source: .claudeDesktop, cliSessionId: "cli-one") == .idle)
    }

    /// Unread is the only thing separating a finished turn the user has seen from
    /// one that is waiting for them.
    @Test func unreadMeansActivityAfterTheLastLook() throws {
        let (store, root) = try makeStore([
            Record(desktopId: "local_read", cliId: "cli-read", lastActivityAt: 1_000, lastFocusedAt: 2_000),
            Record(desktopId: "local_unread", cliId: "cli-unread", lastActivityAt: 3_000, lastFocusedAt: 2_000)
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(store.session(forCLISession: "cli-read")?.isUnread == false)
        #expect(store.session(forCLISession: "cli-unread")?.isUnread == true)
    }

    @Test func anUnreadFinishedDesktopSessionIsTheUsersMove() throws {
        let (store, root) = try makeTwoSessionStore()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(store.resolvedState(hookState: .idle, source: .claudeDesktop, cliSessionId: "cli-unread") == .waiting)
        // A session still working, one running anywhere else, and one the app
        // has no record of all keep the state the hook reported.
        #expect(store.resolvedState(hookState: .active, source: .claudeDesktop, cliSessionId: "cli-unread") == .active)
        #expect(store.resolvedState(hookState: .compacting, source: .claudeDesktop, cliSessionId: "cli-unread") == .compacting)
        #expect(store.resolvedState(hookState: .idle, source: .terminal(app: "Terminal"), cliSessionId: "cli-unread") == .idle)
        #expect(store.resolvedState(hookState: .idle, source: .claudeDesktop, cliSessionId: "cli-none") == .idle)
    }

    /// The record of the session on screen says unread the whole time it is
    /// open: its focus stamp is set once, while Claude keeps working in it.
    @Test func theSessionInFrontIsNeverTheUsersMove() throws {
        let (store, root) = try makeTwoSessionStore()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(store.session(forCLISession: "cli-open")?.isUnread == true)
        #expect(store.resolvedState(hookState: .idle, source: .claudeDesktop, cliSessionId: "cli-open") == .idle)
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
