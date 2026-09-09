import XCTest
@testable import MyWallpaper

@MainActor
final class SettingsRecoveryTests: XCTestCase {
    func testValidBackupWinsAfterCorruptCanonicalSettings() throws {
        let backup = WallpaperSettings(
            configurationGeneration: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            videos: [ManagedVideo(id: "backup", displayName: "Backup", path: "/backup.mp4")]
        )
        let result = WallpaperStore.decodeInitialSettings(
            candidates: [
                SettingsDataCandidate(data: Data("not json".utf8), requiresCanonicalEnvelope: true),
                SettingsDataCandidate(data: try JSONEncoder().encode(backup), requiresCanonicalEnvelope: true)
            ],
            foundPersistedData: true
        )

        XCTAssertEqual(result.settings, backup)
        XCTAssertNil(result.legacySettings)
        XCTAssertFalse(result.hadUnrecoverableData)
        XCTAssertTrue(result.allowsDestructiveCleanup)
    }

    func testUnenvelopedPrimaryCannotMaskValidUserDefaultsRecovery() throws {
        let defaults = WallpaperSettings(
            videos: [ManagedVideo(id: "defaults", displayName: "Defaults", path: "/defaults.mp4")]
        )
        let unenveloped = Data(#"{"videos":[],"screens":[]}"#.utf8)
        let result = WallpaperStore.decodeInitialSettings(
            candidates: [
                SettingsDataCandidate(data: unenveloped, requiresCanonicalEnvelope: true),
                SettingsDataCandidate(data: try JSONEncoder().encode(defaults), requiresCanonicalEnvelope: false)
            ],
            foundPersistedData: true
        )

        XCTAssertEqual(result.settings, defaults)
        XCTAssertFalse(result.hadUnrecoverableData)
    }

    func testLegacySingleVideoPayloadIsKeptForExplicitMigration() {
        let legacy = Data(#"{"videoPath":"/legacy.mp4","videoDisplayName":"Legacy","idleMinutes":5,"isEnabled":true,"isMuted":false,"scaling":"Fill screen"}"#.utf8)
        let result = WallpaperStore.decodeInitialSettings(
            candidates: [SettingsDataCandidate(data: legacy, requiresCanonicalEnvelope: false)],
            foundPersistedData: true
        )

        XCTAssertNil(result.settings)
        XCTAssertEqual(result.legacySettings?.videoPath, "/legacy.mp4")
        XCTAssertEqual(result.legacySettings?.videoDisplayName, "Legacy")
        XCTAssertFalse(result.hadUnrecoverableData)
    }

    func testOnlyInvalidPersistedDataFailsClosedAndDisablesCleanup() {
        let result = WallpaperStore.decodeInitialSettings(
            candidates: [
                SettingsDataCandidate(data: Data("bad".utf8), requiresCanonicalEnvelope: true),
                SettingsDataCandidate(data: Data("also bad".utf8), requiresCanonicalEnvelope: false)
            ],
            foundPersistedData: true
        )

        XCTAssertNil(result.settings)
        XCTAssertNil(result.legacySettings)
        XCTAssertTrue(result.hadUnrecoverableData)
        XCTAssertFalse(result.allowsDestructiveCleanup)
        XCTAssertFalse(result.allowsAutomaticPersistence)
    }

    func testFirstLaunchProducesDefaultSettingsWithoutTreatingItAsDataLoss() {
        let result = WallpaperStore.decodeInitialSettings(
            candidates: [],
            foundPersistedData: false
        )

        XCTAssertEqual(result.settings?.schemaVersion, WallpaperSettings.currentSchemaVersion)
        XCTAssertTrue(result.settings?.videos.isEmpty == true)
        XCTAssertTrue(result.settings?.screens.isEmpty == true)
        XCTAssertTrue(result.settings?.isMuted == true)
        XCTAssertEqual(result.settings?.scaling, .fill)
        XCTAssertEqual(result.settings?.playbackQuality, .original)
        XCTAssertEqual(result.settings?.optimizationProfile, .efficient)
        XCTAssertFalse(result.hadUnrecoverableData)
        XCTAssertTrue(result.allowsDestructiveCleanup)
        XCTAssertTrue(result.allowsAutomaticPersistence)
    }
}
