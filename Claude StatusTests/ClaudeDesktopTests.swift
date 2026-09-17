import Foundation
import Testing
@testable import Claude_Status

/// Sessions run by the Claude desktop app: reading its records, telling an
/// answer nobody has read from an abandoned session, and the link that opens one.
@MainActor
struct ClaudeDesktopTests {

    /// Whether the Claude app is in front, as a switch a test can still flip
    /// after handing it to a store.
    @MainActor
    private final class FrontApp {
        var isClaude = true
    }

    private struct Record {
        let desktopId: String
        let cliId: String
        var lastActivityAt: Double = 1_000
        var lastFocusedAt: Double? = 2_000
        var isArchived = false
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
            if record.isArchived { json["isArchived"] = true }
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

    /// Whether the store calls the session unread when Claude's last answer in
    /// its transcript landed at `spokeAt`.
    private func unread(
        _ store: inout ClaudeDesktopSessionStore,
        _ cliSessionId: String,
        spokeAt: Double,
        hookState: SessionState = .idle,
        source: SessionSource = .claudeDesktop
    ) throws -> Bool {
        let transcript = try makeTranscript([transcriptLine("assistant", at: spokeAt)])
        defer { try? FileManager.default.removeItem(at: transcript) }
        return store.isUnread(
            source: source, hookState: hookState, cliSessionId: cliSessionId, transcript: transcript
        )
    }

