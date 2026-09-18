import Foundation
import Testing
@testable import Clawde

struct PetSettingsTests {

    /// Whole points per sprite pixel keep the pixel art crisp, and the slider's
    /// ends bound whatever is asked for.
    @Test func sizeStaysWithinTheSlidersRange() {
        #expect(PetSize(8).scale == 8)
        #expect(PetSize(0) == PetSize(PetSize.range.lowerBound))
        #expect(PetSize(99) == PetSize(PetSize.range.upperBound))
    }

    /// A stored size that is missing or not a number reads as the default, and one
    /// out of range is pulled back in.
    @Test func storedSizeIsReadAsANumber() {
        let suite = "PetSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)
        defer { defaults?.removePersistentDomain(forName: suite) }

        #expect(PetSettings.load(from: defaults).size == .default)
        defaults?.set("large", forKey: PetSettings.Keys.size)
        #expect(PetSettings.load(from: defaults).size == .default)
        defaults?.set(12, forKey: PetSettings.Keys.size)
        #expect(PetSettings.load(from: defaults).size == PetSize(12))
        defaults?.set(40, forKey: PetSettings.Keys.size)
        #expect(PetSettings.load(from: defaults).size == PetSize(PetSize.range.upperBound))
    }
}
