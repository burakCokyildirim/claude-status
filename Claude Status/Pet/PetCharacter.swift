import SwiftUI

/// The colours a character is drawn with.
///
/// Fixed rather than theme-derived: the pet floats over arbitrary wallpapers, so
/// it carries its own contrast instead of borrowing the system appearance.
nonisolated struct PetPalette {
    let outline: Color
    let body: Color
    let highlight: Color
    let shade: Color
    let eye: Color
    let eyeHighlight: Color
}

/// A pet character: a palette plus its pixel art.
///
/// The body is a single pose. Everything that moves — bobbing, swaying, squash
/// and stretch, hops — comes from `PetMotion` and is applied to the whole
/// sprite. Hand-authoring a frame per animation would multiply this file by an
/// order of magnitude to produce what the transform layer already gives.
nonisolated struct PetCharacter {

    let id: PetCharacterID
    let palette: PetPalette

    /// The resting body: `PetLayout.gridHeight` rows of `PetLayout.gridWidth`
    /// characters. `.` is transparent, everything else indexes the palette.
    let body: [String]

    /// Rows that differ while the pet is off the ground, keyed by row index.
    /// Only the legs tuck up, so this stays a handful of lines per character.
    let airborneRows: [Int: String]

    static func character(for id: PetCharacterID) -> PetCharacter {
        switch id {
        case .nibble: nibble
        case .lint: lint
        case .kernel: kernel
        }
    }

    /// The finished sprite for a session state: body, then face, then accent mark.
    func sprite(for state: SessionState, airborne: Bool) -> [String] {
        var rows = body
        if airborne {
            for (index, replacement) in airborneRows where rows.indices.contains(index) {
                rows[index] = replacement
            }
        }
        overlay(PetFace.rows(for: state), onto: &rows, startingAt: PetFace.rowOffset)
        overlay(PetFace.mark(for: state), onto: &rows, startingAt: 0)
        return rows
    }

    /// The colour a sprite character maps to, or `nil` where it is transparent.
    func color(for pixel: Character, accent: Color) -> Color? {
        switch pixel {
        case "o": palette.outline
        case "b": palette.body
        case "h": palette.highlight
        case "s": palette.shade
        case "E": palette.eye
        case "w": palette.eyeHighlight
        case "a": accent
        default: nil
        }
    }

    private func overlay(_ source: [String], onto rows: inout [String], startingAt offset: Int) {
        for (index, line) in source.enumerated() {
            let target = offset + index
            guard rows.indices.contains(target) else { continue }
            rows[target] = String(zip(line, rows[target]).map { $0 == "." ? $1 : $0 })
        }
    }
}

// MARK: - Faces

/// Face and accent overlays, shared by every character: all three heads present
/// the same face area, so the expressions are authored once.
nonisolated enum PetFace {

    /// The grid row the face overlay starts on.
    static let rowOffset = 7

    static func rows(for state: SessionState) -> [String] {
        switch state {
        // Narrow, focused slits.
        case .active: [
            "................",
            "................",
            "....EE....EE....",
            "................",
            "................",
            ".......EE......."
        ]
        // Wide open with a highlight, and an open mouth.
        case .waiting: [
            "....EEE..EEE....",
            "....EwE..EwE....",
            "....EEE..EEE....",
            "................",
            "................",
            "......EEEE......"
        ]
        // Shut tight.
        case .compacting: [
            "................",
            "................",
            "...EEEE..EEEE...",
            "................",
            "................",
            "......EEEE......"
        ]
        // Half closed and sitting low, so it reads as drowsy rather than shut.
        case .idle: [
            "................",
            "................",
            "................",
            "...EEEE..EEEE...",
            "................",
            "................"
        ]
        }
    }

    /// A mark drawn above the head in the session's state colour. At small sizes
    /// this carries most of the at-a-glance read, where eye shape alone is subtle.
    static func mark(for state: SessionState) -> [String] {
        switch state {
        // Motion ticks either side of the head.
        case .active: [
            "................",
            "....a......a....",
            "...aa......aa..."
        ]
        // An exclamation mark.
        case .waiting: [
            ".......aa.......",
            ".......aa.......",
            ".......aa......."
        ]
        // Dust being swept up.
        case .compacting: [
            "................",
            "....a...a...a...",
            "................"
        ]
        // A "z".
        case .idle: [
            "......aaa.......",
            ".......a........",
            "......aaa......."
        ]
        }
    }
}

// MARK: - Characters

extension PetCharacter {

