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
    @Published private(set) var screenSaverIntegrationState = ScreenSaverIntegrationState.verificationRequired
    @Published private(set) var isStartingScreenSaver = false

    private let nativeScreenSaver = NativeScreenSaverController()
    private let previewController = FullScreenPreviewController()

    private var previewLooper: AVPlayerLooper?
    private var previewScreenID: String?
    private var displayChangeCancellable: AnyCancellable?
    private var applicationActiveCancellable: AnyCancellable?
    private let defaultsKey = "wallpaperSettings"
    private let verificationAttemptedKey = "screenSaverVerificationAttempted"
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
        persistSharedSettings()
        applySettings()
        observeDisplayChanges()
        observeApplicationActivation()
        previewController.onError = { [weak self] message in
            self?.errorMessage = message
        }
        Task { await refreshScreenSaverIntegrationState() }
    }

    var statusText: String {
        let configuredCount = allPlaybackPlans().count
        guard configuredCount > 0 else { return "Configure a display to get started" }
        switch screenSaverIntegrationState {
        case .ready:
            return "Ready for \(configuredCount) display\(configuredCount == 1 ? "" : "s")"
        case .updateRequired:
            return "Screen saver update required"
        case .notInstalled:
            return "Screen saver installation required"
        case .verificationRequired:
            return "System setup verification required"
        case .verificationDenied:
            return "Automation permission required"
        case let .notSelected(currentName):
            return currentName.map { "\($0) is selected" } ?? "My Wallpaper is not selected"
        case .moduleUnavailable:
            return "Screen saver integration unavailable"
        }
    }

    var isScreenSaverReady: Bool { screenSaverIntegrationState.isReady }

    func refreshScreens() {
        let connectedScreens = NSScreen.screens.map {
            DisplayInfo(id: DisplayIdentifier.stableID(for: $0), name: $0.localizedName)
        }
        availableScreens = connectedScreens
        for screen in availableScreens {
            if let index = settings.screens.firstIndex(where: { $0.screenID == screen.id }) {
                settings.screens[index].screenName = screen.name
            }
        }
        if let previewScreenID,
           !connectedScreens.contains(where: { $0.id == previewScreenID }) {
            self.previewScreenID = connectedScreens.first?.id
            refreshPreview()
        }
        persistSharedSettings()
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

    func usesFallbackPlayback(for screenID: String) -> Bool {
        let hasPlayableAssignment = videos(for: screenID).contains {
            FileManager.default.isReadableFile(atPath: $0.path)
        }
        return !hasPlayableAssignment && !allPlaybackPlans().isEmpty
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

    func installOrUpdateScreenSaver() {
        errorMessage = nil
        do {
            try nativeScreenSaver.installOrUpdate()
            Task { await refreshScreenSaverIntegrationState() }
        } catch {
            errorMessage = "The screen saver couldn’t be installed: \(error.localizedDescription)"
            Task { await refreshScreenSaverIntegrationState() }
        }
    }

    func verifySystemScreenSaverSetup(requestConsent: Bool) async {
        if requestConsent {
            UserDefaults.standard.set(true, forKey: verificationAttemptedKey)
        }
        screenSaverIntegrationState = await nativeScreenSaver.integrationState(
            verificationAttempted: UserDefaults.standard.bool(forKey: verificationAttemptedKey),
            requestConsent: requestConsent
        )
    }

    func refreshScreenSaverIntegrationState() async {
        await verifySystemScreenSaverSetup(requestConsent: false)
    }

    func openScreenSaverSettings() {
        let destination = if #available(macOS 13.0, *) {
            "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension"
        } else {
            "x-apple.systempreferences:com.apple.preference.desktopscreeneffect"
        }
        guard let url = URL(string: destination) else {
            openSystemSettingsFallback()
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        configuration.promptsUserIfNeeded = true
        NSWorkspace.shared.open(url, configuration: configuration) { [weak self] application, error in
            if error == nil, let application {
                application.activate(options: [.activateAllWindows])
            } else {
                Task { @MainActor [weak self] in self?.openSystemSettingsFallback() }
            }
        }
    }

    func openAutomationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        ) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        configuration.promptsUserIfNeeded = true
        NSWorkspace.shared.open(url, configuration: configuration) { application, error in
            if let error {
                Task { @MainActor [weak self] in
                    self?.errorMessage = "Automation settings could not be opened: \(error.localizedDescription)"
                }
            } else {
                application?.activate(options: [.activateAllWindows])
            }
        }
    }

    func startConfiguredScreenSaver() async -> NativeStartResult {
        guard !isStartingScreenSaver else {
            return .launchFailed(message: "The screen saver is already starting.")
        }
        errorMessage = nil
        guard persistSharedSettings() else {
            let message = "Your screen saver settings could not be prepared."
            errorMessage = message
            return .invalidConfiguration(message: message)
        }
        guard ScreenSaverManifestBuilder.build(
            settings: settings,
            connectedDisplayIDs: availableScreens.map(\.id)
        ) != nil else {
            let message = "Choose at least one readable video before starting the screen saver."
            errorMessage = message
            return .invalidConfiguration(message: message)
        }

        await refreshScreenSaverIntegrationState()
        guard screenSaverIntegrationState == .ready else {
            return .requiresSetup(screenSaverIntegrationState)
        }

        isStartingScreenSaver = true
        defer { isStartingScreenSaver = false }
        do {
            try await nativeScreenSaver.startNativeScreenSaver()
            return .started
        } catch {
            let message = "The native screen saver could not start: \(error.localizedDescription)"
            errorMessage = message
            return .launchFailed(message: message)
        }
    }

    func previewAllDisplays() {
        errorMessage = nil
        previewController.previewAllDisplays()
    }

    func lockMacNow() {
        errorMessage = nil
        let powerManager = URL(fileURLWithPath: "/usr/bin/pmset")
        guard FileManager.default.isExecutableFile(atPath: powerManager.path) else {
            errorMessage = "The macOS display-sleep command couldn’t be found."
            return
        }

        let process = Process()
        process.executableURL = powerManager
        process.arguments = ["displaysleepnow"]
        do {
            try process.run()
        } catch {
            errorMessage = "The display couldn’t be put to sleep: \(error.localizedDescription)"
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

    private func openSystemSettingsFallback() {
        let workspace = NSWorkspace.shared
        guard let url = workspace.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") else {
            errorMessage = "Open System Settings, then choose Wallpaper → Screen Saver → Other → My Wallpaper."
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        configuration.promptsUserIfNeeded = true
        workspace.openApplication(at: url, configuration: configuration) { [weak self] application, error in
            if let error {
                Task { @MainActor [weak self] in
                    self?.errorMessage = "System Settings could not be opened: \(error.localizedDescription)"
                }
            } else {
                application?.activate(options: [.activateAllWindows])
            }
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
        player.play()
    }

    private func previewVideo(for screenID: String) -> ManagedVideo? {
        let configuration = configuration(for: screenID)
        let videoID = configuration.startVideoID ?? configuration.videoIDs.first
        return settings.videos.first { $0.id == videoID }
    }

    private func allPlaybackPlans() -> [ScreenPlaybackPlan] {
        return settings.screens.compactMap { configuration in
            let playableVideos = configuration.videoIDs.compactMap { id -> ManagedVideo? in
                guard let video = settings.videos.first(where: { $0.id == id }),
                      FileManager.default.isReadableFile(atPath: video.path) else { return nil }
                return video
            }
            guard !playableVideos.isEmpty else { return nil }
            let startIndex = playableVideos.firstIndex {
                $0.id == configuration.startVideoID
            } ?? 0
            return ScreenPlaybackPlan(
                screenID: configuration.screenID,
                videoURLs: configuration.mode == .single
                    ? [playableVideos[startIndex].url]
                    : playableVideos.map(\.url),
                startIndex: configuration.mode == .single ? 0 : startIndex
            )
        }
    }

    private func saveAndApply() {
        do {
            let data = try encoder.encode(settings)
            UserDefaults.standard.set(data, forKey: defaultsKey)
            guard persistSharedSettings() else {
                throw WallpaperPersistenceError.sharedSettingsWriteFailed
            }
        } catch {
            errorMessage = "Your screensaver settings couldn’t be saved: \(error.localizedDescription)"
        }
        applySettings()
    }

    private func applySettings() {
        let plans = allPlaybackPlans()
        let connectedIDs = Set(availableScreens.map(\.id))
        let fallback = plans.first { connectedIDs.contains($0.screenID) } ?? plans.first
        previewController.configure(
            plans: plans,
            fallbackPlan: fallback,
            isMuted: settings.isMuted,
            scaling: settings.scaling
        )
    }

    @discardableResult
    private func persistSharedSettings() -> Bool {
        do {
            let directory = try applicationSupportDirectory()
            let legacyData = try encoder.encode(settings)
            try legacyData.write(
                to: directory.appendingPathComponent("settings.json"),
                options: .atomic
            )

            let manifestURL = directory.appendingPathComponent("screensaver-manifest-v1.json")
            if let manifest = ScreenSaverManifestBuilder.build(
                settings: settings,
                connectedDisplayIDs: availableScreens.map(\.id)
            ) {
                try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
            } else if FileManager.default.fileExists(atPath: manifestURL.path) {
                try FileManager.default.removeItem(at: manifestURL)
            }
            return true
        } catch {
            errorMessage = "Your screen saver settings couldn’t be saved: \(error.localizedDescription)"
            return false
        }
    }

    private func observeDisplayChanges() {
        displayChangeCancellable = NotificationCenter.default.publisher(
            for: NSApplication.didChangeScreenParametersNotification
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshScreens()
            }
        }
    }

    private func observeApplicationActivation() {
        applicationActiveCancellable = NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshScreenSaverIntegrationState()
            }
        }
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

private enum WallpaperPersistenceError: LocalizedError {
    case sharedSettingsWriteFailed

    var errorDescription: String? {
        "The native screen saver manifest could not be written."
    }
}
