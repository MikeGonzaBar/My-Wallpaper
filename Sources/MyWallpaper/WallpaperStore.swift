import AppKit
import AVFoundation
import Combine
import Foundation

@MainActor
final class WallpaperStore: ObservableObject {
    @Published private(set) var settings: WallpaperSettings
    @Published private(set) var availableScreens: [DisplayInfo] = []
    @Published private(set) var previewPlayer: AVPlayer?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isImporting = false
    @Published private(set) var isScreenSaverInstalled = false

    let screenSaver = ScreenSaverController()

    private var previewLooper: AVPlayerLooper?
    private var previewScreenID: String?
    private let defaultsKey = "wallpaperSettings"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        let savedData = UserDefaults.standard.data(forKey: defaultsKey)
        if let savedData, let saved = try? decoder.decode(WallpaperSettings.self, from: savedData) {
            settings = saved
        } else if let savedData,
                  let legacy = try? decoder.decode(LegacyWallpaperSettings.self, from: savedData),
                  let path = legacy.videoPath,
                  FileManager.default.fileExists(atPath: path) {
            let migratedVideo = ManagedVideo(
                id: UUID().uuidString,
                displayName: legacy.videoDisplayName ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
                path: path
            )
            settings = WallpaperSettings(
                videos: [migratedVideo],
                isMuted: legacy.isMuted,
                scaling: legacy.scaling
            )
        } else {
            settings = WallpaperSettings()
        }

