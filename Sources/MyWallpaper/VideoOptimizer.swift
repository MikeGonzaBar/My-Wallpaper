@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import VideoToolbox

struct VideoOptimizationProgress: Equatable {
    let completedCount: Int
    let totalCount: Int
    let currentVideoName: String?
    let currentFraction: Double

    var overallFraction: Double {
        guard totalCount > 0 else { return 0 }
        return min(1, (Double(completedCount) + currentFraction) / Double(totalCount))
    }
}

protocol VideoOptimizing {
    func metadata(for sourceURL: URL) async throws -> VideoTechnicalMetadata
    func optimize(
        sourceURL: URL,
        destinationURL: URL,
        profile: VideoOptimizationProfile,
        progress: @escaping (Double) -> Void
    ) async throws
}

enum VideoOptimizationError: LocalizedError {
    case missingVideoTrack
    case invalidDuration
    case cannotCreateReader
    case cannotCreateWriter
    case readerFailed(Error?)
    case writerFailed(Error?)

    var errorDescription: String? {
        switch self {
        case .missingVideoTrack:
            "The file does not contain a readable video track."
        case .invalidDuration:
            "The video does not have a finite playable duration."
        case .cannotCreateReader:
            "The video decoder could not be created."
        case .cannotCreateWriter:
            "The optimized video encoder could not be created."
        case let .readerFailed(error):
            error?.localizedDescription ?? "The source video could not be decoded."
        case let .writerFailed(error):
            error?.localizedDescription ?? "The optimized video could not be written."
        }
    }
}

private final class VideoTranscodingSession: @unchecked Sendable {
    let reader: AVAssetReader
    let writer: AVAssetWriter
    let videoOutput: AVAssetReaderOutput
    let videoInput: AVAssetWriterInput
    let audioOutput: AVAssetReaderOutput?
    let audioInput: AVAssetWriterInput?

    init(
        reader: AVAssetReader,
        writer: AVAssetWriter,
        videoOutput: AVAssetReaderOutput,
        videoInput: AVAssetWriterInput,
        audioPair: (AVAssetReaderOutput, AVAssetWriterInput)?
    ) {
        self.reader = reader
        self.writer = writer
        self.videoOutput = videoOutput
        self.videoInput = videoInput
        audioOutput = audioPair?.0
        audioInput = audioPair?.1
    }
}

final class AVFoundationVideoOptimizer: VideoOptimizing {
    func metadata(for sourceURL: URL) async throws -> VideoTechnicalMetadata {
        let asset = AVURLAsset(url: sourceURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoOptimizationError.missingVideoTrack
        }
        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let frameRate = Self.finiteNonnegative(Double(try await track.load(.nominalFrameRate)))
        let bitRate = Self.finiteNonnegative(Double(try await track.load(.estimatedDataRate)))
        let duration = try await asset.load(.duration)
        let durationSeconds = duration.seconds
        let presentationSize = Self.presentationSize(
            naturalSize: naturalSize,
            preferredTransform: preferredTransform
        )
        return VideoTechnicalMetadata(
            width: Int(presentationSize.width.rounded()),
            height: Int(presentationSize.height.rounded()),
            frameRate: frameRate,
            estimatedBitRate: bitRate,
            durationSeconds: durationSeconds.isFinite ? max(0, durationSeconds) : nil
        )
    }

    func optimize(
        sourceURL: URL,
        destinationURL: URL,
        profile: VideoOptimizationProfile,
        progress: @escaping (Double) -> Void
    ) async throws {
        let asset = AVURLAsset(url: sourceURL)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoOptimizationError.missingVideoTrack
        }
        let duration = try await asset.load(.duration)
        guard duration.isNumeric, duration.seconds.isFinite, duration.seconds > 0 else {
            throw VideoOptimizationError.invalidDuration
        }
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let sourceFrameRate = Double(try await videoTrack.load(.nominalFrameRate))
        let nominalFrameRate = Self.finiteNonnegative(sourceFrameRate)
        let presentationSize = Self.presentationSize(
            naturalSize: naturalSize,
            preferredTransform: preferredTransform
        )
        let targetSize = Self.targetSize(for: presentationSize, profile: profile)

        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: destinationURL, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true

