import Foundation

@MainActor
enum VideoLibraryRefresher {
    static func refresh<Value>(
        videos: () -> [ManagedVideo],
        needsRefresh: (ManagedVideo) -> Bool,
        load: @MainActor (URL) async -> Value?,
        apply: (Int, Value) -> Void
    ) async -> Bool {
        var changed = false
        for videoID in videos().map(\.id) {
            guard !Task.isCancelled else { break }
            guard let video = videos().first(where: { $0.id == videoID }),
                  needsRefresh(video),
                  let value = await load(video.url) else { continue }
            guard !Task.isCancelled else { break }
            // Library edits can run while loading. Resolve the current item before writing.
            let currentVideos = videos()
            guard let index = currentVideos.firstIndex(where: { $0.id == videoID }),
                  currentVideos[index].path == video.path,
                  needsRefresh(currentVideos[index]) else { continue }
            apply(index, value)
            changed = true
        }
        return changed
    }
}
