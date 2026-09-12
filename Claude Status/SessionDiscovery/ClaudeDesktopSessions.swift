import Foundation

/// What the Claude desktop app records about one Claude Code session.
struct ClaudeDesktopSession: Equatable {
    /// The desktop app's own ID (`local_…`), which its deep link takes.
    let sessionId: String
    /// Epoch milliseconds, the way the desktop app stores them.
    let lastActivityAt: Double
    let lastFocusedAt: Double

    /// The session moved after the user last looked at it.
    var isUnread: Bool { lastActivityAt > lastFocusedAt }
}

/// Reads the Claude desktop app's session records: how Claude Status learns a
/// desktop session's own ID, and whether it has gone unread.
///
/// The layout — `claude-code-sessions/<account>/<organization>/local_<id>.json`,
/// tied to our sessions by `cliSessionId` — belongs to the desktop app, so every
/// lookup degrades to "no record" rather than failing.
struct ClaudeDesktopSessionStore {

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
    private var cache: [URL: (modified: Date, cliSessionId: String, session: ClaudeDesktopSession)] = [:]
    private var byCLISessionId: [String: ClaudeDesktopSession] = [:]
    /// The session the app focused last — the one on screen, as near as these
    /// records can say.
    private var frontmostCLISessionId: String?
    private var lastScan: Date = .distantPast

    init(roots: [URL] = ClaudeDesktopSessionStore.defaultRoots) {
        self.roots = roots
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
        // Ties break on the ID so the pick cannot flicker between two records.
        frontmostCLISessionId = index
            .max { ($0.value.lastFocusedAt, $1.key) < ($1.value.lastFocusedAt, $0.key) }?
            .key
    }

    /// The state to show for a session the hook reported as `hookState`.
    ///
    /// A finished desktop session the user has not looked at since is their
    /// move, not idle: the hook writes idle whenever a turn ends without a
    /// question, so the unread mark is the only thing separating the two.
    ///
    /// The session in front is never counted unread, however loudly its record
    /// says so. `lastFocusedAt` is stamped when the app brings a session up and
    /// then left alone, while `lastActivityAt` keeps climbing as Claude works —
    /// so the session being read right now reads as unread the whole time it is
    /// open, which would put a "waiting" on the one session that plainly is not.
    func resolvedState(
        hookState: SessionState,
        source: SessionSource,
        cliSessionId: String
    ) -> SessionState {
        guard source == .claudeDesktop,
              hookState == .idle,
              cliSessionId != frontmostCLISessionId,
              session(forCLISession: cliSessionId)?.isUnread == true else {
            return hookState
        }
        return .waiting
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
