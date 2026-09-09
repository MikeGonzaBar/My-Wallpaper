@preconcurrency import AppKit
@preconcurrency import AVFoundation
import Combine

struct RollingPlaylistState: Equatable {
    private let orderedURLs: [URL]
    private(set) var failedURLs: Set<URL> = []
    private var nextIndex = 0

    init(orderedURLs: [URL]) {
        self.orderedURLs = orderedURLs
    }

    var targetBufferedItemCount: Int {
        min(2, Set(orderedURLs).subtracting(failedURLs).count)
    }

    var hasPlayableURL: Bool {
        orderedURLs.contains { !failedURLs.contains($0) }
    }

    mutating func markFailed(_ url: URL) {
        failedURLs.insert(url)
    }

    mutating func nextPlayableURL() -> URL? {
        guard hasPlayableURL else { return nil }
        for _ in orderedURLs.indices {
            let url = orderedURLs[nextIndex]
            nextIndex = (nextIndex + 1) % orderedURLs.count
            if !failedURLs.contains(url) {
                return url
            }
        }
        return nil
    }
}

@MainActor
final class PlaylistPlayerView: NSView {
    private let player = AVQueuePlayer()
    private let playerLayer = AVPlayerLayer()
    private let exitButton = NSButton()
    private let countdownLabel = NSTextField(labelWithString: "")
    private let onExit: () -> Void
    private var playlistState: RollingPlaylistState
    private var ownedItems: [ObjectIdentifier: URL] = [:]
    private var playbackCancellables: Set<AnyCancellable> = []

    init(
        videoURLs: [URL],
        isMuted: Bool,
        scaling: VideoScaling,
        onExit: @escaping () -> Void
    ) {
        playlistState = RollingPlaylistState(orderedURLs: videoURLs)
        self.onExit = onExit
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.player = player
        playerLayer.videoGravity = scaling == .fill ? .resizeAspectFill : .resizeAspect
        layer?.addSublayer(playerLayer)
        player.isMuted = isMuted
        fillPlaybackQueue()

        exitButton.title = "EXIT PREVIEW"
        exitButton.bezelStyle = .rounded
        exitButton.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        exitButton.target = self
        exitButton.action = #selector(exitPreview)
        addSubview(exitButton)

        countdownLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        countdownLabel.textColor = .white
        countdownLabel.backgroundColor = NSColor.black.withAlphaComponent(0.72)
        countdownLabel.drawsBackground = true
        countdownLabel.alignment = .center
        countdownLabel.isHidden = true
        addSubview(countdownLabel)

        let center = NotificationCenter.default
        center.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .compactMap { notification in
                (notification.object as? AVPlayerItem).map(ObjectIdentifier.init)
            }
            .receive(on: RunLoop.main)
            .sink { [weak self] itemID in
                MainActor.assumeIsolated {
                    self?.requeueIfOwned(itemID)
                }
            }
            .store(in: &playbackCancellables)
        center.publisher(for: .AVPlayerItemFailedToPlayToEndTime)
            .compactMap { notification in
                (notification.object as? AVPlayerItem).map(ObjectIdentifier.init)
            }
            .receive(on: RunLoop.main)
            .sink { [weak self] itemID in
                MainActor.assumeIsolated {
                    self?.discardIfOwned(itemID)
                }
            }
            .store(in: &playbackCancellables)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
        exitButton.sizeToFit()
        exitButton.frame.origin = CGPoint(
            x: max(20, bounds.maxX - exitButton.frame.width - 28),
            y: max(20, bounds.maxY - exitButton.frame.height - 24)
        )
        countdownLabel.frame = CGRect(
            x: max(20, bounds.midX - 210),
            y: 28,
            width: min(420, max(0, bounds.width - 40)),
            height: 34
        )
    }

    func play() {
        player.play()
    }

    func updateCountdown(secondsRemaining: Int) {
        countdownLabel.isHidden = secondsRemaining > 10
        countdownLabel.stringValue = "PREVIEW DOES NOT LOCK • ENDS IN \(secondsRemaining) SECONDS"
    }

    func stop() {
        player.pause()
        player.removeAllItems()
        playbackCancellables.removeAll()
        ownedItems.removeAll()
    }

    @objc private func exitPreview() {
        onExit()
    }

    private func enqueue(_ url: URL) {
        let item = AVPlayerItem(url: url)
        ownedItems[ObjectIdentifier(item)] = url
        player.insert(item, after: nil)
    }

    private func requeueIfOwned(_ itemID: ObjectIdentifier) {
        guard ownedItems.removeValue(forKey: itemID) != nil else { return }
        fillPlaybackQueue()
    }

    private func discardIfOwned(_ itemID: ObjectIdentifier) {
        guard let failedURL = ownedItems.removeValue(forKey: itemID) else { return }
        playlistState.markFailed(failedURL)
        if playlistState.hasPlayableURL {
            fillPlaybackQueue()
        } else {
            player.pause()
        }
    }

    private func fillPlaybackQueue() {
        while ownedItems.count < playlistState.targetBufferedItemCount,
              let url = playlistState.nextPlayableURL() {
            enqueue(url)
        }
    }
}
