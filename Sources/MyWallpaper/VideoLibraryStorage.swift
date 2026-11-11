import Foundation

struct VideoLibraryStorage {
    let originalBytes: Int64
    let performanceBytes: Int64
    let unusedBytes: Int64

    var totalBytes: Int64 { originalBytes + performanceBytes }

    init(videos: [ManagedVideo], screens: [ScreenConfiguration], fileSize: (String) -> Int64 = Self.fileSize) {
        var originals: Int64 = 0
        var performance: Int64 = 0
        var unused: Int64 = 0
        var counted = Set<String>()
        let usedIDs = Set(screens.flatMap { $0.videoIDs + $0.stashedPlaylistVideoIDs })
        let usedPaths = Set(videos.filter { usedIDs.contains($0.id) }.flatMap {
            [$0.path, $0.optimizedPath].compactMap { $0 }
        })
        for video in videos {
            for (path, isOriginal) in [(video.path, true), (video.optimizedPath, false)] {
                guard let path, counted.insert(path).inserted else { continue }
                let bytes = max(0, fileSize(path))
                if isOriginal { originals += bytes } else { performance += bytes }
                if !usedPaths.contains(path) { unused += bytes }
            }
        }
        originalBytes = originals
        performanceBytes = performance
        unusedBytes = unused
    }

    static func reclaimableBytes(removing ids: Set<String>, from videos: [ManagedVideo]) -> Int64 {
        let retainedPaths = Set(videos.filter { !ids.contains($0.id) }.flatMap {
            [$0.path, $0.optimizedPath].compactMap { $0 }
        })
        let removedPaths = Set(videos.filter { ids.contains($0.id) }.flatMap {
            [$0.path, $0.optimizedPath].compactMap { $0 }
        })
        return removedPaths.subtracting(retainedPaths).reduce(0) { $0 + fileSize($1) }
    }

    static func fileSize(_ path: String) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    static func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
