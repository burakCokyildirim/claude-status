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
    }

    /// The desktop app's record for the session the hook reports as `cliSessionId`.
    func session(forCLISession cliSessionId: String) -> ClaudeDesktopSession? {
        byCLISessionId[cliSessionId]
    }

    mutating func refresh(force: Bool = false, now: Date = Date()) {
        guard force || now.timeIntervalSince(lastScan) >= Self.scanInterval else { return }
        lastScan = now

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

        focusLog.refresh()
        recordWhatIsBeingRead(now: now)
    }

    /// Whether the desktop app has output here the user has not seen.
    ///
    /// The hook writes idle whenever a turn ends without a question, so an answer
    /// waiting to be read looks exactly like a session abandoned days ago. This
    /// separates the two, and deliberately does not touch the session's state:
    /// unread is not the same claim as "blocked on you", which is what the hook's
    /// own waiting state means.
    ///
    /// When Claude spoke comes from the hook's `.cstatus` timestamp, not from the
    /// record's `lastActivityAt`: the desktop app throttles that field and can
    /// leave it an hour behind, which would hold the answer back.
    func isUnread(
        source: SessionSource,
        hookState: SessionState,
        cliSessionId: String,
        lastSpokeAt: Date
    ) -> Bool {
        guard source == .claudeDesktop,
              hookState == .idle,
              let record = byCLISessionId[cliSessionId],
              let seen = lastSeen(cliSessionId, record: record) else {
            return false
        }
        return lastSpokeAt.timeIntervalSince1970 * 1000 > seen
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
            lastFocusedAt: (json["lastFocusedAt"] as? NSNumber)?.doubleValue
        ))
    }
}