    /// A tidy little shell bot with a wedge bitten out of the top of its dome.
    static let nibble = PetCharacter(
        id: .nibble,
        palette: PetPalette(
            outline: Color(red: 0.11, green: 0.13, blue: 0.18),
            body: Color(red: 0.42, green: 0.55, blue: 0.75),
            highlight: Color(red: 0.62, green: 0.74, blue: 0.90),
            shade: Color(red: 0.30, green: 0.40, blue: 0.58),
            eye: Color(red: 0.08, green: 0.09, blue: 0.12),
            eyeHighlight: .white
        ),
        body: [
            "................",
            "................",
            "................",
            ".....oooo.oo....",
            "...oohhhhoohho..",
            "..ohhhhhhhhhho..",
            ".ohhhhhhhhhhhho.",
            ".obbbbbbbbbbbbo.",
            "obbbbbbbbbbbbbbo",
            "obbbbbbbbbbbbbbo",
            "obbbbbbbbbbbbbbo",
            "obbbbbbbbbbbbbbo",
            "obbbbbbbbbbbbbbo",
            ".obbbbbbbbbbbbo.",
            "..oobbbbbbbboo..",
            "...oobbbbbboo...",
            "..obbbbssbbbbo..",
            "..obbbbssbbbbo..",
            "..obbbbbbbbbbo..",
            "..obbbbbbbbbbo..",
            "...oobbbbbboo...",
            "....obbo.obbo...",
            "....obbo.obbo...",
            "....oooo.oooo..."
        ],
        airborneRows: [
            21: "................",
            22: ".....obbobbo....",
            23: ".....oooooo....."
        ]
    )

    /// A fuzzball that cannot leave a mess alone. Irregular tufts, wide base.
    static let lint = PetCharacter(
        id: .lint,
        palette: PetPalette(
            outline: Color(red: 0.16, green: 0.14, blue: 0.13),
            body: Color(red: 0.68, green: 0.62, blue: 0.56),
            highlight: Color(red: 0.82, green: 0.77, blue: 0.71),
            shade: Color(red: 0.52, green: 0.47, blue: 0.42),
            eye: Color(red: 0.10, green: 0.09, blue: 0.08),
            eyeHighlight: .white
        ),
        body: [
            "................",
            "................",
            "................",
            "...o..oooo..o...",
            "..ohoohhhhooho..",
            ".ohhhhhhhhhhhho.",
            "oohhhhhhhhhhhhoo",
            ".obbbbbbbbbbbbo.",
            "obbbbbbbbbbbbbbo",
            "obbbbbbbbbbbbbbo",
            "obbbbbbbbbbbbbbo",
            "obbbbbbbbbbbbbbo",
            "obbbbbbbbbbbbbbo",
            "obbbbbbbbbbbbbbo",
            ".obbbbbbbbbbbbo.",
            ".obbbbbbbbbbbbo.",
            "obbbbssbbssbbbbo",
            "obbbbbbbbbbbbbbo",
            ".obbbbbbbbbbbbo.",
            "..obbbbbbbbbbo..",
            "..obbbbbbbbbbo..",
            ".oobbo.oo.obboo.",
            ".ooooo.oo.ooooo.",
            "................"
        ],
        airborneRows: [
            21: "..obbbo..obbbo..",
            22: "..ooooo..ooooo.."
        ]
    )

    /// Quiet until it isn't. A kernel with a puff on top and a narrow base.
    static let kernel = PetCharacter(
        id: .kernel,
        palette: PetPalette(
            outline: Color(red: 0.22, green: 0.15, blue: 0.06),
            body: Color(red: 0.93, green: 0.78, blue: 0.36),
            highlight: Color(red: 0.99, green: 0.94, blue: 0.78),
            shade: Color(red: 0.78, green: 0.60, blue: 0.22),
            eye: Color(red: 0.20, green: 0.13, blue: 0.05),
            eyeHighlight: .white
        ),
        body: [
            "................",
            "................",
            "................",
            "......hhhh......",
            ".....hhhhhh.....",
            "....ohhhhhho....",
            "...oohhhhhhoo...",
            "..obbbbbbbbbbo..",
            ".obbbbbbbbbbbbo.",
            "obbbbbbbbbbbbbbo",
            "obbbbbbbbbbbbbbo",
            "obbbbbbbbbbbbbbo",
            "obbbbbbbbbbbbbbo",
            "obbbbbbbbbbbbbbo",
            ".obbbbbbbbbbbbo.",
            "..obbbbbbbbbbo..",
            "..obssbbbbssbo..",
            "..obbbbbbbbbbo..",
            "...obbbbbbbbo...",
            "...obbbbbbbbo...",
            "....obbbbbbo....",
            ".....obbbbo.....",
            ".....o.oo.o.....",
            ".....ooooo......"
        ],
        airborneRows: [
            22: ".....obbbbo.....",
            23: ".....oooooo....."
        ]
    )
}
