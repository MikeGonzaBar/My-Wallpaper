import Foundation

struct VideoLibraryRecovery: Sendable {
    let importer: VideoLibraryImporter

    func replacement(for video: ManagedVideo, from sourceURL: URL) async throws -> ManagedVideo {
        guard ["mov", "mp4", "m4v"].contains(sourceURL.pathExtension.lowercased()) else {
            throw VideoLibraryRecoveryError.unsupportedVideo
        }
        let candidates = await importer.prepareCandidates(from: [sourceURL], existingVideos: [])
        try Task.checkCancellation()
        guard let candidate = candidates.first, candidate.metadata != nil else {
            throw VideoLibraryRecoveryError.unreadableVideo
        }
        guard let imported = try await importer.importVideos(candidates: [candidate]).first else {
            throw VideoLibraryRecoveryError.unreadableVideo
        }
        // Keep the library identity so assignments, order, and starting video survive recovery.
        return ManagedVideo(id: video.id, displayName: video.displayName, path: imported.path,
            sourceMetadata: imported.sourceMetadata, contentFingerprint: imported.contentFingerprint)
    }
}

enum VideoLibraryRecoveryError: LocalizedError {
    case unsupportedVideo
    case unreadableVideo
    case changedDuringRecovery

    var errorDescription: String? {
        switch self {
        case .unsupportedVideo: "Choose a MOV, MP4, or M4V video."
        case .unreadableVideo: "The selected file does not contain a readable video."
        case .changedDuringRecovery: "This library item changed during recovery. Select it again and retry."
        }
    }
}
