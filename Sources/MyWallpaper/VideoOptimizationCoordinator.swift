import Combine
import Foundation

enum VideoOptimizationState: Equatable {
    case queued
    case optimizing(Double)
    case paused
    case ready
    case failed(String)

    var title: String {
        switch self {
        case .queued: "Queued"
        case let .optimizing(fraction): "Optimizing \(Int(fraction * 100))%"
        case .paused: "Paused"
        case .ready: "Ready"
        case .failed: "Failed"
        }
    }
}

@MainActor
final class VideoOptimizationCoordinator: ObservableObject {
    @Published private(set) var states: [String: VideoOptimizationState] = [:]
    @Published private(set) var progress: VideoOptimizationProgress?

    private let optimizer: VideoOptimizing
    private let files: ManagedVideoFileStore
    private let settings: () -> WallpaperSettings
    private let commit: (ManagedVideo, String, VideoOptimizationProfile, VideoTechnicalMetadata?) -> Bool
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var pendingIDs = Set<String>()
    private var suspensionReasons = Set<PlaybackSuspensionReason>()

    init(
        optimizer: VideoOptimizing,
        files: ManagedVideoFileStore,
        settings: @escaping () -> WallpaperSettings,
        commit: @escaping (ManagedVideo, String, VideoOptimizationProfile, VideoTechnicalMetadata?) -> Bool
    ) {
        self.optimizer = optimizer
        self.files = files
        self.settings = settings
        self.commit = commit
    }

    var hasPendingWork: Bool { task != nil || !pendingIDs.isEmpty }

    func state(for video: ManagedVideo, profile: VideoOptimizationProfile) -> VideoOptimizationState? {
        if video.optimizedProfile == profile,
           let path = video.optimizedPath,
           FileManager.default.isReadableFile(atPath: path) { return .ready }
        return states[video.id] == .ready ? nil : states[video.id]
    }

    func enqueue(_ ids: Set<String>? = nil) {
        let snapshot = settings()
        guard snapshot.playbackQuality == .performance else { return }
        let requested = ids ?? Set(snapshot.videos.map(\.id))
        for video in snapshot.videos where requested.contains(video.id) {
            if state(for: video, profile: snapshot.optimizationProfile) == .ready { continue }
            // Repeated requests must not enqueue the file currently being encoded again.
            if case .optimizing = states[video.id] { continue }
            pendingIDs.insert(video.id)
            states[video.id] = suspensionReasons.isEmpty ? .queued : .paused
        }
        startIfNeeded()
    }

    func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        pendingIDs.removeAll()
        states = states.filter { _, state in
            if case .failed = state { return true }
            return state == .ready
        }
        progress = nil
    }

    func invalidate() {
        cancel()
        states.removeAll()
    }

    func suspend(_ reason: PlaybackSuspensionReason) {
        guard suspensionReasons.insert(reason).inserted else { return }
        for (id, state) in states {
            switch state {
            case .queued, .optimizing:
                pendingIDs.insert(id)
                states[id] = .paused
            default: break
            }
        }
        generation = UUID()
        task?.cancel()
        task = nil
        progress = nil
    }

    func resume(_ reason: PlaybackSuspensionReason) {
        suspensionReasons.remove(reason)
        guard suspensionReasons.isEmpty else { return }
        for id in pendingIDs { states[id] = .queued }
        startIfNeeded()
    }

    private func startIfNeeded() {
        guard task == nil, suspensionReasons.isEmpty, !pendingIDs.isEmpty else { return }
        let runID = UUID()
        generation = runID
        task = Task { [weak self] in await self?.run(runID: runID) }
    }

    private func run(runID: UUID) async {
        defer {
            if generation == runID {
                task = nil
                progress = nil
            }
        }
        var completed = 0
        while generation == runID, !Task.isCancelled, !pendingIDs.isEmpty {
            let snapshot = settings()
            guard snapshot.playbackQuality == .performance else { return }
            guard let video = snapshot.videos.first(where: { pendingIDs.contains($0.id) }) else {
                pendingIDs.removeAll()
                return
            }
            pendingIDs.remove(video.id)
            let profile = snapshot.optimizationProfile
            let position = completed
            let total = completed + pendingIDs.count + 1
            states[video.id] = .optimizing(0)
            progress = VideoOptimizationProgress(completedCount: position, totalCount: total,
                currentVideoName: video.displayName, currentFraction: 0)
            var destination: URL?
            do {
                let directory = try files.optimizedVideosDirectory()
                let output = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
                destination = output
                try await optimizer.optimize(sourceURL: video.url, destinationURL: output, profile: profile) {
                    [weak self] fraction in
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == runID,
                              case .optimizing = self.states[video.id] else { return }
                        let fraction = fraction.isFinite ? min(1, max(0, fraction)) : 0
                        self.states[video.id] = .optimizing(fraction)
                        self.progress = VideoOptimizationProgress(completedCount: position, totalCount: total,
                            currentVideoName: video.displayName, currentFraction: fraction)
                    }
                }
                try Task.checkCancellation()
                guard FileManager.default.isReadableFile(atPath: output.path) else {
                    throw VideoOptimizationError.writerFailed(nil)
                }
                try files.ensurePrivateFilePermissions(at: output)
                let metadata = video.sourceMetadata == nil ? try? await optimizer.metadata(for: video.url) : nil
                try Task.checkCancellation()
                let current = settings()
                guard generation == runID, current.playbackQuality == .performance,
                      current.optimizationProfile == profile,
                      current.videos.contains(where: { $0.id == video.id && $0.path == video.path }) else {
                    files.removeOptimizedFileIfOwned(atPath: output.path)
                    if generation == runID { states.removeValue(forKey: video.id) }
                    continue
                }
                guard commit(video, output.path, profile, metadata) else {
                    throw WallpaperOptimizationCommitError()
                }
                states[video.id] = .ready
            } catch {
                if let destination { files.removeOptimizedFileIfOwned(atPath: destination.path) }
                guard generation == runID, !Task.isCancelled else { return }
                if settings().videos.contains(where: { $0.id == video.id && $0.path == video.path }) {
                    states[video.id] = .failed(error.localizedDescription)
                } else {
                    states.removeValue(forKey: video.id)
                }
            }
            completed += 1
        }
    }
}

enum PlaybackSuspensionReason: Hashable {
    case preview
    case nativeScreenSaver
}

private struct WallpaperOptimizationCommitError: LocalizedError {
    var errorDescription: String? { "The performance copy could not be saved. Retry after checking available storage." }
}
