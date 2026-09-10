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

/// User settings for the desktop pet, persisted in the App Group defaults.
///
/// Mirrors `ProfileStore`: `@Observable` for the settings UI, plus an `onChange`
/// callback for `AppDelegate`, which is not a view and cannot observe bindings.
/// The stored position is deliberately excluded from `onChange` — saving where
/// the user dropped the pet must not trigger a reconfiguration.
@Observable
@MainActor
final class PetSettings {

    /// Invoked after any user-facing setting changes.
    var onChange: (() -> Void)?

    var isEnabled: Bool {
        didSet { commit(isEnabled, oldValue, key: Keys.enabled, encode: { $0 }) }
    }
    var size: PetSize {
        didSet { commit(size, oldValue, key: Keys.size, encode: { $0.rawValue }) }
    }
    var bubbleMode: PetBubbleMode {
        didSet { commit(bubbleMode, oldValue, key: Keys.bubbleMode, encode: { $0.rawValue }) }
    }
    var emptyBehavior: PetEmptyBehavior {
        didSet { commit(emptyBehavior, oldValue, key: Keys.emptyBehavior, encode: { $0.rawValue }) }
    }
    var character: PetCharacterID {
        didSet { commit(character, oldValue, key: Keys.character, encode: { $0.rawValue }) }
    }

    private let defaults: UserDefaults?

    private enum Keys {
        static let enabled = "petEnabled"
        static let size = "petSize"
        static let bubbleMode = "petBubbleMode"
        static let emptyBehavior = "petEmptyBehavior"
        static let character = "petCharacter"
        static let position = "petPosition"
    }

    init(defaults: UserDefaults? = AppGroup.defaults) {
        self.defaults = defaults
        // The pet is a new, always-visible piece of UI, so it stays opt-in.
        isEnabled = defaults?.bool(forKey: Keys.enabled) ?? false
        size = Self.value(defaults?.string(forKey: Keys.size), default: .medium)
        bubbleMode = Self.value(defaults?.string(forKey: Keys.bubbleMode), default: .hover)
        emptyBehavior = Self.value(defaults?.string(forKey: Keys.emptyBehavior), default: .rest)
        character = Self.value(defaults?.string(forKey: Keys.character), default: .nibble)
    }

    // MARK: - Position

    /// The pet's stored position, or `nil` when it has never been moved.
    var savedPosition: PetPosition? {
        guard let data = defaults?.data(forKey: Keys.position) else { return nil }
        return try? JSONDecoder().decode(PetPosition.self, from: data)
    }

    /// Persists a dropped position. Intentionally silent: this must not fire
    /// `onChange` and rebuild the panel the user just finished dragging.
    func savePosition(_ position: PetPosition) {
        guard let data = try? JSONEncoder().encode(position) else { return }
        defaults?.set(data, forKey: Keys.position)
    }

    /// Forgets the stored position so the pet returns to its default corner.
    func clearPosition() {
        defaults?.removeObject(forKey: Keys.position)
    }

    // MARK: - Persistence

    /// Writes a changed setting and notifies. No-ops when the value is unchanged,
    /// so redundant writes never cascade into a panel rebuild.
    private func commit<T: Equatable>(
        _ new: T,
        _ old: T,
        key: String,
        encode: (T) -> Any
    ) {
        guard new != old else { return }
        defaults?.set(encode(new), forKey: key)
        onChange?()
    }

    private static func value<T: RawRepresentable>(
        _ raw: String?,
        default fallback: T
    ) -> T where T.RawValue == String {
        raw.flatMap(T.init(rawValue:)) ?? fallback
    }
}
