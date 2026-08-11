import AppKit
import AVFoundation
import SwiftUI

struct VideoThumbnailView: View {
    let videoURL: URL
    var width: CGFloat = 112
    var height: CGFloat = 64

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Rectangle().fill(RetroPalette.ink)
            if let image {
                Image(nsImage: image)
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
            image = await Self.loadThumbnail(from: videoURL)
        }
    }

    private static func loadThumbnail(from url: URL) async -> NSImage? {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { url.stopAccessingSecurityScopedResource() }
        }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 180)
        guard let result = try? await generator.image(
            at: CMTime(seconds: 0.25, preferredTimescale: 600)
        ) else { return nil }
        return NSImage(cgImage: result.image, size: .zero)
    }
}
