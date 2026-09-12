import CoreGraphics
import SwiftUI
import Testing
@testable import Claude_Status

/// Renders the real views: the regressions guarded here only show up in pixels.
@MainActor
struct PetViewTests {

    /// The backdrop plus the seven colours a waiting Nibble is drawn with.
    private static let paletteColourCount = 8

    private func renderPet(
        _ transform: PetTransform,
        state: SessionState = .waiting,
        isUnread: Bool = false
    ) throws -> CGImage {
        let scale = PetSize.medium.scale
        let panel = PetLayout.panelSize(scale: scale)
        let view = PetView(
            character: PetCharacter.character(for: .nibble),
            state: state,
            isUnread: isUnread,
            transform: transform,
            scale: scale,
            sessionCount: 1,
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
        return Set(pixels).count
    }

    @Test func restingSpriteUsesOnlyPaletteColours() throws {
        #expect(distinctColours(in: try renderPet(.identity)) <= Self.paletteColourCount)
    }

    /// Squash and stretch puts cell edges between device pixels. Filled with
    /// anti-aliasing, every seam lets the backdrop bleed through as a grid.
    @Test func squashedSpriteKeepsHardPixelEdges() throws {
        let squash = PetMotion.transform(for: .poke, phase: 0.18)
        #expect(distinctColours(in: try renderPet(squash)) <= Self.paletteColourCount)
    }

    /// At the top of a hop the stretched body rises past the pet box, so the
    /// mark above the head has to be drawn there rather than clipped off.
    @Test func hopKeepsTheMarkAboveTheHead() throws {
        let hopPeak = PetMotion.transform(for: .poke, phase: 0.42)
        #expect(distinctColours(in: try renderPet(hopPeak)) == distinctColours(in: try renderPet(.identity)))
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
