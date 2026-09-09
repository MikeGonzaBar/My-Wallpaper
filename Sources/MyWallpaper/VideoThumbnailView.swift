@preconcurrency import AppKit
@preconcurrency import AVFoundation
import SwiftUI

private actor VideoThumbnailCache {
    static let shared = VideoThumbnailCache()

    private struct InFlightRequest {
        let task: Task<CGImage?, Never>
        var waiters: Set<UUID>
        let cost: Int
    }

    private let images = NSCache<NSString, CGImage>()
    private var inFlight: [String: InFlightRequest] = [:]

    init() {
        images.countLimit = 128
        images.totalCostLimit = 64 * 1_024 * 1_024
    }

    func image(from url: URL, maximumSize: CGSize) async -> CGImage? {
        let key = Self.cacheKey(for: url, maximumSize: maximumSize)
        if let cached = images.object(forKey: key as NSString) {
            return cached
        }

        let waiterID = UUID()
        let task: Task<CGImage?, Never>
        let cost = max(1, Int(maximumSize.width * maximumSize.height * 4))
        if var request = inFlight[key] {
            request.waiters.insert(waiterID)
            inFlight[key] = request
            task = request.task
        } else {
            task = Task(priority: .utility) {
                await Self.generateImage(from: url, maximumSize: maximumSize)
            }
            inFlight[key] = InFlightRequest(
                task: task,
                waiters: [waiterID],
                cost: cost
            )
        }

        return await withTaskCancellationHandler {
            let image = await task.value
            finishRequest(key: key, waiterID: waiterID, image: image)
            return Task.isCancelled ? nil : image
        } onCancel: {
            Task { await self.cancelRequest(key: key, waiterID: waiterID) }
        }
    }

    private func finishRequest(
        key: String,
        waiterID: UUID,
        image: CGImage?
    ) {
        guard var request = inFlight[key] else { return }
        if let image {
            images.setObject(image, forKey: key as NSString, cost: request.cost)
        }
        request.waiters.remove(waiterID)
        if request.waiters.isEmpty {
            inFlight[key] = nil
        } else {
            inFlight[key] = request
        }
    }

    private func cancelRequest(key: String, waiterID: UUID) {
        guard var request = inFlight[key] else { return }
        request.waiters.remove(waiterID)
        if request.waiters.isEmpty {
            request.task.cancel()
            inFlight[key] = nil
        } else {
            inFlight[key] = request
        }
    }

    private static func cacheKey(for url: URL, maximumSize: CGSize) -> String {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { url.stopAccessingSecurityScopedResource() }
        }
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modified = values?.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0
        let fileSize = values?.fileSize ?? 0
        return "\(url.standardizedFileURL.path)|\(fileSize)|\(modified)|"
            + "\(Int(maximumSize.width))x\(Int(maximumSize.height))"
    }

    private static func generateImage(from url: URL, maximumSize: CGSize) async -> CGImage? {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { url.stopAccessingSecurityScopedResource() }
        }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maximumSize
        do {
            let result = try await withTaskCancellationHandler {
                try await generator.image(
                    at: CMTime(seconds: 0.25, preferredTimescale: 600)
                )
            } onCancel: {
                generator.cancelAllCGImageGeneration()
            }
            try Task.checkCancellation()
            return result.image
        } catch {
            return nil
        }
    }
}

struct VideoThumbnailView: View {
    let videoURL: URL
    var width: CGFloat = 112
    var height: CGFloat = 64

    @State private var image: CGImage?

    var body: some View {
        ZStack {
            Rectangle().fill(RetroPalette.ink)
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Text("▶")
                    .font(RetroFont.headline(size: 18))
                    .foregroundStyle(RetroPalette.paper)
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .overlay { Rectangle().stroke(RetroPalette.ink, lineWidth: 1) }
        .task(id: videoURL.path) {
            image = nil
            let thumbnail = await VideoThumbnailCache.shared.image(
                from: videoURL,
                maximumSize: CGSize(width: 320, height: 180)
            )
            guard !Task.isCancelled else { return }
            image = thumbnail
        }
    }
}
