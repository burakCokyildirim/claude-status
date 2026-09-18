import WidgetKit
import SwiftUI

/// Widget bundle containing all Clawde widgets.
@main
@MainActor
struct ClawdeWidgetBundle: WidgetBundle {
    var body: some Widget {
        ClawdeStatusWidget()
        Claude_ProductivityWidget()
        Claude_ScoreWidget()
    }
}

/// The main Clawde widget displaying Claude Code session information.
@MainActor
struct ClawdeStatusWidget: Widget {
    let kind: String = "ClawdeStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClawdeTimelineProvider()) { entry in
            ClawdeWidgetEntryView(entry: entry)
                .padding(.trailing, 4)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Claude Sessions")
        .description("Monitor active Claude Code sessions")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

#Preview(as: .systemMedium) {
    ClawdeStatusWidget()
} timeline: {
    SessionEntry(date: .now, sessions: [
        ClaudeSession(
            sessionId: "preview-1",
            pid: 12345,
            workingDirectory: "/Users/test/Projects/Example",
            projectName: "Example",
            state: .active,
            lastActivityAt: Date().addingTimeInterval(-120),
            iTermSessionId: nil,
            tmuxPaneId: nil,
            tmuxSocket: nil,
            source: .terminal(app: "iTerm2"),
            activity: "Edit",
            sessionName: "API Refactor"
        ),
        ClaudeSession(
            sessionId: "preview-2",
            pid: 12346,
            workingDirectory: "/Users/test/Projects/Another",
            projectName: "Another",
            state: .waiting,
            lastActivityAt: Date().addingTimeInterval(-180),
            iTermSessionId: nil,
            tmuxPaneId: nil,
            tmuxSocket: nil,
            source: .vscode,
            activity: "",
            sessionName: nil
        ),
    ])
}

#Preview(as: .systemLarge) {
    ClawdeStatusWidget()
} timeline: {
    SessionEntry(date: .now, sessions: [
        ClaudeSession(
            sessionId: "preview-1",
            pid: 12345,
            workingDirectory: "/Users/test/Projects/Example",
            projectName: "Example",
            state: .active,
            lastActivityAt: Date().addingTimeInterval(-120),
            iTermSessionId: nil,
            tmuxPaneId: nil,
            tmuxSocket: nil,
            source: .terminal(app: "iTerm2"),
            activity: "Edit",
            sessionName: "API Refactor"
        ),
        ClaudeSession(
            sessionId: "preview-2",
            pid: 12346,
            workingDirectory: "/Users/test/Projects/Another",
            projectName: "Another Project",
            state: .waiting,
            lastActivityAt: Date().addingTimeInterval(-180),
            iTermSessionId: nil,
            tmuxPaneId: nil,
            tmuxSocket: nil,
            source: .vscode,
            activity: "",
            sessionName: nil
        ),
        ClaudeSession(
            sessionId: "preview-3",
            pid: 12347,
            workingDirectory: "/Users/test/Projects/Backend",
            projectName: "Backend API",
            state: .active,
            lastActivityAt: Date().addingTimeInterval(-30),
            iTermSessionId: nil,
            tmuxPaneId: nil,
            tmuxSocket: nil,
            source: .terminal(app: "Ghostty"),
            activity: "Bash",
            sessionName: nil
        ),
        ClaudeSession(
            sessionId: "preview-4",
            pid: 12348,
            workingDirectory: "/Users/test/Projects/Frontend",
            projectName: "Frontend App",
            state: .idle,
            lastActivityAt: Date().addingTimeInterval(-3600),
            iTermSessionId: nil,
            tmuxPaneId: nil,
            tmuxSocket: nil,
            source: .terminal(app: "Terminal"),
            activity: "",
            sessionName: nil
        ),
        ClaudeSession(
            sessionId: "preview-5",
            pid: 12349,
            workingDirectory: "/Users/test/Projects/Infra",
            projectName: "Infrastructure",
            state: .compacting,
            lastActivityAt: Date().addingTimeInterval(-45),
            iTermSessionId: nil,
            tmuxPaneId: nil,
            tmuxSocket: nil,
            source: .jetbrains(ide: "IntelliJ"),
            activity: "",
            sessionName: nil
        ),
    ])
}
