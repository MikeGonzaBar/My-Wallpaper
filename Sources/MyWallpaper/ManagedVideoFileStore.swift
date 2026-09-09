import Foundation

struct ManagedVideoFileStore: Sendable {
    private let rootDirectory: URL?

    init(rootDirectory: URL? = nil) {
        self.rootDirectory = rootDirectory
    }

    func managedVideosDirectory() throws -> URL {
        let directory = try applicationSupportDirectory()
            .appendingPathComponent("Videos", isDirectory: true)
        try ensurePrivateDirectory(directory)
        return directory
    }

    func optimizedVideosDirectory() throws -> URL {
        let directory = try applicationSupportDirectory()
            .appendingPathComponent("Optimized Videos", isDirectory: true)
        try ensurePrivateDirectory(directory)
        return directory
    }

    func removeOrphanedOptimizedFiles(retaining paths: Set<String>) {
        guard let directory = try? optimizedVideosDirectory(),
              let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
              ) else { return }
        let retainedPaths = Set(paths.map {
            URL(fileURLWithPath: $0).standardizedFileURL.resolvingSymlinksInPath().path
        })
        for file in files where !retainedPaths.contains(file.resolvingSymlinksInPath().path) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    func removeOptimizedFileIfOwned(atPath path: String) {
        guard let directory = try? optimizedVideosDirectory() else { return }
        let file = URL(fileURLWithPath: path).standardizedFileURL
        guard file.deletingLastPathComponent() == directory.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: file)
    }

    func deleteManagedFiles(for video: ManagedVideo) throws {
        if let optimizedPath = video.optimizedPath {
            try removeFileIfPresent(
                at: URL(fileURLWithPath: optimizedPath),
                ownedBy: try optimizedVideosDirectory()
            )
        }
        try removeFileIfPresent(at: video.url, ownedBy: try managedVideosDirectory())
    }

    func removeFileIfPresent(at url: URL, ownedBy directory: URL) throws {
        let file = url.standardizedFileURL
        let standardizedDirectory = directory.standardizedFileURL
        guard file.deletingLastPathComponent() == standardizedDirectory else {
            throw CocoaError(.fileWriteNoPermission)
        }
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }

    func applicationSupportDirectory() throws -> URL {
        if let rootDirectory {
            try ensurePrivateDirectory(rootDirectory)
            return rootDirectory
        }
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appendingPathComponent("My Wallpaper", isDirectory: true)
        try ensurePrivateDirectory(directory)
        return directory
    }

    func ensurePrivateFilePermissions(at url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    private func ensurePrivateDirectory(_ directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
    }
}
