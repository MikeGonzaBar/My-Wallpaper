import Foundation

@MainActor
final class PlaylistAssignmentEditor {
    weak var undoManager: UndoManager?
    private let settings: () -> WallpaperSettings
    private let configuration: (String) -> ScreenConfiguration
    private let commit: (ScreenConfiguration) -> Bool

    init(
        settings: @escaping () -> WallpaperSettings,
        configuration: @escaping (String) -> ScreenConfiguration,
        commit: @escaping (ScreenConfiguration) -> Bool
    ) {
        self.settings = settings
        self.configuration = configuration
        self.commit = commit
    }

    func edit(for screenID: String, actionName: String, mutation: (inout ScreenConfiguration) -> Void) {
        let previous = configuration(screenID)
        var candidate = previous
        mutation(&candidate)
        guard candidate != previous, commit(candidate) else { return }
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated { target.restore(previous, actionName: actionName) }
        }
        undoManager?.setActionName(actionName)
    }

    private func restore(_ saved: ScreenConfiguration, actionName: String) {
        let restored = PlaylistEditing.restoring(saved, knownIDs: Set(settings().videos.map(\.id)))
        edit(for: restored.screenID, actionName: actionName) { $0 = restored }
    }
}
