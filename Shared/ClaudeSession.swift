import Foundation

/// Represents the current state of a Claude Code session.
enum SessionState: Comparable, Codable {
    case active
    case waiting
    case idle
    case compacting

    /// String key used in ProductivityStats.timeInState dictionaries.
    var key: String {
        switch self {
        case .active: "active"
        case .waiting: "waiting"
        case .idle: "idle"
        case .compacting: "compacting"
        }
    }

    var sfSymbol: String {
        switch self {
        case .active: "circle.fill"
        case .waiting: "circle.fill"
        case .idle: "circle"
        case .compacting: "arrow.triangle.2.circlepath"
        }
    }

    var colorName: String {
        switch self {
        case .active: "green"
        case .waiting: "yellow"
        case .idle: "gray"
        case .compacting: "blue"
        }
    }

    var emoji: String {
        switch self {
        case .active: "\u{26A1}"
        case .waiting: "\u{23F3}"
        case .idle: "\u{1F4A4}"
        case .compacting: "\u{1F9F9}"
        }
    }

    var label: String {
        switch self {
        case .active: "Active"
        case .waiting: "Waiting"
        case .idle: "Idle"
        case .compacting: "Compacting"
        }
    }

    /// Priority for aggregate status (higher = more urgent).
    var priority: Int {
        switch self {
        case .waiting: 3
        case .active: 2
        case .compacting: 1
        case .idle: 0
        }
    }

    /// Sort order for display (lower = appears first).
    /// Waiting (needs input) > Active (working) > Compacting > Idle.
    var sortOrder: Int {
        switch self {
        case .waiting: 0
        case .active: 1
        case .compacting: 2
        case .idle: 3
        }
    }
}

/// Where a Claude session is running.
enum SessionSource: Codable, Equatable {
    case terminal(app: String)  // e.g. "iTerm2", "Terminal", "Ghostty"
    case xcode
    case vscode
    case jetbrains(ide: String)  // e.g. "PyCharm", "IntelliJ IDEA"
    case zed
    case claudeDesktop  // Claude Code in the Claude desktop app

    var label: String {
        switch self {
        case .terminal(let app): app
        case .xcode: "Xcode"
        case .vscode: "VS Code"
        case .jetbrains(let ide): ide
        case .zed: "Zed"
        case .claudeDesktop: "Claude"
        }
    }

    /// Whether this is a terminal session (not an IDE-embedded agent).
    var isTerminal: Bool {
        if case .terminal = self { return true }
        return false
    }

    /// Whether this is any JetBrains IDE.
    var isJetBrains: Bool {
        if case .jetbrains = self { return true }
        return false
    }
}

/// A discovered Claude Code session on the local machine.
struct ClaudeSession: Identifiable, Codable, Equatable {
    /// The session UUID from Claude Code (stable across refreshes).
    let sessionId: String
    let pid: pid_t
    let workingDirectory: String
    let projectName: String
    let state: SessionState
    let lastActivityAt: Date
    let iTermSessionId: String?
    /// tmux pane ID (e.g. "%5") when session runs inside tmux.
    let tmuxPaneId: String?
    /// tmux socket path for targeting the correct server.
    let tmuxSocket: String?
    let source: SessionSource
    /// Current activity description (e.g. tool name, "thinking", "subagent").
    /// Empty string when no specific activity is known.
    let activity: String
    /// Optional custom session name set by the user via /name-session.
    let sessionName: String?
    /// Display name of the Claude Code profile (config dir) this session belongs to.
    /// Nil for data written before profile support.
    var profileName: String? = nil
    /// Claude has spoken here since the user last had the session in front of
    /// them. Its own signal rather than a state: unread says something is here
    /// to read, while `waiting` says the session is blocked until the user
    /// answers. Optional so data written before it still decodes.
    var isUnread: Bool? = nil
    /// The Remote Control session this process is bridged to, as the Claude
    /// desktop app names it (`session_…`). Set only for a session no terminal or
    /// IDE owns, which the user reaches through the app instead. Optional so data
    /// written before it still decodes.
    var remoteSessionId: String? = nil

    /// Use sessionId as the SwiftUI identity (stable, unlike PIDs).
    var id: String { sessionId }

    /// Relative time since last activity, human-readable.
    var timeSinceActivity: String {
        let interval = Date().timeIntervalSince(lastActivityAt)
        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return "\(mins)m ago"
        } else {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        }
    }

    /// Deep link URL for focusing this session from the widget.
    var deepLinkURL: URL {
        var components = URLComponents()
        components.scheme = "clawde"
        components.host = "session"
        components.path = "/\(id)"
        return components.url ?? URL(string: "clawde://session/unknown")!
    }
}

extension ClaudeSession {
    /// Ordering for the surfaces that show unread — the pet and the popover.
    ///
    /// Unread sits between waiting and active: an answer nobody has read wants
    /// the user more than a session busy working, and less than one that has
    /// stopped and cannot go on until they reply. Kept apart from
    /// `sortedByStateAndActivity`, which the widget uses and which groups
    /// strictly by state.
    var attentionRank: Int {
        if state == .waiting { return 0 }
        if isUnread == true { return 1 }
        return state.sortOrder + 1
    }
}

extension Array where Element == ClaudeSession {
    /// Sessions sorted by state (Waiting, Active, Compacting, Idle), then most recent first.
    var sortedByStateAndActivity: [ClaudeSession] {
        sorted {
            if $0.state.sortOrder != $1.state.sortOrder {
                return $0.state.sortOrder < $1.state.sortOrder
            }
            return $0.lastActivityAt > $1.lastActivityAt
        }
    }
}
