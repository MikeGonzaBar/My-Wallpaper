import Foundation

enum VideoImportDuplicate: Equatable {
    case library(videoID: String)
    case selection(candidateID: UUID)
}

struct VideoImportCandidate: Identifiable, Equatable {
    let id: UUID
    let sourceURL: URL
    let displayName: String
    let fileSize: Int64
    let metadata: VideoTechnicalMetadata?
    let contentFingerprint: String?
    let duplicate: VideoImportDuplicate?

    init(
        id: UUID = UUID(),
        sourceURL: URL,
        displayName: String,
        fileSize: Int64,
        metadata: VideoTechnicalMetadata?,
        contentFingerprint: String?,
        duplicate: VideoImportDuplicate?
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.displayName = displayName
        self.fileSize = fileSize
        self.metadata = metadata
        self.contentFingerprint = contentFingerprint
        self.duplicate = duplicate
    }

    var isDuplicate: Bool { duplicate != nil }
}

struct VideoLibraryDeduplicationResult: Equatable {
    let settings: WallpaperSettings
    let redundantVideos: [ManagedVideo]
}

enum VideoLibraryLogic {
    static func normalizedName(_ name: String) -> String {
        URL(fileURLWithPath: name)
            .deletingPathExtension()
            .lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    static func duplicateReferences(
        candidateIDs: [UUID],
        for names: [String],
        fingerprints: [String?],
        existingVideos: [ManagedVideo]
    ) -> [VideoImportDuplicate?] {
        guard candidateIDs.count == names.count,
              names.count == fingerprints.count else {
            return Array(repeating: nil, count: names.count)
        }

        var existingIDByFingerprint: [String: String] = [:]
        var existingIDByName: [String: String] = [:]
        for video in existingVideos {
            if let fingerprint = video.contentFingerprint {
                existingIDByFingerprint[fingerprint] = existingIDByFingerprint[fingerprint]
                    ?? video.id
            }
            let name = normalizedName(video.displayName)
            existingIDByName[name] = existingIDByName[name] ?? video.id
        }

        var firstCandidateIDByFingerprint: [String: UUID] = [:]
        var firstCandidateIDByName: [String: UUID] = [:]
        return names.indices.map { index in
            let candidateID = candidateIDs[index]
            if let fingerprint = fingerprints[index] {
                if let videoID = existingIDByFingerprint[fingerprint] {
                    return .library(videoID: videoID)
                }
                if let firstCandidateID = firstCandidateIDByFingerprint[fingerprint] {
                    return .selection(candidateID: firstCandidateID)
                }
                firstCandidateIDByFingerprint[fingerprint] = candidateID
                return nil
            }

            let name = normalizedName(names[index])
            if let videoID = existingIDByName[name] {
                return .library(videoID: videoID)
            }
            if let firstCandidateID = firstCandidateIDByName[name] {
                return .selection(candidateID: firstCandidateID)
            }
            firstCandidateIDByName[name] = candidateID
            return nil
        }
    }

    static func assigning(
        _ additions: [String],
        to existing: [String],
        mode: PlaybackMode
    ) -> [String] {
        guard mode == .playlist else { return additions.first.map { [$0] } ?? existing }
        var result = existing
        for id in additions where !result.contains(id) {
            result.append(id)
        }
        return result
    }

    static func usageCount(for videoID: String, screens: [ScreenConfiguration]) -> Int {
        screens.filter {
            $0.videoIDs.contains(videoID) || $0.stashedPlaylistVideoIDs.contains(videoID)
        }.count
    }

    static func resolvedVideoIDs(
        for candidates: [VideoImportCandidate],
        importedVideos: [ManagedVideo]
    ) -> [String] {
        var importedIterator = importedVideos.makeIterator()
        var resolvedByCandidateID: [UUID: String] = [:]
        var orderedIDs: [String] = []
        for candidate in candidates {
            let videoID: String?
            switch candidate.duplicate {
            case let .library(existingVideoID):
                videoID = existingVideoID
            case let .selection(firstCandidateID):
                videoID = resolvedByCandidateID[firstCandidateID]
            case nil:
                videoID = importedIterator.next()?.id
            }
            guard let videoID else { continue }
            resolvedByCandidateID[candidate.id] = videoID
            if !orderedIDs.contains(videoID) {
                orderedIDs.append(videoID)
            }
        }
        return orderedIDs
    }

    static func deduplicatingLegacyVideos(
        in settings: WallpaperSettings,
        fingerprint: (ManagedVideo) -> String?
    ) -> VideoLibraryDeduplicationResult {
        let nameCounts = Dictionary(
            grouping: settings.videos,
            by: { normalizedName($0.displayName) }
        ).mapValues(\.count)
        var canonicalIDByFingerprint: [String: String] = [:]
        var replacementIDs: [String: String] = [:]
        var retainedVideos: [ManagedVideo] = []
        var redundantVideos: [ManagedVideo] = []

        for video in settings.videos {
            let normalizedDisplayName = normalizedName(video.displayName)
            guard nameCounts[normalizedDisplayName, default: 0] > 1,
                  let contentFingerprint = fingerprint(video) else {
                retainedVideos.append(video)
                continue
            }

            let key = normalizedDisplayName + "\u{1F}" + contentFingerprint
            if let canonicalID = canonicalIDByFingerprint[key] {
                replacementIDs[video.id] = canonicalID
                redundantVideos.append(video)
            } else {
                canonicalIDByFingerprint[key] = video.id
                retainedVideos.append(video)
            }
        }

        guard !replacementIDs.isEmpty else {
            return VideoLibraryDeduplicationResult(
                settings: settings,
                redundantVideos: []
            )
        }

        var migrated = settings
        migrated.videos = retainedVideos
        migrated.screens = settings.screens.map { screen in
            var updated = screen
            updated.videoIDs = remappingVideoIDs(screen.videoIDs, using: replacementIDs)
            updated.stashedPlaylistVideoIDs = remappingVideoIDs(
                screen.stashedPlaylistVideoIDs,
                using: replacementIDs
            )
            if let startVideoID = screen.startVideoID {
                let remappedStartID = replacementIDs[startVideoID] ?? startVideoID
                updated.startVideoID = updated.videoIDs.contains(remappedStartID)
                    ? remappedStartID
                    : updated.videoIDs.first
            }
            return updated
        }
        return VideoLibraryDeduplicationResult(
            settings: migrated,
            redundantVideos: redundantVideos
        )
    }

    private static func remappingVideoIDs(
        _ ids: [String],
        using replacements: [String: String]
    ) -> [String] {
        var seen = Set<String>()
        return ids.compactMap { id in
            let remapped = replacements[id] ?? id
            return seen.insert(remapped).inserted ? remapped : nil
        }
    }
}
