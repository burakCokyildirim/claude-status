import Foundation

/// A body animation the pet can be playing.
nonisolated enum PetAnimation: Equatable {

    /// No movement at all, and no timer behind it.
    case still
    /// Waiting: a slow breath, so it reads as alive but patient.
    case breathe
    /// Active: a quick, working rhythm.
    case work
    /// Compacting: a side-to-side sweep.
    case sweep
    /// One-shot reaction to being clicked.
    case poke
    /// One-shot reaction to the session changing state.
    case startle

    /// How long a one-shot runs. `nil` for the looping animations.
    var duration: TimeInterval? {
        switch self {
        case .poke: 0.40
        case .startle: 0.30
        case .still, .breathe, .work, .sweep: nil
        }
    }

    /// Seconds per cycle.
    var period: TimeInterval {
        switch self {
        case .still: 1
        case .breathe: 1.40
        case .work: 0.60
        case .sweep: 0.90
        case .poke: 0.40
        case .startle: 0.30
        }
    }

    /// Whether this animation needs the frame timer running.
    var isAnimated: Bool { self != .still }

    /// The looping animation a session state rests in.
    static func resting(for state: SessionState?) -> PetAnimation {
        guard let state else { return .still }
        switch state {
        case .active: return .work
        case .waiting: return .breathe
        case .compacting: return .sweep
        case .idle: return .still
        }
    }
}

/// How the sprite is displaced for one frame.
///
/// Offsets are in grid pixels and stay whole, so the pixel art never lands
/// between grid lines while the body moves. Squash and stretch is the one thing
/// that scales, which is what makes the motion read as a body rather than a
/// sliding image.
nonisolated struct PetTransform: Equatable {
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 0
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    /// Swaps in the tucked-leg rows while the pet is off the ground.
    var isAirborne: Bool = false

    static let identity = PetTransform()
}

/// The motion layer: pure functions from an animation and a phase to a transform.
///
/// Keeping this separate from the sprite data is what lets three characters share
/// five animations without three times the art, and it is testable without a
/// window, a timer, or a screen.
nonisolated enum PetMotion {

    /// The transform for `animation` at `phase`, a normalized position through
    /// one cycle for a loop, or through the whole thing for a one-shot.
    ///
    /// Every animation returns `.identity` at phase 0 and lands back on it at
    /// phase 1, so loops do not jump and one-shots settle cleanly.
    static func transform(for animation: PetAnimation, phase: Double) -> PetTransform {
        let phase = min(max(phase, 0), 1)
        switch animation {
        case .still:
            return .identity

        case .breathe:
            let wave = sin(phase * 2 * .pi)
            return PetTransform(
                offsetY: CGFloat((wave * 1.2).rounded()),
                scaleX: 1 - CGFloat(wave) * 0.02,
                scaleY: 1 + CGFloat(wave) * 0.03
            )

        case .work:
            let wave = sin(phase * 2 * .pi)
            return PetTransform(
                offsetX: CGFloat((wave * 1.2).rounded()),
                offsetY: CGFloat((abs(wave) * 1.4).rounded()),
                scaleX: 1 + CGFloat(abs(wave)) * 0.04,
                scaleY: 1 - CGFloat(abs(wave)) * 0.05
            )

        case .sweep:
            let wave = sin(phase * 2 * .pi)
            return PetTransform(
                offsetX: CGFloat((wave * 1.8).rounded()),
                scaleX: 1 + CGFloat(abs(wave)) * 0.05,
                scaleY: 1 - CGFloat(abs(wave)) * 0.03
            )

        case .poke:
            return poke(phase: phase)

        case .startle:
            return startle(phase: phase)
        }
    }

    /// Squash, spring up, fall, and settle.
    private static func poke(phase: Double) -> PetTransform {
        switch phase {
        case ..<0.18:
            let t = ease(phase / 0.18)
            return PetTransform(scaleX: lerp(1, 1.20, t), scaleY: lerp(1, 0.76, t))
        case ..<0.42:
            let t = ease((phase - 0.18) / 0.24)
            return PetTransform(
                offsetY: lerp(0, 4, t).rounded(),
                scaleX: lerp(1.20, 0.90, t),
                scaleY: lerp(0.76, 1.18, t),
                isAirborne: t > 0.35
            )
        case ..<0.74:
            let t = ease((phase - 0.42) / 0.32)
            return PetTransform(
                offsetY: lerp(4, 0, t).rounded(),
                scaleX: lerp(0.90, 1.10, t),
                scaleY: lerp(1.18, 0.88, t),
                isAirborne: t < 0.75
            )
        default:
            let t = ease((phase - 0.74) / 0.26)
            return PetTransform(scaleX: lerp(1.10, 1, t), scaleY: lerp(0.88, 1, t))
        }
    }

    /// A quick hop of surprise, then back down.
    private static func startle(phase: Double) -> PetTransform {
        if phase < 0.38 {
            let t = ease(phase / 0.38)
            return PetTransform(
                offsetY: lerp(0, 3, t).rounded(),
                scaleX: lerp(1, 0.92, t),
                scaleY: lerp(1, 1.14, t),
                isAirborne: t > 0.4
            )
        }
        let t = ease((phase - 0.38) / 0.62)
        return PetTransform(
            offsetY: lerp(3, 0, t).rounded(),
            scaleX: lerp(0.92, 1, t),
            scaleY: lerp(1.14, 1, t),
            isAirborne: t < 0.6
        )
    }

    private static func lerp(_ from: Double, _ to: Double, _ t: Double) -> CGFloat {
        CGFloat(from + (to - from) * t)
    }

    /// Smoothstep, so the piecewise segments do not read as linear ramps.
    private static func ease(_ t: Double) -> Double {
        let t = min(max(t, 0), 1)
        return t * t * (3 - 2 * t)
    }
}
