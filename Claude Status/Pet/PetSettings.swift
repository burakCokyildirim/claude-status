import Foundation

/// How large the pet is drawn, as an integer scale of the sprite grid.
enum PetSize: String, CaseIterable {
    case small
    case medium
    case large

    var label: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    /// Points per sprite pixel. Kept integral so the pixel art stays crisp.
    var scale: CGFloat {
        switch self {
        case .small: 3
        case .medium: 4
        case .large: 5
        }
    }
}

/// When the pet shows its speech bubble.
enum PetBubbleMode: String, CaseIterable {
    case always
    case hover
    case never

    var label: String {
        switch self {
        case .always: "Always"
        case .hover: "On Hover"
        case .never: "Never"
        }
    }
}

/// What the pet does while no Claude Code sessions are running.
enum PetEmptyBehavior: String, CaseIterable {
    case rest
    case hide

    var label: String {
        switch self {
        case .rest: "Show Resting Pet"
        case .hide: "Hide Pet"
        }
    }
}

/// Which character the pet is drawn as.
enum PetCharacterID: String, CaseIterable {
    case nibble
    case lint
    case kernel

    var label: String {
        switch self {
        case .nibble: "Nibble"
        case .lint: "Lint"
        case .kernel: "Kernel"
        }
    }

    /// One-line personality blurb, shown under the picker.
    var blurb: String {
        switch self {
        case .nibble: "A tidy little bot, one bite short of a byte."
        case .lint: "A fuzzball that cannot leave a mess alone."
        case .kernel: "Quiet until it isn't. Then it pops."
        }
    }
}

/// A snapshot of the desktop pet's settings, read from the App Group defaults.
///
/// A value rather than an observable object, matching how `iconStyle` already
/// works in this app: `SettingsView` writes through `@AppStorage`, and
/// `AppDelegate` re-reads on the status item's existing one-second tick and
/// reconfigures when something actually changed. That keeps the pet off any
/// notification or observation machinery of its own.
nonisolated struct PetSettings: Equatable {

    var isEnabled: Bool
    var size: PetSize
    var bubbleMode: PetBubbleMode
    var emptyBehavior: PetEmptyBehavior
    var character: PetCharacterID

    enum Keys {
        static let enabled = "petEnabled"
        static let size = "petSize"
        static let bubbleMode = "petBubbleMode"
        static let emptyBehavior = "petEmptyBehavior"
        static let character = "petCharacter"
        static let position = "petPosition"
    }

    /// The pet is a new, always-visible piece of UI in someone else's menu bar
    /// app, so every default here keeps it out of the way until asked for.
    static let `default` = PetSettings(
        isEnabled: false,
        size: .medium,
        bubbleMode: .hover,
        emptyBehavior: .rest,
        character: .nibble
    )

    static func load(from defaults: UserDefaults? = AppGroup.defaults) -> PetSettings {
        guard let defaults else { return .default }
        return PetSettings(
            isEnabled: defaults.bool(forKey: Keys.enabled),
            size: value(defaults.string(forKey: Keys.size), default: .medium),
            bubbleMode: value(defaults.string(forKey: Keys.bubbleMode), default: .hover),
            emptyBehavior: value(defaults.string(forKey: Keys.emptyBehavior), default: .rest),
            character: value(defaults.string(forKey: Keys.character), default: .nibble)
        )
    }

    /// Used by the pet's own "Hide Pet" menu item, which has no view to bind to.
    static func setEnabled(_ enabled: Bool, in defaults: UserDefaults? = AppGroup.defaults) {
        defaults?.set(enabled, forKey: Keys.enabled)
    }

    // MARK: - Position

    /// Where the user last dropped the pet, or `nil` if it has never been moved.
    static func savedPosition(in defaults: UserDefaults? = AppGroup.defaults) -> PetPosition? {
        guard let data = defaults?.data(forKey: Keys.position) else { return nil }
        return try? JSONDecoder().decode(PetPosition.self, from: data)
    }

    static func savePosition(_ position: PetPosition, in defaults: UserDefaults? = AppGroup.defaults) {
        guard let data = try? JSONEncoder().encode(position) else { return }
        defaults?.set(data, forKey: Keys.position)
    }

    /// Forgets the stored position so the pet returns to its default corner.
    static func clearPosition(in defaults: UserDefaults? = AppGroup.defaults) {
        defaults?.removeObject(forKey: Keys.position)
    }

    private static func value<T: RawRepresentable>(
        _ raw: String?,
        default fallback: T
    ) -> T where T.RawValue == String {
        raw.flatMap(T.init(rawValue:)) ?? fallback
    }
}
