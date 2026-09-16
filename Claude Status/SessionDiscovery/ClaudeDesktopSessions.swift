import AppKit
import Foundation

/// What the Claude desktop app records about one Claude Code session.
struct ClaudeDesktopSession: Equatable {
    /// The desktop app's own ID (`local_…`), which its deep link takes.
    let sessionId: String
    /// Epoch milliseconds, the way the desktop app stores them.
    let lastActivityAt: Double
    /// When the session was last opened in the app, or `nil` for the records
    /// that carry no stamp at all.
    let lastFocusedAt: Double?
    let isArchived: Bool
}

/// A desktop session as it was last seen running, and the transcript it writes to.
private struct RunningSession: Codable {
    let session: ClaudeSession
    let transcript: URL
}

/// Reads the Claude desktop app's own bookkeeping: how Claude Status learns a
/// desktop session's ID, and whether its last answer has been seen.
///
/// The layout — `claude-code-sessions/<account>/<organization>/local_<id>.json`,
/// tied to our sessions by `cliSessionId` — belongs to the desktop app, so every
/// lookup degrades to "no record" rather than failing.
struct ClaudeDesktopSessionStore {

    static let claudeDesktopBundleId = "com.anthropic.claudefordesktop"

    /// Where our own "you have seen this" marks live, in the App Group.
    static let seenKey = "claudeDesktopSeenAt"

    /// Where the sessions with an unread answer are saved, as last seen running.
    static let unreadSessionsKey = "claudeDesktopUnreadSessions"

    /// Both names the desktop app has used for its support directory.
    static var defaultRoots: [URL] {
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else {
            return []
        }
        return ["Claude-V2", "Claude"].map {
            support.appendingPathComponent($0).appendingPathComponent("claude-code-sessions")
        }
    }

    /// A machine can hold hundreds of records, so the directories are walked at
    /// most this often and a record is re-read only when its file changes.
    private static let scanInterval: TimeInterval = 2

    private let roots: [URL]
    private let defaults: UserDefaults?
    private let isDesktopAppInFront: @MainActor () -> Bool

    private var cache: [URL: (modified: Date, cliSessionId: String, session: ClaudeDesktopSession)] = [:]
    private var byCLISessionId: [String: ClaudeDesktopSession] = [:]
    private var focusLog: ClaudeDesktopFocusLog
    /// Epoch milliseconds, keyed by our session ID: when the user was last
    /// watching that session.
    private var seenAt: [String: Double]
    /// When Claude last answered, keyed by our session ID, with the transcript
    /// state it was read from.
    private var answers: [String: (transcript: URL, size: Int, modified: Date, answeredAt: Date?)] = [:]
    /// Desktop sessions as last seen running, keyed by our session ID.
    private var lastRunning: [String: RunningSession]
    private var savedUnreadIds: Set<String>
    private var lastScan: Date = .distantPast

    init(
        roots: [URL] = ClaudeDesktopSessionStore.defaultRoots,
        defaults: UserDefaults? = AppGroup.defaults,
        focusLog: ClaudeDesktopFocusLog = ClaudeDesktopFocusLog(),
        isDesktopAppInFront: @escaping @MainActor () -> Bool = {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                == ClaudeDesktopSessionStore.claudeDesktopBundleId
        }
    ) {
        self.roots = roots
        self.defaults = defaults
        self.focusLog = focusLog
        self.isDesktopAppInFront = isDesktopAppInFront
        self.seenAt = Self.loadSeen(from: defaults)
        self.lastRunning = Self.loadUnreadSessions(from: defaults)
        self.savedUnreadIds = Set(lastRunning.keys)
    }

    /// The desktop app's record for the session the hook reports as `cliSessionId`.
    func session(forCLISession cliSessionId: String) -> ClaudeDesktopSession? {
        byCLISessionId[cliSessionId]
    }

    mutating func refresh(force: Bool = false, now: Date = Date()) {
        // Walking the directories is the expensive part, and the only part worth
        // holding back. Tailing the log and stamping one mark cost a file open
        // and a dictionary compare, and skipping them would flash unread at a
        // user watching the answer land: the hook's own notification brings a
        // scan straight here, well inside the interval.
        if force || now.timeIntervalSince(lastScan) >= Self.scanInterval {
            lastScan = now
            readRecords()
        }
        focusLog.refresh()
        recordWhatIsBeingRead(now: now)
    }

