import Foundation
import Testing
@testable import Claude_Status

/// The rename moved the App Group, and with it everything the user had set.
struct AppGroupMigrationTests {

    private func suite(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// What the old group held is carried over once: settings, the marks the app
    /// cannot work out again, and the files it shares with the widget.
    @Test func whatTheOldGroupHeldIsCarriedOverOnce() throws {
        let legacy = "test.legacy.\(UUID().uuidString)"
        let current = "test.current.\(UUID().uuidString)"
        let old = suite(legacy)
        let new = suite(current)
        defer {
            old.removePersistentDomain(forName: legacy)
            new.removePersistentDomain(forName: current)
        }
        old.set("dots", forKey: "iconStyle")
        old.set(9, forKey: "petSize")
        old.set(["local_a": 1.0], forKey: "claudeDesktopSeenAt")
        // Already answered under the new identifier: the user's own choice wins.
        new.set(true, forKey: "petEnabled")
        old.set(false, forKey: "petEnabled")

        let containers = FileManager.default.temporaryDirectory
            .appendingPathComponent("containers-\(UUID().uuidString)", isDirectory: true)
        let oldContainer = containers.appendingPathComponent(legacy, isDirectory: true)
        let newContainer = containers.appendingPathComponent(current, isDirectory: true)
        try FileManager.default.createDirectory(at: oldContainer, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newContainer, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: containers) }
        try Data("[]".utf8).write(to: oldContainer.appendingPathComponent("sessions.json"))
        try Data("{}".utf8).write(to: oldContainer.appendingPathComponent("productivity.json"))

        AppGroupMigration.run(
            into: new, container: newContainer, legacyIdentifiers: [legacy], groupContainers: containers
        )

        #expect(new.string(forKey: "iconStyle") == "dots")
        #expect(new.integer(forKey: "petSize") == 9)
        #expect(new.dictionary(forKey: "claudeDesktopSeenAt")?.keys.first == "local_a")
        #expect(new.bool(forKey: "petEnabled"))
        #expect(FileManager.default.fileExists(atPath: newContainer.appendingPathComponent("sessions.json").path))

        // Once only: a later change to the old group is not dragged across.
        old.set("emoji", forKey: "iconStyle")
        AppGroupMigration.run(
            into: new, container: newContainer, legacyIdentifiers: [legacy], groupContainers: containers
        )
        #expect(new.string(forKey: "iconStyle") == "dots")
    }

    /// A fresh install has no old group to read, and must not keep looking.
    @Test func nothingToCarryIsStillOnlyLookedForOnce() {
        let current = "test.current.\(UUID().uuidString)"
        let new = suite(current)
        defer { new.removePersistentDomain(forName: current) }

        AppGroupMigration.run(
            into: new,
            container: nil,
            legacyIdentifiers: ["test.missing.\(UUID().uuidString)"],
            groupContainers: FileManager.default.temporaryDirectory
        )

        #expect(new.bool(forKey: AppGroupMigration.flagKey))
        #expect(new.string(forKey: "iconStyle") == nil)
    }
}
