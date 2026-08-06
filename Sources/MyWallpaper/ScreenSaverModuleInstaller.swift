import CryptoKit
import Foundation
import Security

enum ScreenSaverModuleInstallationState {
    case unavailable(message: String)
    case notInstalled
    case updateRequired
    case current(URL)
}

protocol ScreenSaverModuleManaging {
    func installationState() -> ScreenSaverModuleInstallationState
    func installOrUpdate() throws
    func bundleIdentifier(atPath path: String) -> String?
}

final class ScreenSaverModuleInstaller: ScreenSaverModuleManaging {
    static let bundleIdentifier = "com.prototype.mywallpaper.saver"

    private let fileManager: FileManager
    private let embeddedSaverURLOverride: URL?
    private let installedSaverURLOverride: URL?
    private let signatureValidator: (URL) -> Bool

    init(
        fileManager: FileManager = .default,
        embeddedSaverURL: URL? = nil,
        installedSaverURL: URL? = nil,
        signatureValidator: ((URL) -> Bool)? = nil
    ) {
        self.fileManager = fileManager
        embeddedSaverURLOverride = embeddedSaverURL
        installedSaverURLOverride = installedSaverURL
        self.signatureValidator = signatureValidator ?? Self.hasValidSignature
    }

    func installationState() -> ScreenSaverModuleInstallationState {
        let embedded: SaverBundleDetails
        do {
            embedded = try embeddedSaverDetails()
        } catch {
            return .unavailable(message: error.localizedDescription)
        }

        let destination: URL
        do {
            destination = try installedScreenSaverURL(createDirectory: false)
        } catch {
            return .notInstalled
        }
        guard fileManager.fileExists(atPath: destination.path) else {
            return .notInstalled
        }

        let installed: SaverBundleDetails
        do {
            installed = try saverDetails(at: destination)
        } catch {
            return .updateRequired
        }
        guard installed.version == embedded.version,
              installed.build == embedded.build,
              installed.fingerprint == embedded.fingerprint else {
            return .updateRequired
        }
        return .current(destination)
    }

    func installOrUpdate() throws {
        let embedded = try embeddedSaverDetails()
        let destination = try installedScreenSaverURL(createDirectory: true)
        let parent = destination.deletingLastPathComponent()
        let staged = parent.appendingPathComponent(".My Wallpaper-\(UUID().uuidString).saver")
        let backupName = ".My Wallpaper-\(UUID().uuidString).backup.saver"
        let backup = parent.appendingPathComponent(backupName)

        defer {
            try? fileManager.removeItem(at: staged)
            try? fileManager.removeItem(at: backup)
        }

        try fileManager.copyItem(at: embedded.url, to: staged)
        let stagedDetails = try saverDetails(at: staged)
        guard stagedDetails.version == embedded.version,
              stagedDetails.build == embedded.build,
              stagedDetails.fingerprint == embedded.fingerprint else {
            throw ScreenSaverModuleError.stagedBundleMismatch
        }

        if fileManager.fileExists(atPath: destination.path) {
            do {
                _ = try fileManager.replaceItemAt(
                    destination,
                    withItemAt: staged,
                    backupItemName: backupName,
                    options: [.withoutDeletingBackupItem]
                )
            } catch {
                try restoreBackupIfPresent(backup, destination: destination)
                throw error
            }
        } else {
            try fileManager.moveItem(at: staged, to: destination)
        }

        do {
            let installed = try saverDetails(at: destination)
            guard installed.version == embedded.version,
                  installed.build == embedded.build,
                  installed.fingerprint == embedded.fingerprint else {
                throw ScreenSaverModuleError.installedBundleMismatch
            }
        } catch {
            if fileManager.fileExists(atPath: backup.path) {
                do {
                    try restoreBackupIfPresent(backup, destination: destination)
                } catch {
                    throw ScreenSaverModuleError.rollbackFailed
                }
            } else {
                try? fileManager.removeItem(at: destination)
            }
            throw error
        }
    }

    func bundleIdentifier(atPath path: String) -> String? {
        (try? bundleInfo(at: URL(fileURLWithPath: path)))?["CFBundleIdentifier"] as? String
    }

