import Foundation

/// Resolves which single session the desktop pet represents.
///
/// The pet always stands for exactly one session. The ordering reuses the app's
/// existing state vocabulary (`SessionState.sortOrder`) so the pet agrees with the
/// menu bar dropdown and the widgets: waiting first (it needs input and must never
/// hide behind a working session), then active, then compacting, then idle.
///
/// Ties break on most recent activity, then on ascending session ID, so the choice
/// is fully deterministic even when two sessions share a timestamp.
///
/// Main actor-isolated because `SessionState.sortOrder` is: the project builds
/// with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Still a pure function of its
/// input, so it needs no window, screen, or running app to test.
@MainActor
enum PetPresenter {

    /// The session the pet should represent, or `nil` when no sessions are live.
    static func resolve(from sessions: [ClaudeSession]) -> ClaudeSession? {
        sessions.min(by: hasHigherPriority)
    }

    /// Whether `lhs` outranks `rhs` for the pet.
    ///
    /// `Array.sortedByStateAndActivity` is deliberately not reused here: it stops at
    /// the activity timestamp, which leaves the pet's pick undefined when two
    /// sessions tie. The state ordering still comes from the same source of truth.
    private static func hasHigherPriority(_ lhs: ClaudeSession, _ rhs: ClaudeSession) -> Bool {
        if lhs.state.sortOrder != rhs.state.sortOrder {
            return lhs.state.sortOrder < rhs.state.sortOrder
        }
        if lhs.lastActivityAt != rhs.lastActivityAt {
            return lhs.lastActivityAt > rhs.lastActivityAt
        }
        return lhs.sessionId < rhs.sessionId
    }
}
