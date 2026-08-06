import CoreGraphics
import XCTest
import VideoToolbox
@testable import MyWallpaper

final class VideoOptimizerTests: XCTestCase {
    func testPerformanceModeRequiresHardwareEncoding() {
        XCTAssertEqual(
            AVFoundationVideoOptimizer.hardwareEncoderSpecification[
                kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String
            ] as? Bool,
            true
        )
    }

    func testEfficientProfileLimitsLandscapeVideoTo1440p() {
        XCTAssertEqual(
            AVFoundationVideoOptimizer.targetSize(
                for: CGSize(width: 3840, height: 2160),
                profile: .efficient
            ),
            CGSize(width: 2560, height: 1440)
        )
    }

    func testEfficientProfilePreservesPortraitAspectRatio() {
        XCTAssertEqual(
            AVFoundationVideoOptimizer.targetSize(
                for: CGSize(width: 2160, height: 3840),
                profile: .efficient
            ),
            CGSize(width: 810, height: 1440)
        )
    }

    func testOptimizationDoesNotUpscaleSmallerVideo() {
        XCTAssertEqual(
            AVFoundationVideoOptimizer.targetSize(
                for: CGSize(width: 1920, height: 1080),
                profile: .maximum
            ),
            CGSize(width: 1920, height: 1080)
        )
    }

    func testDemandingMetadataDetectsHighFrameRateAndBitRate() {
        XCTAssertTrue(VideoTechnicalMetadata(
            width: 3840,
            height: 2160,
            frameRate: 120,
            estimatedBitRate: 22_000_000
        ).isDemanding)
        XCTAssertTrue(VideoTechnicalMetadata(
            width: 1920,
            height: 1080,
            frameRate: 30,
            estimatedBitRate: 80_000_000
        ).isDemanding)
        XCTAssertFalse(VideoTechnicalMetadata(
            width: 2560,
            height: 1440,
            frameRate: 60,
            estimatedBitRate: 18_000_000
        ).isDemanding)
    }
}
