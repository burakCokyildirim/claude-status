import Foundation

nonisolated extension PetCharacter {

    /// A kernel that pops out bits of program while it works, and squeezes back down
    /// when it is not.
    static let kernel = PetCharacter(
        palette: [
            "o": 0x3B2A12, "b": 0xE8C35C, "h": 0xFFF1CB, "s": 0xA87F2E,
            "e": 0x241804, "w": 0xF7F3E8
        ],
        badgeCorner: CGPoint(x: 2.8, y: 4.8),
        active: PetRoutine(
            // One tile at a time: a squash, a pop, and the tile floats up out of the head,
            // drifting outwards, to puff away at the top row.
            loop: [
                PetFrame(120, Part.base.at(0, 14), Part.body.at(0, 6)),
                PetFrame(130, Part.tilePrompt.at(4, 3), Part.base.at(0, 14), Part.body.at(0, 4)),
                PetFrame(130, Part.tilePrompt.at(3, 1), Part.base.at(0, 14), Part.body.at(0, 5)),
                PetFrame(360, Part.tilePrompt.at(2, 0), Part.base.at(0, 14), Part.body.at(0, 5)),
                PetFrame(110, Part.base.at(0, 14), Part.body.at(0, 5), Part.puff.at(3, 1)),
                PetFrame(120, Part.base.at(0, 14), Part.body.at(0, 6)),
                PetFrame(130, Part.tileArrow.at(9, 3), Part.base.at(0, 14), Part.body.at(0, 4)),
                PetFrame(130, Part.tileArrow.at(10, 1), Part.base.at(0, 14), Part.body.at(0, 5)),
                PetFrame(360, Part.tileArrow.at(11, 0), Part.base.at(0, 14), Part.body.at(0, 5)),
                PetFrame(110, Part.base.at(0, 14), Part.body.at(0, 5), Part.puff.at(12, 1)),
                PetFrame(120, Part.base.at(0, 14), Part.body.at(0, 6)),
                PetFrame(130, Part.tileComment.at(6, 3), Part.base.at(0, 14), Part.body.at(0, 4)),
                PetFrame(130, Part.tileComment.at(6, 1), Part.base.at(0, 14), Part.body.at(0, 5)),
                PetFrame(360, Part.tileComment.at(6, 0), Part.base.at(0, 14), Part.body.at(0, 5)),
                PetFrame(110, Part.base.at(0, 14), Part.body.at(0, 5), Part.puff.at(7, 1)),
            ],
            still: 3
        ),
        waiting: PetRoutine(
            loop: [
                PetFrame(300, Part.base.at(0, 14), Part.body.at(-1, 5), Part.question.at(14, 2)),
                PetFrame(300, Part.base.at(0, 14), Part.body.at(0, 5), Part.question.at(14, 1)),
                PetFrame(300, Part.base.at(0, 14), Part.body.at(1, 5), Part.question.at(15, 0)),
                PetFrame(300, Part.base.at(0, 14), Part.body.at(0, 5), Part.question.at(15, 0)),
                PetFrame(300, Part.base.at(0, 14), Part.body.at(-1, 5)),
            ]
        ),
        unread: PetRoutine(
            loop: [
                PetFrame(520, Part.base.at(0, 14), Part.body.at(0, 5), PetProp.bubble.at(12, 0)),
                PetFrame(520, Part.base.at(0, 14), Part.body.at(0, 4), PetProp.bubble.at(12, 1)),
                PetFrame(520, Part.base.at(0, 14), Part.body.at(0, 5), PetProp.bubble.at(12, 0)),
                PetFrame(150, Part.base.at(0, 14), Part.bodyShut.at(0, 5), PetProp.bubble.at(12, 1)),
            ]
        ),
        compacting: PetRoutine(
            loop: [
                PetFrame(180, Part.base.at(0, 14), Part.body.at(0, 5)),
                PetFrame(180, Part.base.at(0, 14), Part.body.at(0, 6)),
                PetFrame(340, Part.tight.at(0, 10), PetProp.dust.at(2, 12)),
                PetFrame(180, Part.base.at(0, 14), Part.body.at(0, 6)),
            ],
            still: 2
        ),
        idle: PetRoutine(
            loop: [
                PetFrame(460, Part.base.at(0, 14), Part.bodyShut.at(0, 7), PetProp.snore.at(14, 2)),
                PetFrame(460, Part.base.at(0, 14), Part.bodyShut.at(0, 7), PetProp.snore.at(15, 1)),
                PetFrame(460, Part.base.at(0, 14), Part.bodyShut.at(0, 7), PetProp.snore.at(15, 0)),
                PetFrame(460, Part.base.at(0, 14), Part.bodyShut.at(0, 7)),
            ]
        ),
        resting: PetRoutine(
            loop: [
                PetFrame(2000, Part.base.at(0, 14), Part.body.at(0, 5)),
                PetFrame(150, Part.base.at(0, 14), Part.bodyShut.at(0, 5)),
                PetFrame(1400, Part.base.at(0, 14), Part.body.at(0, 5)),
                PetFrame(600, Part.base.at(0, 14), Part.body.at(0, 4)),
            ]
        )
    )
}

/// Kernel's pieces, each placed on the canvas by the frames above.
nonisolated private enum Part {

    static let body: PetPart = [
        "......hh..hh........",
        ".....hhhhhhhhh......",
        "....hhhhhhhhhhh.....",
        "...ohhhhhhhhhhho....",
        "...obbbbbbbbbbbo....",
        "...obbeebbbbeebo....",
        "...obbeebbbbeebo....",
        "...obbbbbbbbbbbo....",
        "....obbbbbbbbbo.....",
    ]

    static let bodyShut: PetPart = [
        "......hh..hh........",
        ".....hhhhhhhhh......",
        "....hhhhhhhhhhh.....",
        "...ohhhhhhhhhhho....",
        "...obbbbbbbbbbbo....",
        "...obbbbbbbbbbbo....",
        "...obbeebbbbeebo....",
        "...obbbbbbbbbbbo....",
        "....obbbbbbbbbo.....",
    ]

    static let base: PetPart = [
        ".....ossssssso......",
        "......oooooooo......",
    ]

    /// Squeezed back down, for compacting.
    static let tight: PetPart = [
        ".....ohhhhhho.......",
        "....obbbbbbbbo......",
        "....obeebbeebo......",
        "....obbbbbbbbo......",
        ".....ossssssso......",
        "......oooooooo......",
    ]

    /// Bits of program it pops out, each a token on a key-shaped tile: ">_".
    static let tilePrompt: PetPart = [
        ".bbbbb.",
        "bobbbbb",
        "bbobbbb",
        "bobboob",
        ".sssss.",
    ]

    /// "=>"
    static let tileArrow: PetPart = [
        ".bbbbb.",
        "boobobb",
        "bbbbbob",
        "boobobb",
        ".sssss.",
    ]

    /// "//"
    static let tileComment: PetPart = [
        ".bbbbb.",
        "bbbobob",
        "bbobobb",
        "bobobbb",
        ".sssss.",
    ]

    /// A tile puffing away at the top of the canvas.
    static let puff: PetPart = [
        ".b.b.",
        "b...b",
        ".b.b.",
    ]

    /// A question mark in the kernel's own colours.
    static let question: PetPart = [
        ".hh.",
        "h..h",
        "...h",
        "..h.",
        "....",
        "..h.",
    ]
}
