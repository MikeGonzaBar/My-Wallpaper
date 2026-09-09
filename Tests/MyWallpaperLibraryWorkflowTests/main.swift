import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("Video library workflow test failed: \(message)\n", stderr)
        exit(1)
    }
}

let stableSettings = WallpaperSettings(
    screens: [ScreenConfiguration(
        screenID: "display",
        screenName: "Display",
        mode: .playlist
    )],
    scaling: .fit,
    playbackQuality: .performance,
    optimizationProfile: .maximum
)
let stableSettingsObject = try! JSONSerialization.jsonObject(
    with: JSONEncoder().encode(stableSettings)
) as! [String: Any]
expect(stableSettingsObject["scaling"] as? String == "fit", "scaling should encode a stable token")
expect(
    stableSettingsObject["playbackQuality"] as? String == "performance",
    "playback quality should encode a stable token"
)
let stableScreens = stableSettingsObject["screens"] as! [[String: Any]]
expect(stableScreens[0]["mode"] as? String == "playlist", "playback mode should encode a stable token")

let legacySettingsJSON = #"{"videos":[],"screens":[{"screenID":"display","screenName":"Display","mode":"Single video","videoIDs":[],"stashedPlaylistVideoIDs":[]}],"isMuted":true,"scaling":"Fit to screen","playbackQuality":"Original quality","optimizationProfile":"1440p / 60 FPS"}"#
let decodedLegacySettings = try! JSONDecoder().decode(
    WallpaperSettings.self,
    from: Data(legacySettingsJSON.utf8)
)
expect(
    decodedLegacySettings.scaling == .fit
        && decodedLegacySettings.playbackQuality == .original
        && decodedLegacySettings.optimizationProfile == .efficient
        && decodedLegacySettings.screens[0].mode == .single,
    "legacy presentation values should remain decodable"
)
let unknownSettingsJSON = #"{"schemaVersion":1,"videos":[],"screens":[],"isMuted":true,"scaling":"stretch"}"#
expect(
    (try? JSONDecoder().decode(
        WallpaperSettings.self,
        from: Data(unknownSettingsJSON.utf8)
    )) == nil,
    "unknown persisted values should fail closed"
)

let unassignedVideo = ManagedVideo(
    id: "unassigned",
    displayName: "Unassigned",
    path: "/video.mp4"
)
let modernUnassigned = WallpaperSettingsMigration.assigningLegacyVideoIfNeeded(
    in: WallpaperSettings(videos: [unassignedVideo]),
    displays: [DisplayInfo(id: "display", name: "Display")],
    decodedFromLegacyFormat: false
)
expect(
    modernUnassigned.screens.isEmpty,
    "modern library-only settings must not be mistaken for a legacy display migration"
)

let existingVideo = ManagedVideo(
    id: "existing",
    displayName: "Mountain Drive 4K",
    path: "/videos/existing.mp4",
    contentFingerprint: "existing-content"
)
let firstCandidateID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
let secondCandidateID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
let thirdCandidateID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
let fourthCandidateID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
let duplicateReferences = VideoLibraryLogic.duplicateReferences(
    candidateIDs: [firstCandidateID, secondCandidateID, thirdCandidateID, fourthCandidateID],
    for: ["Renamed Mountain", "Ocean", "Another Ocean Name", "Mountain Drive 4K"],
    fingerprints: ["existing-content", "ocean-content", "ocean-content", "different-content"],
    existingVideos: [existingVideo]
)
expect(
    duplicateReferences == [
        .library(videoID: "existing"),
        nil,
        .selection(candidateID: secondCandidateID),
        nil,
    ],
    "content matching should find renamed library videos and repeated selections without blocking different content"
)

let fallbackReferences = VideoLibraryLogic.duplicateReferences(
    candidateIDs: [firstCandidateID],
    for: ["MOUNTAIN DRIVE 4K.mov"],
    fingerprints: [nil],
    existingVideos: [ManagedVideo(
        id: "legacy-without-fingerprint",
        displayName: "Mountain Drive 4K",
        path: "/videos/legacy.mp4"
    )]
)
expect(
    fallbackReferences == [nil],
    "a matching filename must not suppress an import when content cannot be fingerprinted"
)

