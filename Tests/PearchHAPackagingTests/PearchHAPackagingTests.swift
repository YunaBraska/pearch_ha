#if canImport(XCTest)
import CryptoKit
import Foundation
import XCTest
import PearchHAPackaging

final class PearchHAPackagingTests: XCTestCase {
    func testInfoPlistDeclaresCallbackURLSchemeAndMenuBarAgent() throws {
        let manifest = try PearchHAAppBundleManifest(
            callbackURLScheme: "pearchha-test",
            iconFileName: "PearchHA"
        )

        let plist = try propertyList(from: manifest.propertyListData())

        XCTAssertEqual(plist["CFBundleName"] as? String, "PearchHA")
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "PearchHA")
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "dev.pearchha.app")
        XCTAssertEqual(plist["CFBundlePackageType"] as? String, "APPL")
        XCTAssertEqual(plist["CFBundleIconFile"] as? String, "PearchHA")
        XCTAssertEqual(plist["LSMinimumSystemVersion"] as? String, "13.0")
        XCTAssertEqual(plist["LSUIElement"] as? Bool, true)
        let urlTypes = try XCTUnwrap(plist["CFBundleURLTypes"] as? [[String: Any]])
        XCTAssertEqual(urlTypes.count, 1)
        XCTAssertEqual(urlTypes.first?["CFBundleTypeRole"] as? String, "Viewer")
        XCTAssertEqual(urlTypes.first?["CFBundleURLName"] as? String, "dev.pearchha.app.oauth")
        XCTAssertEqual(urlTypes.first?["CFBundleURLSchemes"] as? [String], ["pearchha-test"])
    }

    func testAppBundleBuilderCreatesBundleWithExecutableInfoPlistAndPkgInfo() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executableURL = directory.appendingPathComponent("PearchHA-source", isDirectory: false)
        let iconURL = directory.appendingPathComponent("PearchHA.icns", isDirectory: false)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executableURL)
        try Data("icon".utf8).write(to: iconURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        let outputURL = directory.appendingPathComponent("PearchHA.app", isDirectory: true)

        let result = try PearchHAAppBundleBuilder().build(
            PearchHAAppBundleBuildConfiguration(
                executableURL: executableURL,
                outputURL: outputURL,
                manifest: try PearchHAAppBundleManifest(
                    callbackURLScheme: "pearchha",
                    iconFileName: "PearchHA"
                ),
                iconURL: iconURL
            )
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.appURL.path))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: result.executableURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.infoPlistURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.appendingPathComponent("Contents/Resources/PearchHA.icns").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.appendingPathComponent("Contents/PkgInfo").path))
        let plist = try propertyList(from: Data(contentsOf: result.infoPlistURL))
        XCTAssertEqual(plist["CFBundleIconFile"] as? String, "PearchHA")
        let urlTypes = try XCTUnwrap(plist["CFBundleURLTypes"] as? [[String: Any]])
        XCTAssertEqual(urlTypes.first?["CFBundleURLSchemes"] as? [String], ["pearchha"])
    }

    func testAppBundleBuilderRejectsMissingConfiguredIcon() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executableURL = directory.appendingPathComponent("PearchHA-source", isDirectory: false)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        let outputURL = directory.appendingPathComponent("PearchHA.app", isDirectory: true)
        let missingIconURL = directory.appendingPathComponent("Missing.icns", isDirectory: false)

        XCTAssertThrowsError(
            try PearchHAAppBundleBuilder().build(
                PearchHAAppBundleBuildConfiguration(
                    executableURL: executableURL,
                    outputURL: outputURL,
                    manifest: try PearchHAAppBundleManifest(
                        callbackURLScheme: "pearchha",
                        iconFileName: "Missing"
                    ),
                    iconURL: missingIconURL
                )
            )
        ) { error in
            XCTAssertEqual(error as? PearchHAAppBundleBuildError, .iconMissing(missingIconURL.path))
        }
    }

    func testAppBundleBuilderRefusesToOverwriteWithoutReplace() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executableURL = directory.appendingPathComponent("PearchHA-source", isDirectory: false)
        try Data().write(to: executableURL)
        let outputURL = directory.appendingPathComponent("PearchHA.app", isDirectory: true)
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

        XCTAssertThrowsError(
            try PearchHAAppBundleBuilder().build(
                PearchHAAppBundleBuildConfiguration(
                    executableURL: executableURL,
                    outputURL: outputURL,
                    manifest: try PearchHAAppBundleManifest()
                )
            )
        ) { error in
            XCTAssertEqual(error as? PearchHAAppBundleBuildError, .outputExists(outputURL.path))
        }
    }

    func testManifestRejectsInvalidCallbackURLScheme() {
        XCTAssertThrowsError(try PearchHAAppBundleManifest(callbackURLScheme: "1pearchha")) { error in
            XCTAssertEqual(error as? PearchHAAppBundleManifestError, .invalidCallbackURLScheme("1pearchha"))
        }
    }

    func testOAuthClientWebsiteManifestRendersCanonicalLinkAndRedirectDeclaration() throws {
        let manifest = try PearchHAOAuthClientWebsiteManifest(
            clientID: "https://pearchha.dev/app",
            redirectURI: "pearchha://auth"
        )

        let html = manifest.html

        XCTAssertTrue(html.contains(#"<link rel="canonical" href="https://pearchha.dev/app">"#))
        XCTAssertTrue(html.contains(#"<link rel="redirect_uri" href="pearchha://auth">"#))
        XCTAssertTrue(html.contains("PearchHA OAuth Redirect"))
    }

    func testOAuthClientWebsiteBuilderCreatesArtifactAndVerifierAcceptsIt() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let outputURL = directory.appendingPathComponent("oauth-site/index.html", isDirectory: false)
        let manifest = try PearchHAOAuthClientWebsiteManifest(
            clientID: "https://pearchha.dev/app",
            redirectURI: "pearchha://auth"
        )

        let build = try PearchHAOAuthClientWebsiteBuilder().build(
            PearchHAOAuthClientWebsiteBuildConfiguration(
                outputURL: outputURL,
                manifest: manifest
            )
        )
        let verification = try PearchHAOAuthClientWebsiteVerifier().verify(
            PearchHAOAuthClientWebsiteVerificationConfiguration(
                siteURL: outputURL,
                manifest: manifest
            )
        )

        XCTAssertEqual(build.siteURL.path, outputURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertEqual(verification.clientID, "https://pearchha.dev/app")
        XCTAssertEqual(verification.redirectURI, "pearchha://auth")
    }

    func testOAuthClientWebsiteVerifierAcceptsPublishedHTMLData() throws {
        let manifest = try PearchHAOAuthClientWebsiteManifest(
            clientID: "https://pearchha.dev/app",
            redirectURI: "pearchha://auth"
        )

        let verification = try PearchHAOAuthClientWebsiteVerifier().verify(
            data: manifest.htmlData(),
            siteURL: URL(string: "https://pearchha.dev/app")!,
            manifest: manifest
        )

        XCTAssertEqual(verification.siteURL.absoluteString, "https://pearchha.dev/app")
        XCTAssertEqual(verification.clientID, "https://pearchha.dev/app")
        XCTAssertEqual(verification.redirectURI, "pearchha://auth")
    }

    func testOAuthClientWebsiteVerifierRejectsMissingRedirectDeclarationInFirstTenKB() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let outputURL = directory.appendingPathComponent("index.html", isDirectory: false)
        let manifest = try PearchHAOAuthClientWebsiteManifest(
            clientID: "https://pearchha.dev/app",
            redirectURI: "pearchha://auth"
        )
        try """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <link rel="canonical" href="https://pearchha.dev/app">
        </head>
        <body>missing redirect declaration</body>
        </html>
        """.write(to: outputURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try PearchHAOAuthClientWebsiteVerifier().verify(
                PearchHAOAuthClientWebsiteVerificationConfiguration(
                    siteURL: outputURL,
                    manifest: manifest
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? PearchHAOAuthClientWebsiteError,
                .redirectDeclarationMissing("pearchha://auth")
            )
        }
    }

    func testThinXcodeWrapperDeclaresMenuBarCallbackAndPackageLibraryProduct() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let infoPlistURL = rootURL.appendingPathComponent("Xcode/PearchHA/Info.plist", isDirectory: false)
        let projectURL = rootURL.appendingPathComponent("PearchHA.xcodeproj/project.pbxproj", isDirectory: false)
        let schemeURL = rootURL.appendingPathComponent(
            "PearchHA.xcodeproj/xcshareddata/xcschemes/PearchHA.xcscheme",
            isDirectory: false
        )
        let entrypointURL = rootURL.appendingPathComponent("Xcode/PearchHA/main.swift", isDirectory: false)
        let swiftPMEntrypointURL = rootURL.appendingPathComponent("Sources/PearchHAApp/main.swift", isDirectory: false)

        let plist = try propertyList(from: Data(contentsOf: infoPlistURL))
        XCTAssertEqual(plist["CFBundleName"] as? String, "PearchHA")
        XCTAssertEqual(plist["CFBundlePackageType"] as? String, "APPL")
        XCTAssertEqual(plist["LSMinimumSystemVersion"] as? String, "13.0")
        XCTAssertEqual(plist["LSUIElement"] as? Bool, true)
        XCTAssertEqual(plist["NSPrincipalClass"] as? String, "NSApplication")
        let urlTypes = try XCTUnwrap(plist["CFBundleURLTypes"] as? [[String: Any]])
        XCTAssertEqual(urlTypes.first?["CFBundleTypeRole"] as? String, "Viewer")
        XCTAssertEqual(urlTypes.first?["CFBundleURLSchemes"] as? [String], ["pearchha"])

        let project = try String(contentsOf: projectURL, encoding: .utf8)
        XCTAssertTrue(project.contains("productType = \"com.apple.product-type.application\";"))
        XCTAssertTrue(project.contains("INFOPLIST_FILE = Xcode/PearchHA/Info.plist;"))
        XCTAssertTrue(project.contains("XCLocalSwiftPackageReference"))
        XCTAssertTrue(project.contains("productName = PearchHAAppShell;"))

        let scheme = try String(contentsOf: schemeURL, encoding: .utf8)
        XCTAssertTrue(scheme.contains("BlueprintName = \"PearchHA\""))
        XCTAssertTrue(scheme.contains("BuildableName = \"PearchHA.app\""))
        XCTAssertTrue(scheme.contains("buildForTesting = \"YES\""))
        XCTAssertTrue(scheme.contains("<TestAction"))

        let entrypoint = try String(contentsOf: entrypointURL, encoding: .utf8)
        XCTAssertTrue(entrypoint.contains("import PearchHAAppShell"))
        XCTAssertTrue(entrypoint.contains("PearchHAApplication.main()"))
        XCTAssertEqual(entrypoint, try String(contentsOf: swiftPMEntrypointURL, encoding: .utf8))
    }

    func testCIWorkflowUsesTheSharedBuildContract() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let workflowURL = rootURL.appendingPathComponent(".github/workflows/build-pr.yml", isDirectory: false)
        let workflow = try String(contentsOf: workflowURL, encoding: .utf8)

        XCTAssertTrue(workflow.contains("pull_request:"))
        XCTAssertTrue(workflow.contains("wc_swift_build_common.yml@"))
        XCTAssertTrue(workflow.contains("ref: ${{ github.event.pull_request.head.sha }}"))
        XCTAssertTrue(workflow.contains("secrets: inherit"))
    }

    func testCheckScriptEnforcesTestsCoverageSmokeAndAudit() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let scriptURL = rootURL.appendingPathComponent("scripts/check.sh", isDirectory: false)
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        XCTAssertTrue(script.contains("set -eu"))
        XCTAssertTrue(script.contains("swift build -Xswiftc -warnings-as-errors"))
        XCTAssertTrue(
            script.contains(
                "swift test --disable-swift-testing --enable-xctest -Xswiftc -warnings-as-errors --enable-code-coverage"
            )
        )
        XCTAssertTrue(script.contains("swift run pearchha-coverage-check"))
        XCTAssertTrue(script.contains("--line-target PearchHACore=95"))
        XCTAssertTrue(script.contains("--branch-target PearchHACore=90"))
        XCTAssertTrue(script.contains("PEARCHHA_SMOKE_SNAPSHOT_DIR=.build/pearchha-snapshots swift run pearchha-smoke"))
        XCTAssertTrue(script.contains("swift run pearchha-repo-audit"))
    }

    func testXcodePreflightReportsBlockedWhenOnlyCommandLineToolsAreSelected() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let project = try testXcodeProject(in: directory, schemeName: "PearchHA")
        let applicationsDirectory = directory.appendingPathComponent("Applications", isDirectory: true)
        _ = try makeDiscoveredXcodeDeveloperDirectory(
            in: applicationsDirectory,
            appName: "Xcode 26.0.app"
        )
        let xcodeSelectURL = try fakeExecutable(in: directory, name: "xcode-select")
        let xcrunURL = try fakeExecutable(in: directory, name: "xcrun")
        let runner = RecordingCommandRunner { executableURL, arguments in
            if executableURL == xcodeSelectURL {
                XCTAssertEqual(arguments, ["-p"])
                return PearchHACommandResult(
                    status: 0,
                    output: "/Library/Developer/CommandLineTools"
                )
            }
            if executableURL == xcrunURL {
                if arguments == ["--find", "xctest"] {
                    return PearchHACommandResult(status: 72, output: "unable to find utility")
                }
                if arguments == ["--find", "xcodebuild"] {
                    return PearchHACommandResult(status: 72, output: "unable to find utility")
                }
            }
            XCTFail("unexpected command: \(executableURL.path) \(arguments)")
            return PearchHACommandResult(status: 1, output: "unexpected command")
        }

        let configuration = PearchHAXcodePreflightConfiguration(
            projectURL: project,
            schemeName: "PearchHA"
        )
        let report = try PearchHAXcodePreflightChecker(
            fileManager: .default,
            xcodeSelectURL: xcodeSelectURL,
            xcrunURL: xcrunURL,
            applicationSearchRoots: [applicationsDirectory],
            environment: [:],
            commandRunner: runner
        ).check(configuration)

        let discoveredAppURL = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(
                at: applicationsDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ).first { $0.lastPathComponent == "Xcode 26.0.app" }
        )
        let discoveredDeveloperDirectoryPath = discoveredAppURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Developer", isDirectory: true)
            .path
        XCTAssertTrue(report.projectAvailable)
        XCTAssertTrue(report.sharedSchemeAvailable)
        XCTAssertFalse(report.projectListingAvailable)
        XCTAssertEqual(report.activeDeveloperDirectory, "/Library/Developer/CommandLineTools")
        XCTAssertEqual(report.discoveredXcodeDeveloperDirectories, [discoveredDeveloperDirectoryPath])
        XCTAssertFalse(report.fullXcodeSelected)
        XCTAssertFalse(report.xctestAvailable)
        XCTAssertFalse(report.xcodebuildAvailable)
        XCTAssertFalse(report.isReadyForNativeVerification)
        XCTAssertEqual(
            report.issues,
            [
                .commandLineToolsSelected("/Library/Developer/CommandLineTools"),
                .xctestUnavailable(status: 72),
                .xcodebuildUnavailable(status: 72)
            ]
        )

        let diagnostic = report.diagnostic(configuration: configuration)
        XCTAssertEqual(diagnostic.project, .present)
        XCTAssertEqual(diagnostic.sharedScheme, .present)
        XCTAssertEqual(diagnostic.projectListing, .blocked)
        XCTAssertEqual(diagnostic.discoveredXcodeDeveloperDirectories, [discoveredDeveloperDirectoryPath])
        XCTAssertEqual(diagnostic.fullXcode, .blocked)
        XCTAssertEqual(diagnostic.nativeVerification, .blocked)
        XCTAssertTrue(
            diagnostic.suggestedCommands.contains(
                "sudo xcode-select -s '\(discoveredDeveloperDirectoryPath)'"
            )
        )
        XCTAssertTrue(
            diagnostic.suggestedCommands.contains(
                "DEVELOPER_DIR='\(discoveredDeveloperDirectoryPath)' swift run pearchha-xcode-doctor --json --strict --project \(project.path) --scheme PearchHA"
            )
        )
    }

    func testXcodePreflightHonorsDeveloperDirectoryEnvironmentOverride() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let project = try testXcodeProject(in: directory, schemeName: "PearchHA")
        let xcrunURL = try fakeExecutable(in: directory, name: "xcrun")
        let runner = RecordingCommandRunner { executableURL, arguments in
            XCTAssertEqual(executableURL, xcrunURL)
            if arguments == ["--find", "xctest"] {
                return PearchHACommandResult(
                    status: 0,
                    output: "/Applications/Xcode.app/Contents/Developer/usr/bin/xctest"
                )
            }
            if arguments == ["--find", "xcodebuild"] {
                return PearchHACommandResult(
                    status: 0,
                    output: "/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild"
                )
            }
            if arguments == ["xcodebuild", "-list", "-project", project.path] {
                return PearchHACommandResult(
                    status: 0,
                    output: """
                    Information about project "PearchHA":
                        Schemes:
                            PearchHA
                    """
                )
            }
            XCTFail("unexpected command: \(executableURL.path) \(arguments)")
            return PearchHACommandResult(status: 1, output: "unexpected command")
        }

        let configuration = PearchHAXcodePreflightConfiguration(
            projectURL: project,
            schemeName: "PearchHA"
        )
        let report = try PearchHAXcodePreflightChecker(
            fileManager: .default,
            xcodeSelectURL: directory.appendingPathComponent("missing-xcode-select", isDirectory: false),
            xcrunURL: xcrunURL,
            environment: [
                PearchHAXcodePreflightChecker.developerDirectoryEnvironmentKey: "/Applications/Xcode.app/Contents/Developer"
            ],
            commandRunner: runner
        ).check(configuration)

        XCTAssertEqual(report.activeDeveloperDirectory, "/Applications/Xcode.app/Contents/Developer")
        XCTAssertTrue(report.fullXcodeSelected)
        XCTAssertTrue(report.projectListingAvailable)
        XCTAssertTrue(report.xctestAvailable)
        XCTAssertTrue(report.xcodebuildAvailable)
        XCTAssertTrue(report.issues.isEmpty)
        XCTAssertTrue(report.isReadyForNativeVerification)

        let diagnostic = report.diagnostic(configuration: configuration)
        XCTAssertTrue(
            diagnostic.suggestedCommands.contains(
                "DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --disable-swift-testing --enable-xctest list"
            )
        )
        XCTAssertFalse(
            diagnostic.suggestedCommands.contains("sudo xcode-select -s /Applications/Xcode.app/Contents/Developer")
        )
    }

    func testXcodePreflightReportsReadyWhenFullXcodeAndSharedSchemeAreAvailable() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let project = try testXcodeProject(in: directory, schemeName: "PearchHA")
        let xcodeSelectURL = try fakeExecutable(in: directory, name: "xcode-select")
        let xcrunURL = try fakeExecutable(in: directory, name: "xcrun")
        let runner = RecordingCommandRunner { executableURL, arguments in
            if executableURL == xcodeSelectURL {
                XCTAssertEqual(arguments, ["-p"])
                return PearchHACommandResult(
                    status: 0,
                    output: "/Applications/Xcode.app/Contents/Developer"
                )
            }
            if executableURL == xcrunURL {
                if arguments == ["--find", "xctest"] {
                    return PearchHACommandResult(status: 0, output: "/Applications/Xcode.app/Contents/Developer/usr/bin/xctest")
                }
                if arguments == ["--find", "xcodebuild"] {
                    return PearchHACommandResult(status: 0, output: "/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild")
                }
                if arguments == ["xcodebuild", "-list", "-project", project.path] {
                    return PearchHACommandResult(
                        status: 0,
                        output: """
                        Information about project "PearchHA":
                            Schemes:
                                PearchHA
                        """
                    )
                }
            }
            XCTFail("unexpected command: \(executableURL.path) \(arguments)")
            return PearchHACommandResult(status: 1, output: "unexpected command")
        }

        let configuration = PearchHAXcodePreflightConfiguration(
            projectURL: project,
            schemeName: "PearchHA"
        )
        let emptyApplicationsDirectory = directory.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyApplicationsDirectory, withIntermediateDirectories: true)
        let report = try PearchHAXcodePreflightChecker(
            fileManager: .default,
            xcodeSelectURL: xcodeSelectURL,
            xcrunURL: xcrunURL,
            applicationSearchRoots: [emptyApplicationsDirectory],
            environment: [:],
            commandRunner: runner
        ).check(configuration)

        XCTAssertTrue(report.projectAvailable)
        XCTAssertTrue(report.sharedSchemeAvailable)
        XCTAssertTrue(report.projectListingAvailable)
        XCTAssertEqual(report.activeDeveloperDirectory, "/Applications/Xcode.app/Contents/Developer")
        XCTAssertTrue(report.discoveredXcodeDeveloperDirectories.isEmpty)
        XCTAssertTrue(report.fullXcodeSelected)
        XCTAssertTrue(report.xctestAvailable)
        XCTAssertTrue(report.xcodebuildAvailable)
        XCTAssertTrue(report.issues.isEmpty)
        XCTAssertTrue(report.isReadyForNativeVerification)

        let diagnostic = report.diagnostic(configuration: configuration)
        XCTAssertEqual(diagnostic.projectListing, .ready)
        XCTAssertEqual(diagnostic.nativeVerification, .ready)
        XCTAssertTrue(
            diagnostic.suggestedCommands.contains(
                "DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --disable-swift-testing --enable-xctest list"
            )
        )
        XCTAssertTrue(
            diagnostic.suggestedCommands.contains(
                "DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project \(project.path) -scheme PearchHA -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build"
            )
        )
    }

    func testXcodePreflightReportsLicenseAcceptanceGuidance() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let project = try testXcodeProject(in: directory, schemeName: "PearchHA")
        let xcodeSelectURL = try fakeExecutable(in: directory, name: "xcode-select")
        let xcrunURL = try fakeExecutable(in: directory, name: "xcrun")
        let runner = RecordingCommandRunner { executableURL, arguments in
            if executableURL == xcodeSelectURL {
                return PearchHACommandResult(
                    status: 0,
                    output: "/Applications/Xcode.app/Contents/Developer"
                )
            }
            if executableURL == xcrunURL {
                if arguments == ["--find", "xctest"] {
                    return PearchHACommandResult(
                        status: 69,
                        output: "You have not agreed to the Xcode license agreements. Please run 'sudo xcodebuild -license' to review and agree to the Xcode license agreements."
                    )
                }
                if arguments == ["--find", "xcodebuild"] {
                    return PearchHACommandResult(
                        status: 69,
                        output: "You have not agreed to the Xcode license agreements. Please run 'sudo xcodebuild -license' to review and agree to the Xcode license agreements."
                    )
                }
            }
            XCTFail("unexpected command: \(executableURL.path) \(arguments)")
            return PearchHACommandResult(status: 1, output: "unexpected command")
        }

        let configuration = PearchHAXcodePreflightConfiguration(
            projectURL: project,
            schemeName: "PearchHA"
        )
        let report = try PearchHAXcodePreflightChecker(
            fileManager: .default,
            xcodeSelectURL: xcodeSelectURL,
            xcrunURL: xcrunURL,
            commandRunner: runner
        ).check(configuration)

        XCTAssertEqual(report.issues, [.xcodeLicenseNotAccepted])
        XCTAssertFalse(report.xctestAvailable)
        XCTAssertFalse(report.xcodebuildAvailable)
        XCTAssertFalse(report.projectListingAvailable)

        let diagnostic = report.diagnostic(configuration: configuration)
        XCTAssertTrue(
            diagnostic.nextSteps.contains(
                "Accept the Xcode license once on this Mac before rerunning native verification."
            )
        )
        XCTAssertTrue(
            diagnostic.suggestedCommands.contains(
                "sudo env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -license accept"
            )
        )
        XCTAssertTrue(
            diagnostic.suggestedCommands.contains(
                "DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run pearchha-xcode-doctor --json --strict --project \(project.path) --scheme PearchHA"
            )
        )
    }

    func testXcodePreflightDiagnosticCarriesDiscoveredXcodeDeveloperDirectories() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let applicationsDirectory = directory.appendingPathComponent("Applications", isDirectory: true)
        let developerDirectory = try makeDiscoveredXcodeDeveloperDirectory(
            in: applicationsDirectory,
            appName: "Xcode-beta.app"
        )
        let report = PearchHAXcodePreflightReport(
            projectAvailable: true,
            sharedSchemeAvailable: true,
            projectListingAvailable: false,
            activeDeveloperDirectory: "/Library/Developer/CommandLineTools",
            discoveredXcodeDeveloperDirectories: [developerDirectory.path],
            fullXcodeSelected: false,
            xctestAvailable: false,
            xcodebuildAvailable: false,
            issues: [
                .commandLineToolsSelected("/Library/Developer/CommandLineTools"),
                .xctestUnavailable(status: 72),
                .xcodebuildUnavailable(status: 72)
            ]
        )
        let diagnostic = report.diagnostic(
            configuration: PearchHAXcodePreflightConfiguration(
                projectURL: URL(fileURLWithPath: "/tmp/PearchHA.xcodeproj", isDirectory: true),
                schemeName: "PearchHA"
            )
        )

        XCTAssertEqual(diagnostic.discoveredXcodeDeveloperDirectories, [developerDirectory.path])
    }

    func testXcodeDoctorCommandSupportsScriptableJSONAndStrictMode() throws {
        var output: [String] = []
        var errors: [String] = []
        let exitCode = PearchHAXcodeDoctorCommand.run(
            arguments: ["--json"],
            standardOutput: { output.append($0) },
            standardError: { errors.append($0) }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(errors.isEmpty)

        let data = Data(output.joined(separator: "\n").utf8)
        let diagnostic = try JSONDecoder().decode(PearchHAXcodePreflightDiagnostic.self, from: data)
        XCTAssertEqual(diagnostic.project, .present)
        XCTAssertEqual(diagnostic.sharedScheme, .present)
        if diagnostic.nativeVerification == .ready {
            XCTAssertTrue(diagnostic.issues.isEmpty)
            XCTAssertEqual(diagnostic.projectListing, .ready)
            // The discovered Xcode path varies by machine (CI runners install
            // version-suffixed bundles), so assert the command's shape.
            XCTAssertTrue(
                diagnostic.suggestedCommands.contains { command in
                    command.hasPrefix("DEVELOPER_DIR=")
                        && command.hasSuffix(" swift test --disable-swift-testing --enable-xctest list")
                }
            )
        } else {
            XCTAssertEqual(diagnostic.projectListing, .blocked)
            XCTAssertFalse(diagnostic.issues.isEmpty)
        }

        let strictExitCode = PearchHAXcodeDoctorCommand.run(
            arguments: ["--json", "--strict"],
            standardOutput: { _ in },
            standardError: { _ in }
        )
        XCTAssertEqual(strictExitCode, diagnostic.nativeVerification == .ready ? 0 : 1)
    }

    func testXcodePreflightRejectsProjectListingWithoutConfiguredScheme() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let project = try testXcodeProject(in: directory, schemeName: "PearchHA")
        let xcodeSelectURL = try fakeExecutable(in: directory, name: "xcode-select")
        let xcrunURL = try fakeExecutable(in: directory, name: "xcrun")
        let runner = RecordingCommandRunner { executableURL, arguments in
            if executableURL == xcodeSelectURL {
                return PearchHACommandResult(
                    status: 0,
                    output: "/Applications/Xcode.app/Contents/Developer"
                )
            }
            if executableURL == xcrunURL {
                if arguments == ["--find", "xctest"] {
                    return PearchHACommandResult(status: 0, output: "/Applications/Xcode.app/Contents/Developer/usr/bin/xctest")
                }
                if arguments == ["--find", "xcodebuild"] {
                    return PearchHACommandResult(status: 0, output: "/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild")
                }
                if arguments == ["xcodebuild", "-list", "-project", project.path] {
                    return PearchHACommandResult(
                        status: 0,
                        output: """
                        Information about project "PearchHA":
                            Schemes:
                                WrongScheme
                        """
                    )
                }
            }
            XCTFail("unexpected command: \(executableURL.path) \(arguments)")
            return PearchHACommandResult(status: 1, output: "unexpected command")
        }

        let report = try PearchHAXcodePreflightChecker(
            fileManager: .default,
            xcodeSelectURL: xcodeSelectURL,
            xcrunURL: xcrunURL,
            commandRunner: runner
        ).check(
            PearchHAXcodePreflightConfiguration(
                projectURL: project,
                schemeName: "PearchHA"
            )
        )

        XCTAssertFalse(report.projectListingAvailable)
        XCTAssertEqual(report.issues, [.sharedSchemeNotListed("PearchHA")])
        XCTAssertFalse(report.isReadyForNativeVerification)
    }

    func testReleaseReviewBaselineListsCanonicalSmokeSnapshotsAndContactSheet() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let baselineURL = rootURL.appendingPathComponent("docs/release-review-baseline.json", isDirectory: false)
        let payload = try JSONSerialization.jsonObject(
            with: Data(contentsOf: baselineURL)
        ) as? [String: Any]

        let variants = payload?["variants"] as? [[String: Any]]
        let variantNames = variants?.compactMap { $0["name"] as? String } ?? []
        let contactSheet = payload?["contactSheet"] as? [String: Any]
        let contactSheetName = contactSheet?["name"] as? String

        XCTAssertEqual(payload?["schemaVersion"] as? Int, 1)
        XCTAssertEqual(
            Set(variantNames + [contactSheetName].compactMap { $0 }),
            Set(PearchHAReleaseEvidenceScreenshots.requiredNames)
        )
    }

    func testReleaseGuideListsCanonicalRequiredScreenshotNames() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let packageURL = rootURL.appendingPathComponent("scripts/package.sh", isDirectory: false)
        let package = try String(contentsOf: packageURL, encoding: .utf8)
        let baselineURL = rootURL.appendingPathComponent("docs/release-review-baseline.json", isDirectory: false)

        XCTAssertTrue(package.contains("--snapshot-dir .build/pearchha-snapshots/current"))
        XCTAssertTrue(package.contains("--release-manifest dist/pearchha-release-manifest.json"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: baselineURL.path))
        XCTAssertFalse(PearchHAReleaseEvidenceScreenshots.requiredNames.isEmpty)
    }

    func testReleaseWorkflowBuildsVerifiesAndPublishesTheUniversalBundle() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let workflowURL = rootURL.appendingPathComponent(".github/workflows/release.yml", isDirectory: false)
        let workflow = try String(contentsOf: workflowURL, encoding: .utf8)
        let packageURL = rootURL.appendingPathComponent("scripts/package.sh", isDirectory: false)
        let package = try String(contentsOf: packageURL, encoding: .utf8)

        XCTAssertTrue(workflow.contains("# yuna-release: true"))
        XCTAssertTrue(workflow.contains("workflow_dispatch:"))
        XCTAssertTrue(workflow.contains("wc_swift_release.yml@"))
        XCTAssertTrue(workflow.contains("force: ${{ inputs.force }}"))
        XCTAssertFalse(workflow.contains("homebrew-tap"))
        XCTAssertFalse(workflow.contains("RELEASE_TOKEN"))

        XCTAssertTrue(package.contains("swift build -c release --arch arm64 --product PearchHA --scratch-path .build-release-arm64"))
        XCTAssertTrue(package.contains("swift build -c release --arch x86_64 --product PearchHA --scratch-path .build-release-x86_64"))
        XCTAssertTrue(package.contains("lipo -create"))
        XCTAssertTrue(package.contains("--sign-ad-hoc"))
        XCTAssertTrue(package.contains("--sign-identity \"${identity}\""))
        XCTAssertTrue(package.contains("--notary-profile \"${notary_profile}\""))
        XCTAssertTrue(package.contains("--package-dmg"))
        XCTAssertTrue(package.contains("--executable dist/PearchHA"))
        XCTAssertTrue(package.contains("--release-manifest dist/pearchha-release-manifest.json"))
        XCTAssertTrue(package.contains("--bundle-release-evidence dist/pearchha-release-evidence"))
        XCTAssertTrue(package.contains("--snapshot-dir .build/pearchha-snapshots/current"))
        XCTAssertTrue(package.contains("--verify-release-manifest dist/pearchha-release-manifest.json"))
        XCTAssertTrue(package.contains("codesign --verify --deep"))
        XCTAssertTrue(package.contains("ditto -c -k"))
        XCTAssertTrue(package.contains("PearchHA-${version}.zip"))
        XCTAssertTrue(package.contains("PearchHA-${version}.dmg"))
    }

    func testReleaseGuideDocumentsTheWorkflows() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let docsIndexURL = rootURL.appendingPathComponent("docs/README.md", isDirectory: false)
        let docsIndex = try String(contentsOf: docsIndexURL, encoding: .utf8)
        let workflow = try String(
            contentsOf: rootURL.appendingPathComponent(".github/workflows/release.yml", isDirectory: false),
            encoding: .utf8
        )

        XCTAssertTrue(docsIndex.contains("ROADMAP.md"))
        XCTAssertTrue(docsIndex.contains("ARCHITECTURE.md"))
        XCTAssertTrue(docsIndex.contains("TESTING.md"))
        XCTAssertTrue(workflow.contains("workflow_dispatch:"))
        XCTAssertTrue(workflow.contains("force:"))
        XCTAssertTrue(workflow.contains("wc_swift_release.yml@"))
    }

    func testDMGBuilderStagesAppApplicationsShortcutAndRunsHdiutilCreate() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let bundle = try testBundle(
            in: directory,
            callbackScheme: "pearchha-dmg",
            bundleIdentifier: "dev.pearchha.tests.dmg"
        )
        let hdiutilURL = try fakeExecutable(in: directory, name: "hdiutil")
        let outputURL = directory.appendingPathComponent("PearchHA.dmg", isDirectory: false)
        let runner = RecordingCommandRunner { _, arguments in
            XCTAssertEqual(arguments.first, "create")
            XCTAssertEqual(arguments[safe: 1], "-volname")
            XCTAssertEqual(arguments[safe: 2], "PearchHA Test")
            guard let sourceFolderIndex = arguments.firstIndex(of: "-srcfolder"),
                  arguments.indices.contains(arguments.index(after: sourceFolderIndex))
            else {
                XCTFail("missing source folder argument")
                return PearchHACommandResult(status: 1, output: "missing source folder")
            }
            let stagingURL = URL(fileURLWithPath: arguments[arguments.index(after: sourceFolderIndex)], isDirectory: true)
            XCTAssertTrue(FileManager.default.fileExists(atPath: stagingURL.appendingPathComponent("PearchHA.app").path))
            var isDirectory: ObjCBool = false
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: stagingURL.appendingPathComponent("Applications").path,
                    isDirectory: &isDirectory
                )
            )
            XCTAssertTrue(isDirectory.boolValue)
            try Data("dmg".utf8).write(to: outputURL)
            return PearchHACommandResult(status: 0, output: "created")
        }

        let result = try PearchHADMGBuilder(hdiutilURL: hdiutilURL, commandRunner: runner).build(
            PearchHADMGBuildConfiguration(
                appURL: bundle.appURL,
                outputURL: outputURL,
                volumeName: " PearchHA Test "
            )
        )

        XCTAssertEqual(result.dmgURL.path, outputURL.path)
        XCTAssertEqual(result.volumeName, "PearchHA Test")
        XCTAssertEqual(runner.invocations.count, 1)
        let invocation = try XCTUnwrap(runner.invocations.first)
        let sourceFolderIndex = try XCTUnwrap(invocation.arguments.firstIndex(of: "-srcfolder"))
        let stagedFolder = invocation.arguments[invocation.arguments.index(after: sourceFolderIndex)]
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagedFolder))
    }

    func testDMGBuilderRefusesOverwriteWithoutReplace() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let bundle = try testBundle(
            in: directory,
            callbackScheme: "pearchha-dmg-overwrite",
            bundleIdentifier: "dev.pearchha.tests.dmg.overwrite"
        )
        let outputURL = directory.appendingPathComponent("PearchHA.dmg", isDirectory: false)
        try Data("existing".utf8).write(to: outputURL)

        XCTAssertThrowsError(
            try PearchHADMGBuilder(hdiutilURL: try fakeExecutable(in: directory, name: "hdiutil")).build(
                PearchHADMGBuildConfiguration(appURL: bundle.appURL, outputURL: outputURL)
            )
        ) { error in
            XCTAssertEqual(error as? PearchHADMGBuildError, .outputExists(outputURL.path))
        }
    }

    func testDMGBuilderReportsHdiutilCreateFailure() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let bundle = try testBundle(
            in: directory,
            callbackScheme: "pearchha-dmg-failure",
            bundleIdentifier: "dev.pearchha.tests.dmg.failure"
        )
        let hdiutilURL = try fakeExecutable(in: directory, name: "hdiutil")
        let runner = RecordingCommandRunner { _, _ in
            PearchHACommandResult(status: 64, output: "create failed")
        }

        XCTAssertThrowsError(
            try PearchHADMGBuilder(hdiutilURL: hdiutilURL, commandRunner: runner).build(
                PearchHADMGBuildConfiguration(
                    appURL: bundle.appURL,
                    outputURL: directory.appendingPathComponent("PearchHA.dmg", isDirectory: false)
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? PearchHADMGBuildError,
                .hdiutilFailed(operation: "create", status: 64, output: "create failed")
            )
        }
    }

    func testDMGVerifierRunsHdiutilVerifyAndReportsFailure() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let dmgURL = directory.appendingPathComponent("PearchHA.dmg", isDirectory: false)
        try Data("dmg".utf8).write(to: dmgURL)
        let hdiutilURL = try fakeExecutable(in: directory, name: "hdiutil")
        let successRunner = RecordingCommandRunner { _, arguments in
            XCTAssertEqual(arguments, ["verify", dmgURL.path])
            return PearchHACommandResult(status: 0, output: "verified")
        }

        let result = try PearchHADMGVerifier(hdiutilURL: hdiutilURL, commandRunner: successRunner).verify(
            PearchHADMGVerificationConfiguration(dmgURL: dmgURL)
        )
        XCTAssertEqual(result.dmgURL.path, dmgURL.path)

        let failingRunner = RecordingCommandRunner { _, _ in
            PearchHACommandResult(status: 1, output: "bad image")
        }
        XCTAssertThrowsError(
            try PearchHADMGVerifier(hdiutilURL: hdiutilURL, commandRunner: failingRunner).verify(
                PearchHADMGVerificationConfiguration(dmgURL: dmgURL)
            )
        ) { error in
            XCTAssertEqual(
                error as? PearchHADMGBuildError,
                .hdiutilFailed(operation: "verify", status: 1, output: "bad image")
            )
        }
    }

    func testDMGVerifierRetriesTemporaryResourceFailure() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let dmgURL = directory.appendingPathComponent("PearchHA.dmg", isDirectory: false)
        try Data("dmg".utf8).write(to: dmgURL)
        let hdiutilURL = try fakeExecutable(in: directory, name: "hdiutil")
        let attempts = LockedValue(0)
        let runner = RecordingCommandRunner { _, arguments in
            XCTAssertEqual(arguments, ["verify", dmgURL.path])
            let attempt = attempts.get() + 1
            attempts.set(attempt)
            return attempt == 1
                ? PearchHACommandResult(status: 1, output: "Resource temporarily unavailable")
                : PearchHACommandResult(status: 0, output: "verified")
        }

        let result = try PearchHADMGVerifier(hdiutilURL: hdiutilURL, commandRunner: runner).verify(
            PearchHADMGVerificationConfiguration(dmgURL: dmgURL)
        )

        XCTAssertEqual(result.dmgURL.path, dmgURL.path)
        XCTAssertEqual(runner.invocations.count, 2)
    }

    func testDMGContentVerifierMountsImageChecksAppShortcutAndDetaches() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let dmgURL = directory.appendingPathComponent("PearchHA.dmg", isDirectory: false)
        try Data("dmg".utf8).write(to: dmgURL)
        let hdiutilURL = try fakeExecutable(in: directory, name: "hdiutil")
        let mountpointURL = LockedValue<URL?>(nil)
        let runner = RecordingCommandRunner { _, arguments in
            if arguments.first == "attach" {
                let mountpointIndex = try XCTUnwrap(arguments.firstIndex(of: "-mountpoint"))
                let mountpoint = URL(fileURLWithPath: arguments[arguments.index(after: mountpointIndex)], isDirectory: true)
                mountpointURL.set(mountpoint)
                XCTAssertEqual(arguments.last, dmgURL.path)
                try FileManager.default.createDirectory(
                    at: mountpoint.appendingPathComponent("PearchHA.app", isDirectory: true),
                    withIntermediateDirectories: true
                )
                try FileManager.default.createSymbolicLink(
                    at: mountpoint.appendingPathComponent("Applications"),
                    withDestinationURL: URL(fileURLWithPath: "/Applications", isDirectory: true)
                )
                return PearchHACommandResult(status: 0, output: "attached")
            }
            XCTAssertEqual(arguments, ["detach", try XCTUnwrap(mountpointURL.get()).path])
            return PearchHACommandResult(status: 0, output: "detached")
        }

        let result = try PearchHADMGContentVerifier(hdiutilURL: hdiutilURL, commandRunner: runner).verify(
            PearchHADMGContentVerificationConfiguration(dmgURL: dmgURL, appBundleName: "PearchHA.app")
        )

        XCTAssertEqual(result.dmgURL.path, dmgURL.path)
        XCTAssertEqual(result.mountedAppURL.lastPathComponent, "PearchHA.app")
        XCTAssertEqual(result.applicationsShortcutURL?.lastPathComponent, "Applications")
        XCTAssertEqual(runner.invocations.map { $0.arguments.first }, ["attach", "detach"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(mountpointURL.get()).path))
    }

    func testDMGContentVerifierReportsMissingMountedAppAndStillDetaches() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let dmgURL = directory.appendingPathComponent("PearchHA.dmg", isDirectory: false)
        try Data("dmg".utf8).write(to: dmgURL)
        let hdiutilURL = try fakeExecutable(in: directory, name: "hdiutil")
        let mountpointURL = LockedValue<URL?>(nil)
        let runner = RecordingCommandRunner { _, arguments in
            if arguments.first == "attach" {
                let mountpointIndex = try XCTUnwrap(arguments.firstIndex(of: "-mountpoint"))
                let mountpoint = URL(fileURLWithPath: arguments[arguments.index(after: mountpointIndex)], isDirectory: true)
                mountpointURL.set(mountpoint)
                try FileManager.default.createSymbolicLink(
                    at: mountpoint.appendingPathComponent("Applications"),
                    withDestinationURL: URL(fileURLWithPath: "/Applications", isDirectory: true)
                )
                return PearchHACommandResult(status: 0, output: "attached")
            }
            XCTAssertEqual(arguments, ["detach", try XCTUnwrap(mountpointURL.get()).path])
            return PearchHACommandResult(status: 0, output: "detached")
        }

        XCTAssertThrowsError(
            try PearchHADMGContentVerifier(hdiutilURL: hdiutilURL, commandRunner: runner).verify(
                PearchHADMGContentVerificationConfiguration(dmgURL: dmgURL, appBundleName: "PearchHA.app")
            )
        ) { error in
            guard let mountpointURL = mountpointURL.get() else {
                XCTFail("missing mountpoint")
                return
            }
            XCTAssertEqual(
                error as? PearchHADMGBuildError,
                .mountedAppMissing(mountpointURL.appendingPathComponent("PearchHA.app", isDirectory: true).path)
            )
        }
        XCTAssertEqual(runner.invocations.map { $0.arguments.first }, ["attach", "detach"])
    }

    func testDMGContentVerifierReportsDetachFailure() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let dmgURL = directory.appendingPathComponent("PearchHA.dmg", isDirectory: false)
        try Data("dmg".utf8).write(to: dmgURL)
        let hdiutilURL = try fakeExecutable(in: directory, name: "hdiutil")
        let runner = RecordingCommandRunner { _, arguments in
            if arguments.first == "attach" {
                let mountpointIndex = try XCTUnwrap(arguments.firstIndex(of: "-mountpoint"))
                let mountpoint = URL(fileURLWithPath: arguments[arguments.index(after: mountpointIndex)], isDirectory: true)
                try FileManager.default.createDirectory(
                    at: mountpoint.appendingPathComponent("PearchHA.app", isDirectory: true),
                    withIntermediateDirectories: true
                )
                try FileManager.default.createSymbolicLink(
                    at: mountpoint.appendingPathComponent("Applications"),
                    withDestinationURL: URL(fileURLWithPath: "/Applications", isDirectory: true)
                )
                return PearchHACommandResult(status: 0, output: "attached")
            }
            return PearchHACommandResult(status: 1, output: "detach failed")
        }

        XCTAssertThrowsError(
            try PearchHADMGContentVerifier(hdiutilURL: hdiutilURL, commandRunner: runner).verify(
                PearchHADMGContentVerificationConfiguration(dmgURL: dmgURL, appBundleName: "PearchHA.app")
            )
        ) { error in
            XCTAssertEqual(
                error as? PearchHADMGBuildError,
                .hdiutilFailed(operation: "detach", status: 1, output: "detach failed")
            )
        }
        XCTAssertEqual(runner.invocations.map { $0.arguments.first }, ["attach", "detach"])
    }

    func testCodeSignerRunsCodesignWithRuntimeTimestampEntitlementsAndVerifiesSignature() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let bundle = try testBundle(
            in: directory,
            callbackScheme: "pearchha-sign",
            bundleIdentifier: "dev.pearchha.tests.sign"
        )
        let entitlementsURL = directory.appendingPathComponent("PearchHA.entitlements", isDirectory: false)
        try Data("<plist/>".utf8).write(to: entitlementsURL)
        let codesignURL = try fakeExecutable(in: directory, name: "codesign")
        let identity = "Developer ID Application: PearchHA"
        let runner = RecordingCommandRunner { _, arguments in
            if arguments.first == "--verify" {
                XCTAssertEqual(arguments, ["--verify", "--strict", "--verbose=2", bundle.appURL.path])
                return PearchHACommandResult(status: 0, output: "valid")
            }
            XCTAssertEqual(
                arguments,
                [
                    "--force",
                    "--timestamp",
                    "--options", "runtime",
                    "--entitlements", entitlementsURL.path,
                    "--sign", identity,
                    bundle.appURL.path
                ]
            )
            return PearchHACommandResult(status: 0, output: "signed")
        }

        let signing = try PearchHACodeSigner(codesignURL: codesignURL, commandRunner: runner).sign(
            PearchHACodeSigningConfiguration(
                appURL: bundle.appURL,
                identity: " \(identity) ",
                entitlementsURL: entitlementsURL
            )
        )
        let verification = try PearchHACodeSignatureVerifier(codesignURL: codesignURL, commandRunner: runner).verify(
            PearchHACodeSignatureVerificationConfiguration(appURL: bundle.appURL)
        )

        XCTAssertEqual(signing.identity, identity)
        XCTAssertEqual(signing.appURL.path, bundle.appURL.path)
        XCTAssertEqual(signing.entitlementsURL?.path, entitlementsURL.path)
        XCTAssertTrue(signing.hardenedRuntime)
        XCTAssertTrue(signing.timestamp)
        XCTAssertEqual(verification.appURL.path, bundle.appURL.path)
        XCTAssertEqual(runner.invocations.count, 2)
    }

    func testCodeSignerRejectsBlankIdentityMissingEntitlementsAndReportsFailure() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let bundle = try testBundle(
            in: directory,
            callbackScheme: "pearchha-sign-failure",
            bundleIdentifier: "dev.pearchha.tests.sign.failure"
        )
        let codesignURL = try fakeExecutable(in: directory, name: "codesign")

        XCTAssertThrowsError(
            try PearchHACodeSigner(codesignURL: codesignURL).sign(
                PearchHACodeSigningConfiguration(appURL: bundle.appURL, identity: "  ")
            )
        ) { error in
            XCTAssertEqual(error as? PearchHACodeSigningError, .blankIdentity)
        }

        let missingEntitlementsURL = directory.appendingPathComponent("Missing.entitlements", isDirectory: false)
        XCTAssertThrowsError(
            try PearchHACodeSigner(codesignURL: codesignURL).sign(
                PearchHACodeSigningConfiguration(
                    appURL: bundle.appURL,
                    identity: "Developer ID Application: PearchHA",
                    entitlementsURL: missingEntitlementsURL
                )
            )
        ) { error in
            XCTAssertEqual(error as? PearchHACodeSigningError, .entitlementsMissing(missingEntitlementsURL.path))
        }

        let failingRunner = RecordingCommandRunner { _, _ in
            PearchHACommandResult(status: 1, output: "identity not found")
        }
        XCTAssertThrowsError(
            try PearchHACodeSigner(codesignURL: codesignURL, commandRunner: failingRunner).sign(
                PearchHACodeSigningConfiguration(appURL: bundle.appURL, identity: "Developer ID Application: PearchHA")
            )
        ) { error in
            XCTAssertEqual(
                error as? PearchHACodeSigningError,
                .codesignFailed(operation: "sign", status: 1, output: "identity not found")
            )
        }
    }

    func testNotarySubmitterRunsNotarytoolWaitsAndStaplesArtifact() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let dmgURL = directory.appendingPathComponent("PearchHA.dmg", isDirectory: false)
        try Data("dmg".utf8).write(to: dmgURL)
        let xcrunURL = try fakeExecutable(in: directory, name: "xcrun")
        let runner = RecordingCommandRunner { _, arguments in
            if arguments.first == "stapler" {
                XCTAssertEqual(arguments, ["stapler", "staple", dmgURL.path])
                return PearchHACommandResult(status: 0, output: "stapled")
            }
            XCTAssertEqual(
                arguments,
                [
                    "notarytool",
                    "submit",
                    dmgURL.path,
                    "--keychain-profile",
                    "pearchha-release",
                    "--no-progress",
                    "--wait",
                    "--timeout", "30m"
                ]
            )
            return PearchHACommandResult(status: 0, output: "accepted")
        }

        let result = try PearchHANotarySubmitter(xcrunURL: xcrunURL, commandRunner: runner).submit(
            PearchHANotarySubmissionConfiguration(
                artifactURL: dmgURL,
                keychainProfile: " pearchha-release ",
                waitForCompletion: true,
                timeout: "30m",
                staple: true
            )
        )

        XCTAssertEqual(result.artifactURL.path, dmgURL.path)
        XCTAssertEqual(result.keychainProfile, "pearchha-release")
        XCTAssertTrue(result.waitedForCompletion)
        XCTAssertTrue(result.stapled)
        XCTAssertEqual(runner.invocations.count, 2)
    }

    func testNotarySubmitterRejectsMissingInputsAndReportsCommandFailures() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let dmgURL = directory.appendingPathComponent("PearchHA.dmg", isDirectory: false)
        let missingDmgURL = directory.appendingPathComponent("Missing.dmg", isDirectory: false)
        let xcrunURL = try fakeExecutable(in: directory, name: "xcrun")

        XCTAssertThrowsError(
            try PearchHANotarySubmitter(xcrunURL: xcrunURL).submit(
                PearchHANotarySubmissionConfiguration(artifactURL: missingDmgURL, keychainProfile: "profile")
            )
        ) { error in
            XCTAssertEqual(error as? PearchHANotaryError, .artifactMissing(missingDmgURL.path))
        }

        try Data("dmg".utf8).write(to: dmgURL)
        XCTAssertThrowsError(
            try PearchHANotarySubmitter(xcrunURL: xcrunURL).submit(
                PearchHANotarySubmissionConfiguration(artifactURL: dmgURL, keychainProfile: " ")
            )
        ) { error in
            XCTAssertEqual(error as? PearchHANotaryError, .blankKeychainProfile)
        }

        XCTAssertThrowsError(
            try PearchHANotarySubmitter(xcrunURL: xcrunURL).submit(
                PearchHANotarySubmissionConfiguration(
                    artifactURL: dmgURL,
                    keychainProfile: "profile",
                    waitForCompletion: false,
                    staple: true
                )
            )
        ) { error in
            XCTAssertEqual(error as? PearchHANotaryError, .stapleRequiresCompletedSubmission)
        }

        let notaryFailureRunner = RecordingCommandRunner { _, _ in
            PearchHACommandResult(status: 65, output: "rejected")
        }
        XCTAssertThrowsError(
            try PearchHANotarySubmitter(xcrunURL: xcrunURL, commandRunner: notaryFailureRunner).submit(
                PearchHANotarySubmissionConfiguration(artifactURL: dmgURL, keychainProfile: "profile")
            )
        ) { error in
            XCTAssertEqual(error as? PearchHANotaryError, .notaryToolFailed(status: 65, output: "rejected"))
        }

        let staplerFailureRunner = RecordingCommandRunner { _, arguments in
            arguments.first == "notarytool"
                ? PearchHACommandResult(status: 0, output: "accepted")
                : PearchHACommandResult(status: 1, output: "ticket unavailable")
        }
        XCTAssertThrowsError(
            try PearchHANotarySubmitter(xcrunURL: xcrunURL, commandRunner: staplerFailureRunner).submit(
                PearchHANotarySubmissionConfiguration(artifactURL: dmgURL, keychainProfile: "profile")
            )
        ) { error in
            XCTAssertEqual(error as? PearchHANotaryError, .staplerFailed(status: 1, output: "ticket unavailable"))
        }
    }

    func testReleasePreflightChecksDeveloperIDIdentityAndNotaryProfile() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let securityURL = try fakeExecutable(in: directory, name: "security")
        let xcrunURL = try fakeExecutable(in: directory, name: "xcrun")
        let identity = "Developer ID Application: PearchHA (TEAMID)"
        let runner = RecordingCommandRunner { _, arguments in
            if arguments.first == "find-identity" {
                XCTAssertEqual(arguments, ["find-identity", "-p", "codesigning", "-v"])
                return PearchHACommandResult(
                    status: 0,
                    output: #"  1) ABCDEF1234567890 "Developer ID Application: PearchHA (TEAMID)""#
                )
            }
            XCTAssertEqual(
                arguments,
                [
                    "notarytool",
                    "history",
                    "--keychain-profile",
                    "pearchha-release",
                    "--output-format",
                    "json",
                    "--no-progress"
                ]
            )
            return PearchHACommandResult(status: 0, output: #"{"history":[]}"#)
        }

        let report = try PearchHAReleasePreflightChecker(
            securityURL: securityURL,
            xcrunURL: xcrunURL,
            commandRunner: runner
        ).check(
            PearchHAReleasePreflightConfiguration(
                signingIdentity: " \(identity) ",
                notaryProfile: " pearchha-release "
            )
        )

        XCTAssertTrue(report.isReadyForCredentialedRelease)
        XCTAssertTrue(report.signingIdentityAvailable)
        XCTAssertTrue(report.notaryProfileAvailable)
        XCTAssertEqual(report.issues, [])
        XCTAssertEqual(runner.invocations.count, 2)
    }

    func testReleasePreflightRejectsAdHocAndMissingNotaryProfileWithoutRunningCommands() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let securityURL = try fakeExecutable(in: directory, name: "security")
        let xcrunURL = try fakeExecutable(in: directory, name: "xcrun")
        let runner = RecordingCommandRunner { _, _ in
            XCTFail("release preflight should fail before command execution")
            return PearchHACommandResult(status: 1, output: "")
        }

        let report = try PearchHAReleasePreflightChecker(
            securityURL: securityURL,
            xcrunURL: xcrunURL,
            commandRunner: runner
        ).check(
            PearchHAReleasePreflightConfiguration(
                signingIdentity: "-",
                notaryProfile: nil
            )
        )

        XCTAssertFalse(report.isReadyForCredentialedRelease)
        XCTAssertFalse(report.signingIdentityAvailable)
        XCTAssertFalse(report.notaryProfileAvailable)
        XCTAssertEqual(report.issues, [.adHocSigningIdentity, .blankNotaryProfile])
        XCTAssertEqual(runner.invocations, [])
    }

    func testReleasePreflightReportsMissingDeveloperIDIdentityAndNotaryFailureWithoutOutputLeak() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let securityURL = try fakeExecutable(in: directory, name: "security")
        let xcrunURL = try fakeExecutable(in: directory, name: "xcrun")
        let runner = RecordingCommandRunner { _, arguments in
            if arguments.first == "find-identity" {
                return PearchHACommandResult(
                    status: 0,
                    output: #"  1) ABCDEF1234567890 "Apple Development: Someone Else (TEAMID)""#
                )
            }
            return PearchHACommandResult(status: 69, output: "profile password secret")
        }

        let report = try PearchHAReleasePreflightChecker(
            securityURL: securityURL,
            xcrunURL: xcrunURL,
            commandRunner: runner
        ).check(
            PearchHAReleasePreflightConfiguration(
                signingIdentity: "Developer ID Application: PearchHA (TEAMID)",
                notaryProfile: "pearchha-release"
            )
        )

        XCTAssertFalse(report.isReadyForCredentialedRelease)
        XCTAssertFalse(report.signingIdentityAvailable)
        XCTAssertFalse(report.notaryProfileAvailable)
        XCTAssertEqual(report.issues, [.signingIdentityNotFound, .notaryProfileCheckFailed(status: 69)])
        let issueText = report.issues.map(\.description).joined(separator: "\n")
        XCTAssertFalse(issueText.contains("profile password secret"))
        XCTAssertEqual(runner.invocations.count, 2)
    }

    func testReleasePreflightDiagnosticIsScriptableAndRedacted() throws {
        let configuration = PearchHAReleasePreflightConfiguration(
            signingIdentity: "Developer ID Application: Real Team (ABC1234567)",
            notaryProfile: "release-prod"
        )
        let report = PearchHAReleasePreflightReport(
            signingIdentityAvailable: false,
            notaryProfileAvailable: false,
            issues: [
                .signingIdentityNotFound,
                .notaryProfileCheckFailed(status: 69)
            ]
        )

        let diagnostic = report.diagnostic(configuration: configuration)
        let data = try JSONEncoder().encode(diagnostic)
        let decoded = try JSONDecoder().decode(PearchHAReleasePreflightDiagnostic.self, from: data)
        let text = String(decoding: data, as: UTF8.self)

        XCTAssertEqual(decoded.signingIdentity, .present)
        XCTAssertEqual(decoded.notaryProfile, .present)
        XCTAssertEqual(decoded.developerIDIdentity, .blocked)
        XCTAssertEqual(decoded.notaryKeychainProfile, .blocked)
        XCTAssertEqual(decoded.credentialedRelease, .blocked)
        XCTAssertEqual(
            decoded.issues.map(\.code),
            ["signingIdentityNotFound", "notaryProfileCheckFailed"]
        )
        XCTAssertEqual(
            decoded.nextSteps,
            [
                "Choose a Developer ID Application signing identity from the login keychain, then rerun release preflight.",
                "Create or repair a usable notarytool Keychain profile, then rerun release preflight."
            ]
        )
        XCTAssertEqual(
            decoded.suggestedCommands,
            [
                "security find-identity -p codesigning -v",
                "xcrun notarytool history --keychain-profile pearchha-release --output-format json --no-progress",
                #"swift run pearchha-package-app --release-preflight --json --sign-identity "Developer ID Application: Example (TEAMID)" --notary-profile pearchha-release"#
            ]
        )
        XCTAssertFalse(text.contains("Developer ID Application: Real Team"))
        XCTAssertFalse(text.contains("release-prod"))
        XCTAssertFalse(text.contains("profile password secret"))
    }

    func testReleasePreflightReadyGuidanceSuggestsCredentialedPackageCommand() {
        let configuration = PearchHAReleasePreflightConfiguration(
            signingIdentity: "Developer ID Application: Real Team (ABC1234567)",
            notaryProfile: "release-prod"
        )
        let report = PearchHAReleasePreflightReport(
            signingIdentityAvailable: true,
            notaryProfileAvailable: true,
            issues: []
        )

        XCTAssertEqual(
            report.nextSteps(configuration: configuration),
            [
                "Credentialed release preflight passed. Build the signed, notarized DMG with the credentialed packaging command from docs/RELEASE.md."
            ]
        )
        XCTAssertEqual(
            report.suggestedCommands(configuration: configuration),
            [PearchHAReleasePreflightGuidance.credentialedPackageCommand]
        )
    }

    func testReleaseEvidenceWriterWritesManifestWithArtifactHashesAndScreenshots() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let bundle = try testBundle(
            in: directory,
            callbackScheme: "pearchha-release",
            bundleIdentifier: "dev.pearchha.tests.release"
        )
        let dmgURL = directory.appendingPathComponent("PearchHA.dmg", isDirectory: false)
        try Data("dmg".utf8).write(to: dmgURL)
        let screenshotDirectory = directory.appendingPathComponent("snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true)
        let screenshotURL = screenshotDirectory.appendingPathComponent("connected-light.png", isDirectory: false)
        try Data("png".utf8).write(to: screenshotURL)
        let reviewBaselineURL = screenshotDirectory.appendingPathComponent(
            PearchHAReleaseEvidenceReview.expectedBaselineFilename,
            isDirectory: false
        )
        try Data("baseline".utf8).write(to: reviewBaselineURL)
        let oauthSiteURL = directory.appendingPathComponent("oauth-site/index.html", isDirectory: false)
        try FileManager.default.createDirectory(at: oauthSiteURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("oauth-site".utf8).write(to: oauthSiteURL)
        let manifestURL = directory.appendingPathComponent("release-manifest.json", isDirectory: false)

        let manifest = try PearchHAReleaseEvidenceWriter().write(
            PearchHAReleaseEvidenceConfiguration(
                appURL: bundle.appURL,
                dmgURL: dmgURL,
                manifestURL: manifestURL,
                oauthClientWebsiteURL: oauthSiteURL,
                screenshotDirectoryURL: screenshotDirectory,
                reviewBaselineURL: reviewBaselineURL,
                signingIdentity: "Developer ID Application: PearchHA (TEAMID)",
                signatureVerified: true,
                notarySubmitted: true,
                stapled: true
            )
        )
        let decoded = try JSONDecoder().decode(
            PearchHAReleaseEvidenceManifest.self,
            from: Data(contentsOf: manifestURL)
        )

        XCTAssertEqual(decoded, manifest)
        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.app.path, "PearchHA.app")
        XCTAssertEqual(manifest.app.name, "PearchHA")
        XCTAssertEqual(manifest.app.bundleIdentifier, "dev.pearchha.tests.release")
        XCTAssertEqual(manifest.app.version, "0.1.0")
        XCTAssertEqual(manifest.app.buildVersion, "1")
        XCTAssertEqual(manifest.app.minimumSystemVersion, "13.0")
        XCTAssertEqual(manifest.app.callbackURLSchemes, ["pearchha-release"])
        XCTAssertEqual(manifest.dmg.name, "PearchHA.dmg")
        XCTAssertEqual(manifest.dmg.path, "PearchHA.dmg")
        XCTAssertEqual(manifest.dmg.sha256, sha256Hex(Data("dmg".utf8)))
        XCTAssertEqual(manifest.dmg.byteCount, 3)
        XCTAssertEqual(manifest.oauthClientWebsite?.name, "index.html")
        XCTAssertEqual(manifest.oauthClientWebsite?.path, "oauth-site/index.html")
        XCTAssertEqual(manifest.oauthClientWebsite?.sha256, sha256Hex(Data("oauth-site".utf8)))
        XCTAssertEqual(manifest.screenshots.map(\.name), ["connected-light.png"])
        XCTAssertEqual(manifest.screenshots.first?.path, "snapshots/connected-light.png")
        XCTAssertEqual(manifest.screenshots.first?.sha256, sha256Hex(Data("png".utf8)))
        XCTAssertEqual(manifest.reviewBaseline?.name, PearchHAReleaseEvidenceReview.expectedBaselineFilename)
        XCTAssertEqual(
            manifest.reviewBaseline?.path,
            "snapshots/\(PearchHAReleaseEvidenceReview.expectedBaselineFilename)"
        )
        XCTAssertEqual(manifest.reviewBaseline?.sha256, sha256Hex(Data("baseline".utf8)))
        XCTAssertEqual(manifest.signing.identity, "Developer ID Application: PearchHA (TEAMID)")
        XCTAssertFalse(manifest.signing.adHoc)
        XCTAssertTrue(manifest.signing.signatureVerified)
        XCTAssertTrue(manifest.notarization.submitted)
        XCTAssertTrue(manifest.notarization.stapled)
    }

    func testReleaseEvidenceWriterAcceptsCanonicalRequiredScreenshotNames() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let bundle = try testBundle(
            in: directory,
            callbackScheme: "pearchha-release-canonical-screenshots",
            bundleIdentifier: "dev.pearchha.tests.release.canonical.screenshots"
        )
        let dmgURL = directory.appendingPathComponent("PearchHA.dmg", isDirectory: false)
        try Data("dmg".utf8).write(to: dmgURL)
        let screenshotDirectory = directory.appendingPathComponent("snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true)
        for name in PearchHAReleaseEvidenceScreenshots.requiredNames {
            try Data(name.utf8).write(
                to: screenshotDirectory.appendingPathComponent(name, isDirectory: false)
            )
        }
        let manifestURL = directory.appendingPathComponent("release-manifest.json", isDirectory: false)

        let manifest = try PearchHAReleaseEvidenceWriter().write(
            PearchHAReleaseEvidenceConfiguration(
                appURL: bundle.appURL,
                dmgURL: dmgURL,
                manifestURL: manifestURL,
                screenshotDirectoryURL: screenshotDirectory,
                requiredScreenshotNames: PearchHAReleaseEvidenceScreenshots.requiredNames
            )
        )

        XCTAssertEqual(
            Set(manifest.screenshots.map(\.name)),
            Set(PearchHAReleaseEvidenceScreenshots.requiredNames)
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: manifestURL.path))
    }

    func testReleaseEvidenceWriterRejectsMissingArtifactsAndEmptyScreenshotDirectory() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let bundle = try testBundle(
            in: directory,
            callbackScheme: "pearchha-release-missing",
            bundleIdentifier: "dev.pearchha.tests.release.missing"
        )
        let missingDmgURL = directory.appendingPathComponent("Missing.dmg", isDirectory: false)
        let manifestURL = directory.appendingPathComponent("release-manifest.json", isDirectory: false)

        XCTAssertThrowsError(
            try PearchHAReleaseEvidenceWriter().write(
                PearchHAReleaseEvidenceConfiguration(
                    appURL: bundle.appURL,
                    dmgURL: missingDmgURL,
                    manifestURL: manifestURL
                )
            )
        ) { error in
            XCTAssertEqual(error as? PearchHAReleaseEvidenceError, .dmgMissing(missingDmgURL.path))
        }

        let dmgURL = directory.appendingPathComponent("PearchHA.dmg", isDirectory: false)
        try Data("dmg".utf8).write(to: dmgURL)

        XCTAssertThrowsError(
            try PearchHAReleaseEvidenceWriter().write(
                PearchHAReleaseEvidenceConfiguration(
                    appURL: bundle.appURL,
                    dmgURL: dmgURL,
                    manifestURL: manifestURL,
                    screenshotDirectoryURL: nil,
                    requiredScreenshotNames: ["connected-light.png"]
                )
            )
        ) { error in
            XCTAssertEqual(error as? PearchHAReleaseEvidenceError, .screenshotDirectoryRequired)
        }

        let screenshotDirectory = directory.appendingPathComponent("empty-snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true)

        XCTAssertThrowsError(
            try PearchHAReleaseEvidenceWriter().write(
                PearchHAReleaseEvidenceConfiguration(
                    appURL: bundle.appURL,
                    dmgURL: dmgURL,
                    manifestURL: manifestURL,
                    screenshotDirectoryURL: screenshotDirectory
                )
            )
        ) { error in
            XCTAssertEqual(error as? PearchHAReleaseEvidenceError, .screenshotsMissing(screenshotDirectory.path))
        }

        let populatedScreenshotDirectory = directory.appendingPathComponent("snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: populatedScreenshotDirectory, withIntermediateDirectories: true)
        try Data("png".utf8).write(
            to: populatedScreenshotDirectory.appendingPathComponent("connected-light.png", isDirectory: false)
        )
        let missingReviewBaselineURL = populatedScreenshotDirectory.appendingPathComponent(
            PearchHAReleaseEvidenceReview.expectedBaselineFilename,
            isDirectory: false
        )

        XCTAssertThrowsError(
            try PearchHAReleaseEvidenceWriter().write(
                PearchHAReleaseEvidenceConfiguration(
                    appURL: bundle.appURL,
                    dmgURL: dmgURL,
                    manifestURL: manifestURL,
                    screenshotDirectoryURL: populatedScreenshotDirectory,
                    reviewBaselineURL: missingReviewBaselineURL
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? PearchHAReleaseEvidenceError,
                .reviewBaselineMissing(missingReviewBaselineURL.path)
            )
        }
    }

    func testReleaseEvidenceWriterRejectsMissingRequiredScreenshotNameBeforeWritingManifest() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let bundle = try testBundle(
            in: directory,
            callbackScheme: "pearchha-release-missing-required-screenshot",
            bundleIdentifier: "dev.pearchha.tests.release.missing.required.screenshot"
        )
        let dmgURL = directory.appendingPathComponent("PearchHA.dmg", isDirectory: false)
        try Data("dmg".utf8).write(to: dmgURL)
        let screenshotDirectory = directory.appendingPathComponent("snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true)
        try Data("png".utf8).write(
            to: screenshotDirectory.appendingPathComponent("connected-light.png", isDirectory: false)
        )
        let manifestURL = directory.appendingPathComponent("release-manifest.json", isDirectory: false)

        XCTAssertThrowsError(
            try PearchHAReleaseEvidenceWriter().write(
                PearchHAReleaseEvidenceConfiguration(
                    appURL: bundle.appURL,
                    dmgURL: dmgURL,
                    manifestURL: manifestURL,
                    screenshotDirectoryURL: screenshotDirectory,
                    requiredScreenshotNames: ["connected-light.png", "review-contact-sheet.png"]
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? PearchHAReleaseEvidenceError,
                .requiredScreenshotMissing(name: "review-contact-sheet.png", directory: screenshotDirectory.path)
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: manifestURL.path))
    }

    func testReleaseEvidenceWriterRejectsInvalidSigningAndNotarizationStatus() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let bundle = try testBundle(
            in: directory,
            callbackScheme: "pearchha-release-invalid-status",
            bundleIdentifier: "dev.pearchha.tests.release.invalid.status"
        )
        let dmgURL = directory.appendingPathComponent("PearchHA.dmg", isDirectory: false)
        try Data("dmg".utf8).write(to: dmgURL)
        let screenshotDirectory = directory.appendingPathComponent("snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true)
        try Data("png".utf8).write(
            to: screenshotDirectory.appendingPathComponent("connected-light.png", isDirectory: false)
        )
        let manifestURL = directory.appendingPathComponent("release-manifest.json", isDirectory: false)

        XCTAssertThrowsError(
            try PearchHAReleaseEvidenceWriter().write(
                PearchHAReleaseEvidenceConfiguration(
                    appURL: bundle.appURL,
                    dmgURL: dmgURL,
                    manifestURL: manifestURL,
                    screenshotDirectoryURL: screenshotDirectory,
                    signingIdentity: "-",
                    signatureVerified: true,
                    notarySubmitted: true,
                    stapled: true
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? PearchHAReleaseEvidenceError,
                .invalidReleaseStatus("notarized artifact requires a verified Developer ID Application signature")
            )
        }

        XCTAssertThrowsError(
            try PearchHAReleaseEvidenceWriter().write(
                PearchHAReleaseEvidenceConfiguration(
                    appURL: bundle.appURL,
                    dmgURL: dmgURL,
                    manifestURL: manifestURL,
                    screenshotDirectoryURL: screenshotDirectory,
                    signingIdentity: "Apple Development: PearchHA (TEAMID)",
                    signatureVerified: true,
                    notarySubmitted: true,
                    stapled: false
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? PearchHAReleaseEvidenceError,
                .invalidReleaseStatus("notarized artifact requires a verified Developer ID Application signature")
            )
        }
    }

    func testReleaseEvidenceVerifierAcceptsMatchingManifestAndRejectsStaleArtifacts() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let bundle = try testBundle(
            in: directory,
            callbackScheme: "pearchha-release-verify",
            bundleIdentifier: "dev.pearchha.tests.release.verify"
        )
        let dmgURL = directory.appendingPathComponent("PearchHA.dmg", isDirectory: false)
        try Data("dmg".utf8).write(to: dmgURL)
        let screenshotDirectory = directory.appendingPathComponent("snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true)
        let screenshotURL = screenshotDirectory.appendingPathComponent("connected-light.png", isDirectory: false)
        try Data("png".utf8).write(
            to: screenshotURL
        )
        let oauthSiteURL = directory.appendingPathComponent("oauth-site/index.html", isDirectory: false)
        try FileManager.default.createDirectory(at: oauthSiteURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("oauth-site".utf8).write(to: oauthSiteURL)
        let reviewBaselineURL = screenshotDirectory.appendingPathComponent(
            PearchHAReleaseEvidenceReview.expectedBaselineFilename,
            isDirectory: false
        )
        try Data("baseline".utf8).write(to: reviewBaselineURL)
        let manifestURL = directory.appendingPathComponent("release-manifest.json", isDirectory: false)
        let codesignURL = try fakeExecutable(in: directory, name: "codesign")
        let xcrunURL = try fakeExecutable(in: directory, name: "xcrun")
        let runner = RecordingCommandRunner { executableURL, arguments in
            if arguments.first == "stapler" {
                XCTAssertEqual(executableURL.path, xcrunURL.path)
                XCTAssertEqual(arguments, ["stapler", "validate", dmgURL.path])
                return PearchHACommandResult(status: 0, output: "valid ticket")
            }
            XCTAssertEqual(executableURL.path, codesignURL.path)
            XCTAssertEqual(arguments, ["--verify", "--strict", "--verbose=2", bundle.appURL.path])
            return PearchHACommandResult(status: 0, output: "valid")
        }
        let verifier = PearchHAReleaseEvidenceVerifier(
            codesignURL: codesignURL,
            xcrunURL: xcrunURL,
            commandRunner: runner
        )
        _ = try PearchHAReleaseEvidenceWriter().write(
            PearchHAReleaseEvidenceConfiguration(
                appURL: bundle.appURL,
                dmgURL: dmgURL,
                manifestURL: manifestURL,
                oauthClientWebsiteURL: oauthSiteURL,
                screenshotDirectoryURL: screenshotDirectory,
                reviewBaselineURL: reviewBaselineURL,
                signingIdentity: "Developer ID Application: PearchHA (TEAMID)",
                signatureVerified: true,
                notarySubmitted: true,
                stapled: true
            )
        )

        let report = try verifier.verify(
            PearchHAReleaseEvidenceVerificationConfiguration(manifestURL: manifestURL)
        )

        XCTAssertEqual(report.manifestURL.path, manifestURL.path)
        XCTAssertEqual(report.appURL.path, bundle.appURL.path)
        XCTAssertEqual(report.dmgURL.path, dmgURL.path)
        XCTAssertEqual(report.dmgSHA256, sha256Hex(Data("dmg".utf8)))
        XCTAssertEqual(report.oauthClientWebsiteURL?.path, oauthSiteURL.path)
        XCTAssertEqual(report.screenshotCount, 1)
        XCTAssertTrue(report.credentialedReleaseReady)

        try Data("changed-png".utf8).write(to: screenshotURL)
        XCTAssertThrowsError(
            try verifier.verify(
                PearchHAReleaseEvidenceVerificationConfiguration(manifestURL: manifestURL)
            )
        ) { error in
            XCTAssertEqual(
                error as? PearchHAReleaseEvidenceVerificationError,
                .artifactSHA256Mismatch(
                    path: screenshotURL.path,
                    expected: sha256Hex(Data("png".utf8)),
                    actual: sha256Hex(Data("changed-png".utf8))
                )
            )
        }

        try Data("png".utf8).write(to: screenshotURL)
        try Data("changed-baseline".utf8).write(to: reviewBaselineURL)
        XCTAssertThrowsError(
            try verifier.verify(
                PearchHAReleaseEvidenceVerificationConfiguration(manifestURL: manifestURL)
            )
        ) { error in
            XCTAssertEqual(
                error as? PearchHAReleaseEvidenceVerificationError,
                .artifactSHA256Mismatch(
                    path: reviewBaselineURL.path,
                    expected: sha256Hex(Data("baseline".utf8)),
                    actual: sha256Hex(Data("changed-baseline".utf8))
                )
            )
        }

        try Data("baseline".utf8).write(to: reviewBaselineURL)
        try Data("changed-oauth-site".utf8).write(to: oauthSiteURL)
        XCTAssertThrowsError(
            try verifier.verify(
                PearchHAReleaseEvidenceVerificationConfiguration(manifestURL: manifestURL)
            )
        ) { error in
            XCTAssertEqual(
                error as? PearchHAReleaseEvidenceVerificationError,
                .artifactSHA256Mismatch(
                    path: oauthSiteURL.path,
                    expected: sha256Hex(Data("oauth-site".utf8)),
                    actual: sha256Hex(Data("changed-oauth-site".utf8))
                )
            )
        }

        try Data("oauth-site".utf8).write(to: oauthSiteURL)
        try Data("changed-dmg".utf8).write(to: dmgURL)
        XCTAssertThrowsError(
            try verifier.verify(
                PearchHAReleaseEvidenceVerificationConfiguration(manifestURL: manifestURL)
            )
        ) { error in
            XCTAssertEqual(
                error as? PearchHAReleaseEvidenceVerificationError,
                .artifactSHA256Mismatch(
                    path: dmgURL.path,
                    expected: sha256Hex(Data("dmg".utf8)),
                    actual: sha256Hex(Data("changed-dmg".utf8))
                )
            )
        }
        XCTAssertEqual(runner.invocations.count, 10)
    }

    func testReleaseEvidenceVerifierAcceptsRelocatedRelativeManifestBundle() throws {
        let directory = temporaryDirectory()
        let relocatedDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: relocatedDirectory)
        }
        let bundle = try testBundle(
            in: directory,
            callbackScheme: "pearchha-release-relocated",
            bundleIdentifier: "dev.pearchha.tests.release.relocated"
        )
        let dmgURL = directory.appendingPathComponent("PearchHA.dmg", isDirectory: false)
        try Data("dmg".utf8).write(to: dmgURL)
        let screenshotDirectory = directory.appendingPathComponent("pearchha-snapshots/current", isDirectory: true)
        try FileManager.default.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true)
        try Data("png".utf8).write(
            to: screenshotDirectory.appendingPathComponent("connected-light.png", isDirectory: false)
        )
        let oauthSiteURL = directory.appendingPathComponent("pearchha-oauth-site/index.html", isDirectory: false)
        try FileManager.default.createDirectory(at: oauthSiteURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("oauth-site".utf8).write(to: oauthSiteURL)
        let manifestURL = directory.appendingPathComponent("pearchha-release-manifest.json", isDirectory: false)

        let manifest = try PearchHAReleaseEvidenceWriter().write(
            PearchHAReleaseEvidenceConfiguration(
                appURL: bundle.appURL,
                dmgURL: dmgURL,
                manifestURL: manifestURL,
                oauthClientWebsiteURL: oauthSiteURL,
                screenshotDirectoryURL: screenshotDirectory,
                requiredScreenshotNames: ["connected-light.png"]
            )
        )
        XCTAssertEqual(manifest.app.path, "PearchHA.app")
        XCTAssertEqual(manifest.dmg.path, "PearchHA.dmg")
        XCTAssertEqual(manifest.oauthClientWebsite?.path, "pearchha-oauth-site/index.html")
        XCTAssertEqual(manifest.screenshots.first?.path, "pearchha-snapshots/current/connected-light.png")

        try FileManager.default.createDirectory(at: relocatedDirectory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: bundle.appURL, to: relocatedDirectory.appendingPathComponent("PearchHA.app", isDirectory: true))
        try FileManager.default.copyItem(at: dmgURL, to: relocatedDirectory.appendingPathComponent("PearchHA.dmg", isDirectory: false))
        try FileManager.default.copyItem(
            at: oauthSiteURL.deletingLastPathComponent(),
            to: relocatedDirectory.appendingPathComponent("pearchha-oauth-site", isDirectory: true)
        )
        try FileManager.default.copyItem(
            at: screenshotDirectory.deletingLastPathComponent(),
            to: relocatedDirectory.appendingPathComponent("pearchha-snapshots", isDirectory: true)
        )
        let relocatedManifestURL = relocatedDirectory.appendingPathComponent("pearchha-release-manifest.json", isDirectory: false)
        try FileManager.default.copyItem(at: manifestURL, to: relocatedManifestURL)

        let report = try PearchHAReleaseEvidenceVerifier().verify(
            PearchHAReleaseEvidenceVerificationConfiguration(
                manifestURL: relocatedManifestURL,
                requiredScreenshotNames: ["connected-light.png"]
            )
        )

        XCTAssertEqual(report.manifestURL.path, relocatedManifestURL.path)
        XCTAssertEqual(report.appURL.path, relocatedDirectory.appendingPathComponent("PearchHA.app", isDirectory: true).path)
        XCTAssertEqual(report.dmgURL.path, relocatedDirectory.appendingPathComponent("PearchHA.dmg", isDirectory: false).path)
        XCTAssertEqual(report.oauthClientWebsiteURL?.path, relocatedDirectory.appendingPathComponent("pearchha-oauth-site/index.html", isDirectory: false).path)
        XCTAssertEqual(report.screenshotCount, 1)
        XCTAssertFalse(report.credentialedReleaseReady)
    }

    func testReleaseEvidenceBundlerCopiesPortableBundleAndVerifierAcceptsCopiedManifest() throws {
        let directory = temporaryDirectory()
        let bundledDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: bundledDirectory)
        }
        let bundle = try testBundle(
            in: directory,
            callbackScheme: "pearchha-release-bundle",
            bundleIdentifier: "dev.pearchha.tests.release.bundle"
        )
        let dmgURL = directory.appendingPathComponent("PearchHA.dmg", isDirectory: false)
        try Data("dmg".utf8).write(to: dmgURL)
        let oauthSiteURL = directory.appendingPathComponent("pearchha-oauth-site/index.html", isDirectory: false)
        try FileManager.default.createDirectory(at: oauthSiteURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("oauth-site".utf8).write(to: oauthSiteURL)
        let screenshotDirectory = directory.appendingPathComponent("pearchha-snapshots/current", isDirectory: true)
        try FileManager.default.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true)
        try Data("png".utf8).write(
            to: screenshotDirectory.appendingPathComponent("connected-light.png", isDirectory: false)
        )
        let expectedBaselineURL = screenshotDirectory.appendingPathComponent(
            PearchHAReleaseEvidenceReview.expectedBaselineFilename,
            isDirectory: false
        )
        let currentBaselineURL = screenshotDirectory.appendingPathComponent(
            PearchHAReleaseEvidenceReview.currentBaselineFilename,
            isDirectory: false
        )
        try Data("expected-baseline".utf8).write(to: expectedBaselineURL)
        try Data("current-baseline".utf8).write(to: currentBaselineURL)
        let manifestURL = directory.appendingPathComponent("pearchha-release-manifest.json", isDirectory: false)
        _ = try PearchHAReleaseEvidenceWriter().write(
            PearchHAReleaseEvidenceConfiguration(
                appURL: bundle.appURL,
                dmgURL: dmgURL,
                manifestURL: manifestURL,
                oauthClientWebsiteURL: oauthSiteURL,
                screenshotDirectoryURL: screenshotDirectory,
                reviewBaselineURL: expectedBaselineURL,
                requiredScreenshotNames: ["connected-light.png"]
            )
        )

        let result = try PearchHAReleaseEvidenceBundler().bundle(
            PearchHAReleaseEvidenceBundleConfiguration(
                manifestURL: manifestURL,
                outputDirectoryURL: bundledDirectory,
                replaceExisting: true
            )
        )
        let report = try PearchHAReleaseEvidenceVerifier().verify(
            PearchHAReleaseEvidenceVerificationConfiguration(
                manifestURL: result.manifestURL,
                requiredScreenshotNames: ["connected-light.png"]
            )
        )

        XCTAssertEqual(result.bundleDirectoryURL.path, bundledDirectory.path)
        XCTAssertEqual(result.manifestURL.path, bundledDirectory.appendingPathComponent("pearchha-release-manifest.json", isDirectory: false).path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundledDirectory.appendingPathComponent("PearchHA.app", isDirectory: true).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundledDirectory.appendingPathComponent("PearchHA.dmg", isDirectory: false).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundledDirectory.appendingPathComponent("pearchha-oauth-site/index.html", isDirectory: false).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundledDirectory.appendingPathComponent("pearchha-snapshots/current/connected-light.png", isDirectory: false).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundledDirectory.appendingPathComponent("pearchha-snapshots/current/review-baseline-expected.json", isDirectory: false).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundledDirectory.appendingPathComponent("pearchha-snapshots/current/review-baseline-current.json", isDirectory: false).path))
        XCTAssertEqual(report.appURL.path, bundledDirectory.appendingPathComponent("PearchHA.app", isDirectory: true).path)
        XCTAssertEqual(report.dmgURL.path, bundledDirectory.appendingPathComponent("PearchHA.dmg", isDirectory: false).path)
        XCTAssertEqual(report.oauthClientWebsiteURL?.path, bundledDirectory.appendingPathComponent("pearchha-oauth-site/index.html", isDirectory: false).path)
    }

    func testReleaseEvidenceBundlerRewritesEscapingRelativePathsInsidePortableBundle() throws {
        let directory = temporaryDirectory()
        let bundledDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: bundledDirectory)
        }
        let bundle = try testBundle(
            in: directory,
            callbackScheme: "pearchha-release-bundle-nested",
            bundleIdentifier: "dev.pearchha.tests.release.bundle.nested"
        )
        let dmgURL = directory.appendingPathComponent("PearchHA.dmg", isDirectory: false)
        try Data("dmg".utf8).write(to: dmgURL)
        let oauthSiteURL = directory.appendingPathComponent("pearchha-oauth-site/index.html", isDirectory: false)
        try FileManager.default.createDirectory(at: oauthSiteURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("oauth-site".utf8).write(to: oauthSiteURL)
        let screenshotDirectory = directory.appendingPathComponent("pearchha-snapshots/current", isDirectory: true)
        try FileManager.default.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true)
        try Data("png".utf8).write(
            to: screenshotDirectory.appendingPathComponent("connected-light.png", isDirectory: false)
        )
        let expectedBaselineURL = screenshotDirectory.appendingPathComponent(
            PearchHAReleaseEvidenceReview.expectedBaselineFilename,
            isDirectory: false
        )
        try Data("expected-baseline".utf8).write(to: expectedBaselineURL)
        let manifestDirectory = directory.appendingPathComponent("release/evidence", isDirectory: true)
        try FileManager.default.createDirectory(at: manifestDirectory, withIntermediateDirectories: true)
        let manifestURL = manifestDirectory.appendingPathComponent("pearchha-release-manifest.json", isDirectory: false)
        let manifest = try PearchHAReleaseEvidenceWriter().write(
            PearchHAReleaseEvidenceConfiguration(
                appURL: bundle.appURL,
                dmgURL: dmgURL,
                manifestURL: manifestURL,
                oauthClientWebsiteURL: oauthSiteURL,
                screenshotDirectoryURL: screenshotDirectory,
                reviewBaselineURL: expectedBaselineURL,
                requiredScreenshotNames: ["connected-light.png"]
            )
        )

        XCTAssertEqual(manifest.app.path, "../../PearchHA.app")
        XCTAssertEqual(manifest.dmg.path, "../../PearchHA.dmg")
        XCTAssertEqual(manifest.oauthClientWebsite?.path, "../../pearchha-oauth-site/index.html")
        XCTAssertEqual(manifest.screenshots.first?.path, "../../pearchha-snapshots/current/connected-light.png")

        let result = try PearchHAReleaseEvidenceBundler().bundle(
            PearchHAReleaseEvidenceBundleConfiguration(
                manifestURL: manifestURL,
                outputDirectoryURL: bundledDirectory,
                replaceExisting: true
            )
        )
        let bundledManifest = try JSONDecoder().decode(
            PearchHAReleaseEvidenceManifest.self,
            from: Data(contentsOf: result.manifestURL)
        )
        let report = try PearchHAReleaseEvidenceVerifier().verify(
            PearchHAReleaseEvidenceVerificationConfiguration(
                manifestURL: result.manifestURL,
                requiredScreenshotNames: ["connected-light.png"]
            )
        )

        XCTAssertEqual(bundledManifest.app.path, "PearchHA.app")
        XCTAssertEqual(bundledManifest.dmg.path, "PearchHA.dmg")
        XCTAssertEqual(bundledManifest.oauthClientWebsite?.path, "pearchha-oauth-site/index.html")
        XCTAssertEqual(bundledManifest.screenshots.first?.path, "pearchha-snapshots/current/connected-light.png")
        XCTAssertEqual(bundledManifest.reviewBaseline?.path, "pearchha-snapshots/current/review-baseline-expected.json")
        XCTAssertFalse(bundledManifest.app.path.contains(".."))
        XCTAssertFalse(bundledManifest.dmg.path.contains(".."))
        XCTAssertFalse(bundledManifest.screenshots.contains { $0.path.contains("..") })
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundledDirectory.appendingPathComponent("PearchHA.app", isDirectory: true).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundledDirectory.appendingPathComponent("PearchHA.dmg", isDirectory: false).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundledDirectory.appendingPathComponent("pearchha-oauth-site/index.html", isDirectory: false).path))
        XCTAssertEqual(report.appURL.path, bundledDirectory.appendingPathComponent("PearchHA.app", isDirectory: true).path)
        XCTAssertEqual(report.dmgURL.path, bundledDirectory.appendingPathComponent("PearchHA.dmg", isDirectory: false).path)
        XCTAssertEqual(report.oauthClientWebsiteURL?.path, bundledDirectory.appendingPathComponent("pearchha-oauth-site/index.html", isDirectory: false).path)
    }

    func testReleaseEvidenceBundlerRefusesToOverwriteWithoutReplace() throws {
        let directory = temporaryDirectory()
        let bundledDirectory = temporaryDirectory()
        try FileManager.default.createDirectory(at: bundledDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: bundledDirectory)
        }
        let bundle = try testBundle(
            in: directory,
            callbackScheme: "pearchha-release-bundle-existing",
            bundleIdentifier: "dev.pearchha.tests.release.bundle.existing"
        )
        let dmgURL = directory.appendingPathComponent("PearchHA.dmg", isDirectory: false)
        try Data("dmg".utf8).write(to: dmgURL)
        let screenshotDirectory = directory.appendingPathComponent("snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true)
        try Data("png".utf8).write(
            to: screenshotDirectory.appendingPathComponent("connected-light.png", isDirectory: false)
        )
        let manifestURL = directory.appendingPathComponent("pearchha-release-manifest.json", isDirectory: false)
        _ = try PearchHAReleaseEvidenceWriter().write(
            PearchHAReleaseEvidenceConfiguration(
                appURL: bundle.appURL,
                dmgURL: dmgURL,
                manifestURL: manifestURL,
                screenshotDirectoryURL: screenshotDirectory
            )
        )

        XCTAssertThrowsError(
            try PearchHAReleaseEvidenceBundler().bundle(
                PearchHAReleaseEvidenceBundleConfiguration(
                    manifestURL: manifestURL,
                    outputDirectoryURL: bundledDirectory
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? PearchHAReleaseEvidenceBundleError,
                .outputExists(bundledDirectory.path)
            )
        }
    }

    func testReleaseEvidenceVerifierRejectsMissingRequiredScreenshotName() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let bundle = try testBundle(
            in: directory,
            callbackScheme: "pearchha-release-required-screenshot",
            bundleIdentifier: "dev.pearchha.tests.release.required.screenshot"
        )
        let dmgURL = directory.appendingPathComponent("PearchHA.dmg", isDirectory: false)
        try Data("dmg".utf8).write(to: dmgURL)
        let screenshotDirectory = directory.appendingPathComponent("snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true)
        try Data("png".utf8).write(
            to: screenshotDirectory.appendingPathComponent("connected-light.png", isDirectory: false)
        )
        let manifestURL = directory.appendingPathComponent("release-manifest.json", isDirectory: false)
        _ = try PearchHAReleaseEvidenceWriter().write(
            PearchHAReleaseEvidenceConfiguration(
                appURL: bundle.appURL,
                dmgURL: dmgURL,
                manifestURL: manifestURL,
                screenshotDirectoryURL: screenshotDirectory
            )
        )
        let verifier = PearchHAReleaseEvidenceVerifier()

        let report = try verifier.verify(
            PearchHAReleaseEvidenceVerificationConfiguration(
                manifestURL: manifestURL,
                requiredScreenshotNames: [" connected-light.png ", "connected-light.png"]
            )
        )
        XCTAssertEqual(report.screenshotCount, 1)

        XCTAssertThrowsError(
            try verifier.verify(
                PearchHAReleaseEvidenceVerificationConfiguration(
                    manifestURL: manifestURL,
                    requiredScreenshotNames: ["connected-light.png", "review-contact-sheet.png"]
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? PearchHAReleaseEvidenceVerificationError,
                .requiredScreenshotMissing(name: "review-contact-sheet.png", manifest: manifestURL.path)
            )
        }
    }

    func testReleaseEvidenceVerifierRejectsRecordedSignatureThatNoLongerVerifies() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let bundle = try testBundle(
            in: directory,
            callbackScheme: "pearchha-release-signature",
            bundleIdentifier: "dev.pearchha.tests.release.signature"
        )
        let dmgURL = directory.appendingPathComponent("PearchHA.dmg", isDirectory: false)
        try Data("dmg".utf8).write(to: dmgURL)
        let screenshotDirectory = directory.appendingPathComponent("snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true)
        try Data("png".utf8).write(
            to: screenshotDirectory.appendingPathComponent("connected-light.png", isDirectory: false)
        )
        let manifestURL = directory.appendingPathComponent("release-manifest.json", isDirectory: false)
        _ = try PearchHAReleaseEvidenceWriter().write(
            PearchHAReleaseEvidenceConfiguration(
                appURL: bundle.appURL,
                dmgURL: dmgURL,
                manifestURL: manifestURL,
                screenshotDirectoryURL: screenshotDirectory,
                signingIdentity: "-",
                signatureVerified: true
            )
        )
        let codesignURL = try fakeExecutable(in: directory, name: "codesign")
        let runner = RecordingCommandRunner { _, arguments in
            XCTAssertEqual(arguments, ["--verify", "--strict", "--verbose=2", bundle.appURL.path])
            return PearchHACommandResult(status: 1, output: "signature changed")
        }

        XCTAssertThrowsError(
            try PearchHAReleaseEvidenceVerifier(codesignURL: codesignURL, commandRunner: runner).verify(
                PearchHAReleaseEvidenceVerificationConfiguration(manifestURL: manifestURL)
            )
        ) { error in
            XCTAssertEqual(
                error as? PearchHAReleaseEvidenceVerificationError,
                .codeSignatureVerificationFailed(
                    "codesign verify failed with status 1: signature changed"
                )
            )
        }
        XCTAssertEqual(runner.invocations.count, 1)
    }

    func testReleaseEvidenceVerifierRejectsRecordedStapledArtifactThatNoLongerValidates() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let bundle = try testBundle(
            in: directory,
            callbackScheme: "pearchha-release-staple",
            bundleIdentifier: "dev.pearchha.tests.release.staple"
        )
        let dmgURL = directory.appendingPathComponent("PearchHA.dmg", isDirectory: false)
        try Data("dmg".utf8).write(to: dmgURL)
        let screenshotDirectory = directory.appendingPathComponent("snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true)
        try Data("png".utf8).write(
            to: screenshotDirectory.appendingPathComponent("connected-light.png", isDirectory: false)
        )
        let manifestURL = directory.appendingPathComponent("release-manifest.json", isDirectory: false)
        _ = try PearchHAReleaseEvidenceWriter().write(
            PearchHAReleaseEvidenceConfiguration(
                appURL: bundle.appURL,
                dmgURL: dmgURL,
                manifestURL: manifestURL,
                screenshotDirectoryURL: screenshotDirectory,
                signingIdentity: "Developer ID Application: PearchHA (TEAMID)",
                signatureVerified: true,
                notarySubmitted: true,
                stapled: true
            )
        )
        let codesignURL = try fakeExecutable(in: directory, name: "codesign")
        let xcrunURL = try fakeExecutable(in: directory, name: "xcrun")
        let runner = RecordingCommandRunner { _, arguments in
            arguments.first == "stapler"
                ? PearchHACommandResult(status: 65, output: "ticket changed")
                : PearchHACommandResult(status: 0, output: "valid signature")
        }

        XCTAssertThrowsError(
            try PearchHAReleaseEvidenceVerifier(
                codesignURL: codesignURL,
                xcrunURL: xcrunURL,
                commandRunner: runner
            ).verify(
                PearchHAReleaseEvidenceVerificationConfiguration(manifestURL: manifestURL)
            )
        ) { error in
            XCTAssertEqual(
                error as? PearchHAReleaseEvidenceVerificationError,
                .staplerValidationFailed(status: 65, output: "ticket changed")
            )
        }
        XCTAssertEqual(runner.invocations.count, 2)
    }

    func testReleaseEvidenceVerifierRejectsMissingScreenshotsAndInvalidReleaseStatus() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let bundle = try testBundle(
            in: directory,
            callbackScheme: "pearchha-release-status",
            bundleIdentifier: "dev.pearchha.tests.release.status"
        )
        let dmgURL = directory.appendingPathComponent("PearchHA.dmg", isDirectory: false)
        try Data("dmg".utf8).write(to: dmgURL)
        let screenshotDirectory = directory.appendingPathComponent("snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true)
        try Data("png".utf8).write(
            to: screenshotDirectory.appendingPathComponent("connected-light.png", isDirectory: false)
        )
        let manifestURL = directory.appendingPathComponent("release-manifest.json", isDirectory: false)
        _ = try PearchHAReleaseEvidenceWriter().write(
            PearchHAReleaseEvidenceConfiguration(
                appURL: bundle.appURL,
                dmgURL: dmgURL,
                manifestURL: manifestURL,
                screenshotDirectoryURL: screenshotDirectory,
                signingIdentity: "-",
                signatureVerified: true
            )
        )

        var manifestObject = try jsonObject(from: manifestURL)
        manifestObject["screenshots"] = []
        try writeJSONObject(manifestObject, to: manifestURL)
        XCTAssertThrowsError(
            try PearchHAReleaseEvidenceVerifier().verify(
                PearchHAReleaseEvidenceVerificationConfiguration(manifestURL: manifestURL)
            )
        ) { error in
            XCTAssertEqual(
                error as? PearchHAReleaseEvidenceVerificationError,
                .screenshotsMissing(manifestURL.path)
            )
        }

        manifestObject = try jsonObject(from: manifestURL)
        manifestObject["screenshots"] = [
            [
                "name": "connected-light.png",
                "path": screenshotDirectory.appendingPathComponent("connected-light.png").path,
                "sha256": sha256Hex(Data("png".utf8)),
                "byteCount": 3
            ]
        ]
        manifestObject["notarization"] = ["submitted": true, "stapled": false]
        try writeJSONObject(manifestObject, to: manifestURL)
        XCTAssertThrowsError(
            try PearchHAReleaseEvidenceVerifier().verify(
                PearchHAReleaseEvidenceVerificationConfiguration(manifestURL: manifestURL)
            )
        ) { error in
            XCTAssertEqual(
                error as? PearchHAReleaseEvidenceVerificationError,
                .invalidReleaseStatus("notarized artifact requires a verified Developer ID Application signature")
            )
        }
    }

    func testReleaseEvidenceVerifierRejectsMissingManifestAndChangedAppMetadata() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let missingManifestURL = directory.appendingPathComponent("missing-release-manifest.json", isDirectory: false)

        XCTAssertThrowsError(
            try PearchHAReleaseEvidenceVerifier().verify(
                PearchHAReleaseEvidenceVerificationConfiguration(manifestURL: missingManifestURL)
            )
        ) { error in
            XCTAssertEqual(
                error as? PearchHAReleaseEvidenceVerificationError,
                .manifestMissing(missingManifestURL.path)
            )
        }

        let bundle = try testBundle(
            in: directory,
            callbackScheme: "pearchha-release-metadata",
            bundleIdentifier: "dev.pearchha.tests.release.metadata"
        )
        let dmgURL = directory.appendingPathComponent("PearchHA.dmg", isDirectory: false)
        try Data("dmg".utf8).write(to: dmgURL)
        let screenshotDirectory = directory.appendingPathComponent("snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true)
        try Data("png".utf8).write(
            to: screenshotDirectory.appendingPathComponent("connected-light.png", isDirectory: false)
        )
        let manifestURL = directory.appendingPathComponent("release-manifest.json", isDirectory: false)
        _ = try PearchHAReleaseEvidenceWriter().write(
            PearchHAReleaseEvidenceConfiguration(
                appURL: bundle.appURL,
                dmgURL: dmgURL,
                manifestURL: manifestURL,
                screenshotDirectoryURL: screenshotDirectory,
                signingIdentity: "-",
                signatureVerified: true
            )
        )
        var plist = try propertyList(from: Data(contentsOf: bundle.infoPlistURL))
        plist["CFBundleVersion"] = "2"
        let rewritten = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try rewritten.write(to: bundle.infoPlistURL, options: .atomic)

        XCTAssertThrowsError(
            try PearchHAReleaseEvidenceVerifier().verify(
                PearchHAReleaseEvidenceVerificationConfiguration(manifestURL: manifestURL)
            )
        ) { error in
            XCTAssertEqual(
                error as? PearchHAReleaseEvidenceVerificationError,
                .appMetadataMismatch(field: "buildVersion", expected: "1", actual: "2")
            )
        }
    }

    func testLaunchServicesVerifierRegistersBundleAndClaimsCallbackScheme() throws {
        let uniqueID = UUID().uuidString.lowercased()
        let executableURL = URL(fileURLWithPath: "/usr/bin/true", isDirectory: false)
        let outputURL = launchServicesAppURL(uniqueID: uniqueID)
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }
        let scheme = "pearchha-test-\(uniqueID)"
        let bundleID = "dev.pearchha.tests.\(uniqueID.replacingOccurrences(of: "-", with: ""))"
        let bundle = try PearchHAAppBundleBuilder().build(
            PearchHAAppBundleBuildConfiguration(
                executableURL: executableURL,
                outputURL: outputURL,
                manifest: try PearchHAAppBundleManifest(
                    bundleIdentifier: bundleID,
                    callbackURLScheme: scheme
                )
            )
        )
        defer {
            unregisterBundle(at: bundle.appURL)
        }

        let result = try PearchHALaunchServicesVerifier().verify(
            PearchHALaunchServicesVerificationConfiguration(
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
        let executableURL = directory.appendingPathComponent("PearchHA-source", isDirectory: false)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        let outputURL = directory.appendingPathComponent("PearchHA.app", isDirectory: true)
        let bundle = try PearchHAAppBundleBuilder().build(
            PearchHAAppBundleBuildConfiguration(
                executableURL: executableURL,
                outputURL: outputURL,
                manifest: try PearchHAAppBundleManifest(callbackURLScheme: "pearchha-present")
            )
        )

        XCTAssertThrowsError(
            try PearchHALaunchServicesVerifier().verify(
                PearchHALaunchServicesVerificationConfiguration(
                    appURL: bundle.appURL,
                    callbackURLScheme: "pearchha-missing",
                    registerBundle: false
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? PearchHALaunchServicesVerificationError,
                .callbackSchemeMissing("pearchha-missing")
            )
        }
    }

    func testLaunchServicesVerifierRejectsBundleWithoutCallbackRole() throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executableURL = directory.appendingPathComponent("PearchHA-source", isDirectory: false)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        let outputURL = directory.appendingPathComponent("PearchHA.app", isDirectory: true)
        let bundle = try PearchHAAppBundleBuilder().build(
            PearchHAAppBundleBuildConfiguration(
                executableURL: executableURL,
                outputURL: outputURL,
                manifest: try PearchHAAppBundleManifest(callbackURLScheme: "pearchha-present")
            )
        )
        var plist = try propertyList(from: Data(contentsOf: bundle.infoPlistURL))
        var urlTypes = try XCTUnwrap(plist["CFBundleURLTypes"] as? [[String: Any]])
        urlTypes[0].removeValue(forKey: "CFBundleTypeRole")
        plist["CFBundleURLTypes"] = urlTypes
        let rewritten = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try rewritten.write(to: bundle.infoPlistURL, options: .atomic)

        XCTAssertThrowsError(
            try PearchHALaunchServicesVerifier().verify(
                PearchHALaunchServicesVerificationConfiguration(
                    appURL: bundle.appURL,
                    callbackURLScheme: "pearchha-present",
                    registerBundle: false
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? PearchHALaunchServicesVerificationError,
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
            callbackScheme: "pearchha-dump-role",
            bundleIdentifier: "dev.pearchha.tests.dump.role"
        )
        let toolURL = try fakeLaunchServicesTool(
            in: directory,
            output: launchServicesDump(
                appPath: bundle.appURL.standardizedFileURL.resolvingSymlinksInPath().path,
                scheme: "pearchha-dump-role",
                claimRole: "Editor"
            )
        )

        XCTAssertThrowsError(
            try PearchHALaunchServicesVerifier(toolURL: toolURL).verify(
                PearchHALaunchServicesVerificationConfiguration(
                    appURL: bundle.appURL,
                    callbackURLScheme: "pearchha-dump-role"
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? PearchHALaunchServicesVerificationError,
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
            callbackScheme: "pearchha-dump-scheme",
            bundleIdentifier: "dev.pearchha.tests.dump.scheme"
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
            try PearchHALaunchServicesVerifier(toolURL: toolURL).verify(
                PearchHALaunchServicesVerificationConfiguration(
                    appURL: bundle.appURL,
                    callbackURLScheme: "pearchha-dump-scheme"
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? PearchHALaunchServicesVerificationError,
                .launchServicesSchemeMissing("pearchha-dump-scheme")
            )
        }
    }

    private func propertyList(from data: Data) throws -> [String: Any] {
        let value = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try XCTUnwrap(value as? [String: Any])
    }

    private func jsonObject(from url: URL) throws -> [String: Any] {
        let value = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        return try XCTUnwrap(value as? [String: Any])
    }

    private func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url, options: .atomic)
    }

    private func testBundle(
        in directory: URL,
        callbackScheme: String,
        bundleIdentifier: String
    ) throws -> PearchHAAppBundleBuildResult {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executableURL = directory.appendingPathComponent("PearchHA-source", isDirectory: false)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        return try PearchHAAppBundleBuilder().build(
            PearchHAAppBundleBuildConfiguration(
                executableURL: executableURL,
                outputURL: directory.appendingPathComponent("PearchHA.app", isDirectory: true),
                manifest: try PearchHAAppBundleManifest(
                    bundleIdentifier: bundleIdentifier,
                    callbackURLScheme: callbackScheme
                )
            )
        )
    }

    private func testXcodeProject(in directory: URL, schemeName: String) throws -> URL {
        let projectURL = directory.appendingPathComponent("PearchHA.xcodeproj", isDirectory: true)
        let schemeDirectoryURL = projectURL
            .appendingPathComponent("xcshareddata", isDirectory: true)
            .appendingPathComponent("xcschemes", isDirectory: true)
        try FileManager.default.createDirectory(at: schemeDirectoryURL, withIntermediateDirectories: true)
        try Data("// !$*UTF8*$!\n".utf8).write(
            to: projectURL.appendingPathComponent("project.pbxproj", isDirectory: false)
        )
        try Data("<Scheme />\n".utf8).write(
            to: schemeDirectoryURL.appendingPathComponent("\(schemeName).xcscheme", isDirectory: false)
        )
        return projectURL
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

    private func fakeExecutable(in directory: URL, name: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let toolURL = directory.appendingPathComponent(name, isDirectory: false)
        try "#!/bin/sh\nexit 0\n".write(to: toolURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: toolURL.path)
        return toolURL
    }

    private func makeDiscoveredXcodeDeveloperDirectory(in directory: URL, appName: String) throws -> URL {
        let developerDirectory = directory
            .appendingPathComponent(appName, isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Developer", isDirectory: true)
        let xcodebuildURL = developerDirectory
            .appendingPathComponent("usr", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("xcodebuild", isDirectory: false)
        try FileManager.default.createDirectory(at: xcodebuildURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\nexit 0\n".write(to: xcodebuildURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: xcodebuildURL.path)
        return developerDirectory
    }

    private func launchServicesDump(appPath: String, scheme: String, claimRole: String) -> String {
        """
        ---------------------------------------------------------------------------------
        bundle id:                  PearchHA (0x1)
        path:                       \(appPath) (0x2)
        identifier:                 dev.pearchha.tests
        claimed schemes:            \(scheme):
        ---------------------------------------------------------------------------------
        claim id:                   unrelated (0x3)
        roles:                      Viewer (0000000000000002)
        bindings:                   unrelated:
        ---------------------------------------------------------------------------------
        claim id:                   dev.pearchha.tests.oauth (0x4)
        flags:                      url-type (0000000000000040)
        roles:                      \(claimRole) (0000000000000004)
        bindings:                   \(scheme):
        ---------------------------------------------------------------------------------
        """
    }

    private func temporaryDirectory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pearchha-packaging-test-\(UUID().uuidString)", isDirectory: true)
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func launchServicesAppURL(uniqueID: String) -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/pearchha-packaging-test-\(uniqueID).app", isDirectory: true)
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

private final class RecordingCommandRunner: PearchHACommandRunning, @unchecked Sendable {
    struct Invocation: Equatable {
        let executableURL: URL
        let arguments: [String]
    }

    private let handler: @Sendable (URL, [String]) throws -> PearchHACommandResult
    private(set) var invocations: [Invocation] = []

    init(handler: @escaping @Sendable (URL, [String]) throws -> PearchHACommandResult) {
        self.handler = handler
    }

    func run(executableURL: URL, arguments: [String]) throws -> PearchHACommandResult {
        invocations.append(Invocation(executableURL: executableURL, arguments: arguments))
        return try handler(executableURL, arguments)
    }
}

private final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func set(_ newValue: Value) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> Value {
        lock.lock()
        let currentValue = value
        lock.unlock()
        return currentValue
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
#endif
