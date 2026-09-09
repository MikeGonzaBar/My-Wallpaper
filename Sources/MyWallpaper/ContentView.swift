import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var store: WallpaperStore
    @StateObject private var importFlow = VideoImportFlowCoordinator()
    @State private var selectedScreenID: String?
    @State private var selectedLibraryVideoID: String?
    @State private var selectedSection = SidebarSection.displays
    @State private var pageMotionDirection = RetroVerticalMotion.up
    @State private var displayMotionDirection = RetroHorizontalMotion.left

    var body: some View {
        HStack(spacing: 0) {
            WallpaperSidebar(selectedSection: selectedSection, onSelect: selectSection)
            Rectangle()
                .fill(RetroPalette.ink)
                .frame(width: 1)
            mainContent
        }
        .background(RetroPalette.desktop)
        .foregroundStyle(RetroPalette.ink)
        .environment(\.font, RetroFont.body())
        .fileImporter(
            isPresented: $importFlow.isPickingVideo,
            allowedContentTypes: [.movie],
            allowsMultipleSelection: true,
            onCompletion: { result in
                importFlow.handleFileImport(result, prepare: store.prepareVideoImports)
            }
        )
        .sheet(item: $importFlow.libraryPickerRequest) { request in
            AddFromLibrarySheet(
                store: store,
                screenID: request.screenID,
                initialVideoID: request.initialVideoID,
                onImportNew: { importFlow.beginImport(destinationScreenID: request.screenID) },
                onDismiss: { importFlow.libraryPickerRequest = nil }
            )
        }
        .sheet(item: $importFlow.reviewRequest) { request in
            ImportVideosReviewSheet(
                store: store,
                candidates: request.candidates,
                destinationScreenID: request.destinationScreenID,
                onChooseMore: { importFlow.chooseMore(for: request) },
                onComplete: { selectedVideoID in
                    if request.destinationScreenID == nil {
                        selectedLibraryVideoID = selectedVideoID
                        selectSection(.library)
                    }
                    importFlow.finishReview()
                },
                onDismiss: importFlow.finishReview
            )
        }
        .overlay {
            VideoImportPreparationOverlay(
                isPresented: importFlow.isPreparingImports,
                onCancel: importFlow.cancelPreparation
            )
        }
        .onAppear {
            store.refreshScreens()
            reconcileSelectedScreen(with: store.availableScreens)
            store.setDisplaysPageVisible(selectedSection == .displays)
        }
        .onDisappear {
            importFlow.cancelPreparation()
            store.setDisplaysPageVisible(false)
        }
        .onChange(of: selectedSection) { _, section in
            store.setDisplaysPageVisible(section == .displays)
        }
        .onChange(of: store.availableScreens) { _, screens in
            reconcileSelectedScreen(with: screens)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showMyWallpaperScreenSaverSetup)) { _ in
            selectSection(.preferences)
        }
        .alert(
            "MY WALLPAPER NEEDS ATTENTION",
            isPresented: Binding(
                get: { store.errorMessage != nil || importFlow.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        clearErrors()
                    }
                }
            )
        ) {
            Button("OK", role: .cancel, action: clearErrors)
        } message: {
            Text(store.errorMessage ?? importFlow.errorMessage ?? "Unknown error")
        }
    }

    private var mainContent: some View {
        ZStack(alignment: .topLeading) {
            Group {
                switch selectedSection {
                case .displays:
                    DisplaysDashboardView(
                        store: store,
                        selectedScreenID: selectedScreenID,
                        pageMotionDirection: pageMotionDirection,
                        displayMotionDirection: displayMotionDirection,
                        onSelectScreen: { selectScreen($0) },
                        onShowLibraryPicker: { importFlow.showLibraryPicker(for: $0) },
                        onBeginImport: { importFlow.beginImport(destinationScreenID: $0) }
                    )
                case .library:
                    VideoLibraryView(
                        store: store,
                        selectedVideoID: $selectedLibraryVideoID,
                        onImport: { importFlow.beginImport(destinationScreenID: nil) },
                        addDestinationName: selectedDisplayName,
                        onAddToDisplay: addToSelectedDisplay
                    )
                case .preferences:
                    PreferencesDashboardView(store: store, motionDirection: pageMotionDirection)
                }
            }
            .id(selectedSection)
            .transition(reduceMotion ? .opacity : .retroVertical(pageMotionDirection))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private func selectScreen(_ screenID: String?) {
        guard screenID != selectedScreenID else { return }

        let currentIndex = store.availableScreens.firstIndex { $0.id == selectedScreenID }
        let newIndex = store.availableScreens.firstIndex { $0.id == screenID }
        if let currentIndex, let newIndex {
            displayMotionDirection = .direction(from: currentIndex, to: newIndex)
        }

        let shouldAnimate = selectedScreenID != nil && screenID != nil
        if shouldAnimate && !reduceMotion {
            withAnimation(RetroMotion.panel) {
                applyScreenSelection(screenID)
            }
        } else {
            applyScreenSelection(screenID)
        }
    }

    private func applyScreenSelection(_ screenID: String?) {
        selectedScreenID = screenID
        store.selectScreen(screenID)
    }

    private func reconcileSelectedScreen(with screens: [DisplayInfo]) {
        guard !screens.contains(where: { $0.id == selectedScreenID }) else { return }
        selectScreen(screens.first?.id)
    }

    private var selectedDisplayName: String? {
        let screenID = selectedScreenID ?? store.availableScreens.first?.id
        return store.availableScreens.first { $0.id == screenID }?.name
    }

    private func addToSelectedDisplay(_ video: ManagedVideo) {
        guard let screenID = selectedScreenID ?? store.availableScreens.first?.id else { return }
        store.assignVideos([video.id], to: screenID)
    }

    private func selectSection(_ section: SidebarSection) {
        guard section != selectedSection else { return }

        pageMotionDirection = section.rawValue > selectedSection.rawValue ? .up : .down
        withAnimation(reduceMotion ? .linear(duration: 0.01) : RetroMotion.panel) {
            selectedSection = section
        }
    }

    private func clearErrors() {
        store.clearError()
        importFlow.clearError()
    }
}