    private mutating func readRecords() {
        var refreshed: [URL: (modified: Date, cliSessionId: String, session: ClaudeDesktopSession)] = [:]
        var index: [String: ClaudeDesktopSession] = [:]
        for file in recordFiles() {
            let modified = modificationDate(of: file)
            let entry: (modified: Date, cliSessionId: String, session: ClaudeDesktopSession)
            if let cached = cache[file], cached.modified == modified {
                entry = cached
            } else if let record = Self.read(file) {
                entry = (modified, record.cliSessionId, record.session)
            } else {
                continue
            }
            refreshed[file] = entry
            // The same session can be filed under two accounts, with the stale
            // copy carrying an older answer; the newer record wins.
            if let existing = index[entry.cliSessionId],
               existing.lastActivityAt > entry.session.lastActivityAt {
                continue
            }
            index[entry.cliSessionId] = entry.session
        }
        cache = refreshed
        byCLISessionId = index
        // Like the marks, answers go with sessions the app has dropped, and are
        // kept through a scan that lists nothing.
        if !index.isEmpty {
            answers = answers.filter { index[$0.key] != nil }
        }
    }

    /// Whether the desktop app has output here the user has not seen.
    ///
    /// The hook writes idle whenever a turn ends without a question, so an answer
    /// waiting to be read looks exactly like a session abandoned days ago. This
    /// separates the two, and deliberately does not touch the session's state:
    /// unread is not the same claim as "blocked on you", which is what the hook's
    /// own waiting state means.
    ///
    /// When Claude spoke comes from the session's transcript, the one place that
    /// records answers and nothing else. The record's `lastActivityAt` is
    /// throttled by the desktop app and can sit an hour behind, which would hold
    /// the answer back. The hook's `.cstatus` timestamp moves for more than
    /// answers: the app starts a session's process whenever the session is
    /// clicked, and can evict it again a minute later, and every start rewrites
    /// that file — so a session the user merely passed over would come back
    /// unread each time.
    mutating func isUnread(
        source: SessionSource,
        hookState: SessionState,
        cliSessionId: String,
        transcript: URL
    ) -> Bool {
        guard source == .claudeDesktop,
              hookState == .idle,
              let record = byCLISessionId[cliSessionId],
              let seen = lastSeen(cliSessionId, record: record),
              let answeredAt = lastAnswer(cliSessionId, in: transcript) else {
            return false
        }
        return answeredAt.timeIntervalSince1970 * 1000 > seen
    }

    // MARK: - Answers

    /// A turn's last answer is followed by bookkeeping — attachments, file
    /// snapshots, titles — so the transcript is read from the end in growing
    /// steps. Across 299 transcripts on the test machine the answer sat a median
    /// of 3 KB from the end and never more than 185 KB; one further back than the
    /// last step counts as no answer rather than a read of the whole file.
    private static let tailSizes: [UInt64] = [64_000, 256_000, 1_024_000]

