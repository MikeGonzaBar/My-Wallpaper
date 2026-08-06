import AppKit
import AVFoundation

@MainActor
final class PlaylistPlayerView: NSView {
    private let player = AVQueuePlayer()
    private let playerLayer = AVPlayerLayer()
    private let exitButton = NSButton()
    private let countdownLabel = NSTextField(labelWithString: "")
    private let orderedURLs: [URL]
    private let onExit: () -> Void
    private var nextLoopIndex = 0
    private var ownedItems: Set<ObjectIdentifier> = []
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?

    init(
        videoURLs: [URL],
        isMuted: Bool,
        scaling: VideoScaling,
        onExit: @escaping () -> Void
    ) {
        orderedURLs = videoURLs
        self.onExit = onExit
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.player = player
        playerLayer.videoGravity = scaling == .fill ? .resizeAspectFill : .resizeAspect
        layer?.addSublayer(playerLayer)
        player.isMuted = isMuted
        orderedURLs.forEach(enqueue)

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
        endObserver = center.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.requeueIfOwned(notification.object as? AVPlayerItem)
            }
        }
        failureObserver = center.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.discardIfOwned(notification.object as? AVPlayerItem)
            }
        }
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
        let center = NotificationCenter.default
        if let endObserver {
            center.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let failureObserver {
            center.removeObserver(failureObserver)
            self.failureObserver = nil
        }
        ownedItems.removeAll()
    }

    @objc private func exitPreview() {
        onExit()
    }

    private func enqueue(_ url: URL) {
        let item = AVPlayerItem(url: url)
        ownedItems.insert(ObjectIdentifier(item))
        player.insert(item, after: nil)
    }

    private func requeueIfOwned(_ endedItem: AVPlayerItem?) {
        guard let endedItem, !orderedURLs.isEmpty,
              ownedItems.remove(ObjectIdentifier(endedItem)) != nil else { return }
        enqueue(orderedURLs[nextLoopIndex])
        nextLoopIndex = (nextLoopIndex + 1) % orderedURLs.count
    }

    private func discardIfOwned(_ failedItem: AVPlayerItem?) {
        guard let failedItem else { return }
        ownedItems.remove(ObjectIdentifier(failedItem))
    }
}
