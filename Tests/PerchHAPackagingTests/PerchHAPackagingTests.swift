#if canImport(XCTest)
import Foundation
import XCTest
import PerchHAPackaging

final class PerchHAPackagingTests: XCTestCase {
    func testInfoPlistDeclaresCallbackURLSchemeAndMenuBarAgent() throws {
        let manifest = try PerchHAAppBundleManifest(callbackURLScheme: "perchha-test")

        let plist = try propertyList(from: manifest.propertyListData())

        XCTAssertEqual(plist["CFBundleName"] as? String, "PerchHA")
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "PerchHA")
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "dev.perchha.app")
        XCTAssertEqual(plist["CFBundlePackageType"] as? String, "APPL")
        XCTAssertEqual(plist["LSMinimumSystemVersion"] as? String, "13.0")
        XCTAssertEqual(plist["LSUIElement"] as? Bool, true)
        let urlTypes = try XCTUnwrap(plist["CFBundleURLTypes"] as? [[String: Any]])
        XCTAssertEqual(urlTypes.count, 1)
        XCTAssertEqual(urlTypes.first?["CFBundleTypeRole"] as? String, "Viewer")
        XCTAssertEqual(urlTypes.first?["CFBundleURLName"] as? String, "dev.perchha.app.oauth")
        XCTAssertEqual(urlTypes.first?["CFBundleURLSchemes"] as? [String], ["perchha-test"])
    }

    func testAppBundleBuilderCreatesBundleWithExecutableInfoPlistAndPkgInfo() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executableURL = directory.appendingPathComponent("PerchHA-source", isDirectory: false)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        let outputURL = directory.appendingPathComponent("PerchHA.app", isDirectory: true)

        let result = try PerchHAAppBundleBuilder().build(
            PerchHAAppBundleBuildConfiguration(
                executableURL: executableURL,
                outputURL: outputURL,
                manifest: try PerchHAAppBundleManifest(callbackURLScheme: "perchha")
            )
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.appURL.path))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: result.executableURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.infoPlistURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.appendingPathComponent("Contents/PkgInfo").path))
        let plist = try propertyList(from: Data(contentsOf: result.infoPlistURL))
        let urlTypes = try XCTUnwrap(plist["CFBundleURLTypes"] as? [[String: Any]])
        XCTAssertEqual(urlTypes.first?["CFBundleURLSchemes"] as? [String], ["perchha"])
    }

    func testAppBundleBuilderRefusesToOverwriteWithoutReplace() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executableURL = directory.appendingPathComponent("PerchHA-source", isDirectory: false)
        try Data().write(to: executableURL)
        let outputURL = directory.appendingPathComponent("PerchHA.app", isDirectory: true)
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

        XCTAssertThrowsError(
            try PerchHAAppBundleBuilder().build(
                PerchHAAppBundleBuildConfiguration(
                    executableURL: executableURL,
                    outputURL: outputURL,
                    manifest: try PerchHAAppBundleManifest()
                )
            )
        ) { error in
            XCTAssertEqual(error as? PerchHAAppBundleBuildError, .outputExists(outputURL.path))
        }
    }

    func testManifestRejectsInvalidCallbackURLScheme() {
        XCTAssertThrowsError(try PerchHAAppBundleManifest(callbackURLScheme: "1perchha")) { error in
            XCTAssertEqual(error as? PerchHAAppBundleManifestError, .invalidCallbackURLScheme("1perchha"))
        }
    }

    func testLaunchServicesVerifierRegistersBundleAndClaimsCallbackScheme() throws {
        let uniqueID = UUID().uuidString.lowercased()
        let executableURL = URL(fileURLWithPath: "/usr/bin/true", isDirectory: false)
        let outputURL = launchServicesAppURL(uniqueID: uniqueID)
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }
        let scheme = "perchha-test-\(uniqueID)"
        let bundleID = "dev.perchha.tests.\(uniqueID.replacingOccurrences(of: "-", with: ""))"
        let bundle = try PerchHAAppBundleBuilder().build(
            PerchHAAppBundleBuildConfiguration(
                executableURL: executableURL,
                outputURL: outputURL,
                manifest: try PerchHAAppBundleManifest(
                    bundleIdentifier: bundleID,
                    callbackURLScheme: scheme
                )
            )
        )
        defer {
            unregisterBundle(at: bundle.appURL)
        }

        let result = try PerchHALaunchServicesVerifier().verify(
            PerchHALaunchServicesVerificationConfiguration(
                appURL: bundle.appURL,
                callbackURLScheme: scheme
            )
        )

        XCTAssertEqual(result.appURL.path, bundle.appURL.standardizedFileURL.resolvingSymlinksInPath().path)
        XCTAssertEqual(result.callbackURL.absoluteString, "\(scheme)://auth")
        XCTAssertEqual(result.registeredApplicationURL.path, result.appURL.path)
        XCTAssertEqual(result.callbackRole, "Viewer")
    }

    func testLaunchServicesVerifierRejectsBundleWithoutCallbackScheme() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executableURL = directory.appendingPathComponent("PerchHA-source", isDirectory: false)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        let outputURL = directory.appendingPathComponent("PerchHA.app", isDirectory: true)
        let bundle = try PerchHAAppBundleBuilder().build(
            PerchHAAppBundleBuildConfiguration(
                executableURL: executableURL,
                outputURL: outputURL,
                manifest: try PerchHAAppBundleManifest(callbackURLScheme: "perchha-present")
            )
        )

        XCTAssertThrowsError(
            try PerchHALaunchServicesVerifier().verify(
                PerchHALaunchServicesVerificationConfiguration(
                    appURL: bundle.appURL,
                    callbackURLScheme: "perchha-missing",
                    registerBundle: false
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? PerchHALaunchServicesVerificationError,
                .callbackSchemeMissing("perchha-missing")
            )
        }
    }

    func testLaunchServicesVerifierRejectsBundleWithoutCallbackRole() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executableURL = directory.appendingPathComponent("PerchHA-source", isDirectory: false)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        let outputURL = directory.appendingPathComponent("PerchHA.app", isDirectory: true)
        let bundle = try PerchHAAppBundleBuilder().build(
            PerchHAAppBundleBuildConfiguration(
                executableURL: executableURL,
                outputURL: outputURL,
                manifest: try PerchHAAppBundleManifest(callbackURLScheme: "perchha-present")
            )
        )
        var plist = try propertyList(from: Data(contentsOf: bundle.infoPlistURL))
        var urlTypes = try XCTUnwrap(plist["CFBundleURLTypes"] as? [[String: Any]])
        urlTypes[0].removeValue(forKey: "CFBundleTypeRole")
        plist["CFBundleURLTypes"] = urlTypes
        let rewritten = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try rewritten.write(to: bundle.infoPlistURL, options: .atomic)

        XCTAssertThrowsError(
            try PerchHALaunchServicesVerifier().verify(
                PerchHALaunchServicesVerificationConfiguration(
                    appURL: bundle.appURL,
                    callbackURLScheme: "perchha-present",
                    registerBundle: false
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? PerchHALaunchServicesVerificationError,
                .callbackRoleMissing("Viewer")
            )
        }
    }

    func testLaunchServicesVerifierRejectsDumpWhenClaimBindingHasWrongRole() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let bundle = try testBundle(
            in: directory,
            callbackScheme: "perchha-dump-role",
            bundleIdentifier: "dev.perchha.tests.dump.role"
        )
        let toolURL = try fakeLaunchServicesTool(
            in: directory,
            output: launchServicesDump(
                appPath: bundle.appURL.standardizedFileURL.resolvingSymlinksInPath().path,
                scheme: "perchha-dump-role",
                claimRole: "Editor"
            )
        )

        XCTAssertThrowsError(
            try PerchHALaunchServicesVerifier(toolURL: toolURL).verify(
                PerchHALaunchServicesVerificationConfiguration(
                    appURL: bundle.appURL,
                    callbackURLScheme: "perchha-dump-role"
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? PerchHALaunchServicesVerificationError,
                .launchServicesRoleMissing("Viewer")
            )
        }
    }

    func testLaunchServicesVerifierRejectsDumpWhenSchemeBindingIsMissing() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let bundle = try testBundle(
            in: directory,
            callbackScheme: "perchha-dump-scheme",
            bundleIdentifier: "dev.perchha.tests.dump.scheme"
        )
        let toolURL = try fakeLaunchServicesTool(
            in: directory,
            output: launchServicesDump(
                appPath: bundle.appURL.standardizedFileURL.resolvingSymlinksInPath().path,
                scheme: "other-scheme",
                claimRole: "Viewer"
            )
        )

        XCTAssertThrowsError(
            try PerchHALaunchServicesVerifier(toolURL: toolURL).verify(
                PerchHALaunchServicesVerificationConfiguration(
                    appURL: bundle.appURL,
                    callbackURLScheme: "perchha-dump-scheme"
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? PerchHALaunchServicesVerificationError,
                .launchServicesSchemeMissing("perchha-dump-scheme")
            )
        }
    }

    private func propertyList(from data: Data) throws -> [String: Any] {
        let value = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try XCTUnwrap(value as? [String: Any])
    }

    private func testBundle(
        in directory: URL,
        callbackScheme: String,
        bundleIdentifier: String
    ) throws -> PerchHAAppBundleBuildResult {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executableURL = directory.appendingPathComponent("PerchHA-source", isDirectory: false)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        return try PerchHAAppBundleBuilder().build(
            PerchHAAppBundleBuildConfiguration(
                executableURL: executableURL,
                outputURL: directory.appendingPathComponent("PerchHA.app", isDirectory: true),
                manifest: try PerchHAAppBundleManifest(
                    bundleIdentifier: bundleIdentifier,
                    callbackURLScheme: callbackScheme
                )
            )
        )
    }

    private func fakeLaunchServicesTool(in directory: URL, output: String) throws -> URL {
        let toolURL = directory.appendingPathComponent("fake-lsregister", isDirectory: false)
        let escapedOutput = output.replacingOccurrences(of: "'", with: "'\\''")
        try """
        #!/bin/sh
        if [ "$1" = "-f" ]; then
            exit 0
        fi
        printf '%s' '\(escapedOutput)'
        """.write(to: toolURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: toolURL.path)
        return toolURL
    }

    private func launchServicesDump(appPath: String, scheme: String, claimRole: String) -> String {
        """
        ---------------------------------------------------------------------------------
        bundle id:                  PerchHA (0x1)
        path:                       \(appPath) (0x2)
        identifier:                 dev.perchha.tests
        claimed schemes:            \(scheme):
        ---------------------------------------------------------------------------------
        claim id:                   unrelated (0x3)
        roles:                      Viewer (0000000000000002)
        bindings:                   unrelated:
        ---------------------------------------------------------------------------------
        claim id:                   dev.perchha.tests.oauth (0x4)
        flags:                      url-type (0000000000000040)
        roles:                      \(claimRole) (0000000000000004)
        bindings:                   \(scheme):
        ---------------------------------------------------------------------------------
        """
    }

    private func temporaryDirectory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perchha-packaging-test-\(UUID().uuidString)", isDirectory: true)
    }

    private func launchServicesAppURL(uniqueID: String) -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/perchha-packaging-test-\(uniqueID).app", isDirectory: true)
    }

    private func unregisterBundle(at url: URL) {
        let lsregisterURL = URL(fileURLWithPath: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister")
        guard FileManager.default.isExecutableFile(atPath: lsregisterURL.path) else {
            return
        }
        let process = Process()
        process.executableURL = lsregisterURL
        process.arguments = ["-u", url.path]
        try? process.run()
        process.waitUntilExit()
    }
}
#endif