    private static let assistantMarker = Data(#""assistant""#.utf8)

    /// The last answer in one session's transcript, read again only when the
    /// file changes.
    private mutating func lastAnswer(_ cliSessionId: String, in transcript: URL) -> Date? {
        // A URL keeps the values it looked up, which would hide the file growing.
        var file = transcript
        file.removeAllCachedResourceValues()
        let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard let size = values?.fileSize, let modified = values?.contentModificationDate else {
            return nil
        }
        if let cached = answers[cliSessionId], cached.transcript == transcript,
           cached.size == size, cached.modified == modified {
            return cached.answeredAt
        }
        let answeredAt = Self.lastAnswer(in: transcript)
        answers[cliSessionId] = (transcript, size, modified, answeredAt)
        return answeredAt
    }

    /// When Claude last answered in a Claude Code transcript: the timestamp of
    /// its last assistant line, or `nil` when there is none to find.
    ///
    /// Two kinds of assistant line are not answers. Subagents write their own
    /// (`isSidechain`). And a session resumed after a turn was cut off gets a
    /// placeholder from Claude Code itself, under the model `<synthetic>`, the
    /// moment the app starts it. The same model marks API errors, which do end a
    /// turn the user needs to see, so those still count.
    static func lastAnswer(in transcript: URL) -> Date? {
        guard let handle = try? FileHandle(forReadingFrom: transcript) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        for tailSize in tailSizes {
            let start = size > tailSize ? size - tailSize : 0
            guard (try? handle.seek(toOffset: start)) != nil,
                  let tail = try? handle.readToEnd() else {
                return nil
            }
            // Unless the read begins the file, its first line is cut off.
            for line in tail.split(separator: UInt8(ascii: "\n")).dropFirst(start == 0 ? 0 : 1).reversed() {
                if let answeredAt = answerDate(line) { return answeredAt }
            }
            if start == 0 { return nil }
        }
        return nil
    }

    /// The time on one transcript line, when that line is an answer.
    private static func answerDate(_ line: Data) -> Date? {
        // Most lines are not; those are skipped without being parsed.
        guard line.range(of: assistantMarker) != nil,
              let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              json["type"] as? String == "assistant",
              json["isSidechain"] as? Bool != true,
              let timestamp = json["timestamp"] as? String else {
            return nil
        }
        let model = (json["message"] as? [String: Any])?["model"] as? String
        if model == "<synthetic>", json["isApiErrorMessage"] as? Bool != true {
            return nil
        }
        return (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(timestamp))
            ?? (try? Date.ISO8601FormatStyle().parse(timestamp))
    }

    // MARK: - Seen

    /// Marks the session on screen as seen, so an answer the user watched arrive
    /// is not announced back to them the moment they look somewhere else.
    ///
    /// The app's own `lastFocusedAt` cannot carry this: it is stamped when a
    /// session is opened and then left alone, so a session read for an hour keeps
    /// an hour-old stamp while its activity climbs.
    private mutating func recordWhatIsBeingRead(now: Date) {
        var updated = seenAt
        if isDesktopAppInFront(), let open = onScreenCLISessionId() {
            updated[open] = now.timeIntervalSince1970 * 1000
        }
        // Sessions the app has dropped take their marks with them — but only
        // once it has listed some, so an unreadable directory cannot wipe them
        // and leave every session looking unread at once.
        if !byCLISessionId.isEmpty {
            updated = updated.filter { byCLISessionId[$0.key] != nil }
        }
        // This runs on every scan; the App Group is only written when a mark moved.
        guard updated != seenAt else { return }
        seenAt = updated
        defaults?.set(seenAt, forKey: Self.seenKey)
    }

    /// The session the app actually has on screen, as one of ours.
    ///
    /// The log is the only signal that can say "the app is up but showing
    /// something else". Without it the best guess is the session opened most
    /// recently, which cannot tell that apart and so keeps marking a session read
    /// long after the user has moved on — hence the fallback is only for a log
    /// that never spoke.
    private func onScreenCLISessionId() -> String? {
        switch focusLog.focus {
        case .session(let desktopSessionId):
            return byCLISessionId.first { $0.value.sessionId == desktopSessionId }?.key
        case .noSession:
            return nil
        case .unknown:
            return mostRecentlyOpenedCLISessionId()
        }
    }

    /// The last point we can show the user saw the session: our own mark from
    /// while it was on screen, or the app's stamp from when they opened it,
    /// whichever is later.
    ///
    /// `nil` when neither exists. Some records carry no focus stamp at all, and
    /// reading that as "never seen" would call every one of them unread.
    private func lastSeen(_ cliSessionId: String, record: ClaudeDesktopSession) -> Double? {
        [seenAt[cliSessionId], record.lastFocusedAt].compactMap { $0 }.max()
    }

    private func mostRecentlyOpenedCLISessionId() -> String? {
        // Ties break on the ID so the pick cannot flicker between two records.
        byCLISessionId
            .filter { $0.value.lastFocusedAt != nil }
            .max { ($0.value.lastFocusedAt ?? 0, $1.key) < ($1.value.lastFocusedAt ?? 0, $0.key) }?
            .key
    }

    private static func loadSeen(from defaults: UserDefaults?) -> [String: Double] {
        guard let stored = defaults?.dictionary(forKey: seenKey) else { return [:] }
        return stored.compactMapValues { ($0 as? NSNumber)?.doubleValue }
    }

    // MARK: - Stopped

    /// The transcript of the session a hook status file belongs to: the hook
    /// names its file after the transcript it sits beside.
    static func transcript(beside cstatusFile: URL) -> URL {
        cstatusFile.deletingPathExtension().appendingPathExtension("jsonl")
    }

    /// Desktop sessions whose process has stopped with an answer still unread.
    ///
    /// The desktop app evicts idle sessions' processes once it has too many open
    /// — often a minute or two after the user clicks away from one — or after
    /// half an hour untouched, and stops every one when it quits. The hook's `.cstatus` goes with the process, so
    /// an answer nobody has read would drop off the list just when it matters.
    /// What is kept is the session as last seen running, for as long as the
    /// running rule would still call it unread: it had finished its turn, it
    /// is not archived, and nobody has looked since. A session never seen
    /// running is not guessed at — applying the rule to every record instead
    /// raised sessions from weeks ago that the app does not show as unread.
    mutating func stoppedUnread(
        running: [ClaudeSession],
        cstatusFiles: [String: URL],
        projectsDirectories: [URL]
    ) -> [ClaudeSession] {
        for session in running {
            if session.source == .claudeDesktop, let file = cstatusFiles[session.sessionId] {
                lastRunning[session.sessionId] = RunningSession(
                    session: session, transcript: Self.transcript(beside: file)
                )
            } else {
                lastRunning[session.sessionId] = nil
            }
        }
        // A scan that lists no records can say nothing about any of them.
        guard !byCLISessionId.isEmpty else { return [] }
        let runningIds = Set(running.map(\.sessionId))
        var stopped: [ClaudeSession] = []
        for (id, last) in lastRunning where !runningIds.contains(id) {
            let tracked = projectsDirectories.contains { last.transcript.path.hasPrefix($0.path + "/") }
            guard tracked,
                  last.session.state == .idle,
                  byCLISessionId[id]?.isArchived == false,
                  isUnread(source: .claudeDesktop, hookState: .idle, cliSessionId: id, transcript: last.transcript)
            else {
                lastRunning[id] = nil
                continue
            }
            var session = last.session
            session.isUnread = true
            stopped.append(session)
        }
        saveUnreadSessions(lastRunning.values.filter {
            !runningIds.contains($0.session.sessionId) || $0.session.isUnread == true
        })
        return stopped.sorted { $0.sessionId < $1.sessionId }
    }

    /// Saves the sessions with an unread answer, running or not, so a relaunch
    /// still shows the ones the app stops meanwhile. Written only when that set
    /// changes.
    private mutating func saveUnreadSessions(_ sessions: [RunningSession]) {
        let ids = Set(sessions.map(\.session.sessionId))
        guard ids != savedUnreadIds else { return }
        savedUnreadIds = ids
        let sorted = sessions.sorted { $0.session.sessionId < $1.session.sessionId }
        defaults?.set(try? JSONEncoder().encode(sorted), forKey: Self.unreadSessionsKey)
    }

    private static func loadUnreadSessions(from defaults: UserDefaults?) -> [String: RunningSession] {
        guard let data = defaults?.data(forKey: unreadSessionsKey),
              let saved = try? JSONDecoder().decode([RunningSession].self, from: data) else {
            return [:]
        }
        return Dictionary(saved.map { ($0.session.sessionId, $0) }) { _, newer in newer }
    }

    // MARK: - Records

    private func recordFiles() -> [URL] {
        func children(of url: URL) -> [URL] {
            (try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.contentModificationDateKey]
            )) ?? []
        }
        return roots
            .flatMap(children)  // accounts
            .flatMap(children)  // organizations
            .flatMap(children)  // records
            .filter { $0.lastPathComponent.hasPrefix("local_") && $0.pathExtension == "json" }
    }

    private func modificationDate(of file: URL) -> Date {
        (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            ?? .distantPast
    }

    /// One record, or `nil` when it is not a session that can be keyed to ours.
    private static func read(_ file: URL) -> (cliSessionId: String, session: ClaudeDesktopSession)? {
        guard let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cliSessionId = json["cliSessionId"] as? String,
              let sessionId = json["sessionId"] as? String else {
            return nil
        }
        return (cliSessionId, ClaudeDesktopSession(
            sessionId: sessionId,
            lastActivityAt: (json["lastActivityAt"] as? NSNumber)?.doubleValue ?? 0,
            lastFocusedAt: (json["lastFocusedAt"] as? NSNumber)?.doubleValue,
            isArchived: json["isArchived"] as? Bool ?? false
        ))
    }
}
