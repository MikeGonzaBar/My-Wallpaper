import AppKit
import CoreImage

@MainActor
enum MenuBarIcon {
    static let image: NSImage? = {
        guard
            let sourceData = NSApp.applicationIconImage.tiffRepresentation,
            let sourceImage = CIImage(data: sourceData),
            let filter = CIFilter(name: "CIColorMatrix")
        else {
            return nil
        }

        filter.setValue(sourceImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputRVector")
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputGVector")
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector")
        filter.setValue(
            CIVector(x: -0.2126, y: -0.7152, z: -0.0722, w: 0),
            forKey: "inputAVector"
        )
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputBiasVector")

        guard
            let outputImage = filter.outputImage,
            let cgImage = CIContext(options: [.useSoftwareRenderer: false]).createCGImage(
                outputImage,
                from: sourceImage.extent
            )
        else {
            return nil
        }

        let image = NSImage(cgImage: cgImage, size: NSSize(width: 18, height: 18))
        image.isTemplate = true
        return image
    }()
}
