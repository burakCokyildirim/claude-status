import CoreGraphics
import SwiftUI
import Testing
@testable import Clawde

/// Renders the real views: the regressions guarded here only show up in pixels.
@MainActor
struct PetViewTests {

    private static let nibble = PetCharacter.character(for: .nibble)

    private func renderPet(
        _ frame: PetFrame,
        character: PetCharacter,
        mood: PetMood = .waiting,
        sessionCount: Int = 1,
        isBubbleShown: Bool = false,
        isBubbleOpen: Bool = false
    ) throws -> CGImage {
        let scale = PetSize.default.scale
        let panel = PetLayout.panelSize(scale: scale)
        let view = PetView(
            character: character,
            frame: frame,
            mood: mood,
            scale: scale,
            sessionCount: sessionCount,
            isBubbleShown: isBubbleShown,
            isBubbleOpen: isBubbleOpen,
            jumpCount: 0
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

    /// The pixels of `image` inside `rect`, in the points it was laid out in.
    private func pixels(of image: CGImage, in rect: CGRect) throws -> [UInt32] {
        let scale = CGFloat(image.width) / PetLayout.panelSize(scale: PetSize.default.scale).width
        let crop = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
        return pixels(of: try #require(image.cropping(to: crop.integral)))
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
        let unread = try renderPet(frame, character: nibble, mood: .unread, sessionCount: 2)
        let idle = try renderPet(frame, character: nibble, mood: .idle, sessionCount: 2)

        #expect(pixelCount(in: pixels(of: unread), near: SessionPalette.unread) > 0)
        #expect(pixelCount(in: pixels(of: idle), near: SessionPalette.unread) == 0)
    }

    /// While the bubble's list is open the badge draws in to a dot of its colour,
    /// with no count; and with only one session to show, the badge is there only
    /// while a bubble points at it.
    @Test func theBadgeDrawsInWhileTheListIsOpen() throws {
        let nibble = Self.nibble
        let frame = nibble.still(for: .waiting)
        let scale = PetSize.default.scale
        let badge = PetLayout.badgeRect(scale: scale, corner: nibble.badgeCorner, digits: 1)

        let counting = try pixels(of: renderPet(frame, character: nibble, sessionCount: 3), in: badge)
        let open = try pixels(
            of: renderPet(frame, character: nibble, sessionCount: 3, isBubbleShown: true, isBubbleOpen: true),
            in: badge
        )
        #expect(pixelCount(in: counting, near: .white) > 0)
        #expect(pixelCount(in: open, near: .white) == 0)
        #expect(pixelCount(in: open, near: PetMood.waiting.accent) > 0)
        #expect(pixelCount(in: open, near: PetMood.waiting.accent) < pixelCount(in: counting, near: PetMood.waiting.accent))

        let alone = try pixels(of: renderPet(frame, character: nibble), in: badge)
        let pointedAt = try pixels(of: renderPet(frame, character: nibble, isBubbleShown: true), in: badge)
        #expect(pixelCount(in: alone, near: PetMood.waiting.accent) == 0)
        #expect(pixelCount(in: pointedAt, near: PetMood.waiting.accent) > 0)
    }

    /// Pixels within a few steps of `colour` on every channel.
    private func pixelCount(in pixels: [UInt32], near colour: Color) -> Int {
        let resolved = colour.resolve(in: EnvironmentValues())
        let target = [resolved.red, resolved.green, resolved.blue].map { Int(($0 * 255).rounded()) }
        return pixels.count { pixel in
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

    private func session(name: String?, activity: String = "", isUnread: Bool? = nil) -> ClaudeSession {
        ClaudeSession(
            sessionId: "s",
            pid: 1,
            workingDirectory: "/tmp/claude-status",
            projectName: "claude-status",
            state: .idle,
            lastActivityAt: Date().addingTimeInterval(-150),
            iTermSessionId: nil,
            tmuxPaneId: nil,
            tmuxSocket: nil,
            source: .claudeDesktop,
            activity: activity,
            sessionName: name,
            profileName: nil,
            isUnread: isUnread
        )
    }

    /// A line says what the session list says: the name over its folder, the
    /// host app, and what it is doing, and the state over its time. The folder
    /// is left out where it is already the name.
    @Test func bubbleLinesReadLikeTheSessionList() {
        let named = PetBubbleRow(session: session(name: "Desktop pet", activity: "Bash", isUnread: true))
        #expect(named.title == "Desktop pet")
        #expect(named.details == ["claude-status", "Claude", "Bash"])
        #expect(named.stateLabel == "Unread")
        #expect(named.time == "2m ago")
        #expect(named.mood == .unread)
        #expect(named.emoji == "\u{1F535}")

        let unnamed = PetBubbleRow(session: session(name: nil))
        #expect(unnamed.title == "claude-status")
        #expect(unnamed.details == ["Claude"])
        #expect(unnamed.stateLabel == "Idle")
    }

    /// A long session name has to truncate. Sized to its text instead, the
    /// bubble outgrows its panel, which clips both ends and the state label.
    @Test func bubbleKeepsToItsWidth() throws {
        let bubble = PetBubbleView(
            rows: [
                PetBubbleRow(session: session(
                    name: "feat-affectionate-archimedes-bsew0o-desktop-pet-with-a-long-name",
                    activity: "a-tool-with-a-long-name-too"
                )),
                PetBubbleRow(session: session(name: "short")),
                PetBubbleRow(moreSessions: 3),
            ],
            isAbove: true,
            highlighted: 1,
            tailX: PetLayout.bubbleTailInset,
            isShown: true
        )
        let renderer = ImageRenderer(content: bubble)
        let image = try #require(renderer.cgImage)
        #expect(CGFloat(image.width) / renderer.scale == PetLayout.bubbleSize(rows: 3).width)
        #expect(CGFloat(image.height) / renderer.scale == PetLayout.bubbleSize(rows: 3).height)
    }
}
