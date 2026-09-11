import Foundation
import Testing
@testable import Claude_Status

/// Sessions run by the Claude desktop app: matching a hook's session ID to the
/// desktop's own session, and the link that opens it.
@MainActor
struct ClaudeDesktopTests {

    /// Lays out `<root>/<account>/<org>/local_<id>.json` the way the Claude
    /// desktop app keeps its Claude Code sessions, under a throwaway root.
    private func makeSessionsRoot(_ sessions: [(desktopId: String, cliId: String)]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-desktop-\(UUID().uuidString)")
        let organization = root.appendingPathComponent("account/organization")
        try FileManager.default.createDirectory(at: organization, withIntermediateDirectories: true)
        for session in sessions {
            let record: [String: Any] = ["sessionId": session.desktopId, "cliSessionId": session.cliId]
            try JSONSerialization.data(withJSONObject: record)
                .write(to: organization.appendingPathComponent("\(session.desktopId).json"))
        }
        return root
    }

    @Test func findsTheDesktopSessionForAHookSession() throws {
        let root = try makeSessionsRoot([
            ("local_1111-aaaa", "cli-one"),
            ("local_2222-bbbb", "cli-two")
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(SessionFocuser.claudeDesktopSessionId(forCLISession: "cli-two", in: [root]) == "local_2222-bbbb")
    }

    @Test func findsNothingWithoutAMatch() throws {
        let root = try makeSessionsRoot([("local_1111-aaaa", "cli-one")])
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(SessionFocuser.claudeDesktopSessionId(forCLISession: "cli-nine", in: [root]) == nil)
        let missing = root.appendingPathComponent("missing")
        #expect(SessionFocuser.claudeDesktopSessionId(forCLISession: "cli-one", in: [missing]) == nil)
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
