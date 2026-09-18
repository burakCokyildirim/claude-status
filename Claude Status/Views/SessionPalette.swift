import SwiftUI

/// Colours shared by the session list and the desktop pet, so the two never
/// disagree about what a session looks like.
enum SessionPalette {

    /// Unread: Claude has spoken and nobody has read it yet.
    ///
    /// The Claude desktop app marks the same thing with the same blue in its own
    /// session list, so a glance at the pet and a glance at that list agree.
    /// Deliberately not the compacting blue, which is a state the session passes
    /// through rather than something asking to be read.
    static let unread = Color(red: 0.165, green: 0.471, blue: 0.839)
}
