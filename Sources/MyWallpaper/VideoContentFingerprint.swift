import CryptoKit
import Foundation

enum VideoContentFingerprint {
    private static let sampledVersionPrefix = "sampled-sha256-v1:"
    private static let fullVersionPrefix = "full-sha256-v1:"
    private static let sampleSize = 1_048_576

    static func isCurrent(_ fingerprint: String) -> Bool {
        fingerprint.hasPrefix(sampledVersionPrefix)
    }

    static func sampled(at url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let sizeNumber = attributes[.size] as? NSNumber,
              let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }

        let fileSize = sizeNumber.uint64Value
        let readableSampleSize = UInt64(min(sampleSize, Int(clamping: fileSize)))
        let offsets = Set([
            UInt64(0),
            fileSize > readableSampleSize
                ? (fileSize - readableSampleSize) / 2
                : 0,
            fileSize > readableSampleSize
                ? fileSize - readableSampleSize
                : 0,
        ]).sorted()

        var hasher = SHA256()
        hasher.update(data: Data("size:\(fileSize)".utf8))
        do {
            for offset in offsets {
                try handle.seek(toOffset: offset)
                hasher.update(data: Data("offset:\(offset)".utf8))
                if readableSampleSize > 0,
                   let data = try handle.read(upToCount: Int(readableSampleSize)) {
                    hasher.update(data: data)
                }
            }
        } catch {
            return nil
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return sampledVersionPrefix + digest
    }

    static func full(at url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        do {
            while let data = try handle.read(upToCount: sampleSize), !data.isEmpty {
                hasher.update(data: data)
            }
        } catch {
            return nil
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return fullVersionPrefix + digest
    }
}