        let videoComposition = Self.videoComposition(
            track: videoTrack,
            naturalSize: naturalSize,
            preferredTransform: preferredTransform,
            presentationSize: presentationSize,
            targetSize: targetSize,
            nominalFrameRate: nominalFrameRate,
            duration: duration
        )
        let videoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: [videoTrack],
            videoSettings: [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            ]
        )
        videoOutput.videoComposition = videoComposition
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw VideoOptimizationError.cannotCreateReader }
        reader.add(videoOutput)

        let referencePixels = profile == .efficient ? 2560.0 * 1440.0 : 3840.0 * 2160.0
        let pixelRatio = (targetSize.width * targetSize.height) / referencePixels
        let baseBitRate = profile == .efficient ? 18_000_000.0 : 30_000_000.0
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: Int(targetSize.width),
                AVVideoHeightKey: Int(targetSize.height),
                AVVideoEncoderSpecificationKey: Self.hardwareEncoderSpecification,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: Int(max(4_000_000, baseBitRate * pixelRatio)),
                    AVVideoExpectedSourceFrameRateKey: Int(min(60, max(1, nominalFrameRate.rounded()))),
                    AVVideoMaxKeyFrameIntervalDurationKey: 2
                ]
            ]
        )
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else { throw VideoOptimizationError.cannotCreateWriter }
        writer.add(videoInput)

        var audioPair: (AVAssetReaderOutput, AVAssetWriterInput)?
        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
            let output = AVAssetReaderTrackOutput(
                track: audioTrack,
                outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM]
            )
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48_000,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: 128_000
                ]
            )
            input.expectsMediaDataInRealTime = false
            if reader.canAdd(output), writer.canAdd(input) {
                reader.add(output)
                writer.add(input)
                audioPair = (output, input)
            }
        }

        guard writer.startWriting() else {
            throw VideoOptimizationError.writerFailed(writer.error)
        }
        guard reader.startReading() else {
            writer.cancelWriting()
            throw VideoOptimizationError.readerFailed(reader.error)
        }
        writer.startSession(atSourceTime: .zero)

        let session = VideoTranscodingSession(
            reader: reader,
            writer: writer,
            videoOutput: videoOutput,
            videoInput: videoInput,
            audioPair: audioPair
        )

        try await withTaskCancellationHandler {
            try await Self.writeSamples(
                session: session,
                duration: duration,
                progress: progress
            )
        } onCancel: {
            session.reader.cancelReading()
            session.writer.cancelWriting()
        }
    }

    static func targetSize(
        for sourceSize: CGSize,
        profile: VideoOptimizationProfile
    ) -> CGSize {
        let maximum = profile == .efficient
            ? CGSize(width: 2560, height: 1440)
            : CGSize(width: 3840, height: 2160)
        guard sourceSize.width > 0, sourceSize.height > 0 else { return maximum }
        let scale = min(1, maximum.width / sourceSize.width, maximum.height / sourceSize.height)
        return CGSize(
            width: evenDimension(sourceSize.width * scale),
            height: evenDimension(sourceSize.height * scale)
        )
    }

    static var hardwareEncoderSpecification: [String: Any] {
        [kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true]
    }

    private static func presentationSize(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform
    ) -> CGSize {
        let rect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        return CGSize(width: abs(rect.width), height: abs(rect.height))
    }

    private static func evenDimension(_ value: CGFloat) -> CGFloat {
        max(2, floor(value / 2) * 2)
    }

    private static func finiteNonnegative(_ value: Double) -> Double {
        value.isFinite ? max(0, value) : 0
    }

    private static func videoComposition(
        track: AVAssetTrack,
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        presentationSize: CGSize,
        targetSize: CGSize,
        nominalFrameRate: Double,
        duration: CMTime
    ) -> AVVideoComposition {
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        var transform = preferredTransform.concatenating(CGAffineTransform(
            translationX: -transformedRect.minX,
            y: -transformedRect.minY
        ))
        let scale = min(
            targetSize.width / max(presentationSize.width, 1),
            targetSize.height / max(presentationSize.height, 1)
        )
        transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))

        let outputFrameRate = min(60, max(1, nominalFrameRate > 0 ? nominalFrameRate : 30))
        let frameDuration = CMTime(seconds: 1 / outputFrameRate, preferredTimescale: 60_000)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layerInstruction.setTransform(transform, at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.layerInstructions = [layerInstruction]

        let composition = AVMutableVideoComposition()
        composition.renderSize = targetSize
        composition.frameDuration = frameDuration
        composition.instructions = [instruction]
        return composition
    }

    private static func writeSamples(
        session: VideoTranscodingSession,
        duration: CMTime,
        progress: @escaping (Double) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let group = DispatchGroup()
            let lock = NSLock()
            var appendFailed = false
            var lastReportedProgress = -1.0

            func markAppendFailed() {
                lock.lock()
                appendFailed = true
                lock.unlock()
                session.reader.cancelReading()
            }

            group.enter()
            session.videoInput.requestMediaDataWhenReady(on: DispatchQueue(label: "video-optimizer.video")) {
                while session.videoInput.isReadyForMoreMediaData {
                    guard let sample = session.videoOutput.copyNextSampleBuffer() else {
                        session.videoInput.markAsFinished()
                        group.leave()
                        return
                    }
                    let seconds = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                    if duration.seconds > 0 {
                        let fraction = min(1, max(0, seconds / duration.seconds))
                        if fraction - lastReportedProgress >= 0.01 {
                            lastReportedProgress = fraction
                            progress(fraction)
                        }
                    }
                    guard session.videoInput.append(sample) else {
                        markAppendFailed()
                        session.videoInput.markAsFinished()
                        group.leave()
                        return
                    }
                }
            }

            if let audioInput = session.audioInput, session.audioOutput != nil {
                group.enter()
                audioInput.requestMediaDataWhenReady(on: DispatchQueue(label: "video-optimizer.audio")) {
                    while session.audioInput?.isReadyForMoreMediaData == true {
                        guard let sample = session.audioOutput?.copyNextSampleBuffer() else {
                            session.audioInput?.markAsFinished()
                            group.leave()
                            return
                        }
                        guard session.audioInput?.append(sample) == true else {
                            markAppendFailed()
                            session.audioInput?.markAsFinished()
                            group.leave()
                            return
                        }
                    }
                }
            }

            group.notify(queue: DispatchQueue(label: "video-optimizer.finish")) {
                lock.lock()
                let failed = appendFailed
                lock.unlock()
                guard !failed, session.reader.status == .completed else {
                    session.writer.cancelWriting()
                    continuation.resume(throwing: VideoOptimizationError.readerFailed(session.reader.error))
                    return
                }
                session.writer.finishWriting {
                    if session.writer.status == .completed {
                        progress(1)
                        continuation.resume(returning: ())
                    } else {
                        continuation.resume(throwing: VideoOptimizationError.writerFailed(session.writer.error))
                    }
                }
            }
        }
    }
}
