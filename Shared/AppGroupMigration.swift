import Foundation

/// Carries what the app kept under its old identifiers into the new ones, once.
///
/// The App Group holds everything the user set and everything the app learned —
/// the pet's place on screen, which sessions have been seen, the productivity
/// history — and it is keyed on an identifier that the rename changed. Without
/// this, an update would look like a fresh install.
///
/// The old group is read through its own defaults suite and its own container
/// directory rather than an entitlement: the app is not sandboxed, and a group
/// this app no longer claims could not be signed for anyway.
nonisolated enum AppGroupMigration {

    /// Written once the old container has been looked at, whether or not there
    /// was anything in it, so this runs exactly once.
    static let flagKey = "carriedOverFromClaudeStatus"

    /// Where the app kept things before the rename, in the order they are
    /// looked for: the team-prefixed group development builds use, then the
    /// release group.
    static let legacyIdentifiers = [
        "TXQN7T6NNQ.com.poisonpenllc.Claude-Status",
        "group.com.poisonpenllc.Claude-Status",
    ]

    /// Everything the user set, and the marks the app cannot work out again.
    static let keys = [
        "iconStyle",
        "claudeProfiles",
        "countQuestionsAsWaiting",
        "claudeDesktopSeenAt",
        "claudeDesktopUnreadSessions",
        "petEnabled",
        "petSize",
        "petBubbleMode",
        "petEmptyBehavior",
        "petCharacter",
        "petPosition",
    ]

    /// What the app and the widget exchange through the container.
    static let files = ["sessions.json", "productivity.json"]

    static var groupContainers: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers", isDirectory: true)
    }

    /// Copies the first old group that is there, and never runs again.
    ///
    /// Nothing already set under the new identifier is overwritten: a user who
    /// has changed something since the update keeps their change.
    static func run(
        into defaults: UserDefaults? = AppGroup.defaults,
        container: URL? = AppGroup.containerURL,
        legacyIdentifiers: [String] = legacyIdentifiers,
        groupContainers: URL = groupContainers
    ) {
        guard let defaults, !defaults.bool(forKey: flagKey) else { return }
        defaults.set(true, forKey: flagKey)

        for identifier in legacyIdentifiers {
            // macOS keeps a group's container to the apps entitled to it, which is
            // why the old identifiers are still in the entitlements: asking for the
            // container is what makes it readable. Both places are tried, because a
            // test points the search somewhere else entirely.
            let places = [
                FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier),
                groupContainers.appendingPathComponent(identifier, isDirectory: true),
            ].compactMap { $0 }
            let carriedDefaults = carryDefaults(from: identifier, into: defaults)
            let carriedFiles = places.contains { carryFiles(from: $0, into: container) }
            if carriedDefaults || carriedFiles {
                return
            }
        }
    }

    /// Copies every key the old group holds that the new one does not.
    @discardableResult
    private static func carryDefaults(from identifier: String, into defaults: UserDefaults) -> Bool {
        guard let old = UserDefaults(suiteName: identifier) else { return false }
        var carried = false
        for key in keys where defaults.object(forKey: key) == nil {
            guard let value = old.object(forKey: key) else { continue }
            defaults.set(value, forKey: key)
            carried = true
        }
        return carried
    }

    @discardableResult
    private static func carryFiles(from old: URL, into container: URL?) -> Bool {
        guard let container else { return false }
        var carried = false
        for file in files {
            let source = old.appendingPathComponent(file)
            let destination = container.appendingPathComponent(file)
            guard FileManager.default.fileExists(atPath: source.path),
                  !FileManager.default.fileExists(atPath: destination.path) else {
                continue
            }
            try? FileManager.default.copyItem(at: source, to: destination)
            carried = true
        }
        return carried
    }
}
