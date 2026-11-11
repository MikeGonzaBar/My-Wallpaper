import AppKit
import Foundation

private func expect(_ condition: Bool, _ message: String) {
    precondition(condition, "Improvement workflow test failed: \(message)")
}

@MainActor
private func waitUntil(_ message: String, _ condition: () async -> Bool) async throws {
    let deadline = Date().addingTimeInterval(5)
    while !(await condition()) {
        guard Date() < deadline else { fatalError("Timed out: \(message)") }
        try await Task.sleep(for: .milliseconds(5))
    }
}

private enum StubFailure: LocalizedError {
    case encoding
    var errorDescription: String? { "Hardware encoder unavailable" }
}

private actor ControlledOptimizer: VideoOptimizing {
    struct Pending {
        let destination: URL
        let completion: CheckedContinuation<Void, Error>
    }
    private var pending: [Pending] = []
    var pendingCount: Int { pending.count }

    func metadata(for sourceURL: URL) async throws -> VideoTechnicalMetadata {
        VideoTechnicalMetadata(width: 1920, height: 1080, frameRate: 30, estimatedBitRate: 1_000_000, durationSeconds: 1)
    }

    func optimize(sourceURL: URL, destinationURL: URL, profile: VideoOptimizationProfile,
                  progress: @escaping @Sendable (Double) -> Void) async throws {
        progress(0.5)
        try await withCheckedThrowingContinuation { continuation in
            pending.append(Pending(destination: destinationURL, completion: continuation))
        }
    }

    func finish(failing: Bool = false) throws -> URL {
        let item = pending.removeFirst()
        // Deliberately ignore cancellation to test late completion from an obsolete encoder.
        if failing {
            item.completion.resume(throwing: StubFailure.encoding)
        } else {
            do {
                try Data("optimized".utf8).write(to: item.destination)
                item.completion.resume()
            } catch {
                item.completion.resume(throwing: error)
                throw error
            }
        }
        return item.destination
    }
}

@MainActor
private final class StubApplication: ApplicationPresenting {
    var presentations = 0
    func prepareToPresentWindow() { presentations += 1 }
    func activate() {}
}

@MainActor
private final class StubWindow: MainWindowControlling {
    var identifier: NSUserInterfaceItemIdentifier?
    var isEffectivelyVisible = false
    var presentations = 0
    func makeKeyAndOrderFront(_ sender: Any?) { presentations += 1; isEffectivelyVisible = true }
    func orderOut(_ sender: Any?) { isEffectivelyVisible = false }
}