        refreshScreens()
        migrateLegacyVideoToScreensIfNeeded()
        refreshScreenSaverInstallationStatus()
        persistSharedSettings()
        applySettings()
    }

    var statusText: String {
        let configuredCount = playbackPlans().count
        guard configuredCount > 0 else { return "Configure a display to get started" }
        return isScreenSaverInstalled ? "Installed for \(configuredCount) display\(configuredCount == 1 ? "" : "s")" : "Installation required"
    }

    func refreshScreens() {
        availableScreens = NSScreen.screens.map {
            DisplayInfo(id: DisplayIdentifier.stableID(for: $0), name: $0.localizedName)
        }
        for screen in availableScreens {
            if let index = settings.screens.firstIndex(where: { $0.screenID == screen.id }) {
                settings.screens[index].screenName = screen.name
            }
        }
        applySettings()
    }

    func configuration(for screenID: String) -> ScreenConfiguration {
        settings.screens.first(where: { $0.screenID == screenID })
            ?? ScreenConfiguration(
                screenID: screenID,
                screenName: availableScreens.first(where: { $0.id == screenID })?.name ?? "Display"
            )
    }

    func videos(for screenID: String) -> [ManagedVideo] {
        let ids = configuration(for: screenID).videoIDs
        return ids.compactMap { id in settings.videos.first(where: { $0.id == id }) }
    }

    func selectScreen(_ screenID: String?) {
        previewScreenID = screenID
        refreshPreview()
    }

    func importVideos(from sourceURLs: [URL], for screenID: String) async {
        guard !sourceURLs.isEmpty else { return }
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }

        var imported: [ManagedVideo] = []
        do {
            let directory = try managedVideosDirectory()
            let mode = configuration(for: screenID).mode
            let selectedURLs = mode == .single ? Array(sourceURLs.prefix(1)) : sourceURLs

            for sourceURL in selectedURLs {
                let hasAccess = sourceURL.startAccessingSecurityScopedResource()
                defer {
                    if hasAccess { sourceURL.stopAccessingSecurityScopedResource() }
                }

                let id = UUID().uuidString
                let destination = directory.appendingPathComponent(id)
                    .appendingPathExtension(sourceURL.pathExtension.lowercased())
                try FileManager.default.copyItem(at: sourceURL, to: destination)
                imported.append(ManagedVideo(
                    id: id,
                    displayName: sourceURL.deletingPathExtension().lastPathComponent,
                    path: destination.path
                ))
            }

            settings.videos.append(contentsOf: imported)
            mutateConfiguration(for: screenID) { configuration in
                if configuration.mode == .single {
                    configuration.videoIDs = [imported[0].id]
                } else {
                    configuration.videoIDs.append(contentsOf: imported.map(\.id))
                }
                if !configuration.videoIDs.contains(configuration.startVideoID ?? "") {
                    configuration.startVideoID = configuration.videoIDs.first
                }
            }
            removeUnusedVideos()
            saveAndApply()
            refreshPreview()
        } catch {
            for video in imported {
                try? FileManager.default.removeItem(at: video.url)
            }
            errorMessage = "The video couldn’t be imported: \(error.localizedDescription)"
        }
    }

    func setMode(_ mode: PlaybackMode, for screenID: String) {
        mutateConfiguration(for: screenID) { configuration in
            configuration.changeMode(to: mode)
        }
        saveAndApply()
        refreshPreview()
    }

    func setStartVideo(_ videoID: String, for screenID: String) {
        mutateConfiguration(for: screenID) { configuration in
            guard configuration.videoIDs.contains(videoID) else { return }
            configuration.startVideoID = videoID
        }
        saveAndApply()
        refreshPreview()
    }

    func moveVideo(_ videoID: String, by offset: Int, for screenID: String) {
        mutateConfiguration(for: screenID) { configuration in
            guard let sourceIndex = configuration.videoIDs.firstIndex(of: videoID) else { return }
            let destinationIndex = sourceIndex + offset
            guard configuration.videoIDs.indices.contains(destinationIndex) else { return }
            configuration.videoIDs.swapAt(sourceIndex, destinationIndex)
        }
        saveAndApply()
    }

    func removeVideo(_ videoID: String, from screenID: String) {
        mutateConfiguration(for: screenID) { configuration in
            configuration.videoIDs.removeAll { $0 == videoID }
            configuration.stashedPlaylistVideoIDs.removeAll { $0 == videoID }
            if configuration.startVideoID == videoID {
                configuration.startVideoID = configuration.videoIDs.first
            }
        }
        removeUnusedVideos()
        saveAndApply()
        refreshPreview()
    }

    func setMuted(_ muted: Bool) {
        settings.isMuted = muted
        previewPlayer?.isMuted = muted
        saveAndApply()
    }

    func setScaling(_ scaling: VideoScaling) {
        settings.scaling = scaling
        saveAndApply()
    }

    func clearError() {
        errorMessage = nil
    }

    func installScreenSaver() {
        errorMessage = nil
        do {
            guard let bundledSaver = Bundle.main.url(
                forResource: "My Wallpaper",
                withExtension: "saver"
            ) else {
                throw ScreenSaverInstallationError.missingBundledSaver
            }
            let destination = try installedScreenSaverURL(createDirectory: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: bundledSaver, to: destination)
            isScreenSaverInstalled = true
        } catch {
            errorMessage = "The screen saver couldn’t be installed: \(error.localizedDescription)"
            refreshScreenSaverInstallationStatus()
        }
    }

    func openScreenSaverSettings() {
        let destination = if #available(macOS 13.0, *) {
            "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension"
        } else {
            "x-apple.systempreferences:com.apple.preference.desktopscreeneffect"
        }
        guard let url = URL(string: destination) else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        configuration.promptsUserIfNeeded = true
        NSWorkspace.shared.open(url, configuration: configuration) { application, _ in
            application?.activate(options: [.activateAllWindows])
        }
    }

    func startConfiguredScreenSaver() {
        errorMessage = nil
        guard !playbackPlans().isEmpty else {
            errorMessage = "Choose at least one video before starting the screen saver."
            return
        }
        screenSaver.startScreenSaver { [weak self] in
            self?.lockMacNow()
        }
    }

    func lockMacNow() {
        errorMessage = nil
        let powerManager = URL(fileURLWithPath: "/usr/bin/pmset")
        guard FileManager.default.isExecutableFile(atPath: powerManager.path) else {
            errorMessage = "The macOS display-lock command couldn’t be found."
            return
        }

        let process = Process()
        process.executableURL = powerManager
        process.arguments = ["displaysleepnow"]
        do {
            try process.run()
        } catch {
            errorMessage = "The Mac couldn’t be locked: \(error.localizedDescription)"
        }
    }

    private func mutateConfiguration(
        for screenID: String,
        mutation: (inout ScreenConfiguration) -> Void
    ) {
        if let index = settings.screens.firstIndex(where: { $0.screenID == screenID }) {
            mutation(&settings.screens[index])
        } else {
            var configuration = configuration(for: screenID)
            mutation(&configuration)
            settings.screens.append(configuration)
        }
    }

    private func managedVideosDirectory() throws -> URL {
        let directory = try applicationSupportDirectory()
            .appendingPathComponent("Videos", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func applicationSupportDirectory() throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appendingPathComponent("My Wallpaper", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func removeUnusedVideos() {
        let usedIDs = Set(settings.screens.flatMap {
            $0.videoIDs + $0.stashedPlaylistVideoIDs
        })
        let unused = settings.videos.filter { !usedIDs.contains($0.id) }
        for video in unused {
            try? FileManager.default.removeItem(at: video.url)
        }
        settings.videos.removeAll { !usedIDs.contains($0.id) }
    }

    private func refreshPreview() {
        previewPlayer?.pause()
        previewLooper = nil
        guard let screenID = previewScreenID,
              let video = previewVideo(for: screenID),
              FileManager.default.fileExists(atPath: video.path) else {
            previewPlayer = nil
            return
        }
        let player = AVQueuePlayer()
        previewLooper = AVPlayerLooper(
            player: player,
            templateItem: AVPlayerItem(url: video.url)
        )
        player.isMuted = settings.isMuted
        previewPlayer = player
    }

    private func previewVideo(for screenID: String) -> ManagedVideo? {
        let configuration = configuration(for: screenID)
        let videoID = configuration.startVideoID ?? configuration.videoIDs.first
        return settings.videos.first { $0.id == videoID }
    }

    private func playbackPlans() -> [ScreenPlaybackPlan] {
        let connectedScreenIDs = Set(availableScreens.map(\.id))
        return settings.screens.compactMap { configuration in
            guard connectedScreenIDs.contains(configuration.screenID) else { return nil }
            let playableVideos = configuration.videoIDs.compactMap { id -> ManagedVideo? in
                guard let video = settings.videos.first(where: { $0.id == id }),
                      FileManager.default.fileExists(atPath: video.path) else { return nil }
                return video
            }
            guard !playableVideos.isEmpty else { return nil }
            let startIndex = playableVideos.firstIndex {
                $0.id == configuration.startVideoID
            } ?? 0
            return ScreenPlaybackPlan(
                screenID: configuration.screenID,
                videoURLs: configuration.mode == .single
                    ? [playableVideos[0].url]
                    : playableVideos.map(\.url),
                startIndex: configuration.mode == .single ? 0 : startIndex
            )
        }
    }

    private func saveAndApply() {
        do {
            let data = try encoder.encode(settings)
            UserDefaults.standard.set(data, forKey: defaultsKey)
            try data.write(
                to: applicationSupportDirectory().appendingPathComponent("settings.json"),
                options: .atomic
            )
        } catch {
            errorMessage = "Your screensaver settings couldn’t be saved: \(error.localizedDescription)"
        }
        applySettings()
    }

    private func applySettings() {
        let plans = playbackPlans()
        screenSaver.configure(
            plans: plans,
            isMuted: settings.isMuted,
            scaling: settings.scaling
        )
    }

    private func persistSharedSettings() {
        guard let data = try? encoder.encode(settings),
              let directory = try? applicationSupportDirectory() else { return }
        try? data.write(to: directory.appendingPathComponent("settings.json"), options: .atomic)
    }

    private func installedScreenSaverURL(createDirectory: Bool) throws -> URL {
        let library = try FileManager.default.url(
            for: .libraryDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: createDirectory
        )
        let screenSavers = library.appendingPathComponent("Screen Savers", isDirectory: true)
        if createDirectory {
            try FileManager.default.createDirectory(at: screenSavers, withIntermediateDirectories: true)
        }
        return screenSavers.appendingPathComponent("My Wallpaper.saver", isDirectory: true)
    }

    private func refreshScreenSaverInstallationStatus() {
        guard let url = try? installedScreenSaverURL(createDirectory: false) else {
            isScreenSaverInstalled = false
            return
        }
        isScreenSaverInstalled = FileManager.default.fileExists(atPath: url.path)
    }

    private func migrateLegacyVideoToScreensIfNeeded() {
        guard settings.screens.isEmpty,
              let video = settings.videos.first else { return }
        settings.screens = availableScreens.map {
            ScreenConfiguration(
                screenID: $0.id,
                screenName: $0.name,
                videoIDs: [video.id],
                startVideoID: video.id
            )
        }
        saveAndApply()
    }

}

private struct LegacyWallpaperSettings: Codable {
    let videoPath: String?
    let videoDisplayName: String?
    let idleMinutes: Int
    let isEnabled: Bool
    let isMuted: Bool
    let scaling: VideoScaling
}

private enum ScreenSaverInstallationError: LocalizedError {
    case missingBundledSaver

    var errorDescription: String? {
        "The My Wallpaper screen saver isn’t included in this app build."
    }
}
