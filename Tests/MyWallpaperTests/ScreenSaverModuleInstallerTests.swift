import Foundation
import XCTest
@testable import MyWallpaper

final class ScreenSaverModuleInstallerTests: XCTestCase {
    private let fileManager = FileManager.default
    private var temporaryDirectory: URL!
    private var embeddedURL: URL!
    private var installedURL: URL!

    override func setUpWithError() throws {
        temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("MyWallpaperInstallerTests-\(UUID().uuidString)")
        embeddedURL = temporaryDirectory.appendingPathComponent("Embedded.saver")
        installedURL = temporaryDirectory.appendingPathComponent("Installed.saver")
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if temporaryDirectory != nil {
            try? fileManager.removeItem(at: temporaryDirectory)
        }
    }

    func testMissingInstalledBundleIsNotInstalled() throws {
        try makeSaver(at: embeddedURL, marker: "current")

        switch makeInstaller().installationState() {
        case .notInstalled:
            break
        default:
            XCTFail("Expected a missing installed bundle to report not installed")
        }
    }

    func testInvalidInstalledBundleRequiresUpdate() throws {
        try makeSaver(at: embeddedURL, marker: "current")
        try makeSaver(at: installedURL, bundleIdentifier: "example.invalid", marker: "current")

        switch makeInstaller().installationState() {
        case .updateRequired:
            break
        default:
            XCTFail("Expected an invalid installed bundle to require an update")
        }
    }

    func testDifferentFunctionalContentRequiresUpdate() throws {
        try makeSaver(at: embeddedURL, marker: "new")
        try makeSaver(at: installedURL, marker: "old")

        switch makeInstaller().installationState() {
        case .updateRequired:
            break
        default:
            XCTFail("Expected differing bundle content to require an update")
        }
    }

    func testMatchingBundleIsCurrent() throws {
        try makeSaver(at: embeddedURL, marker: "same")
        try fileManager.copyItem(at: embeddedURL, to: installedURL)

        switch makeInstaller().installationState() {
        case let .current(url):
            XCTAssertEqual(url.standardizedFileURL, installedURL.standardizedFileURL)
        default:
            XCTFail("Expected matching bundles to report current")
        }
    }

    func testFailedPostReplacementValidationRestoresPreviousBundle() throws {
        try makeSaver(at: embeddedURL, marker: "new")
        try makeSaver(at: installedURL, marker: "old")
        var validationCount = 0
        let installer = makeInstaller { _ in
            validationCount += 1
            return validationCount < 3
        }

        XCTAssertThrowsError(try installer.installOrUpdate())

        XCTAssertEqual(try marker(at: installedURL), "old")
    }

    private func makeInstaller(
        signatureValidator: @escaping (URL) -> Bool = { _ in true }
    ) -> ScreenSaverModuleInstaller {
        ScreenSaverModuleInstaller(
            fileManager: fileManager,
            embeddedSaverURL: embeddedURL,
            installedSaverURL: installedURL,
            signatureValidator: signatureValidator
        )
    }

    private func makeSaver(
        at url: URL,
        bundleIdentifier: String = ScreenSaverModuleInstaller.bundleIdentifier,
        marker: String
    ) throws {
        let executableDirectory = url.appendingPathComponent("Contents/MacOS")
        try fileManager.createDirectory(at: executableDirectory, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleExecutable": "TestSaver",
            "CFBundleShortVersionString": "0.3.0",
            "CFBundleVersion": "4"
        ]
        let infoData = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try infoData.write(to: url.appendingPathComponent("Contents/Info.plist"))
        let executable = executableDirectory.appendingPathComponent("TestSaver")
        try Data(marker.utf8).write(to: executable)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }

    private func marker(at url: URL) throws -> String {
        let data = try Data(contentsOf: url.appendingPathComponent("Contents/MacOS/TestSaver"))
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }
}
