import Foundation

nonisolated extension PetCharacter {

    /// A screen-faced little robot with a bite out of its dome. Everything it has to
    /// say, it says with its eyes, which turn into braces while it works.
    static let nibble = PetCharacter(
        palette: [
            "o": 0x171C26, "b": 0x4E6B99, "h": 0x7FA0CE, "s": 0x35496B,
            "v": 0x10141C, "c": 0x7FE3FF, "e": 0x0A0C10, "w": 0xF2F5F8
        ],
        badgeCorner: CGPoint(x: 2.6, y: 3.6),
        active: PetRoutine(
            enter: [
                PetFrame(140, Part.legs.at(0, 13), Part.head.at(0, 4)),
                PetFrame(110, Part.legs.at(0, 13), Part.head.at(0, 4), Part.eyeNarrow.at(6, 9),
                              Part.eyeNarrow.at(11, 9)),
                PetFrame(160, Part.legs.at(0, 13), Part.head.at(0, 4), Part.braceOpen.at(6, 8),
                              Part.braceClose.at(11, 8)),
            ],
            // The braces see-saw: one up while the other is down.
            loop: [
                PetFrame(150, Part.legs.at(0, 13), Part.head.at(0, 4), Part.braceOpen.at(6, 7),
                              Part.braceClose.at(11, 9)),
                PetFrame(110, Part.legs.at(0, 13), Part.head.at(0, 3), Part.braceOpen.at(6, 7),
                              Part.braceClose.at(11, 7)),
                PetFrame(150, Part.legs.at(0, 13), Part.head.at(0, 4), Part.braceOpen.at(6, 9),
                              Part.braceClose.at(11, 7)),
                PetFrame(110, Part.legs.at(0, 13), Part.head.at(0, 3), Part.braceOpen.at(6, 7),
                              Part.braceClose.at(11, 7)),
                PetFrame(150, Part.legs.at(0, 13), Part.head.at(0, 4), Part.braceOpen.at(6, 7),
                              Part.braceClose.at(11, 9)),
                PetFrame(110, Part.legs.at(0, 13), Part.head.at(0, 3), Part.braceOpen.at(6, 7),
                              Part.braceClose.at(11, 7)),
                PetFrame(150, Part.legs.at(0, 13), Part.head.at(0, 4), Part.braceOpen.at(6, 9),
                              Part.braceClose.at(11, 7)),
                PetFrame(110, Part.legs.at(0, 13), Part.head.at(0, 3), Part.braceOpen.at(6, 7),
                              Part.braceClose.at(11, 7)),
                PetFrame(120, Part.legs.at(0, 13), Part.head.at(0, 4), Part.eyeNarrow.at(6, 9),
                              Part.eyeNarrow.at(11, 9)),
            ],
            exit: [
                PetFrame(120, Part.legs.at(0, 13), Part.head.at(0, 4), Part.braceOpen.at(6, 8),
                              Part.braceClose.at(11, 8)),
                PetFrame(110, Part.legs.at(0, 13), Part.head.at(0, 4), Part.eyeNarrow.at(6, 9),
                              Part.eyeNarrow.at(11, 9)),
                PetFrame(160, Part.legs.at(0, 13), Part.head.at(0, 4)),
            ]
        ),
        waiting: PetRoutine(
            loop: [
                PetFrame(460, Part.legs.at(0, 13), Part.head.at(0, 4), Part.eye.at(7, 7), Part.eye.at(12, 7),
                              PetProp.question.at(15, 2)),
                PetFrame(460, Part.legs.at(0, 13), Part.head.at(0, 4), Part.eye.at(7, 7), Part.eye.at(12, 7),
                              PetProp.question.at(15, 1)),
                PetFrame(460, Part.legs.at(0, 13), Part.head.at(0, 3), Part.eye.at(7, 6), Part.eye.at(12, 6),
                              PetProp.question.at(15, 0)),
                PetFrame(140, Part.legs.at(0, 13), Part.head.at(0, 3), Part.eyeNarrow.at(7, 7),
                              Part.eyeNarrow.at(12, 7), PetProp.question.at(15, 0)),
                PetFrame(460, Part.legs.at(0, 13), Part.head.at(0, 4), Part.eye.at(7, 7), Part.eye.at(12, 7)),
            ]
        ),
        unread: PetRoutine(
            loop: [
                PetFrame(520, Part.legs.at(0, 13), Part.head.at(0, 4), Part.eye.at(6, 7), Part.eye.at(11, 7),
                              PetProp.bubble.at(12, 0)),
                PetFrame(520, Part.legs.at(0, 13), Part.head.at(0, 4), Part.eye.at(6, 7), Part.eye.at(11, 7),
                              PetProp.bubble.at(12, 1)),
                PetFrame(520, Part.legs.at(0, 13), Part.head.at(0, 4), Part.eye.at(6, 8), Part.eye.at(11, 8),
                              PetProp.bubble.at(12, 0)),
                PetFrame(140, Part.legs.at(0, 13), Part.head.at(0, 4), Part.eyeNarrow.at(6, 9),
                              Part.eyeNarrow.at(11, 9), PetProp.bubble.at(12, 1)),
            ]
        ),
        compacting: PetRoutine(
            loop: [
                PetFrame(200, Part.legs.at(0, 13), Part.head.at(0, 4), Part.progress1.at(6, 9)),
                PetFrame(200, Part.legs.at(0, 13), Part.head.at(0, 4), Part.progress2.at(6, 9)),
                PetFrame(200, Part.legs.at(0, 13), Part.head.at(0, 4), Part.progress3.at(6, 9)),
                PetFrame(200, Part.legs.at(0, 13), Part.head.at(0, 5), Part.progress4.at(6, 10),
                              PetProp.dust.at(2, 13), PetProp.dust.at(15, 13)),
            ],
            still: 3
        ),
        idle: PetRoutine(
            loop: [
                PetFrame(460, Part.legs.at(0, 13), Part.head.at(0, 5), Part.eyesSleepy.at(6, 11),
                              PetProp.snore.at(14, 2)),
                PetFrame(460, Part.legs.at(0, 13), Part.head.at(0, 5), Part.eyesSleepy.at(6, 11),
                              PetProp.snore.at(15, 1)),
                PetFrame(460, Part.legs.at(0, 13), Part.head.at(0, 5), Part.eyesSleepy.at(6, 11),
                              PetProp.snore.at(15, 0)),
                PetFrame(460, Part.legs.at(0, 13), Part.head.at(0, 5), Part.eyesSleepy.at(6, 11)),
            ]
        ),
        resting: PetRoutine(
            loop: [
                PetFrame(2200, Part.legs.at(0, 13), Part.head.at(0, 4), Part.eye.at(6, 8), Part.eye.at(11, 8)),
                PetFrame(140, Part.legs.at(0, 13), Part.head.at(0, 4), Part.eyeNarrow.at(6, 9),
                              Part.eyeNarrow.at(11, 9)),
            ]
        )
    )
}

