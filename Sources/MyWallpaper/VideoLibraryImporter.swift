import Foundation

struct VideoLibraryImporter: Sendable {
    let videoOptimizer: VideoOptimizing
    let videoFiles: ManagedVideoFileStore

    func prepareCandidates(
        from sourceURLs: [URL],
        existingVideos: [ManagedVideo]
    ) async -> [VideoImportCandidate] {
        let candidateIDs = sourceURLs.map { _ in UUID() }
        let names = sourceURLs.map { $0.deletingPathExtension().lastPathComponent }
        var fileSizes: [Int64] = []
        var metadataValues: [VideoTechnicalMetadata?] = []
        var fingerprints: [String?] = []

        for sourceURL in sourceURLs {
            guard !Task.isCancelled else { return [] }
            let hasAccess = sourceURL.startAccessingSecurityScopedResource()
            let attributes = try? FileManager.default.attributesOfItem(atPath: sourceURL.path)
            fileSizes.append((attributes?[.size] as? NSNumber)?.int64Value ?? 0)
            metadataValues.append(try? await videoOptimizer.metadata(for: sourceURL))
            guard !Task.isCancelled else {
                if hasAccess { sourceURL.stopAccessingSecurityScopedResource() }
                return []
            }
            fingerprints.append(await sampledFingerprint(for: sourceURL))
            if hasAccess { sourceURL.stopAccessingSecurityScopedResource() }
            guard !Task.isCancelled else { return [] }
        }
        let duplicateReferences = VideoLibraryLogic.duplicateReferences(
            candidateIDs: candidateIDs,
            for: names,
            fingerprints: fingerprints,
            existingVideos: existingVideos
        )
        return sourceURLs.indices.map { index in
            VideoImportCandidate(
                id: candidateIDs[index],
                sourceURL: sourceURLs[index],
                displayName: names[index],
                fileSize: fileSizes[index],
                metadata: metadataValues[index],
                contentFingerprint: fingerprints[index],
                duplicate: duplicateReferences[index]
            )
        }
    }

    func importVideos(candidates: [VideoImportCandidate]) async throws -> [ManagedVideo] {
        let importable = candidates.filter { !$0.isDuplicate }
        guard !importable.isEmpty else { return [] }

        var imported: [ManagedVideo] = []
        var copiedURLs: [URL] = []
        do {
            let directory = try videoFiles.managedVideosDirectory()
            for candidate in importable {
                let sourceURL = candidate.sourceURL
                let hasAccess = sourceURL.startAccessingSecurityScopedResource()
                defer {
                    if hasAccess { sourceURL.stopAccessingSecurityScopedResource() }
                }

                let id = UUID().uuidString
                let destination = directory.appendingPathComponent(id)
                    .appendingPathExtension(sourceURL.pathExtension.lowercased())
                try Task.checkCancellation()
                try await copyFile(from: sourceURL, to: destination)
                copiedURLs.append(destination)
                try videoFiles.ensurePrivateFilePermissions(at: destination)
                let metadata = try? await videoOptimizer.metadata(for: destination)
                try Task.checkCancellation()
                let fingerprint = await sampledFingerprint(for: destination)
                try Task.checkCancellation()
                imported.append(ManagedVideo(
                    id: id,
                    displayName: candidate.displayName,
                    path: destination.path,
                    sourceMetadata: metadata,
                    contentFingerprint: fingerprint
                ))
            }
            return imported
        } catch {
            for url in copiedURLs {
                try? FileManager.default.removeItem(at: url)
            }
            throw error
        }
    }

    func removeManagedFiles(for videos: [ManagedVideo]) {
        for video in videos {
            try? videoFiles.deleteManagedFiles(for: video)
        }
    }

    private func sampledFingerprint(for url: URL) async -> String? {
        await Task.detached(priority: .utility) {
            VideoContentFingerprint.sampled(at: url)
        }.value
    }

    private func copyFile(from source: URL, to destination: URL) async throws {
        let copyTask = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            try FileManager.default.copyItem(at: source, to: destination)
        }
        return try await withTaskCancellationHandler {
            try await copyTask.value
        } onCancel: {
            copyTask.cancel()
        }
    }
}