    /// A Claude Code transcript made of `lines`, under a throwaway name.
    private func makeTranscript(_ lines: [String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcript-\(UUID().uuidString).jsonl")
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// One transcript line the way Claude Code writes it: compact JSON, stamped
    /// in UTC to the millisecond.
    private func transcriptLine(
        _ type: String,
        at milliseconds: Double,
        model: String = "claude-opus-5",
        text: String = "Done.",
        _ fields: [String: Any] = [:]
    ) throws -> String {
        var message: [String: Any] = ["role": type, "content": [["type": "text", "text": text]]]
        if type == "assistant" { message["model"] = model }
        var json = fields
        json["type"] = type
        json["timestamp"] = at(milliseconds).formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        json["message"] = message
        return String(decoding: try JSONSerialization.data(withJSONObject: json), as: UTF8.self)
    }

    private func append(line: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((line + "\n").utf8))
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

    @Test func survivesRootsThatAreNotThere() throws {
        var store = ClaudeDesktopSessionStore(
            roots: [URL(fileURLWithPath: "/nope/claude-code-sessions")],
            defaults: makeDefaults(),
            focusLog: ClaudeDesktopFocusLog(url: URL(fileURLWithPath: "/nope/main.log"))
        ) { true }
        store.refresh(force: true)

        #expect(store.session(forCLISession: "cli-one") == nil)
        #expect(try !unread(&store, "cli-one", spokeAt: 5_000))
    }

    // MARK: - Unread

    /// The case the signal exists for: Claude answered while the user was in
    /// another app, so nobody has read it.
    @Test func anAnswerTheUserWasAwayForIsUnread() throws {
        let root = try makeTwoSessionRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var store = ClaudeDesktopSessionStore(roots: [root], defaults: makeDefaults()) { false }
        store.refresh(force: true, now: at(9_600))

        #expect(try unread(&store, "cli-away", spokeAt: 3_000))
        // A session still working, one running anywhere else, and one the app has
        // no record of are never called unread.
        #expect(try !unread(&store, "cli-away", spokeAt: 3_000, hookState: .active))
        #expect(try !unread(&store, "cli-away", spokeAt: 3_000, hookState: .compacting))
        #expect(try !unread(&store, "cli-away", spokeAt: 3_000, source: .terminal(app: "Terminal")))
        #expect(try !unread(&store, "cli-none", spokeAt: 3_000))
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

        #expect(try !unread(&store, "cli-open", spokeAt: 9_500))
        // The session in the background is still unread.
        #expect(try unread(&store, "cli-away", spokeAt: 3_000))
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

        #expect(try unread(&store, "cli-open", spokeAt: 9_500))
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
        let front = FrontApp()
        var store = ClaudeDesktopSessionStore(
            roots: [root], defaults: makeDefaults(), focusLog: ClaudeDesktopFocusLog(url: log)
        ) { front.isClaude }
        store.refresh(force: true, now: at(10_000))  // read on screen

        front.isClaude = false
        store.refresh(force: true, now: at(20_000))  // user moves to another app

        #expect(try !unread(&store, "cli-open", spokeAt: 9_900))
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

        #expect(try !unread(&relaunched, "cli-open", spokeAt: 9_500))
        #expect(try unread(&relaunched, "cli-away", spokeAt: 3_000))
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

        #expect(try unread(&store, "cli-slow", spokeAt: 5_000))
        // And an answer older than the last look is still nothing to announce.
        #expect(try !unread(&store, "cli-slow", spokeAt: 1_500))
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
        #expect(try !unread(&store, "cli-nofocus", spokeAt: 9_000))
    }

    /// The failure that drove this whole signal, end to end: the user leaves the
    /// session for a plain chat in the same app. The app logs `null` twice in one
    /// second and then writes nothing more — gaps of an hour happen — so a clear
    /// that waits for another line never arrives and the session goes on being
    /// marked read while Claude answers in it.
    @Test func leavingASessionForAPlainChatStopsCountingAsReading() throws {
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
        #expect(try !unread(&store, "cli-open", spokeAt: 9_500))

        try append(to: log, "null")
        try append(to: log, "null")
        store.refresh(force: true, now: at(20_000))  // the app is still in front
        store.refresh(force: true, now: at(30_000))  // and writes nothing more

        #expect(try unread(&store, "cli-open", spokeAt: 25_000))
    }

    /// With no log to read — an older app, a quieter log level — the best guess
    /// left is the session opened most recently, which is what this did before
    /// the log existed. It must degrade to that rather than to "nothing is open".
    @Test func withoutTheLogTheLastOpenedSessionCountsAsOnScreen() throws {
        let root = try makeTwoSessionRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var store = ClaudeDesktopSessionStore(
            roots: [root], defaults: makeDefaults(),
            focusLog: ClaudeDesktopFocusLog(url: URL(fileURLWithPath: "/nope/main.log"))
        ) { true }
        store.refresh(force: true, now: at(10_000))

        #expect(try !unread(&store, "cli-open", spokeAt: 9_500))
        #expect(try unread(&store, "cli-away", spokeAt: 3_000))
    }

    /// A scan that lists nothing — an unreadable directory, a moved folder —
    /// must not wipe the marks and leave every session looking unread at once.
    @Test func marksSurviveAScanThatListsNothing() throws {
        let root = try makeTwoSessionRoot()
        let log = try makeFocusLog(["local_open"])
        let hidden = root.appendingPathExtension("moved")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: hidden)
            try? FileManager.default.removeItem(at: log)
        }
        var store = ClaudeDesktopSessionStore(
            roots: [root], defaults: makeDefaults(), focusLog: ClaudeDesktopFocusLog(url: log)
        ) { true }
        store.refresh(force: true, now: at(10_000))

        try FileManager.default.moveItem(at: root, to: hidden)
        store.refresh(force: true, now: at(20_000))
        try FileManager.default.moveItem(at: hidden, to: root)
        store.refresh(force: true, now: at(30_000))

        #expect(try !unread(&store, "cli-open", spokeAt: 9_500))
    }

    /// Clicking a session in the desktop app starts its process, and the app can
    /// evict it again a minute later. Every start rewrites the hook's file, and a
    /// session whose last turn was cut off also gets a placeholder answer from
    /// Claude Code — neither of which is anything new for the user to read.
    @Test func aSessionTheAppStartsAgainIsNotUnread() throws {
        let root = try makeSessionsRoot([
            Record(desktopId: "local_woken", cliId: "cli-woken", lastActivityAt: 1_000, lastFocusedAt: 2_000)
        ])
        let transcript = try makeTranscript([
            transcriptLine("assistant", at: 1_000),
            transcriptLine("user", at: 1_500, text: "[Request interrupted by user]"),
            // Written as the click starts the process, after the user has moved on.
            transcriptLine("assistant", at: 3_000, model: "<synthetic>", text: "No response requested."),
            #"{"type":"last-prompt","lastPrompt":"test"}"#
        ])
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: transcript)
        }
        var store = ClaudeDesktopSessionStore(roots: [root], defaults: makeDefaults()) { false }
        store.refresh(force: true, now: at(5_000))

