import XCTest
@testable import MyWallpaper

final class VideoLibraryImporterTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var videoFiles: ManagedVideoFileStore!
    private var importer: VideoLibraryImporter!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        videoFiles = ManagedVideoFileStore(
            rootDirectory: temporaryDirectory.appendingPathComponent("managed", isDirectory: true)
        )
        importer = VideoLibraryImporter(
            videoOptimizer: ImporterVideoOptimizer(),
            videoFiles: videoFiles
        )
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: temporaryDirectory.path) {
            try FileManager.default.removeItem(at: temporaryDirectory)
        }
        importer = nil
        videoFiles = nil
        temporaryDirectory = nil
    }

    func testPrepareCandidatesCollectsMetadataFingerprintAndDuplicateIdentity() async throws {
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        let source = temporaryDirectory.appendingPathComponent("Sample.mov")
        try Data("same video bytes".utf8).write(to: source)
        let fingerprint = try XCTUnwrap(VideoContentFingerprint.sampled(at: source))
        let existing = ManagedVideo(
            id: "existing",
            displayName: "Different Name",
            path: "/existing.mov",
            contentFingerprint: fingerprint
        )

        let candidates = await importer.prepareCandidates(
            from: [source],
            existingVideos: [existing]
        )

        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.displayName, "Sample")
        XCTAssertEqual(candidate.fileSize, Int64("same video bytes".utf8.count))
        XCTAssertEqual(candidate.metadata?.width, 1920)
        XCTAssertEqual(candidate.contentFingerprint, fingerprint)
        XCTAssertEqual(candidate.duplicate, .library(videoID: existing.id))
    }

    func testImportCopiesVideoIntoPrivateManagedDirectory() async throws {
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        let source = temporaryDirectory.appendingPathComponent("Sample.mov")
        let sourceData = Data("video bytes".utf8)
        try sourceData.write(to: source)
        let candidate = VideoImportCandidate(
            sourceURL: source,
            displayName: "Sample",
            fileSize: Int64(sourceData.count),
            metadata: nil,
            contentFingerprint: nil,
            duplicate: nil
        )

        let videos = try await importer.importVideos(candidates: [candidate])

        let video = try XCTUnwrap(videos.first)
        XCTAssertEqual(try Data(contentsOf: video.url), sourceData)
        XCTAssertEqual(video.url.deletingLastPathComponent(), try videoFiles.managedVideosDirectory())
        XCTAssertEqual(permissions(at: video.url), 0o600)
        XCTAssertNotNil(video.contentFingerprint)
    }

    private func permissions(at url: URL) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.posixPermissions] as? NSNumber)?.intValue ?? 0
    }
}

private struct ImporterVideoOptimizer: VideoOptimizing {
    func metadata(for sourceURL: URL) async throws -> VideoTechnicalMetadata {
        VideoTechnicalMetadata(
            width: 1920,
            height: 1080,
            frameRate: 30,
            estimatedBitRate: 8_000_000
        )
    }

    func optimize(
        sourceURL: URL,
        destinationURL: URL,
        profile: VideoOptimizationProfile,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        progress(1)
    }
}
