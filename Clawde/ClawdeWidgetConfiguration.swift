import AppIntents
import WidgetKit

/// Configuration intent for the Clawde widget.
struct ClawdeWidgetConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Claude Sessions Widget"
    static var description = IntentDescription("Configure your Claude Code sessions widget.")
}
