import Foundation

/// The App Group shared between the main app and the widget extension.
///
/// The identifier is injected at build time via the `APP_GROUP_ID` build setting
/// (exposed through Info.plist), so a development build can substitute a
/// team-prefixed group (e.g. `TEAMID.com.burakcokyildirim.clawde`) that macOS
/// accepts without a provisioning profile. Falls back to the release identifier.
nonisolated enum AppGroup {

    static let identifier: String = {
        if let id = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String,
           !id.isEmpty {
            return id
        }
        return "group.com.burakcokyildirim.clawde"
    }()

    /// Shared defaults suite backed by the app group.
    static let defaults = UserDefaults(suiteName: identifier)

    /// Shared container directory for files exchanged with the widget.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}
