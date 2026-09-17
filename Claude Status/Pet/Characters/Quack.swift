import Foundation

nonisolated extension PetCharacter {

    /// A rubber duck: the one you explain your code to. It inspects the work through a
    /// magnifying glass, hops while it likes what it sees, and squeaks when squeezed.
    static let quack = PetCharacter(
        palette: [
            "o": 0x4A3508, "b": 0xFFD23F, "h": 0xFFF1A6, "s": 0xE5A91A,
            "k": 0xF28B30, "e": 0x161616, "g": 0x6F7784, "v": 0xD6EEFF,
            "w": 0xF4F1EC
        ],
        badgeCorner: CGPoint(x: 2.3, y: 4.3),
        active: PetRoutine(
            // Lowers the glass and blinks, puts it back up, then a run of hops.
            loop: [
                PetFrame(240, Part.body.at(0, 10), Part.head.at(0, 3), Part.magnifier.at(3, 7)),
                PetFrame(120, Part.body.at(0, 10), Part.headBlink.at(0, 3), Part.magnifier.at(3, 7)),
                PetFrame(200, Part.body.at(0, 10), Part.head.at(0, 3), Part.magnifier.at(3, 7)),
                PetFrame(140, Part.body.at(0, 10), Part.head.at(0, 3), Part.magnifier.at(5, 6)),
                PetFrame(280, Part.body.at(0, 10), Part.head.at(0, 3), Part.magnifiedEye.at(7, 5)),
                PetFrame(150, Part.body.at(0, 9), Part.head.at(0, 2), Part.magnifiedEye.at(7, 4),
                              Part.sparkle.at(13, 2)),
                PetFrame(130, Part.body.at(0, 10), Part.head.at(0, 3), Part.magnifiedEye.at(7, 5)),
                PetFrame(150, Part.body.at(0, 9), Part.head.at(0, 2), Part.magnifiedEye.at(7, 4),
                              Part.sparkle.at(13, 2)),
                PetFrame(130, Part.body.at(0, 10), Part.head.at(0, 3), Part.magnifiedEye.at(7, 5)),
                PetFrame(150, Part.body.at(0, 9), Part.head.at(0, 2), Part.magnifiedEye.at(7, 4),
                              Part.sparkle.at(13, 2)),
                PetFrame(130, Part.body.at(0, 10), Part.head.at(0, 3), Part.magnifiedEye.at(7, 5)),
                PetFrame(150, Part.body.at(0, 9), Part.head.at(0, 2), Part.magnifiedEye.at(7, 4),
                              Part.sparkle.at(13, 2)),
                PetFrame(130, Part.body.at(0, 10), Part.head.at(0, 3), Part.magnifiedEye.at(7, 5)),
                PetFrame(150, Part.body.at(0, 9), Part.head.at(0, 2), Part.magnifiedEye.at(7, 4),
                              Part.sparkle.at(13, 2)),
                PetFrame(130, Part.body.at(0, 10), Part.head.at(0, 3), Part.magnifiedEye.at(7, 5)),
                PetFrame(220, Part.body.at(0, 10), Part.head.at(0, 3), Part.magnifiedEye.at(7, 5)),
                PetFrame(140, Part.body.at(0, 10), Part.head.at(0, 3), Part.magnifier.at(5, 6)),
            ],
            still: 4
        ),
        waiting: PetRoutine(
            loop: [
                PetFrame(460, Part.body.at(0, 10), Part.headUp.at(0, 3), PetProp.question.at(15, 3)),
                PetFrame(460, Part.body.at(0, 10), Part.headUp.at(1, 3), PetProp.question.at(15, 2)),
                PetFrame(460, Part.body.at(0, 10), Part.headUp.at(1, 3), PetProp.question.at(16, 1)),
                PetFrame(140, Part.body.at(0, 10), Part.headBlink.at(1, 3), PetProp.question.at(16, 1)),
                PetFrame(460, Part.body.at(0, 10), Part.headUp.at(0, 3)),
            ]
        ),
        unread: PetRoutine(
            loop: [
                PetFrame(520, Part.body.at(0, 10), Part.headUp.at(0, 3), PetProp.bubble.at(12, 0)),
                PetFrame(520, Part.body.at(0, 10), Part.headUp.at(0, 3), PetProp.bubble.at(12, 1)),
                PetFrame(520, Part.body.at(0, 10), Part.head.at(0, 3), PetProp.bubble.at(12, 0)),
                PetFrame(140, Part.body.at(0, 10), Part.headBlink.at(0, 3), PetProp.bubble.at(12, 1)),
            ]
        ),
        compacting: PetRoutine(
            loop: [
                PetFrame(180, Part.body.at(0, 10), Part.head.at(0, 3)),
                PetFrame(200, Part.body.at(0, 10), Part.headShut.at(0, 4)),
                PetFrame(320, Part.bodySqueezed.at(0, 12), Part.headShut.at(0, 5), Part.squeak.at(9, 3),
                              PetProp.dust.at(1, 13), PetProp.dust.at(16, 13)),
                PetFrame(200, Part.body.at(0, 10), Part.headShut.at(0, 4)),
            ],
            still: 2
        ),
        idle: PetRoutine(
            loop: [
                PetFrame(460, Part.body.at(0, 10), Part.headShut.at(0, 5), PetProp.snore.at(14, 3)),
                PetFrame(460, Part.body.at(0, 10), Part.headShut.at(0, 5), PetProp.snore.at(15, 2)),
                PetFrame(460, Part.body.at(0, 10), Part.headShut.at(0, 5), PetProp.snore.at(15, 1)),
                PetFrame(460, Part.body.at(0, 10), Part.headShut.at(0, 5)),
            ]
        ),
        resting: PetRoutine(
            loop: [
                PetFrame(1300, Part.body.at(0, 10), Part.head.at(0, 3)),
                PetFrame(140, Part.body.at(0, 10), Part.headBlink.at(0, 3)),
                PetFrame(900, Part.body.at(0, 10), Part.head.at(0, 3)),
                PetFrame(420, Part.body.at(0, 9), Part.head.at(0, 2)),
                PetFrame(420, Part.body.at(0, 10), Part.head.at(0, 3)),
            ]
        )
    )
}

