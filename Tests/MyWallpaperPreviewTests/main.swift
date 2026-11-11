import AppKit
import AVFoundation
import AVKit
import SwiftUI
import Foundation

@main
struct PreviewPlaybackTests {
    @MainActor
    static func waitUntil(_ message: String, _ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !predicate() {
            guard Date() < deadline else { fatalError("Timed out: \(message)") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @MainActor
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let movie = root.appendingPathComponent("preview.mov")
        try await makeMovie(at: movie)
        try await testPreviewMounting(movie: movie)
        let playback = LibraryVideoPlayback()
        playback.load(movie, isActive: true)
        try await waitUntil("ready and advancing") {
            !playback.isLoading && playback.player.currentTime().seconds > 0.1
        }
        precondition(playback.errorMessage == nil)
        precondition(playback.player.isMuted)
        playback.setActive(false)
        precondition(playback.player.rate == 0)
        playback.setActive(true)
        _ = await playback.player.seek(to: CMTime(seconds: 0.9, preferredTimescale: 600),
                                       toleranceBefore: .zero, toleranceAfter: .zero)
        try await waitUntil("loop restarts") {
            let time = playback.player.currentTime().seconds
            return time > 0 && time < 0.5
        }
        let oldItem = playback.player.currentItem
        playback.load(movie, isActive: false)
        precondition(playback.player.currentItem !== oldItem)
        precondition(playback.player.rate == 0)
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: playback.player.currentItem)
        NotificationCenter.default.post(name: .AVPlayerItemFailedToPlayToEndTime, object: oldItem)
        try await Task.sleep(for: .milliseconds(50))
        precondition(playback.player.rate == 0 && playback.errorMessage == nil)
        NotificationCenter.default.post(name: .AVPlayerItemFailedToPlayToEndTime, object: playback.player.currentItem)
        try await waitUntil("mid-playback failure") { playback.errorMessage != nil }
        playback.stop()
        precondition(playback.player.currentItem == nil && playback.player.rate == 0)
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: oldItem)
        try await Task.sleep(for: .milliseconds(50))
        precondition(playback.player.currentItem == nil && playback.player.rate == 0)
        playback.load(root.appendingPathComponent("missing.mov"), isActive: true)
        try await waitUntil("missing-file error") { playback.errorMessage != nil }
        precondition(!playback.isLoading)
        playback.stop()
        print("Preview tests passed: UI mounting and teardown, playback advances, mute, pause/resume, loop, replacement, teardown, and error reporting.")
    }

    @MainActor
    static func testPreviewMounting(movie: URL) async throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 270, height: 180),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: AnyView(LibraryVideoPreview(videoURL: movie)))
        window.contentView = host
        defer { window.contentView = nil }

        func findPlayer(in view: NSView) -> AVPlayerView? {
            if let player = view as? AVPlayerView { return player }
            return view.subviews.lazy.compactMap { findPlayer(in: $0) }.first
        }

        // Mount the complete SwiftUI preview, rather than just testing AVPlayer.
        for _ in 0..<3 {
            host.rootView = AnyView(LibraryVideoPreview(videoURL: movie))
            host.layoutSubtreeIfNeeded()
            try await waitUntil("native preview mounted") { findPlayer(in: host)?.player != nil }
            guard let view = findPlayer(in: host), let player = view.player else {
                fatalError("Native preview did not attach its player")
            }
            precondition(view.controlsStyle == .inline)
            player.play()
            try await waitUntil("mounted preview advances") { player.currentTime().seconds > 0.1 }
            host.rootView = AnyView(EmptyView())
            host.layoutSubtreeIfNeeded()
            try await waitUntil("preview detached and stopped") {
                findPlayer(in: host) == nil && player.currentItem == nil && player.rate == 0
            }
        }
    }

    static func makeMovie(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64,
            AVVideoHeightKey: 64
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB])
        writer.add(input)
        precondition(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var buffer: CVPixelBuffer?
        precondition(CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32ARGB, nil, &buffer) == kCVReturnSuccess)
        guard let buffer else { fatalError("Could not allocate fixture frame") }
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer), 127, CVPixelBufferGetDataSize(buffer))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        for frame in 0..<30 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            precondition(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(seconds: 1, preferredTimescale: 30))
        await writer.finishWriting()
        precondition(writer.status == .completed)
    }
}