        let woken = store.isUnread(
            source: .claudeDesktop, hookState: .idle, cliSessionId: "cli-woken", transcript: transcript
        )
        #expect(!woken)

        // A real answer after that is news again.
        try append(line: transcriptLine("assistant", at: 6_000), to: transcript)
        let answered = store.isUnread(
            source: .claudeDesktop, hookState: .idle, cliSessionId: "cli-woken", transcript: transcript
        )
        #expect(answered)
    }

    // MARK: - Stopped sessions

    /// A desktop session as discovery reports it while its process runs, filed
    /// under a throwaway `projects/` directory beside a transcript whose last
    /// answer landed at `answeredAt`.
    private func makeRunningSession(
        _ cliSessionId: String,
        answeredAt: Double,
        state: SessionState = .idle,
        isUnread: Bool = true
    ) throws -> (session: ClaudeSession, cstatusFile: URL, projects: URL) {
        let projects = FileManager.default.temporaryDirectory
            .appendingPathComponent("projects-\(UUID().uuidString)")
        let project = projects.appendingPathComponent("-tmp-project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let cstatusFile = project.appendingPathComponent("\(cliSessionId).cstatus")
        try (transcriptLine("assistant", at: answeredAt) + "\n").write(
            to: ClaudeDesktopSessionStore.transcript(beside: cstatusFile), atomically: true, encoding: .utf8
        )
        let session = ClaudeSession(
            sessionId: cliSessionId, pid: 4242, workingDirectory: "/tmp/project", projectName: "project",
            state: state, lastActivityAt: at(answeredAt), iTermSessionId: nil, tmuxPaneId: nil, tmuxSocket: nil,
            source: .claudeDesktop, activity: "", sessionName: nil, isUnread: isUnread
        )
        return (session, cstatusFile, projects)
    }

    /// The desktop app stops an idle session's process a minute or two after the
    /// user clicks away, and the hook's file goes with it. An answer nobody has
    /// read has to stay listed all the same.
    @Test func anUnreadSessionStaysListedAfterItsProcessStops() throws {
        let root = try makeSessionsRoot([
            Record(desktopId: "local_gone", cliId: "cli-gone", lastActivityAt: 3_000, lastFocusedAt: 2_000)
        ])
        let gone = try makeRunningSession("cli-gone", answeredAt: 3_000)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: gone.projects)
        }
        var store = ClaudeDesktopSessionStore(roots: [root], defaults: makeDefaults()) { false }
        store.refresh(force: true, now: at(4_000))

        let whileRunning = store.stoppedUnread(
            running: [gone.session], cstatusFiles: ["cli-gone": gone.cstatusFile],
            projectsDirectories: [gone.projects]
        )
        let afterStopping = store.stoppedUnread(running: [], cstatusFiles: [:], projectsDirectories: [gone.projects])

        #expect(whileRunning.isEmpty)
        #expect(afterStopping == [gone.session])
    }

    /// It stays only until it is read: opening the session stamps its record.
    @Test func aStoppedSessionLeavesOnceItIsRead() throws {
        let root = try makeSessionsRoot([
            Record(desktopId: "local_gone", cliId: "cli-gone", lastActivityAt: 3_000, lastFocusedAt: 2_000)
        ])
        let gone = try makeRunningSession("cli-gone", answeredAt: 3_000)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: gone.projects)
        }
        var store = ClaudeDesktopSessionStore(roots: [root], defaults: makeDefaults()) { false }
        store.refresh(force: true, now: at(4_000))
        _ = store.stoppedUnread(
            running: [gone.session], cstatusFiles: ["cli-gone": gone.cstatusFile],
            projectsDirectories: [gone.projects]
        )
        let beforeReading = store.stoppedUnread(running: [], cstatusFiles: [:], projectsDirectories: [gone.projects])

        try write(
            [Record(desktopId: "local_gone", cliId: "cli-gone", lastActivityAt: 3_000, lastFocusedAt: 5_000)],
            into: root, account: "account"
        )
        store.refresh(force: true, now: at(6_000))
        let afterReading = store.stoppedUnread(running: [], cstatusFiles: [:], projectsDirectories: [gone.projects])

        #expect(beforeReading.count == 1)
        #expect(afterReading.isEmpty)
    }

    /// Nothing is kept without a finished answer to read, as when the process
    /// stopped mid-turn, or once the user has put the session away: archived in
    /// the app, or in a profile that is no longer tracked.
    @Test func onlyAFinishedAnswerInATrackedSessionIsKept() throws {
        let root = try makeSessionsRoot([
            Record(desktopId: "local_busy", cliId: "cli-busy", lastActivityAt: 3_000, lastFocusedAt: 2_000),
            Record(
                desktopId: "local_archived", cliId: "cli-archived", lastActivityAt: 3_000, lastFocusedAt: 2_000,
                isArchived: true
            ),
            Record(desktopId: "local_untracked", cliId: "cli-untracked", lastActivityAt: 3_000, lastFocusedAt: 2_000)
        ])
        let busy = try makeRunningSession("cli-busy", answeredAt: 3_000, state: .active, isUnread: false)
        let archived = try makeRunningSession("cli-archived", answeredAt: 3_000)
        let untracked = try makeRunningSession("cli-untracked", answeredAt: 3_000)
        let running = [busy, archived, untracked]
        defer {
            try? FileManager.default.removeItem(at: root)
            for made in running { try? FileManager.default.removeItem(at: made.projects) }
        }
        var store = ClaudeDesktopSessionStore(roots: [root], defaults: makeDefaults()) { false }
        store.refresh(force: true, now: at(4_000))
        _ = store.stoppedUnread(
            running: running.map { $0.session },
            cstatusFiles: Dictionary(uniqueKeysWithValues: running.map { ($0.session.sessionId, $0.cstatusFile) }),
            projectsDirectories: running.map { $0.projects }
        )

        let stopped = store.stoppedUnread(
            running: [], cstatusFiles: [:], projectsDirectories: [busy.projects, archived.projects]
        )

        #expect(stopped.isEmpty)
    }

    /// A relaunch keeps them — including a session still running when Claude
    /// Status quit, and stopped before it started again.
    @Test func unreadSessionsOutliveARelaunch() throws {
        let root = try makeSessionsRoot([
            Record(desktopId: "local_gone", cliId: "cli-gone", lastActivityAt: 3_000, lastFocusedAt: 2_000)
        ])
        let gone = try makeRunningSession("cli-gone", answeredAt: 3_000)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: gone.projects)
        }
        let defaults = makeDefaults()
        var store = ClaudeDesktopSessionStore(roots: [root], defaults: defaults) { false }
        store.refresh(force: true, now: at(4_000))
        _ = store.stoppedUnread(
            running: [gone.session], cstatusFiles: ["cli-gone": gone.cstatusFile],
            projectsDirectories: [gone.projects]
        )

        var relaunched = ClaudeDesktopSessionStore(roots: [root], defaults: defaults) { false }
        relaunched.refresh(force: true, now: at(5_000))
        let stopped = relaunched.stoppedUnread(running: [], cstatusFiles: [:], projectsDirectories: [gone.projects])

        #expect(stopped == [gone.session])
    }

    // MARK: - Transcript

    /// Subagents and Claude Code itself write assistant lines too. The last answer
    /// is the last line that is neither, even while another is half written.
    @Test func theLastAnswerSkipsLinesThatAreNotAnswers() throws {
        let transcript = try makeTranscript([
            transcriptLine("assistant", at: 1_000),
            transcriptLine("assistant", at: 2_000, ["isSidechain": true]),
            transcriptLine("assistant", at: 3_000, model: "<synthetic>", text: "No response requested."),
            transcriptLine("user", at: 4_000),
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"te"#
        ])
        // An API error comes from Claude Code as well, but it does end the turn.
        let failed = try makeTranscript([
            transcriptLine("assistant", at: 1_000),
            transcriptLine(
                "assistant", at: 2_000, model: "<synthetic>", text: "API Error: 529 Overloaded",
                ["isApiErrorMessage": true]
            )
        ])
        defer {
            try? FileManager.default.removeItem(at: transcript)
            try? FileManager.default.removeItem(at: failed)
        }

        #expect(ClaudeDesktopSessionStore.lastAnswer(in: transcript) == at(1_000))
        #expect(ClaudeDesktopSessionStore.lastAnswer(in: failed) == at(2_000))
    }

    /// Attachments and file snapshots can pile up after the answer, well past the
    /// first read, which has to reach back for it.
    @Test func anAnswerBehindALongTailIsFound() throws {
        let attachment = #"{"type":"attachment","content":""# + String(repeating: "x", count: 100_000) + #""}"#
        let transcript = try makeTranscript(
            [transcriptLine("assistant", at: 1_000)] + Array(repeating: attachment, count: 3)
        )
        let unanswered = try makeTranscript([transcriptLine("user", at: 1_000)])
        defer {
            try? FileManager.default.removeItem(at: transcript)
            try? FileManager.default.removeItem(at: unanswered)
        }

        #expect(ClaudeDesktopSessionStore.lastAnswer(in: transcript) == at(1_000))
        #expect(ClaudeDesktopSessionStore.lastAnswer(in: unanswered) == nil)
        #expect(ClaudeDesktopSessionStore.lastAnswer(in: unanswered.appendingPathExtension("gone")) == nil)
    }

    // MARK: - Remote Control

    /// A session started outside the app with Remote Control is bridged, and the
    /// transcript says to which session the app shows it as. Reading it again
    /// once the file changes catches a bridge made after the session started.
    @Test func aBridgedTranscriptNamesItsRemoteSession() throws {
        let transcript = try makeTranscript([transcriptLine("assistant", at: 1_000)])
        let malformed = try makeTranscript([
            #"{"type":"bridge-session","sessionId":"cli-x","bridgeSessionId":"cse_../../etc"}"#
        ])
        defer {
            try? FileManager.default.removeItem(at: transcript)
            try? FileManager.default.removeItem(at: malformed)
        }
        var store = ClaudeDesktopSessionStore(roots: [], defaults: makeDefaults()) { false }
        let beforeBridging = store.remoteSessionId("cli-x", transcript: transcript)

        try append(
            line: #"{"type":"bridge-session","sessionId":"cli-x","bridgeSessionId":"cse_018TJSkQZbYQzh9igkcYjrte"}"#,
            to: transcript
        )
        try append(line: transcriptLine("user", at: 2_000), to: transcript)
        let afterBridging = store.remoteSessionId("cli-x", transcript: transcript)

        #expect(beforeBridging == nil)
        #expect(afterBridging == "session_018TJSkQZbYQzh9igkcYjrte")
        #expect(ClaudeDesktopSessionStore.remoteSessionId(inTranscript: malformed) == nil)
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

    @Test func aHeldNullSettlesEvenIfTheAppWritesNothingMore() throws {
        let log = try makeFocusLog(["local_one"])
        defer { try? FileManager.default.removeItem(at: log) }
        var reader = ClaudeDesktopFocusLog(url: log)
        reader.refresh()

        try append(to: log, "null")
        reader.refresh()
        #expect(reader.focus == .session("local_one"))  // held for one scan

        reader.refresh()  // no new bytes at all
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

    /// A session shown through Remote Control has a link of its own, which takes
    /// only the app's `session_` IDs.
    @Test func linksToRemoteSessionsOnlyByTheirIds() {
        #expect(
            SessionFocuser.claudeDesktopURL(forRemoteSession: "session_018TJSkQZbYQzh9igkcYjrte")?.absoluteString
                == "claude://code/session_018TJSkQZbYQzh9igkcYjrte"
        )
        #expect(SessionFocuser.claudeDesktopURL(forRemoteSession: "local_2222-bbbb") == nil)
        #expect(SessionFocuser.claudeDesktopURL(forRemoteSession: "session_x/../continue") == nil)
        #expect(SessionFocuser.claudeDesktopURL(forRemoteSession: "session_") == nil)
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
        #expect(session.remoteSessionId == nil)
    }
}
