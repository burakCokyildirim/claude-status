import Foundation

/// Which frame of which routine the pet is showing, and when that changes.
///
/// A pure value the window controller advances with the clock, so the order
/// things play in can be tested without a timer or a window.
///
/// Moving to another mood leaves through the current routine's exit and comes
/// in through the next one's entrance. Those always run to their last frame —
/// cut short, Claudie's laptop would vanish in mid-air — so a mood that changes
/// again meanwhile is simply where the pet heads once they finish. A loop gives
/// way at once.
nonisolated struct PetPlayback {

    private enum Stage {
        case enter
        case loop
        case exit
    }

    let character: PetCharacter

    /// The mood the pet is headed for.
    private(set) var target: PetMood
    /// The mood whose routine is on screen: behind `target` while an exit or an
    /// entrance is still playing.
    private(set) var mood: PetMood
    private var stage = Stage.loop
    private var index = 0
    private var frameStartedAt: TimeInterval

    /// Starts in the mood's loop. The pet appearing is not the mood beginning,
    /// so there is no entrance to sit through.
    init(character: PetCharacter, mood: PetMood, now: TimeInterval) {
        self.character = character
        target = mood
        self.mood = mood
        frameStartedAt = now
    }

    var frame: PetFrame {
        clip[index]
    }

    /// When the frame on screen has had its time.
    var nextFrameAt: TimeInterval {
        frameStartedAt + frame.duration
    }

    /// Heads for `mood`.
    mutating func play(_ mood: PetMood, now: TimeInterval) {
        target = mood
        if stage == .loop, mood != self.mood {
            leave(now: now)
        }
    }

    /// Moves to the next frame if the current one has had its time.
    ///
    /// Steps at most once, and times the next frame from `now` rather than from
    /// when this one was due: a pet that was off screen for an hour picks up
    /// where it stopped instead of racing through an hour of frames.
    ///
    /// - Returns: Whether the frame changed.
    @discardableResult
    mutating func advance(now: TimeInterval) -> Bool {
        guard now >= nextFrameAt else { return false }
        if index + 1 < clip.count {
            index += 1
            frameStartedAt = now
            return true
        }
        switch stage {
        case .enter, .loop:
            if target == mood {
                begin(.loop, now: now)
            } else {
                leave(now: now)
            }
        case .exit:
            arrive(now: now)
        }
        return true
    }

    private var clip: [PetFrame] {
        let routine = character.routine(for: mood)
        switch stage {
        case .enter: return routine.enter ?? routine.loop
        case .loop: return routine.loop
        case .exit: return routine.exit ?? routine.loop
        }
    }

    /// Out of the current mood: through its exit if it has one, otherwise
    /// straight into the target.
    private mutating func leave(now: TimeInterval) {
        if character.routine(for: mood).exit != nil {
            begin(.exit, now: now)
        } else {
            arrive(now: now)
        }
    }

    /// Into the target: through its entrance if it has one, otherwise straight
    /// into its loop.
    private mutating func arrive(now: TimeInterval) {
        mood = target
        begin(character.routine(for: mood).enter != nil ? .enter : .loop, now: now)
    }

    private mutating func begin(_ stage: Stage, now: TimeInterval) {
        self.stage = stage
        index = 0
        frameStartedAt = now
    }
}