@main
private struct ImprovementTests {
    @MainActor
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await testOptimization(root: root.appendingPathComponent("optimization"))
        try await testRecovery(root: root.appendingPathComponent("recovery"))
        testPlaylistEditing()
        try testStorageAndAvailability(root: root.appendingPathComponent("storage"))
        testWindowReopening()
        print("Improvement workflow tests passed: optimization, recovery, playlist undo, storage, and window reopening.")
    }

    @MainActor
    static func testOptimization(root: URL) async throws {
        let files = ManagedVideoFileStore(rootDirectory: root)
        let source = try files.managedVideosDirectory().appendingPathComponent("original.mp4")
        try Data("original".utf8).write(to: source)
        let video = ManagedVideo(id: "video", displayName: "Video", path: source.path)
        var settings = WallpaperSettings(videos: [video], playbackQuality: .performance)
        let optimizer = ControlledOptimizer()
        var allowsCommit = true
        let coordinator = VideoOptimizationCoordinator(optimizer: optimizer, files: files, settings: { settings }) {
            video, path, profile, metadata in
            guard allowsCommit, let index = settings.videos.firstIndex(where: { $0.id == video.id && $0.path == video.path }) else { return false }
            settings.videos[index].optimizedPath = path
            settings.videos[index].optimizedProfile = profile
            settings.videos[index].sourceMetadata = metadata
            return true
        }
        coordinator.enqueue()
        try await waitUntil("first encoder started") { await optimizer.pendingCount == 1 }
        coordinator.enqueue() // Must not queue a duplicate of the active item.
        coordinator.suspend(.preview)
        coordinator.suspend(.nativeScreenSaver)
        expect(coordinator.states[video.id] == .paused, "competing playback must pause optimization")
        let cancelledOutput = try await optimizer.finish()
        try await waitUntil("cancelled output cleaned") { !FileManager.default.fileExists(atPath: cancelledOutput.path) }
        coordinator.resume(.preview)
        expect(coordinator.states[video.id] == .paused, "one remaining playback reason must keep the queue paused")
        coordinator.resume(.nativeScreenSaver)
        try await waitUntil("resumed encoder started") { await optimizer.pendingCount == 1 }
        _ = try await optimizer.finish(failing: true)
        try await waitUntil("failure visible") {
            if case .failed = coordinator.states[video.id] { return true }
            return false
        }
        expect(coordinator.states[video.id] == .failed("Hardware encoder unavailable"), "retain an actionable failure reason")
        coordinator.enqueue([video.id])
        try await waitUntil("retry started") { await optimizer.pendingCount == 1 }
        let output = try await optimizer.finish()
        try await waitUntil("retry ready") { coordinator.states[video.id] == .ready && !coordinator.hasPendingWork }
        expect(settings.videos[0].optimizedPath == output.path, "successful retry must commit its output")
        expect(try Data(contentsOf: source) == Data("original".utf8), "optimization must preserve originals")
        try FileManager.default.removeItem(at: output)
        expect(coordinator.state(for: settings.videos[0], profile: settings.optimizationProfile) == nil,
               "a deleted performance copy must not retain Ready status")

        coordinator.invalidate()
        settings.videos[0].optimizedPath = nil
        settings.videos[0].optimizedProfile = nil
        coordinator.enqueue()
        try await waitUntil("old profile started") { await optimizer.pendingCount == 1 }
        coordinator.invalidate()
        settings.optimizationProfile = .maximum
        coordinator.enqueue()
        try await waitUntil("new profile started") { await optimizer.pendingCount == 2 }
        let staleOutput = try await optimizer.finish()
        try await waitUntil("old profile output discarded") { !FileManager.default.fileExists(atPath: staleOutput.path) }
        expect(settings.videos[0].optimizedPath == nil, "stale completion must not overwrite settings")
        _ = try await optimizer.finish()
        try await waitUntil("new profile ready") { settings.videos[0].optimizedProfile == .maximum && !coordinator.hasPendingWork }

        coordinator.invalidate()
        settings.videos[0].optimizedPath = nil
        settings.videos[0].optimizedProfile = nil
        coordinator.enqueue()
        try await waitUntil("deleted item encoder started") { await optimizer.pendingCount == 1 }
        settings.videos.removeAll()
        let deletedOutput = try await optimizer.finish()
        try await waitUntil("deleted item output discarded") { !FileManager.default.fileExists(atPath: deletedOutput.path) && !coordinator.hasPendingWork }
        expect(settings.videos.isEmpty, "encoding completion must not resurrect deleted items")

        settings.videos = [video]
        allowsCommit = false
        coordinator.enqueue()
        try await waitUntil("failed commit encoder started") { await optimizer.pendingCount == 1 }
        let rejectedOutput = try await optimizer.finish()
        try await waitUntil("commit failure handled") {
            if case .failed = coordinator.states[video.id] { return true }
            return false
        }
        expect(!FileManager.default.fileExists(atPath: rejectedOutput.path), "failed persistence must clean up new copies")
        coordinator.enqueue()
        coordinator.suspend(.preview)
        coordinator.cancel()
        coordinator.resume(.preview)
        expect(!coordinator.hasPendingWork, "manual cancellation must prevent automatic resumption")
    }

    @MainActor
    static func testRecovery(root: URL) async throws {
        let files = ManagedVideoFileStore(rootDirectory: root)
        let source = try files.managedVideosDirectory().appendingPathComponent("replacement.mp4")
        try Data("replacement".utf8).write(to: source)
        let optimizer = ControlledOptimizer()
        let recovery = VideoLibraryRecovery(importer: VideoLibraryImporter(videoOptimizer: optimizer, videoFiles: files))
        let missing = ManagedVideo(id: "stable", displayName: "Saved Name", path: "/missing.mp4")
        let recovered = try await recovery.replacement(for: missing, from: source)
        expect(recovered.id == missing.id && recovered.displayName == missing.displayName, "recovery must retain library identity")
        expect(recovered.path != source.path && recovered.optimizedPath == nil, "recovery must copy media and discard obsolete optimization")
        expect(try Data(contentsOf: recovered.url) == Data(contentsOf: source), "recovery must preserve the selected file")
        let screens = [ScreenConfiguration(screenID: "display", screenName: "Display", mode: .playlist,
            videoIDs: [missing.id], startVideoID: missing.id)]
        let settings = WallpaperSettings(videos: [recovered], screens: screens)
        expect(settings.repaired().screens == screens, "assignments and start selection must survive recovery")
        do {
            _ = try await recovery.replacement(for: missing, from: source.deletingPathExtension().appendingPathExtension("txt"))
            fatalError("Expected unsupported-file rejection")
        } catch VideoLibraryRecoveryError.unsupportedVideo {}
        do {
            _ = try await recovery.replacement(for: missing, from: root.appendingPathComponent("absent.mp4"))
            fatalError("Expected unreadable-file rejection")
        } catch {}
    }

    @MainActor
    static func testPlaylistEditing() {
        expect(PlaylistEditing.moving(["a", "b", "c", "d"], from: IndexSet([0, 2]), to: 4) == ["b", "d", "a", "c"], "multi-item reorder must preserve relative order")
        expect(PlaylistEditing.moving(["a", "b"], from: IndexSet(integer: 3), to: 0) == ["a", "b"], "stale offsets must be ignored")
        let a = ManagedVideo(id: "a", displayName: "A", path: "/a.mp4")
        let b = ManagedVideo(id: "b", displayName: "B", path: "/b.mp4")
        var settings = WallpaperSettings(videos: [a, b], screens: [ScreenConfiguration(
            screenID: "display", screenName: "Display", mode: .playlist, videoIDs: ["a", "b"], startVideoID: "b")])
        let undo = UndoManager()
        undo.groupsByEvent = false
        var allowsCommit = true
        let editor = PlaylistAssignmentEditor(settings: { settings }, configuration: { _ in settings.screens[0] }) { candidate in
            guard allowsCommit else { return false }
            settings.screens[0] = candidate
            return true
        }
        editor.undoManager = undo
        undo.beginUndoGrouping()
        editor.edit(for: "display", actionName: "Reorder") { $0.videoIDs.reverse() }
        undo.endUndoGrouping()
        settings.videos[0].contentFingerprint = "new metadata"
        undo.undo()
        expect(settings.screens[0].videoIDs == ["a", "b"], "undo must restore playlist order")
        expect(settings.videos[0].contentFingerprint == "new metadata", "assignment undo must preserve newer library metadata")
        undo.redo()
        expect(settings.screens[0].videoIDs == ["b", "a"], "redo must restore the reordered playlist")
        settings.videos.removeAll { $0.id == "b" }
        undo.undo()
        expect(settings.screens[0].videoIDs == ["a"] && settings.screens[0].startVideoID == "a", "undo must not restore permanently deleted media")
        undo.removeAllActions()
        allowsCommit = false
        editor.edit(for: "display", actionName: "Failed") { $0.mode = .single }
        expect(!undo.canUndo, "failed persistence must not register an undo action")
    }

    @MainActor
    static func testStorageAndAvailability(root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("original.mp4")
        let copy = root.appendingPathComponent("optimized.mp4")
        try Data(repeating: 1, count: 100).write(to: source)
        try Data(repeating: 2, count: 40).write(to: copy)
        let video = ManagedVideo(id: "a", displayName: "A", path: source.path, optimizedPath: copy.path, optimizedProfile: .efficient)
        let missing = ManagedVideo(id: "missing", displayName: "Missing", path: root.appendingPathComponent("absent.mp4").path)
        var settings = WallpaperSettings(videos: [video, missing])
        var snapshot = VideoLibrarySnapshot(settings: settings, search: "", filter: .unavailable, selectedID: nil)
        expect(snapshot.visibleVideos.map(\.id) == [missing.id], "missing filter must show unavailable originals")
        expect(snapshot.storage.originalBytes == 100 && snapshot.storage.performanceBytes == 40 && snapshot.storage.unusedBytes == 140,
               "storage must separate originals, copies, and unused media")
        settings.screens = [ScreenConfiguration(screenID: "screen", screenName: "Screen", stashedPlaylistVideoIDs: [video.id])]
        snapshot = VideoLibrarySnapshot(settings: settings, search: "", filter: .all, selectedID: nil)
        expect(snapshot.storage.unusedBytes == 0, "stashed assignments must protect media from unused cleanup")
        try FileManager.default.removeItem(at: copy)
        let refreshed = VideoLibraryStorage(videos: settings.videos, screens: settings.screens)
        expect(refreshed.performanceBytes == 0, "storage must refresh after files are deleted")
        expect(!VideoLibrarySnapshot.isReadableVideoFile(root.path), "directories must not count as readable media")
        let files = ManagedVideoFileStore(rootDirectory: root)
        let shared = try files.managedVideosDirectory().appendingPathComponent("shared.mp4")
        try Data("shared".utf8).write(to: shared)
        let first = ManagedVideo(id: "first", displayName: "First", path: shared.path)
        let second = ManagedVideo(id: "second", displayName: "Second", path: shared.path)
        let used = [ScreenConfiguration(screenID: "screen", screenName: "Screen", videoIDs: [second.id])]
        expect(VideoLibraryStorage(videos: [first, second], screens: used).unusedBytes == 0,
               "a shared path retained by an assignment must not count as reclaimable")
        expect(VideoLibraryStorage.reclaimableBytes(removing: [first.id], from: [first, second]) == 0,
               "single-item cleanup estimates must exclude files retained by another record")
        expect(VideoLibraryStorage.reclaimableBytes(removing: [first.id, second.id], from: [first, second]) == 6,
               "bulk cleanup estimates must count a shared file only once")
        try files.deleteManagedFiles(for: first, retaining: [second])
        expect(FileManager.default.fileExists(atPath: shared.path), "cleanup must protect files referenced by another record")
        try files.deleteManagedFiles(for: second)
        expect(!FileManager.default.fileExists(atPath: shared.path), "unreferenced managed files should be deleted")
    }

    @MainActor
    static func testWindowReopening() {
        let application = StubApplication()
        let registry = MainWindowRegistry(application: application)
        let window = StubWindow()
        registry.requestHiddenWindow()
        registry.register(window)
        expect(!registry.isVisible, "login launch should stay hidden")
        for _ in 0..<3 {
            expect(registry.showExistingWindow(), "reopen should reuse the registered main window")
            window.orderOut(nil)
        }
        expect(window.presentations == 3 && application.presentations == 3, "repeated reopen must present the same logical window")
        registry.unregister(window)
        expect(!registry.showExistingWindow(), "released window should use the scene-opening fallback")
    }
}
