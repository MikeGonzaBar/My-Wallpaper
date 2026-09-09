import SwiftUI

@MainActor
final class VideoImportFlowCoordinator: ObservableObject {
    @Published var isPickingVideo = false
    @Published private(set) var isPreparingImports = false
    @Published private(set) var errorMessage: String?
    @Published var reviewRequest: ImportReviewRequest?
    @Published var libraryPickerRequest: LibraryPickerRequest?

    private var destinationScreenID: String?
    private var preparationTask: Task<Void, Never>?

    func showLibraryPicker(for screenID: String, initialVideoID: String? = nil) {
        libraryPickerRequest = LibraryPickerRequest(
            screenID: screenID,
            initialVideoID: initialVideoID
        )
    }

    func beginImport(destinationScreenID: String?) {
        self.destinationScreenID = destinationScreenID
        isPickingVideo = true
    }

    func handleFileImport(
        _ result: Result<[URL], Error>,
        prepare: @escaping ([URL]) async -> [VideoImportCandidate]
    ) {
        switch result {
        case let .success(urls):
            guard !urls.isEmpty else { return }
            preparationTask?.cancel()
            preparationTask = Task {
                isPreparingImports = true
                let candidates = await prepare(urls)
                guard !Task.isCancelled else { return }
                isPreparingImports = false
                if candidates.isEmpty {
                    errorMessage = "None of the selected files could be analyzed as a supported video."
                } else {
                    reviewRequest = ImportReviewRequest(
                        candidates: candidates,
                        destinationScreenID: destinationScreenID
                    )
                }
                preparationTask = nil
            }
        case let .failure(error):
            errorMessage = "The selected videos couldn’t be opened: \(error.localizedDescription)"
        }
    }

    func chooseMore(for request: ImportReviewRequest) {
        reviewRequest = nil
        DispatchQueue.main.async { [weak self] in
            self?.beginImport(destinationScreenID: request.destinationScreenID)
        }
    }

    func finishReview() {
        reviewRequest = nil
        destinationScreenID = nil
    }

    func cancelPreparation() {
        preparationTask?.cancel()
        preparationTask = nil
        isPreparingImports = false
    }

    func clearError() {
        errorMessage = nil
    }
}

struct VideoImportPreparationOverlay: View {
    let isPresented: Bool
    let onCancel: () -> Void

    @ViewBuilder
    var body: some View {
        if isPresented {
            ZStack {
                DitherPattern(opacity: 0.84)
                VStack(spacing: 12) {
                    Text("ANALYZING VIDEO CONTENT…")
                        .font(RetroFont.label(size: 10))
                    Button("CANCEL", action: onCancel)
                        .buttonStyle(RetroButtonStyle())
                }
                .padding(14)
                .background(RetroPalette.paper)
                .overlay { Rectangle().stroke(RetroPalette.ink, lineWidth: 1) }
            }
        }
    }
}

struct LibraryPickerRequest: Identifiable {
    let id = UUID()
    let screenID: String
    let initialVideoID: String?
}

struct ImportReviewRequest: Identifiable {
    let id = UUID()
    let candidates: [VideoImportCandidate]
    let destinationScreenID: String?
}
