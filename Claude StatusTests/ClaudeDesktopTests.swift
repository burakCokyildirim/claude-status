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

    @Test func anUnreadFinishedDesktopSessionIsTheUsersMove() {
        let unread = ClaudeDesktopSession(sessionId: "local_x", lastActivityAt: 3_000, lastFocusedAt: 2_000)
        let read = ClaudeDesktopSession(sessionId: "local_y", lastActivityAt: 1_000, lastFocusedAt: 2_000)
        let resolve = ClaudeDesktopSessionStore.resolvedState

        #expect(resolve(.idle, .claudeDesktop, unread) == .waiting)
        #expect(resolve(.idle, .claudeDesktop, read) == .idle)
        #expect(resolve(.idle, .claudeDesktop, nil) == .idle)
        // A session still working, or one running anywhere else, is left alone.
        #expect(resolve(.active, .claudeDesktop, unread) == .active)
        #expect(resolve(.compacting, .claudeDesktop, unread) == .compacting)
        #expect(resolve(.idle, .terminal(app: "Terminal"), unread) == .idle)
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
