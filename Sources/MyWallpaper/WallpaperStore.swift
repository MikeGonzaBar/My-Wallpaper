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
    @Published private(set) var optimizationProgress: VideoOptimizationProgress?
    @Published private(set) var screenSaverIntegrationState = ScreenSaverIntegrationState.verificationRequired
    @Published private(set) var isStartingScreenSaver = false
    @Published private(set) var appearanceMode: AppearanceMode
    @Published private(set) var appearanceTransitionID = UUID()

    let launchAtLogin: LaunchAtLoginController

    private let nativeScreenSaver = NativeScreenSaverController()
    private let previewController = FullScreenPreviewController()
    private let videoOptimizer: VideoOptimizing

    private var previewLooper: AVPlayerLooper?
    private var previewScreenID: String?
    private var displayChangeCancellable: AnyCancellable?
    private var applicationActiveCancellable: AnyCancellable?
    private var applicationInactiveCancellables: Set<AnyCancellable> = []
    private var windowStateCancellables: Set<AnyCancellable> = []
    private var screenSaverEngineCancellables: Set<AnyCancellable> = []
    private var inlinePreviewPolicy = InlinePreviewPlaybackPolicy(
        applicationIsActive: NSApp.isActive,
        windowIsVisible: true,
        displaysPageIsVisible: false,
        competingPlaybackIsActive: false
    )
    private var optimizationTask: Task<Void, Never>?
    private var optimizationRestartRequested = false
    private var optimizationShouldResumeAfterPlayback = false
    private var isOptimizationSuspendedForPlayback = false
    private var integrationRefreshGeneration = 0
    private var isFinalizingScreenSaverUpdate = false
    private let defaultsKey = "wallpaperSettings"
    private let appearanceModeKey = "appearanceMode"
    private let verificationAttemptedKey = "screenSaverVerificationAttempted"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        videoOptimizer: VideoOptimizing = AVFoundationVideoOptimizer(),
        launchAtLogin: LaunchAtLoginController? = nil
    ) {
        self.videoOptimizer = videoOptimizer
        self.launchAtLogin = launchAtLogin ?? LaunchAtLoginController()
        appearanceMode = AppearanceMode(
            rawValue: UserDefaults.standard.string(forKey: appearanceModeKey) ?? ""
        ) ?? .automatic
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

        removeOrphanedOptimizedFiles()
        refreshScreens()
        migrateLegacyVideoToScreensIfNeeded()
        migrateDuplicateLibraryVideosIfNeeded()
        persistSharedSettings()
        applySettings()
        observeDisplayChanges()
        observeApplicationActivation()
        observeMainWindowVisibility()
        observeScreenSaverEngineLifecycle()
        previewController.onError = { [weak self] message in
            self?.errorMessage = message
        }
        previewController.onDismiss = { [weak self] in
            self?.resumeOptimizationAfterPlayback()
        }
        Task { await refreshScreenSaverIntegrationState() }
        Task { await refreshVideoMetadata() }
        Task { await refreshVideoFingerprints() }
        if settings.playbackQuality == .performance {
            optimizeExistingVideos()
        }
    }

    var statusText: String {
        let configuredCount = allPlaybackPlans().count
        guard configuredCount > 0 else { return "Configure a display to get started" }
        switch screenSaverIntegrationState {
        case .ready:
            return "Ready for \(configuredCount) display\(configuredCount == 1 ? "" : "s")"
        case .updateRequired:
            return "Screen saver update required"
        case .finalizingUpdate:
            return "Finalizing screen saver update"
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

    func setDisplaysPageVisible(_ isVisible: Bool) {
        inlinePreviewPolicy.displaysPageIsVisible = isVisible
        if isVisible {
            refreshMainWindowVisibility()
        } else {
            updateInlinePreviewPlayback()
        }
    }

    func prepareVideoImports(from sourceURLs: [URL]) async -> [VideoImportCandidate] {
        await refreshVideoFingerprints()
        let candidateIDs = sourceURLs.map { _ in UUID() }
        let names = sourceURLs.map { $0.deletingPathExtension().lastPathComponent }
        var fileSizes: [Int64] = []
        var metadataValues: [VideoTechnicalMetadata?] = []
        var fingerprints: [String?] = []

        for sourceURL in sourceURLs {
            let hasAccess = sourceURL.startAccessingSecurityScopedResource()
            let attributes = try? FileManager.default.attributesOfItem(atPath: sourceURL.path)
            fileSizes.append((attributes?[.size] as? NSNumber)?.int64Value ?? 0)
            metadataValues.append(try? await videoOptimizer.metadata(for: sourceURL))
            fingerprints.append(await contentFingerprint(for: sourceURL))
            if hasAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }
        let duplicateReferences = VideoLibraryLogic.duplicateReferences(
            candidateIDs: candidateIDs,
            for: names,
            fingerprints: fingerprints,
            existingVideos: settings.videos
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

    func importVideosToLibrary(
        candidates: [VideoImportCandidate]
    ) async -> [ManagedVideo] {
        let importable = candidates.filter { !$0.isDuplicate }
        guard !importable.isEmpty else { return [] }
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }

        var imported: [ManagedVideo] = []
        var copiedURLs: [URL] = []
        do {
            let directory = try managedVideosDirectory()
            for candidate in importable {
                let sourceURL = candidate.sourceURL
                let hasAccess = sourceURL.startAccessingSecurityScopedResource()
                defer {
                    if hasAccess { sourceURL.stopAccessingSecurityScopedResource() }
                }

                let id = UUID().uuidString
                let destination = directory.appendingPathComponent(id)
                    .appendingPathExtension(sourceURL.pathExtension.lowercased())
                try FileManager.default.copyItem(at: sourceURL, to: destination)
                copiedURLs.append(destination)
                let metadata: VideoTechnicalMetadata?
                if let candidateMetadata = candidate.metadata {
                    metadata = candidateMetadata
                } else {
                    metadata = try? await videoOptimizer.metadata(for: destination)
                }
                imported.append(ManagedVideo(
                    id: id,
                    displayName: candidate.displayName,
                    path: destination.path,
                    sourceMetadata: metadata,
                    contentFingerprint: candidate.contentFingerprint
                ))
            }

            settings.videos.append(contentsOf: imported)
            saveAndApply()
            if settings.playbackQuality == .performance {
                optimizeExistingVideos()
            }
            return imported
        } catch {
            for url in copiedURLs {
                try? FileManager.default.removeItem(at: url)
            }
            errorMessage = "The video couldn’t be imported: \(error.localizedDescription)"
            return []
        }
    }

    func assignVideos(_ videoIDs: [String], to screenID: String) {
        let knownIDs = Set(settings.videos.map(\.id))
        let additions = videoIDs.filter { knownIDs.contains($0) }
        guard !additions.isEmpty else { return }
        mutateConfiguration(for: screenID) { configuration in
            configuration.videoIDs = VideoLibraryLogic.assigning(
                additions,
                to: configuration.videoIDs,
                mode: configuration.mode
            )
            if !configuration.videoIDs.contains(configuration.startVideoID ?? "") {
                configuration.startVideoID = configuration.videoIDs.first
            }
        }
        saveAndApply()
        refreshPreview()
    }

    func usageCount(for videoID: String) -> Int {
        VideoLibraryLogic.usageCount(for: videoID, screens: settings.screens)
    }

    var unusedVideoCount: Int {
        settings.videos.filter { usageCount(for: $0.id) == 0 }.count
    }

    @discardableResult
    func removeVideoFromLibrary(_ videoID: String) -> Bool {
        guard usageCount(for: videoID) == 0,
              let index = settings.videos.firstIndex(where: { $0.id == videoID }) else {
            return false
        }
        let video = settings.videos[index]
        do {
            try deleteManagedFiles(for: video)
        } catch {
            errorMessage = "The video couldn’t be deleted: \(error.localizedDescription)"
            return false
        }
        settings.videos.remove(at: index)
        saveAndApply()
        return true
    }

    func removeUnusedLibraryVideos() {
        let unused = settings.videos.filter { usageCount(for: $0.id) == 0 }
        guard !unused.isEmpty else { return }
        var deletedIDs = Set<String>()
        var failureCount = 0
        for video in unused {
            do {
                try deleteManagedFiles(for: video)
                deletedIDs.insert(video.id)
            } catch {
                failureCount += 1
            }
        }
        if !deletedIDs.isEmpty {
            settings.videos.removeAll { deletedIDs.contains($0.id) }
            saveAndApply()
        }
        if failureCount > 0 {
            errorMessage = "\(failureCount) video\(failureCount == 1 ? "" : "s") couldn’t be deleted."
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

    func setPlaybackQuality(_ quality: VideoPlaybackQuality) {
        guard settings.playbackQuality != quality else { return }
        settings.playbackQuality = quality
        saveAndApply()
        refreshPreview()
        if quality == .performance {
            optimizeExistingVideos()
        } else {
            cancelOptimization()
        }
    }

    func setOptimizationProfile(_ profile: VideoOptimizationProfile) {
        guard settings.optimizationProfile != profile else { return }
        settings.optimizationProfile = profile
        saveAndApply()
        refreshPreview()
        if settings.playbackQuality == .performance {
            optimizationTask?.cancel()
            optimizeExistingVideos()
        }
    }

    func optimizeExistingVideos() {
        guard !isOptimizationSuspendedForPlayback else {
            optimizationShouldResumeAfterPlayback = true
            return
        }
        guard optimizationTask == nil else {
            optimizationRestartRequested = true
            return
        }
        optimizationRestartRequested = false
        let profile = settings.optimizationProfile
        optimizationTask = Task { @MainActor [weak self] in
            await self?.runOptimization(profile: profile)
        }
    }

    func cancelOptimization() {
        optimizationShouldResumeAfterPlayback = false
        optimizationRestartRequested = false
        optimizationTask?.cancel()
        optimizationProgress = nil
    }

    var demandingVideoCount: Int {
        settings.videos.filter { $0.sourceMetadata?.isDemanding == true }.count
    }

    var optimizedVideoCount: Int {
        settings.videos.filter { video in
            guard video.optimizedProfile == settings.optimizationProfile,
                  let path = video.optimizedPath else { return false }
            return FileManager.default.isReadableFile(atPath: path)
        }.count
    }

    var estimatedOptimizationBytes: Int64 {
        let baseBitRate = settings.optimizationProfile == .efficient
            ? 18_128_000.0
            : 30_128_000.0
        return Int64(settings.videos.reduce(0.0) { total, video in
            total + max(0, video.sourceMetadata?.durationSeconds ?? 0) * baseBitRate / 8
        })
    }

    var optimizedStorageBytes: Int64 {
        settings.videos.reduce(0) { total, video in
            guard let path = video.optimizedPath,
                  let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                  let size = attributes[.size] as? NSNumber else { return total }
            return total + size.int64Value
        }
    }

    func deleteOptimizedCopies() {
        cancelOptimization()
        for index in settings.videos.indices {
            if let path = settings.videos[index].optimizedPath {
                removeOptimizedFileIfOwned(atPath: path)
            }
            settings.videos[index].optimizedPath = nil
            settings.videos[index].optimizedProfile = nil
        }
        saveAndApply()
        refreshPreview()
    }

    func setAppearanceMode(_ mode: AppearanceMode) {
        guard appearanceMode != mode else { return }
        appearanceMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: appearanceModeKey)
        appearanceTransitionID = UUID()
    }

    func clearError() {
        errorMessage = nil
    }

    func installOrUpdateScreenSaver() {
        errorMessage = nil
        integrationRefreshGeneration += 1
        isFinalizingScreenSaverUpdate = true
        screenSaverIntegrationState = .finalizingUpdate
        do {
            try nativeScreenSaver.installOrUpdate()
            Task { await finalizeScreenSaverUpdate() }
        } catch {
            isFinalizingScreenSaverUpdate = false
            errorMessage = "The screen saver couldn’t be installed: \(error.localizedDescription)"
            Task { await refreshScreenSaverIntegrationState() }
        }
    }

    func verifySystemScreenSaverSetup(requestConsent: Bool) async {
        guard !isFinalizingScreenSaverUpdate else { return }
        if requestConsent {
            UserDefaults.standard.set(true, forKey: verificationAttemptedKey)
        }
        let generation = beginIntegrationRefresh()
        let state = await nativeScreenSaver.integrationState(
            verificationAttempted: UserDefaults.standard.bool(forKey: verificationAttemptedKey),
            requestConsent: requestConsent
        )
        guard generation == integrationRefreshGeneration else { return }
        screenSaverIntegrationState = state
    }

    func refreshScreenSaverIntegrationState() async {
        guard !isFinalizingScreenSaverUpdate else { return }
        await verifySystemScreenSaverSetup(requestConsent: false)
    }

    private func finalizeScreenSaverUpdate() async {
        let generation = beginIntegrationRefresh()
        let state = await nativeScreenSaver.integrationState(
            verificationAttempted: UserDefaults.standard.bool(forKey: verificationAttemptedKey),
            retryTransientSelection: true
        )
        guard generation == integrationRefreshGeneration else { return }
        screenSaverIntegrationState = state
        isFinalizingScreenSaverUpdate = false
    }

    private func beginIntegrationRefresh() -> Int {
        integrationRefreshGeneration += 1
        return integrationRefreshGeneration
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
        suspendOptimizationForPlayback()
        do {
            try await nativeScreenSaver.startNativeScreenSaver()
            return .started
        } catch {
            resumeOptimizationAfterPlayback()
            let message = "The native screen saver could not start: \(error.localizedDescription)"
            errorMessage = message
            return .launchFailed(message: message)
        }
    }

    func previewAllDisplays() {
        guard !previewController.isPresenting else { return }
        errorMessage = nil
        suspendOptimizationForPlayback()
        if !previewController.previewAllDisplays() {
            resumeOptimizationAfterPlayback()
        }
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

    private func optimizedVideosDirectory() throws -> URL {
        let directory = try applicationSupportDirectory()
            .appendingPathComponent("Optimized Videos", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func removeOrphanedOptimizedFiles() {
        guard let directory = try? optimizedVideosDirectory(),
              let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
              ) else { return }
        let retainedPaths = Set(settings.videos.compactMap(\.optimizedPath))
        for file in files where !retainedPaths.contains(file.path) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func removeOptimizedFileIfOwned(atPath path: String) {
        guard let directory = try? optimizedVideosDirectory() else { return }
        let file = URL(fileURLWithPath: path).standardizedFileURL
        guard file.deletingLastPathComponent() == directory.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: file)
    }

    private func deleteManagedFiles(for video: ManagedVideo) throws {
        if let optimizedPath = video.optimizedPath {
            let optimizedDirectory = try optimizedVideosDirectory().standardizedFileURL
            try removeFileIfPresent(
                at: URL(fileURLWithPath: optimizedPath),
                ownedBy: optimizedDirectory
            )
        }
        let managedDirectory = try managedVideosDirectory().standardizedFileURL
        try removeFileIfPresent(at: video.url, ownedBy: managedDirectory)
    }

    private func removeFileIfPresent(at url: URL, ownedBy directory: URL) throws {
        let file = url.standardizedFileURL
        guard file.deletingLastPathComponent() == directory.standardizedFileURL else {
            throw CocoaError(.fileWriteNoPermission)
        }
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
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

    private func refreshPreview() {
        previewPlayer?.pause()
        previewLooper = nil
        guard let screenID = previewScreenID,
              let videoURL = previewVideoURL(for: screenID),
              FileManager.default.fileExists(atPath: videoURL.path) else {
            previewPlayer = nil
            return
        }
        let player = AVQueuePlayer()
        previewLooper = AVPlayerLooper(
            player: player,
            templateItem: AVPlayerItem(url: videoURL)
        )
        player.isMuted = settings.isMuted
        previewPlayer = player
        updateInlinePreviewPlayback()
    }

    private func updateInlinePreviewPlayback() {
        if inlinePreviewPolicy.shouldPlay {
            previewPlayer?.play()
        } else {
            previewPlayer?.pause()
        }
    }

    private func previewVideoURL(for screenID: String) -> URL? {
        let configuration = configuration(for: screenID)
        let videoID = configuration.startVideoID ?? configuration.videoIDs.first
        guard let video = settings.videos.first(where: { $0.id == videoID }) else { return nil }
        return URL(fileURLWithPath: video.playbackPath(
            quality: settings.playbackQuality,
            profile: settings.optimizationProfile
        ))
    }

    private func allPlaybackPlans() -> [ScreenPlaybackPlan] {
        return settings.screens.compactMap { configuration in
            let playableVideos = configuration.videoIDs.compactMap { id -> (ManagedVideo, URL)? in
                guard let video = settings.videos.first(where: { $0.id == id }) else { return nil }
                let path = video.playbackPath(
                    quality: settings.playbackQuality,
                    profile: settings.optimizationProfile
                )
                guard FileManager.default.isReadableFile(atPath: path) else { return nil }
                return (video, URL(fileURLWithPath: path))
            }
            guard !playableVideos.isEmpty else { return nil }
            let startIndex = playableVideos.firstIndex {
                $0.0.id == configuration.startVideoID
            } ?? 0
            return ScreenPlaybackPlan(
                screenID: configuration.screenID,
                videoURLs: configuration.mode == .single
                    ? [playableVideos[startIndex].1]
                    : playableVideos.map(\.1),
                startIndex: configuration.mode == .single ? 0 : startIndex
            )
        }
    }

    private func refreshVideoMetadata() async {
        var changed = false
        for videoID in settings.videos.map(\.id) {
            guard !Task.isCancelled,
                  let index = settings.videos.firstIndex(where: { $0.id == videoID }),
                  settings.videos[index].sourceMetadata == nil else { continue }
            if let metadata = try? await videoOptimizer.metadata(for: settings.videos[index].url) {
                settings.videos[index].sourceMetadata = metadata
                changed = true
            }
        }
        if changed { saveAndApply() }
    }

    private func refreshVideoFingerprints() async {
        var changed = false
        for videoID in settings.videos.map(\.id) {
            guard !Task.isCancelled,
                  let index = settings.videos.firstIndex(where: { $0.id == videoID }),
                  settings.videos[index].contentFingerprint.map(
                      VideoContentFingerprint.isCurrent
                  ) != true else { continue }
            if let fingerprint = await contentFingerprint(for: settings.videos[index].url) {
                settings.videos[index].contentFingerprint = fingerprint
                changed = true
            }
        }
        if changed { saveAndApply() }
    }

    private func contentFingerprint(for url: URL) async -> String? {
        await Task.detached(priority: .utility) {
            VideoContentFingerprint.sampled(at: url)
        }.value
    }

    private func runOptimization(profile: VideoOptimizationProfile) async {
        defer {
            let shouldRestart = optimizationRestartRequested
            optimizationRestartRequested = false
            optimizationTask = nil
            optimizationProgress = nil
            if settings.playbackQuality == .performance, shouldRestart {
                optimizeExistingVideos()
            }
        }
        let videoIDs = settings.videos.map(\.id)
        var failures: [String] = []

        for (position, videoID) in videoIDs.enumerated() {
            guard !Task.isCancelled,
                  settings.optimizationProfile == profile,
                  let index = settings.videos.firstIndex(where: { $0.id == videoID }) else { return }
            let video = settings.videos[index]
            if video.optimizedProfile == profile,
               let path = video.optimizedPath,
               FileManager.default.isReadableFile(atPath: path) {
                optimizationProgress = VideoOptimizationProgress(
                    completedCount: position + 1,
                    totalCount: videoIDs.count,
                    currentVideoName: nil,
                    currentFraction: 0
                )
                continue
            }

            optimizationProgress = VideoOptimizationProgress(
                completedCount: position,
                totalCount: videoIDs.count,
                currentVideoName: video.displayName,
                currentFraction: 0
            )
            do {
                let directory = try optimizedVideosDirectory()
                let profileName = profile == .efficient ? "1440p60" : "4k60"
                let destination = directory
                    .appendingPathComponent("\(video.id)-\(profileName)-\(UUID().uuidString)")
                    .appendingPathExtension("mp4")
                do {
                    try await videoOptimizer.optimize(
                        sourceURL: video.url,
                        destinationURL: destination,
                        profile: profile
                    ) { [weak self] fraction in
                        Task { @MainActor [weak self] in
                            guard let self,
                                  self.settings.optimizationProfile == profile else { return }
                            self.optimizationProgress = VideoOptimizationProgress(
                                completedCount: position,
                                totalCount: videoIDs.count,
                                currentVideoName: video.displayName,
                                currentFraction: fraction
                            )
                        }
                    }
                    guard FileManager.default.isReadableFile(atPath: destination.path) else {
                        throw VideoOptimizationError.writerFailed(nil)
                    }
                } catch {
                    try? FileManager.default.removeItem(at: destination)
                    throw error
                }

                guard !Task.isCancelled,
                      settings.playbackQuality == .performance,
                      settings.optimizationProfile == profile,
                      let currentIndex = settings.videos.firstIndex(where: { $0.id == videoID }) else {
                    try? FileManager.default.removeItem(at: destination)
                    return
                }
                let previousPath = settings.videos[currentIndex].optimizedPath
                settings.videos[currentIndex].optimizedPath = destination.path
                settings.videos[currentIndex].optimizedProfile = profile
                if settings.videos[currentIndex].sourceMetadata == nil {
                    settings.videos[currentIndex].sourceMetadata = try? await videoOptimizer.metadata(
                        for: video.url
                    )
                }
                saveAndApply()
                refreshPreview()
                if let previousPath, previousPath != destination.path {
                    removeOptimizedFileIfOwned(atPath: previousPath)
                }
            } catch is CancellationError {
                return
            } catch {
                failures.append(video.displayName)
            }
        }

        if !failures.isEmpty {
            errorMessage = "Performance copies could not be created for \(failures.count) video(s). Originals will be used instead."
        }
    }

    private func suspendOptimizationForPlayback() {
        inlinePreviewPolicy.competingPlaybackIsActive = true
        updateInlinePreviewPlayback()
        guard settings.playbackQuality == .performance else { return }
        isOptimizationSuspendedForPlayback = true
        optimizationShouldResumeAfterPlayback = optimizationTask != nil || settings.videos.contains {
            guard $0.optimizedProfile == settings.optimizationProfile,
                  let path = $0.optimizedPath else { return true }
            return !FileManager.default.isReadableFile(atPath: path)
        }
        optimizationRestartRequested = false
        optimizationTask?.cancel()
        optimizationProgress = nil
    }

    private func resumeOptimizationAfterPlayback() {
        inlinePreviewPolicy.competingPlaybackIsActive = false
        updateInlinePreviewPlayback()
        guard isOptimizationSuspendedForPlayback else { return }
        isOptimizationSuspendedForPlayback = false
        let shouldResume = optimizationShouldResumeAfterPlayback
        optimizationShouldResumeAfterPlayback = false
        if shouldResume {
            optimizeExistingVideos()
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
                self?.inlinePreviewPolicy.applicationIsActive = true
                self?.refreshMainWindowVisibility()
                self?.launchAtLogin.refresh()
                await self?.refreshScreenSaverIntegrationState()
            }
        }

        let center = NotificationCenter.default
        for name in [NSApplication.didResignActiveNotification, NSApplication.didHideNotification] {
            center.publisher(for: name)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.inlinePreviewPolicy.applicationIsActive = false
                        self?.updateInlinePreviewPlayback()
                    }
                }
                .store(in: &applicationInactiveCancellables)
        }
        center.publisher(for: NSApplication.didUnhideNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.inlinePreviewPolicy.applicationIsActive = NSApp.isActive
                    self?.refreshMainWindowVisibility()
                }
            }
            .store(in: &applicationInactiveCancellables)
    }

    private func observeMainWindowVisibility() {
        let center = NotificationCenter.default
        for name in [
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.didChangeOcclusionStateNotification
        ] {
            center.publisher(for: name)
                .receive(on: RunLoop.main)
                .sink { [weak self] notification in
                    guard let window = notification.object as? NSWindow,
                          window.title == "My Wallpaper" else { return }
                    MainActor.assumeIsolated {
                        self?.inlinePreviewPolicy.windowIsVisible =
                            !window.isMiniaturized && window.occlusionState.contains(.visible)
                        self?.updateInlinePreviewPlayback()
                    }
                }
                .store(in: &windowStateCancellables)
        }
    }

    private func refreshMainWindowVisibility() {
        guard let window = NSApp.windows.first(where: { $0.title == "My Wallpaper" }) else {
            inlinePreviewPolicy.windowIsVisible = false
            updateInlinePreviewPlayback()
            return
        }
        inlinePreviewPolicy.windowIsVisible =
            !window.isMiniaturized && window.occlusionState.contains(.visible)
        updateInlinePreviewPlayback()
    }

    private func observeScreenSaverEngineLifecycle() {
        let center = NSWorkspace.shared.notificationCenter
        center.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard Self.isScreenSaverEngine(notification) else { return }
                MainActor.assumeIsolated { self?.suspendOptimizationForPlayback() }
            }
            .store(in: &screenSaverEngineCancellables)
        center.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard Self.isScreenSaverEngine(notification) else { return }
                MainActor.assumeIsolated { self?.resumeOptimizationAfterPlayback() }
            }
            .store(in: &screenSaverEngineCancellables)
    }

    private static func isScreenSaverEngine(_ notification: Notification) -> Bool {
        let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication
        return application?.bundleIdentifier == "com.apple.ScreenSaver.Engine"
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

    private func migrateDuplicateLibraryVideosIfNeeded() {
        let result = VideoLibraryLogic.deduplicatingLegacyVideos(in: settings) { video in
            VideoContentFingerprint.sampled(at: video.url)
        }
        guard !result.redundantVideos.isEmpty,
              let encodedSettings = try? encoder.encode(result.settings) else { return }

        let previousSettings = settings
        settings = result.settings
        guard persistSharedSettings() else {
            settings = previousSettings
            _ = persistSharedSettings()
            return
        }
        UserDefaults.standard.set(encodedSettings, forKey: defaultsKey)

        let retainedPaths = Set(settings.videos.flatMap { video in
            [video.path, video.optimizedPath].compactMap { $0 }
        }.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        var cleanupFailureCount = 0
        for video in result.redundantVideos {
            do {
                let source = video.url.standardizedFileURL
                if !retainedPaths.contains(source.path) {
                    try removeFileIfPresent(
                        at: source,
                        ownedBy: try managedVideosDirectory()
                    )
                }
                if let optimizedPath = video.optimizedPath {
                    let optimized = URL(fileURLWithPath: optimizedPath).standardizedFileURL
                    if !retainedPaths.contains(optimized.path) {
                        try removeFileIfPresent(
                            at: optimized,
                            ownedBy: try optimizedVideosDirectory()
                        )
                    }
                }
            } catch {
                cleanupFailureCount += 1
            }
        }
        if cleanupFailureCount > 0 {
            let suffix = cleanupFailureCount == 1 ? "" : "s"
            errorMessage = "The shared library was repaired, but "
                + "\(cleanupFailureCount) redundant file\(suffix) couldn’t be removed."
        }
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
