import AppKit
import Foundation

/// What the Claude desktop app records about one Claude Code session.
struct ClaudeDesktopSession: Equatable {
    /// The desktop app's own ID (`local_…`), which its deep link takes.
    let sessionId: String
    /// Epoch milliseconds, the way the desktop app stores them.
    let lastActivityAt: Double
    /// Stamped when the app brings the session up, not while it is being read.
    let lastFocusedAt: Double
}

/// Reads the Claude desktop app's session records: how Claude Status learns a
/// desktop session's own ID, and whether its last answer has been seen.
///
/// The layout — `claude-code-sessions/<account>/<organization>/local_<id>.json`,
/// tied to our sessions by `cliSessionId` — belongs to the desktop app, so every
/// lookup degrades to "no record" rather than failing.
struct ClaudeDesktopSessionStore {

    static let claudeDesktopBundleId = "com.anthropic.claudefordesktop"

    /// Where our own "you have seen this" stamps live, in the App Group.
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
    /// Epoch milliseconds, keyed by our session ID: when the user was last
    /// watching that session.
    private var seenAt: [String: Double]
    private var lastScan: Date = .distantPast

    init(
        roots: [URL] = ClaudeDesktopSessionStore.defaultRoots,
        defaults: UserDefaults? = AppGroup.defaults,
        isDesktopAppInFront: @escaping @MainActor () -> Bool = {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                == ClaudeDesktopSessionStore.claudeDesktopBundleId
        }
    ) {
        self.roots = roots
        self.defaults = defaults
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
            if let cached = cache[file], cached.modified == modified {
                refreshed[file] = cached
                index[cached.cliSessionId] = cached.session
                continue
            }
            guard let record = Self.read(file) else { continue }
            refreshed[file] = (modified, record.cliSessionId, record.session)
            index[record.cliSessionId] = record.session
        }
        cache = refreshed
        byCLISessionId = index
        recordWhatIsBeingRead(now: now)
    }

    /// The state to show for a session the hook reported as `hookState`.
    ///
    /// A desktop session that has spoken since the user last saw it is their
    /// move, not idle: the hook writes idle whenever a turn ends without a
    /// question, so an answer nobody has read looks exactly like a session
    /// abandoned days ago.
    func resolvedState(
        hookState: SessionState,
        source: SessionSource,
        cliSessionId: String
    ) -> SessionState {
        guard source == .claudeDesktop,
              hookState == .idle,
              let session = byCLISessionId[cliSessionId],
              session.lastActivityAt > lastSeen(cliSessionId) else {
            return hookState
        }
        return .waiting
    }

    // MARK: - Seen

    /// Marks the session on screen as seen, so an answer the user watched land
    /// is not announced back to them the moment they look somewhere else.
    ///
    /// The desktop app's own `lastFocusedAt` cannot carry this: it is stamped
    /// when a session is brought up and then left alone, so a session being read
    /// for an hour keeps an hour-old stamp while its activity climbs. This runs
    /// on the scan the app already does, which is often enough — the answer the
    /// user is watching arrives on a file change that triggers one.
    ///
    /// The app being in front is taken as reading the session it last focused.
    /// Someone sitting on its settings screen is counted as reading too, which
    /// costs a mark the user might have wanted and never raises a false one.
    private mutating func recordWhatIsBeingRead(now: Date) {
        var updated = seenAt
        if isDesktopAppInFront(), let open = focusedCLISessionId() {
            updated[open] = now.timeIntervalSince1970 * 1000
        }
        // Sessions the app has dropped take their stamps with them — but only
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

    /// The last point we can show the user saw the session: our own stamp from
    /// while it was on screen, or the app's focus stamp, whichever is later.
    private func lastSeen(_ cliSessionId: String) -> Double {
        max(seenAt[cliSessionId] ?? 0, byCLISessionId[cliSessionId]?.lastFocusedAt ?? 0)
    }

    /// The session the app has up: the last one it focused.
    private func focusedCLISessionId() -> String? {
        // Ties break on the ID so the pick cannot flicker between two records.
        byCLISessionId
            .max { ($0.value.lastFocusedAt, $1.key) < ($1.value.lastFocusedAt, $0.key) }?
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
            lastFocusedAt: (json["lastFocusedAt"] as? NSNumber)?.doubleValue ?? 0
        ))
    }
}
