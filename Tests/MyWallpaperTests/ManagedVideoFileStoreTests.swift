import XCTest
@testable import MyWallpaper

final class ManagedVideoFileStoreTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var store: ManagedVideoFileStore!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = ManagedVideoFileStore(rootDirectory: temporaryDirectory)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: temporaryDirectory.path) {
            try FileManager.default.removeItem(at: temporaryDirectory)
        }
        store = nil
        temporaryDirectory = nil
    }

    func testManagedDirectoriesUsePrivatePermissions() throws {
        let managed = try store.managedVideosDirectory()
        let optimized = try store.optimizedVideosDirectory()

        XCTAssertEqual(permissions(at: temporaryDirectory), 0o700)
        XCTAssertEqual(permissions(at: managed), 0o700)
        XCTAssertEqual(permissions(at: optimized), 0o700)
    }

    func testRemoveFileRejectsPathOutsideOwnedDirectory() throws {
        let managed = try store.managedVideosDirectory()
        let outside = temporaryDirectory.appendingPathComponent("outside.mov")
        try Data("video".utf8).write(to: outside)

        XCTAssertThrowsError(try store.removeFileIfPresent(at: outside, ownedBy: managed))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testOrphanCleanupRetainsOnlyReferencedOptimizedFiles() throws {
        let optimized = try store.optimizedVideosDirectory()
        let retained = optimized.appendingPathComponent("retained.mp4")
        let orphaned = optimized.appendingPathComponent("orphaned.mp4")
        try Data("retained".utf8).write(to: retained)
        try Data("orphaned".utf8).write(to: orphaned)

        store.removeOrphanedOptimizedFiles(retaining: [retained.path])

        XCTAssertTrue(FileManager.default.fileExists(atPath: retained.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphaned.path))
    }

    private func permissions(at url: URL) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.posixPermissions] as? NSNumber)?.intValue ?? 0
    }
}
