import Foundation

// Edits only display assignments; managed media and library metadata stay outside undo history.
enum PlaylistEditing {
    static func moving(_ ids: [String], from offsets: IndexSet, to destination: Int) -> [String] {
        guard destination >= 0, destination <= ids.count,
              !offsets.isEmpty, offsets.allSatisfy(ids.indices.contains) else { return ids }
        let moving = offsets.sorted().map { ids[$0] }
        var result = ids.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        let insertion = destination - offsets.filter { $0 < destination }.count
        result.insert(contentsOf: moving, at: insertion)
        return result
    }

    static func restoring(_ configuration: ScreenConfiguration, knownIDs: Set<String>) -> ScreenConfiguration {
        var result = configuration
        result.videoIDs.removeAll { !knownIDs.contains($0) }
        result.stashedPlaylistVideoIDs.removeAll { !knownIDs.contains($0) }
        if !result.videoIDs.contains(result.startVideoID ?? "") { result.startVideoID = result.videoIDs.first }
        return result
    }
}
