import CoreGraphics
import XCTest
import VideoToolbox
@testable import MyWallpaper

final class VideoOptimizerTests: XCTestCase {
    private enum StubError: Error {
        case failed
    }

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

    func testMaximumProfileLimitsLandscapeVideoTo4K() {
        XCTAssertEqual(
            AVFoundationVideoOptimizer.targetSize(
                for: CGSize(width: 7_680, height: 4_320),
                profile: .maximum
            ),
            CGSize(width: 3_840, height: 2_160)
        )
    }

    func testTargetSizeReturnsSafeProfileMaximumForInvalidSourceDimensions() {
        XCTAssertEqual(
            AVFoundationVideoOptimizer.targetSize(
                for: CGSize(width: 0, height: 1_080),
                profile: .efficient
            ),
            CGSize(width: 2_560, height: 1_440)
        )
        XCTAssertEqual(
            AVFoundationVideoOptimizer.targetSize(
                for: CGSize(width: 1_920, height: -1),
                profile: .maximum
            ),
            CGSize(width: 3_840, height: 2_160)
        )
    }

    func testTargetSizeRoundsDownToEvenDimensions() {
        XCTAssertEqual(
            AVFoundationVideoOptimizer.targetSize(
                for: CGSize(width: 2_559, height: 1_439),
                profile: .efficient
            ),
            CGSize(width: 2_558, height: 1_438)
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

    func testCancellationTakesPrecedenceOverAVFoundationFailure() async {
        let task = Task {
            try await AVFoundationVideoOptimizer.propagatingCancellation { () async throws -> Void in
                withUnsafeCurrentTask { $0?.cancel() }
                throw StubError.failed
            }
        }

        do {
            _ = try await task.value
            XCTFail("Expected cancellation to propagate")
        } catch is CancellationError {
            // Expected: AVFoundation reports reader/writer errors after cancellation.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    func testNonCancellationFailureIsPreserved() async {
        do {
            try await AVFoundationVideoOptimizer.propagatingCancellation { () async throws -> Void in
                throw StubError.failed
            }
            XCTFail("Expected the operation to fail")
        } catch StubError.failed {
            // Expected.
        } catch {
            XCTFail("Expected the original failure, got \(error)")
        }
    }
}