let newImportedVideo = ManagedVideo(
    id: "new-import",
    displayName: "Ocean",
    path: "/videos/new-import.mp4"
)
let resolutionCandidates = [
    VideoImportCandidate(
        id: firstCandidateID,
        sourceURL: URL(fileURLWithPath: "/incoming/renamed.mp4"),
        displayName: "Renamed Mountain",
        fileSize: 1,
        metadata: nil,
        contentFingerprint: "existing-content",
        duplicate: .library(videoID: "existing")
    ),
    VideoImportCandidate(
        id: secondCandidateID,
        sourceURL: URL(fileURLWithPath: "/incoming/ocean.mp4"),
        displayName: "Ocean",
        fileSize: 2,
        metadata: nil,
        contentFingerprint: "ocean-content",
        duplicate: nil
    ),
    VideoImportCandidate(
        id: thirdCandidateID,
        sourceURL: URL(fileURLWithPath: "/incoming/ocean-copy.mp4"),
        displayName: "Ocean Copy",
        fileSize: 2,
        metadata: nil,
        contentFingerprint: "ocean-content",
        duplicate: .selection(candidateID: secondCandidateID)
    ),
]
expect(
    VideoLibraryLogic.resolvedVideoIDs(
        for: resolutionCandidates,
        importedVideos: [newImportedVideo]
    ) == ["existing", "new-import"],
    "review completion should reuse library matches and resolve repeated selections to one imported record"
)

expect(
    VideoLibraryLogic.assigning(
        ["two", "three", "two"],
        to: ["one", "two"],
        mode: .playlist
    ) == ["one", "two", "three"],
    "playlist assignment should preserve order and avoid duplicates"
)

expect(
    VideoLibraryLogic.assigning(
        ["replacement", "ignored"],
        to: ["old"],
        mode: .single
    ) == ["replacement"],
    "single-video assignment should keep only the first selection"
)

let screens = [
    ScreenConfiguration(
        screenID: "one",
        screenName: "One",
        mode: .playlist,
        videoIDs: ["video"],
        startVideoID: "video"
    ),
    ScreenConfiguration(
        screenID: "two",
        screenName: "Two",
        mode: .single,
        videoIDs: [],
        stashedPlaylistVideoIDs: ["video"]
    )
]
expect(
    VideoLibraryLogic.usageCount(for: "video", screens: screens) == 2,
    "usage should include active and stashed playlist assignments"
)

let duplicateOne = ManagedVideo(
    id: "duplicate-one",
    displayName: "Same Video.mp4",
    path: "/videos/duplicate-one.mp4"
)
let duplicateTwo = ManagedVideo(
    id: "duplicate-two",
    displayName: "same video.MOV",
    path: "/videos/duplicate-two.mov"
)
let sameNameDifferentContent = ManagedVideo(
    id: "different-content",
    displayName: "Same Video",
    path: "/videos/different-content.mp4"
)
let unreadableCandidate = ManagedVideo(
    id: "unreadable",
    displayName: "Same Video",
    path: "/videos/unreadable.mp4"
)
let duplicateSettings = WallpaperSettings(
    videos: [duplicateOne, duplicateTwo, sameNameDifferentContent, unreadableCandidate],
    screens: [
        ScreenConfiguration(
            screenID: "display-one",
            screenName: "Display One",
            mode: .playlist,
            videoIDs: ["duplicate-two", "different-content"],
            startVideoID: "duplicate-two",
            stashedPlaylistVideoIDs: ["duplicate-one", "duplicate-two"]
        ),
        ScreenConfiguration(
            screenID: "display-two",
            screenName: "Display Two",
            mode: .playlist,
            videoIDs: ["duplicate-one", "duplicate-two"],
            startVideoID: "duplicate-two"
        ),
    ]
)
let fingerprints = [
    "duplicate-one": "matching-content",
    "duplicate-two": "matching-content",
    "different-content": "different-content",
]
let deduplicated = VideoLibraryLogic.deduplicatingLegacyVideos(
    in: duplicateSettings,
    sampledFingerprint: { fingerprints[$0.id] },
    fullFingerprint: { fingerprints[$0.id] }
)
expect(
    deduplicated.settings.videos.map(\.id) == [
        "duplicate-one", "different-content", "unreadable",
    ],
    "deduplication should retain the first matching record and preserve uncertain records"
)
expect(
    deduplicated.redundantVideos.map(\.id) == ["duplicate-two"],
    "deduplication should report only confirmed redundant records"
)
expect(
    deduplicated.settings.screens[0].videoIDs == ["duplicate-one", "different-content"]
        && deduplicated.settings.screens[0].startVideoID == "duplicate-one"
        && deduplicated.settings.screens[0].stashedPlaylistVideoIDs == ["duplicate-one"],
    "deduplication should remap active, starting, and stashed playlist IDs"
)
expect(
    deduplicated.settings.screens[1].videoIDs == ["duplicate-one"]
        && deduplicated.settings.screens[1].startVideoID == "duplicate-one",
    "deduplication should collapse repeated canonical IDs without changing their order"
)
expect(
    VideoLibraryLogic.deduplicatingLegacyVideos(
        in: deduplicated.settings,
        sampledFingerprint: { fingerprints[$0.id] },
        fullFingerprint: { fingerprints[$0.id] }
    ).redundantVideos.isEmpty,
    "the legacy deduplication migration should be idempotent"
)
let renamedCopy = ManagedVideo(
    id: "renamed-copy",
    displayName: "A Different Name",
    path: "/videos/renamed-copy.mp4"
)
let differentlyNamedSettings = WallpaperSettings(videos: [duplicateOne, renamedCopy])
expect(
    VideoLibraryLogic.deduplicatingLegacyVideos(
        in: differentlyNamedSettings,
        sampledFingerprint: { _ in "matching-content" },
        fullFingerprint: { _ in "matching-content" }
    ).settings.videos.count == 2,
    "matching content with different user-visible names should remain separate"
)
let sampledCollision = VideoLibraryLogic.deduplicatingLegacyVideos(
    in: WallpaperSettings(videos: [duplicateOne, duplicateTwo]),
    sampledFingerprint: { _ in "same-sampled-layout" },
    fullFingerprint: { $0.id }
)
expect(
    sampledCollision.redundantVideos.isEmpty && sampledCollision.settings.videos.count == 2,
    "a sampled fingerprint collision must not cause destructive deduplication"
)

let fingerprintDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("my-wallpaper-fingerprint-\(UUID().uuidString)", isDirectory: true)
try! FileManager.default.createDirectory(
    at: fingerprintDirectory,
    withIntermediateDirectories: true
)
defer { try? FileManager.default.removeItem(at: fingerprintDirectory) }
let firstFingerprintURL = fingerprintDirectory.appendingPathComponent("first.mp4")
let copiedFingerprintURL = fingerprintDirectory.appendingPathComponent("copy.mp4")
let differentFingerprintURL = fingerprintDirectory.appendingPathComponent("different.mp4")
let sampledCollisionOneURL = fingerprintDirectory.appendingPathComponent("sample-collision-one.mp4")
let sampledCollisionTwoURL = fingerprintDirectory.appendingPathComponent("sample-collision-two.mp4")
let sampleData = Data(repeating: 0x41, count: 2_500_000)
try! sampleData.write(to: firstFingerprintURL)
try! sampleData.write(to: copiedFingerprintURL)
try! Data(repeating: 0x42, count: sampleData.count).write(to: differentFingerprintURL)
let collisionSize = 6 * 1_048_576
let collisionOneData = Data(repeating: 0x31, count: collisionSize)
var collisionTwoData = collisionOneData
collisionTwoData.replaceSubrange(
    1_310_720..<1_572_864,
    with: Data(repeating: 0x32, count: 262_144)
)
try! collisionOneData.write(to: sampledCollisionOneURL)
try! collisionTwoData.write(to: sampledCollisionTwoURL)
let firstFingerprint = VideoContentFingerprint.sampled(at: firstFingerprintURL)
let copiedFingerprint = VideoContentFingerprint.sampled(at: copiedFingerprintURL)
let differentFingerprint = VideoContentFingerprint.sampled(at: differentFingerprintURL)
expect(
    firstFingerprint == copiedFingerprint,
    "identical file copies should have the same sampled content fingerprint"
)
expect(
    VideoContentFingerprint.sampled(at: sampledCollisionOneURL)
        == VideoContentFingerprint.sampled(at: sampledCollisionTwoURL)
        && VideoContentFingerprint.full(at: sampledCollisionOneURL)
            != VideoContentFingerprint.full(at: sampledCollisionTwoURL),
    "full hashing should distinguish files whose differences fall outside every sampled region"
)
expect(
    VideoContentFingerprint.full(at: firstFingerprintURL)
        == VideoContentFingerprint.full(at: copiedFingerprintURL)
        && VideoContentFingerprint.full(at: firstFingerprintURL)
            != VideoContentFingerprint.full(at: differentFingerprintURL),
    "full streaming fingerprints should confirm exact content before destructive deduplication"
)
expect(
    firstFingerprint != differentFingerprint,
    "same-sized files with different content should not share a fingerprint"
)
expect(
    firstFingerprint.map(VideoContentFingerprint.isCurrent) == true
        && !VideoContentFingerprint.isCurrent("legacy-unversioned-fingerprint"),
    "fingerprints should carry a version so stale persisted values can be refreshed"
)

print("Video library workflow tests passed.")
