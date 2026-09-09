import XCTest
@testable import MyWallpaper

final class VideoLibraryLogicTests: XCTestCase {
    func testDuplicateReferencesRejectMismatchedParallelInputs() {
        let candidateID = UUID()

        XCTAssertEqual(
            VideoLibraryLogic.duplicateReferences(
                candidateIDs: [candidateID],
                for: ["One", "Two"],
                fingerprints: ["fingerprint"],
                existingVideos: []
            ),
            [nil, nil]
        )
    }

    func testDuplicateReferencesUsesFirstExistingLibraryRecordDeterministically() {
        let candidateID = UUID()
        let videos = [
            ManagedVideo(id: "first", displayName: "One", path: "/one.mp4", contentFingerprint: "same"),
            ManagedVideo(id: "second", displayName: "Two", path: "/two.mp4", contentFingerprint: "same")
        ]

        XCTAssertEqual(
            VideoLibraryLogic.duplicateReferences(
                candidateIDs: [candidateID],
                for: ["Renamed"],
                fingerprints: ["same"],
                existingVideos: videos
            ),
            [.library(videoID: "first")]
        )
    }

    func testResolvedVideoIDsSkipsDanglingSelectionAndMissingImportedRecords() {
        let firstID = UUID()
        let danglingID = UUID()
        let candidates = [
            candidate(id: firstID, duplicate: nil),
            candidate(id: UUID(), duplicate: .selection(candidateID: danglingID)),
            candidate(id: UUID(), duplicate: nil)
        ]

        XCTAssertEqual(
            VideoLibraryLogic.resolvedVideoIDs(
                for: candidates,
                importedVideos: [ManagedVideo(id: "imported", displayName: "Imported", path: "/imported.mp4")]
            ),
            ["imported"]
        )
    }

    func testNormalizedNameIgnoresExtensionWhitespaceCaseAndDiacritics() {
        XCTAssertEqual(
            VideoLibraryLogic.normalizedName("  Móuntain Drive.MOV  "),
            VideoLibraryLogic.normalizedName("mountain drive.mp4")
        )
    }

    func testDeduplicationDoesNotCompareDistinctDisplayNames() {
        let first = ManagedVideo(id: "first", displayName: "One", path: "/one.mp4")
        let second = ManagedVideo(id: "second", displayName: "Two", path: "/two.mp4")

        let result = VideoLibraryLogic.deduplicatingLegacyVideos(
            in: WallpaperSettings(videos: [first, second]),
            sampledFingerprint: { _ in "same-sample" },
            fullFingerprint: { _ in "same-full" }
        )

        XCTAssertEqual(result.settings.videos, [first, second])
        XCTAssertTrue(result.redundantVideos.isEmpty)
    }

    private func candidate(id: UUID, duplicate: VideoImportDuplicate?) -> VideoImportCandidate {
        VideoImportCandidate(
            id: id,
            sourceURL: URL(fileURLWithPath: "/candidate.mp4"),
            displayName: "Candidate",
            fileSize: 1,
            metadata: nil,
            contentFingerprint: nil,
            duplicate: duplicate
        )
    }
}