    private func embeddedSaverDetails() throws -> SaverBundleDetails {
        guard let url = embeddedSaverURLOverride ?? Bundle.main.url(
            forResource: "My Wallpaper",
            withExtension: "saver"
        ) else {
            throw ScreenSaverModuleError.missingEmbeddedSaver
        }
        return try saverDetails(at: url)
    }

    private func installedScreenSaverURL(createDirectory: Bool) throws -> URL {
        if let installedSaverURLOverride {
            if createDirectory {
                try fileManager.createDirectory(
                    at: installedSaverURLOverride.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
            }
            return installedSaverURLOverride
        }
        let library = try fileManager.url(
            for: .libraryDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: createDirectory
        )
        let screenSavers = library.appendingPathComponent("Screen Savers", isDirectory: true)
        if createDirectory {
            try fileManager.createDirectory(at: screenSavers, withIntermediateDirectories: true)
        }
        return screenSavers.appendingPathComponent("My Wallpaper.saver", isDirectory: true)
    }

    private func saverDetails(at url: URL) throws -> SaverBundleDetails {
        let info = try bundleInfo(at: url)
        guard info["CFBundleIdentifier"] as? String == Self.bundleIdentifier,
              let executableName = info["CFBundleExecutable"] as? String,
              let version = info["CFBundleShortVersionString"] as? String,
              let build = info["CFBundleVersion"] as? String else {
            throw ScreenSaverModuleError.invalidSaverBundle
        }
        let executableURL = url
            .appendingPathComponent("Contents/MacOS", isDirectory: true)
            .appendingPathComponent(executableName)
        guard fileManager.isExecutableFile(atPath: executableURL.path) else {
            throw ScreenSaverModuleError.invalidSaverBundle
        }

        guard signatureValidator(url) else {
            throw ScreenSaverModuleError.invalidSaverSignature
        }

        return SaverBundleDetails(
            url: url,
            version: version,
            build: build,
            fingerprint: try contentFingerprint(at: url)
        )
    }

    private func contentFingerprint(at bundleURL: URL) throws -> String {
        guard let enumerator = fileManager.enumerator(
            at: bundleURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else {
            throw ScreenSaverModuleError.invalidSaverBundle
        }

        let rootPath = bundleURL.standardizedFileURL.path + "/"
        let files = enumerator.compactMap { $0 as? URL }.filter { url in
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else { return false }
            let relative = String(url.standardizedFileURL.path.dropFirst(rootPath.count))
            return !relative.hasPrefix("Contents/_CodeSignature/")
        }.sorted { $0.path < $1.path }

        var hasher = SHA256()
        for file in files {
            let relative = String(file.standardizedFileURL.path.dropFirst(rootPath.count))
            hasher.update(data: Data(relative.utf8))
            hasher.update(data: try Data(contentsOf: file, options: [.mappedIfSafe]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func bundleInfo(at url: URL) throws -> [String: Any] {
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        let data = try Data(contentsOf: infoURL)
        guard let info = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any] else {
            throw ScreenSaverModuleError.invalidSaverBundle
        }
        return info
    }

    private func restoreBackupIfPresent(_ backup: URL, destination: URL) throws {
        guard fileManager.fileExists(atPath: backup.path) else { return }
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: backup, to: destination)
    }

    private static func hasValidSignature(at url: URL) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else { return false }
        return SecStaticCodeCheckValidity(staticCode, [], nil) == errSecSuccess
    }
}

private struct SaverBundleDetails {
    let url: URL
    let version: String
    let build: String
    let fingerprint: String
}

private enum ScreenSaverModuleError: LocalizedError {
    case missingEmbeddedSaver
    case invalidSaverBundle
    case invalidSaverSignature
    case stagedBundleMismatch
    case installedBundleMismatch
    case rollbackFailed

    var errorDescription: String? {
        switch self {
        case .missingEmbeddedSaver:
            "This app build does not include My Wallpaper.saver."
        case .invalidSaverBundle:
            "The My Wallpaper screen saver bundle is invalid."
        case .invalidSaverSignature:
            "The My Wallpaper screen saver signature could not be verified."
        case .stagedBundleMismatch:
            "The staged screen saver did not match this app."
        case .installedBundleMismatch:
            "The installed screen saver did not match this app after installation."
        case .rollbackFailed:
            "The previous screen saver could not be restored after an installation failure."
        }
    }
}
