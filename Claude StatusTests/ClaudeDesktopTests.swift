import Foundation
import Testing
@testable import Claude_Status

/// Sessions run by the Claude desktop app: reading its records, telling an
/// answer nobody has read from an abandoned session, and the link that opens one.
@MainActor
struct ClaudeDesktopTests {

    private struct Record {
        let desktopId: String
        let cliId: String
        var lastActivityAt: Double = 1_000
        var lastFocusedAt: Double? = 2_000
    }

    /// Lays out `<root>/<account>/<organization>/local_<id>.json` the way the
    /// Claude desktop app keeps its Claude Code sessions, under a throwaway root.
    private func makeSessionsRoot(_ records: [Record], account: String = "account") throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-desktop-\(UUID().uuidString)")
        try write(records, into: root, account: account)
        return root
    }

    private func write(_ records: [Record], into root: URL, account: String) throws {
        let organization = root.appendingPathComponent("\(account)/organization")
        try FileManager.default.createDirectory(at: organization, withIntermediateDirectories: true)
        for record in records {
            var json: [String: Any] = [
                "sessionId": record.desktopId,
                "cliSessionId": record.cliId,
                "lastActivityAt": record.lastActivityAt
            ]
            if let focused = record.lastFocusedAt { json["lastFocusedAt"] = focused }
            try JSONSerialization.data(withJSONObject: json)
                .write(to: organization.appendingPathComponent("\(record.desktopId).json"))
        }
    }

    /// A log with one focus line per entry, in the app's own format.
    private func makeFocusLog(_ focused: [String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-main-\(UUID().uuidString).log")
        let lines = focused.map {
            "2026-09-12 22:31:10 [info] [CCD] LocalSessions.setFocusedSession: sessionId=\($0)"
        }
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Epoch milliseconds as a `Date`, so a test can say "this happened here".
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

    private func unread(
        _ store: ClaudeDesktopSessionStore,
        _ cliSessionId: String,
        spokeAt: Double,
        hookState: SessionState = .idle,
        source: SessionSource = .claudeDesktop
    ) -> Bool {
        store.isUnread(
            source: source, hookState: hookState, cliSessionId: cliSessionId, lastSpokeAt: at(spokeAt)
        )
    }

    // MARK: - Records

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

    /// The same session turns up under two accounts, one copy left behind with an
    /// older answer. The newer record has to win, or the stale one decides.
    @Test func theNewerCopyOfADuplicatedRecordWins() throws {
        let root = try makeSessionsRoot(
            [Record(desktopId: "local_stale", cliId: "cli-dup", lastActivityAt: 1_000, lastFocusedAt: 500)]
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try write(
            [Record(desktopId: "local_fresh", cliId: "cli-dup", lastActivityAt: 8_000, lastFocusedAt: 7_000)],
            into: root, account: "second-account"
        )
        var store = ClaudeDesktopSessionStore(roots: [root], defaults: makeDefaults()) { false }
        store.refresh(force: true)

        #expect(store.session(forCLISession: "cli-dup")?.sessionId == "local_fresh")
    }

    @Test func survivesRootsThatAreNotThere() {
        var store = ClaudeDesktopSessionStore(
            roots: [URL(fileURLWithPath: "/nope/claude-code-sessions")],
            defaults: makeDefaults()
        ) { true }
        store.refresh(force: true)

        #expect(store.session(forCLISession: "cli-one") == nil)
        #expect(!unread(store, "cli-one", spokeAt: 5_000))
    }

    // MARK: - Unread

    /// The case the signal exists for: Claude answered while the user was in
    /// another app, so nobody has read it.
    @Test func anAnswerTheUserWasAwayForIsUnread() throws {
        let root = try makeTwoSessionRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var store = ClaudeDesktopSessionStore(roots: [root], defaults: makeDefaults()) { false }
        store.refresh(force: true, now: at(9_600))

        #expect(unread(store, "cli-away", spokeAt: 3_000))
        // A session still working, one running anywhere else, and one the app has
        // no record of are never called unread.
        #expect(!unread(store, "cli-away", spokeAt: 3_000, hookState: .active))
        #expect(!unread(store, "cli-away", spokeAt: 3_000, hookState: .compacting))
        #expect(!unread(store, "cli-away", spokeAt: 3_000, source: .terminal(app: "Terminal")))
        #expect(!unread(store, "cli-none", spokeAt: 3_000))
    }

    /// Reading a session must not turn it into a notice about itself, however old
    /// the app's own focus stamp has gone.
    @Test func theSessionOnScreenIsNotUnread() throws {
        let root = try makeTwoSessionRoot()
        let log = try makeFocusLog(["local_open"])
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: log)
        }
        var store = ClaudeDesktopSessionStore(
            roots: [root], defaults: makeDefaults(), focusLog: ClaudeDesktopFocusLog(url: log)
        ) { true }
        store.refresh(force: true, now: at(10_000))

        #expect(!unread(store, "cli-open", spokeAt: 9_500))
        // The session in the background is still unread.
        #expect(unread(store, "cli-away", spokeAt: 3_000))
    }

    /// The bug this whole signal kept getting wrong: the Claude app is in front,
    /// but what it is showing is a plain chat, not this session. Its own log says
    /// so, and without that line the last-opened session looks like it is being
    /// read for as long as the window stays up.
    @Test func theAppInFrontShowingSomethingElseIsNotReading() throws {
        let root = try makeTwoSessionRoot()
        let log = try makeFocusLog(["local_open", "null"])
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: log)
        }
        var store = ClaudeDesktopSessionStore(
            roots: [root], defaults: makeDefaults(), focusLog: ClaudeDesktopFocusLog(url: log)
        ) { true }
        store.refresh(force: true, now: at(10_000))

        #expect(unread(store, "cli-open", spokeAt: 9_500))
    }

    /// Watching the answer arrive and then leaving must leave the session quiet:
    /// the mark was taken while it was on screen.
    @Test func anAnswerReadOnScreenStaysQuietAfterLookingAway() throws {
        let root = try makeTwoSessionRoot()
        let log = try makeFocusLog(["local_open"])
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: log)
        }
        var inFront = true
        var store = ClaudeDesktopSessionStore(
            roots: [root], defaults: makeDefaults(), focusLog: ClaudeDesktopFocusLog(url: log)
        ) { inFront }
        store.refresh(force: true, now: at(10_000))  // read on screen

        inFront = false
        store.refresh(force: true, now: at(20_000))  // user moves to another app

        #expect(!unread(store, "cli-open", spokeAt: 9_900))
    }

    /// The marks outlive the app, so a relaunch does not reannounce answers the
    /// user has already read.
    @Test func whatWasReadIsRemembered() throws {
        let root = try makeTwoSessionRoot()
        let log = try makeFocusLog(["local_open"])
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: log)
        }
        let defaults = makeDefaults()
        var store = ClaudeDesktopSessionStore(
            roots: [root], defaults: defaults, focusLog: ClaudeDesktopFocusLog(url: log)
        ) { true }
        store.refresh(force: true, now: at(10_000))

        var relaunched = ClaudeDesktopSessionStore(roots: [root], defaults: defaults) { false }
        relaunched.refresh(force: true, now: at(20_000))

        #expect(!unread(relaunched, "cli-open", spokeAt: 9_500))
        #expect(unread(relaunched, "cli-away", spokeAt: 3_000))
    }

    /// The answer is announced the moment the hook says the turn ended. The
    /// desktop app throttles its own `lastActivityAt` and can leave it an hour
    /// behind, which would hold a finished answer back.
    @Test func aThrottledRecordDoesNotHoldTheAnswerBack() throws {
        let root = try makeSessionsRoot([
            Record(desktopId: "local_slow", cliId: "cli-slow", lastActivityAt: 1_000, lastFocusedAt: 2_000)
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        var store = ClaudeDesktopSessionStore(roots: [root], defaults: makeDefaults()) { false }
        store.refresh(force: true, now: at(5_100))

        #expect(unread(store, "cli-slow", spokeAt: 5_000))
        // And an answer older than the last look is still nothing to announce.
        #expect(!unread(store, "cli-slow", spokeAt: 1_500))
    }

    /// Some records carry no focus stamp at all. Reading that as "never opened"
    /// would call every one of them unread for ever.
    @Test func aRecordWithNoFocusStampIsLeftAlone() throws {
        let root = try makeSessionsRoot([
            Record(desktopId: "local_nofocus", cliId: "cli-nofocus", lastActivityAt: 1_000, lastFocusedAt: nil)
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        var store = ClaudeDesktopSessionStore(roots: [root], defaults: makeDefaults()) { false }
        store.refresh(force: true, now: at(5_000))

        #expect(store.session(forCLISession: "cli-nofocus")?.lastFocusedAt == nil)
        #expect(!unread(store, "cli-nofocus", spokeAt: 9_000))
    }

    // MARK: - Focus log

    @Test func theFocusLogReadsTheLastSwitch() throws {
        let log = try makeFocusLog(["local_one", "local_two"])
        defer { try? FileManager.default.removeItem(at: log) }
        var reader = ClaudeDesktopFocusLog(url: log)
        reader.refresh()

        #expect(reader.focus == .session("local_two"))
    }

    @Test func aLogThatNeverSaidLeavesItUnknown() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("quiet-\(UUID().uuidString).log")
        try "2026-09-12 22:31:10 [info] something else entirely\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        var reader = ClaudeDesktopFocusLog(url: url)
        reader.refresh()

        #expect(reader.focus == .unknown)
        var missing = ClaudeDesktopFocusLog(url: url.appendingPathExtension("gone"))
        missing.refresh()
        #expect(missing.focus == .unknown)
    }

    /// Switching sessions is logged as `null` and then the new ID. Believing the
    /// gap would blink every session to unread, so a clear has to survive a scan.
    @Test func aPassingNullIsNotBelievedAtOnce() throws {
        let log = try makeFocusLog(["local_one"])
        defer { try? FileManager.default.removeItem(at: log) }
        var reader = ClaudeDesktopFocusLog(url: log)
        reader.refresh()
        #expect(reader.focus == .session("local_one"))

        try append(to: log, "null")
        reader.refresh()
        #expect(reader.focus == .session("local_one"))  // held, pending confirmation

        try append(to: log, "null")
        reader.refresh()
        #expect(reader.focus == .noSession)
    }

    @Test func aSwitchSurvivesThePassingNull() throws {
        let log = try makeFocusLog(["local_one"])
        defer { try? FileManager.default.removeItem(at: log) }
        var reader = ClaudeDesktopFocusLog(url: log)
        reader.refresh()

        try append(to: log, "null")
        try append(to: log, "local_two")
        reader.refresh()

        #expect(reader.focus == .session("local_two"))
    }

    /// A rotated log is shorter than the offset we left off at; reading from
    /// there would seek past its end and go blind.
    @Test func aRotatedLogIsReadFromTheStart() throws {
        let log = try makeFocusLog(["local_one", "local_two"])
        defer { try? FileManager.default.removeItem(at: log) }
        var reader = ClaudeDesktopFocusLog(url: log)
        reader.refresh()
        #expect(reader.focus == .session("local_two"))

        let rotated = try makeFocusLog(["local_three"])
        defer { try? FileManager.default.removeItem(at: rotated) }
        try FileManager.default.removeItem(at: log)
        try FileManager.default.copyItem(at: rotated, to: log)
        reader.refresh()

        #expect(reader.focus == .session("local_three"))
    }

    @Test func junkAfterTheMarkerIsIgnored() throws {
        let log = try makeFocusLog(["local_one", "not a session id"])
        defer { try? FileManager.default.removeItem(at: log) }
        var reader = ClaudeDesktopFocusLog(url: log)
        reader.refresh()

        #expect(reader.focus == .session("local_one"))
    }

    private func append(to url: URL, _ sessionId: String) throws {
        let line = "2026-09-12 22:35:00 [info] [CCD] LocalSessions.setFocusedSession: sessionId=\(sessionId)\n"
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(line.utf8))
    }

    // MARK: - Focusing

    /// The desktop app's link handler only accepts `local_` IDs, so anything else
    /// in a record must never make it into the URL.
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

    /// Sessions encoded before unread existed still decode — the widget reads
    /// this type out of the App Group and can be a build behind.
    @Test func sessionsWrittenBeforeUnreadStillDecode() throws {
        let json = """
        {"sessionId":"s","pid":1,"workingDirectory":"/tmp","projectName":"tmp","state":{"idle":{}},
         "lastActivityAt":0,"source":{"claudeDesktop":{}},"activity":""}
        """
        let session = try JSONDecoder().decode(ClaudeSession.self, from: Data(json.utf8))

        #expect(session.isUnread == nil)
    }
}