/// Quack's pieces, each placed on the canvas by the frames above.
nonisolated private enum Part {

    static let body: PetPart = [
        "....obbbbbbbbo...oo.",
        "...obbbbbbbbbbbboho.",
        "..obbbbssssbbbbbbbo.",
        "..obbbbbssssbbbbbbo.",
        "...obbbbbbbbbbbbbo..",
        "....ooooooooooooo...",
    ]

    static let bodySqueezed: PetPart = [
        "..obbbbssssbbbbbbbo.",
        "..obbbbbssssbbbbbbo.",
        "...obbbbbbbbbbbbbo..",
        "....ooooooooooooo...",
    ]

    static let head: PetPart = [
        "........oooo........",
        ".......ohhhbo.......",
        "......ohhbbbbo......",
        "......obebbbbo......",
        "..ooooobbbbbbo......",
        ".okkkkkobbbbbo......",
        "..oooooobbbbbo......",
    ]

    static let headBlink: PetPart = [
        "........oooo........",
        ".......ohhhbo.......",
        "......ohhbbbbo......",
        "......obbbbbbo......",
        "..ooooobbbbbbo......",
        ".okkkkkobbbbbo......",
        "..oooooobbbbbo......",
    ]

    static let headUp: PetPart = [
        "........oooo........",
        ".......ohhhbo.......",
        "......ohhebbbo......",
        "......obbbbbbo......",
        "..ooooobbbbbbo......",
        ".okkkkkobbbbbo......",
        "..oooooobbbbbo......",
    ]

    static let headShut: PetPart = [
        "........oooo........",
        ".......ohhhbo.......",
        "......ohhbbbbo......",
        "......oboobbbo......",
        "..ooooobbbbbbo......",
        ".okkkkkobbbbbo......",
        "..oooooobbbbbo......",
    ]

    static let magnifier: PetPart = [
        ".gg..",
        "gvvg.",
        "gvvg.",
        ".ggg.",
        "...g.",
        "...g.",
    ]

    /// The magnifier held up to its eye.
    static let magnifiedEye: PetPart = [
        ".gg..",
        "geeg.",
        "geeg.",
        ".ggg.",
        "...g.",
        "...g.",
    ]

    static let sparkle: PetPart = [
        ".w.",
        "w.w",
        ".w.",
    ]

    static let squeak: PetPart = [
        "w.w.w",
        "w.w.w",
    ]
}
