import CoreGraphics
import SwiftUI
import Testing
@testable import Claude_Status

/// Renders the real views: the regressions guarded here only show up in pixels.
@MainActor
struct PetViewTests {

    private static let nibble = PetCharacter.character(for: .nibble)

    private func renderPet(
        _ frame: PetFrame,
        character: PetCharacter,
        state: SessionState = .waiting,
        isUnread: Bool = false,
        sessionCount: Int = 1
    ) throws -> CGImage {
        let scale = PetSize.default.scale
        let panel = PetLayout.panelSize(scale: scale)
        let view = PetView(
            character: character,
            frame: frame,
            state: state,
            isUnread: isUnread,
            scale: scale,
            sessionCount: sessionCount,
            bubbleTitle: nil
        )
        .frame(width: panel.width, height: panel.height)
        .background(Color.black)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return try #require(renderer.cgImage)
    }

    /// Pixel art drawn over a flat backdrop only ever produces palette colours;
    /// anti-aliased cell edges add blends of them.
    private func distinctColours(in image: CGImage) -> Int {
        Set(pixels(of: image)).count
    }

    private func pixels(of image: CGImage) -> [UInt32] {
        let width = image.width
        let height = image.height
        var pixels = [UInt32](repeating: 0, count: width * height)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return pixels
    }

    /// The pet is drawn from the frame it is handed, and from nothing else.
    @Test func drawsTheFrameItIsGiven() throws {
        let nibble = Self.nibble
        let waiting = try renderPet(nibble.still(for: .waiting), character: nibble)

        #expect(pixels(of: waiting) != pixels(of: try renderPet(nibble.still(for: .idle), character: nibble)))
        #expect(pixels(of: waiting) == pixels(of: try renderPet(nibble.still(for: .waiting), character: nibble)))
    }

    /// Unread keeps its own colour on the badge rather than the state's: the point
    /// of the signal is that it does not claim the session is blocked on the user.
    @Test func anUnreadPetsBadgeIsDrawnInItsOwnColour() throws {
        let nibble = Self.nibble
        let frame = nibble.still(for: .unread)
        let unread = try renderPet(frame, character: nibble, state: .idle, isUnread: true, sessionCount: 2)
        let idle = try renderPet(frame, character: nibble, state: .idle, isUnread: false, sessionCount: 2)

        #expect(pixelCount(in: unread, near: SessionPalette.unread) > 0)
        #expect(pixelCount(in: idle, near: SessionPalette.unread) == 0)
    }

    /// Pixels within a few steps of `colour` on every channel.
    private func pixelCount(in image: CGImage, near colour: Color) -> Int {
        let resolved = colour.resolve(in: EnvironmentValues())
        let target = [resolved.red, resolved.green, resolved.blue].map { Int(($0 * 255).rounded()) }
        return pixels(of: image).count { pixel in
            let channels = [Int(pixel & 0xFF), Int(pixel >> 8 & 0xFF), Int(pixel >> 16 & 0xFF)]
            return zip(channels, target).allSatisfy { abs($0 - $1) <= 6 }
        }
    }

    /// The backdrop plus the colours the frame uses, and no blends between them.
    @Test func spriteUsesOnlyPaletteColours() throws {
        for id in PetCharacterID.allCases {
            let character = PetCharacter.character(for: id)
            let frame = character.still(for: .active)
            let keys = Set(frame.rows.joined()).subtracting(["."])
            #expect(distinctColours(in: try renderPet(frame, character: character)) <= keys.count + 1)
        }
    }

    /// A long session name has to truncate. Sized to its text instead, the
    /// bubble outgrows the panel, which clips both ends and the state label.
    @Test func bubbleFitsTheWidthItIsOffered() throws {
        let bubble = PetBubbleView(
            title: "feat-affectionate-archimedes-bsew0o-desktop-pet-with-a-long-name",
            stateLabel: "Waiting",
            accent: .orange
        )
        let renderer = ImageRenderer(content: bubble)
        renderer.proposedSize = ProposedViewSize(width: PetLayout.bubbleWidth, height: nil)
        let image = try #require(renderer.cgImage)
        #expect(CGFloat(image.width) / renderer.scale <= PetLayout.bubbleWidth)
    }
}