/// Nibble's pieces, each placed on the canvas by the frames above.
nonisolated private enum Part {

    static let head: PetPart = [
        "......oooooo.o......",
        "....oohhhhhhhhoo....",
        "...ohhhhhhhhhhhho...",
        "...ohvvvvvvvvvvho...",
        "...obvvvvvvvvvvbo...",
        "...obvvvvvvvvvvbo...",
        "...obvvvvvvvvvvbo...",
        "...obvvvvvvvvvvbo...",
        "...obbbbbbbbbbbbo...",
    ]

    static let legs: PetPart = [
        "....oobbbbbbbboo....",
        ".....obbo..obbo.....",
        ".....oooo..oooo.....",
    ]

    /// The eyes, drawn on the visor.
    static let eye: PetPart = [
        "ccc",
        "ccc",
    ]

    static let eyeNarrow: PetPart = [
        "ccc",
    ]

    static let eyesSleepy: PetPart = [
        "cc....cc",
    ]

    /// While it works, its eyes turn into a pair of curly braces.
    static let braceOpen: PetPart = [
        ".cc",
        "c..",
        ".cc",
    ]

    static let braceClose: PetPart = [
        "cc.",
        "..c",
        "cc.",
    ]

    /// A progress bar filling the visor while it compacts.
    static let progress1: PetPart = [
        "cc......",
    ]

    static let progress2: PetPart = [
        "cccc....",
    ]

    static let progress3: PetPart = [
        "cccccc..",
    ]

    static let progress4: PetPart = [
        "cccccccc",
    ]
}
