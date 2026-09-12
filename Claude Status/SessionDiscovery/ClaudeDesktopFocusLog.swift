import Foundation

/// Which Claude Code session the Claude desktop app currently has on screen,
/// read from the app's own log.
///
/// The app records every switch itself — `LocalSessions.setFocusedSession:
/// sessionId=local_…`, and `sessionId=null` when what it is showing is not a
/// Claude Code session at all: a plain chat, its settings, its home screen.
/// Nothing else reachable from outside draws that line. The per-session records
/// say which session was opened last but never whether one is still up, so they
/// cannot tell "reading this session" from "in the app, looking at something
/// else"; window titles could, but only with Screen Recording, which this app
/// has no other reason to ask for.
///
/// The log is only ever appended to, so each scan reads the bytes added since
/// the last one.
struct ClaudeDesktopFocusLog {

    /// What the log says is on screen.
    enum Focus: Equatable {
        /// The log has not said — no file, an older app, a quieter log level.
        /// Callers keep whatever they would have done without it.
        case unknown
        /// The app is showing something that is not a Claude Code session.
        case noSession
        /// The desktop app's own session ID, `local_…`.
        case session(String)
    }

    static var defaultURL: URL? {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs/Claude/main.log")
    }

    /// How far back the first read looks. The app keeps days of lines in one
    /// file; the switch we want is always near the end, and reading megabytes to
    /// find it would cost more than the answer is worth.
    private static let firstReadTail: UInt64 = 256 * 1024

    private static let marker = "setFocusedSession: sessionId="

    private let url: URL?
    private var offset: UInt64 = 0
    private var pendingClear = false

    private(set) var focus: Focus = .unknown

    init(url: URL? = ClaudeDesktopFocusLog.defaultURL) {
        self.url = url
    }

    mutating func refresh() {
        guard let url, let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        // A log that shrank was rotated or replaced; start over rather than
        // seeking past the end of the new one.
        if size < offset { offset = 0 }
        if offset == 0, size > Self.firstReadTail { offset = size - Self.firstReadTail }
        guard size > offset else { return }

        try? handle.seek(toOffset: offset)
        guard let data = try? handle.read(upToCount: Int(size - offset)), !data.isEmpty else { return }
        offset = size
        apply(String(decoding: data, as: UTF8.self))
    }

    private mutating func apply(_ chunk: String) {
        var newest: Focus?
        for line in chunk.split(separator: "\n") {
            guard let marker = line.range(of: Self.marker) else { continue }
            let value = line[marker.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if value == "null" {
                newest = .noSession
            } else if Self.isSessionId(value) {
                newest = .session(value)
            }
        }
        guard let newest else { return }

        // Switching sessions is logged as `null` and then the new ID, so a
        // `null` is only believed once it is still the last word on the next
        // scan. Acting on the gap would blink every session to unread.
        if case .noSession = newest, case .session = focus, !pendingClear {
            pendingClear = true
            return
        }
        pendingClear = false
        focus = newest
    }

    private static func isSessionId(_ value: String) -> Bool {
        let suffix = value.dropFirst("local_".count)
        return value.hasPrefix("local_")
            && (1...64).contains(suffix.count)
            && suffix.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }
}
