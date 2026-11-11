import AVFoundation
import Combine

@MainActor
final class LibraryVideoPlayback: ObservableObject {
    let player = AVPlayer()
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: AnyCancellable?
    private var failureObserver: AnyCancellable?
    private var isActive = false

    init() {
        player.isMuted = true
    }

    func load(_ url: URL, isActive: Bool) {
        stop()
        isLoading = true
        self.isActive = isActive
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let status = item.status
            let failure = item.error?.localizedDescription
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.player.currentItem === item else { return }
                self.isLoading = status == .unknown
                if status == .failed {
                    self.errorMessage = failure ?? "This video could not be played."
                }
            }
        }
        endObserver = NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .receive(on: RunLoop.main)
            .sink { [weak self, weak item] _ in
                MainActor.assumeIsolated {
                    guard let self, let item, self.player.currentItem === item, self.isActive else { return }
                    self.player.seek(to: .zero)
                    self.player.play()
                }
            }
        failureObserver = NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime, object: item)
            .receive(on: RunLoop.main)
            .sink { [weak self, weak item] _ in
                MainActor.assumeIsolated {
                    guard let self, let item, self.player.currentItem === item else { return }
                    self.player.pause()
                    self.isLoading = false
                    self.errorMessage = "Playback stopped before the video ended. Try replacing the video."
                }
            }
        if isActive { player.play() }
    }

    func setActive(_ isActive: Bool) {
        self.isActive = isActive
        if isActive { player.play() }
        else { player.pause() }
    }

    func stop() {
        isActive = false
        player.pause()
        statusObservation = nil
        endObserver = nil
        failureObserver = nil
        player.replaceCurrentItem(with: nil)
        isLoading = false
        errorMessage = nil
    }
}
