#if canImport(XCTest)
import XCTest
import PerchHARepoAudit

final class PerchHARepoAuditTests: XCTestCase {
    func testRepositoryAuditAcceptsCleanRepository() throws {
        let repository = try temporaryGitRepository()
        defer { try? FileManager.default.removeItem(at: repository) }

        let result = runRepoAudit(rootURL: repository)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("Repository audit passed."))
    }

    func testRepositoryAuditAllowsExampleEnvironmentFile() throws {
        let repository = try temporaryGitRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        try writeFile(".env.example", contents: "token=\n", in: repository)
        try git(["add", ".env.example"], in: repository)

        let result = runRepoAudit(rootURL: repository)

        XCTAssertEqual(result.exitCode, 0)
    }

    func testRepositoryAuditAllowsDocumentationMentionOfNoTelemetry() throws {
        let repository = try temporaryGitRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        try writeFile("README.md", contents: "No telemetry by default.\n", in: repository)
        try git(["add", "README.md"], in: repository)

        let result = runRepoAudit(rootURL: repository)

        XCTAssertEqual(result.exitCode, 0)
    }

    func testRepositoryAuditRejectsTrackedLocalEnvironmentFile() throws {
        let repository = try temporaryGitRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        try writeFile(".env.local", contents: "token=do-not-commit\n", in: repository)
        try git(["add", "-f", ".env.local"], in: repository)

        let result = runRepoAudit(rootURL: repository)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.errorText.contains(".env.local: local environment files must stay ignored"))
    }

    func testRepositoryAuditRejectsUnignoredLocalEnvironmentFile() throws {
        let repository = try temporaryGitRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        try writeFile(".env.local", contents: "token=do-not-commit\n", in: repository)

        let result = runRepoAudit(rootURL: repository)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.errorText.contains(".env.local: local environment files must stay ignored"))
    }

    func testRepositoryAuditRejectsPrivateFixtureCapture() throws {
        let repository = try temporaryGitRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        try writeProtectedPath("Fixtures/private/capture.json", contents: #"{"private":true}"#, in: repository, addToIndex: true)

        let result = runRepoAudit(rootURL: repository)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.errorText.contains("Fixtures/private/capture.json: private fixture captures must stay ignored"))
    }

    func testRepositoryAuditRejectsUnignoredPrivateFixtureCapture() throws {
        let repository = try temporaryGitRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        try writeProtectedPath("Fixtures/private/capture.json", contents: #"{"private":true}"#, in: repository, addToIndex: false)

        let result = runRepoAudit(rootURL: repository)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.errorText.contains("Fixtures/private/capture.json: private fixture captures must stay ignored"))
    }

    func testRepositoryAuditRejectsBuildOutput() throws {
        let repository = try temporaryGitRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        try writeProtectedPath(".build/output.txt", contents: "build output\n", in: repository, addToIndex: true)

        let result = runRepoAudit(rootURL: repository)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.errorText.contains(".build/output.txt: build output must stay ignored"))
    }

    func testRepositoryAuditRejectsUnignoredBuildOutput() throws {
        let repository = try temporaryGitRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        try writeProtectedPath(".build/output.txt", contents: "build output\n", in: repository, addToIndex: false)

        let result = runRepoAudit(rootURL: repository)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.errorText.contains(".build/output.txt: build output must stay ignored"))
    }

    func testRepositoryAuditRejectsCredentialArtifacts() throws {
        let repository = try temporaryGitRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        try writeProtectedPath("keys/AuthKey_TEST.p8", contents: "private key\n", in: repository, addToIndex: true)

        let result = runRepoAudit(rootURL: repository)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.errorText.contains("keys/AuthKey_TEST.p8: credential artifact must not be committed"))
    }

    func testRepositoryAuditRejectsUnignoredCredentialArtifacts() throws {
        let repository = try temporaryGitRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        try writeProtectedPath("keys/AuthKey_TEST.p8", contents: "private key\n", in: repository, addToIndex: false)

        let result = runRepoAudit(rootURL: repository)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.errorText.contains("keys/AuthKey_TEST.p8: credential artifact must not be committed"))
    }

    func testRepositoryAuditRejectsPrivateKeyMaterial() throws {
        let repository = try temporaryGitRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        try writeProtectedPath("keys/id_ed25519", contents: "private key\n", in: repository, addToIndex: true)

        let result = runRepoAudit(rootURL: repository)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.errorText.contains("keys/id_ed25519: private key material must not be committed"))
    }

    func testRepositoryAuditRejectsTelemetrySDKImports() throws {
        let repository = try temporaryGitRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        try writeFile("Sources/App/Telemetry.swift", contents: ["import", "Sentry"].joined(separator: " ") + "\n", in: repository)
        try git(["add", "Sources/App/Telemetry.swift"], in: repository)

        let result = runRepoAudit(rootURL: repository)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.errorText.contains("Sources/App/Telemetry.swift: telemetry SDK import must not be present by default"))
    }

    func testRepositoryAuditRejectsAttributedTelemetrySDKImports() throws {
        let repository = try temporaryGitRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        try writeFile(
            "Sources/App/Telemetry.swift",
            contents: ["@preconcurrency", "import", "Firebase"].joined(separator: " ") + "\n",
            in: repository
        )
        try git(["add", "Sources/App/Telemetry.swift"], in: repository)

        let result = runRepoAudit(rootURL: repository)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.errorText.contains("Sources/App/Telemetry.swift: telemetry SDK import must not be present by default"))
    }

    func testRepositoryAuditRejectsAccessQualifiedTelemetrySDKImports() throws {
        let repository = try temporaryGitRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        try writeFile(
            "Sources/App/Telemetry.swift",
            contents: ["public", "import", "FirebaseAnalytics"].joined(separator: " ") + "\n",
            in: repository
        )
        try git(["add", "Sources/App/Telemetry.swift"], in: repository)

        let result = runRepoAudit(rootURL: repository)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.errorText.contains("Sources/App/Telemetry.swift: telemetry SDK import must not be present by default"))
    }

    func testRepositoryAuditRejectsTelemetryPackageDependencies() throws {
        let repository = try temporaryGitRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        let dependencyURL = "https://github.com/" + "get" + "sentry" + "/" + "sentry" + "-cocoa"
        try writeFile(
            "Package.swift",
            contents: #".package(url: "\#(dependencyURL)", from: "1.0.0")"#,
            in: repository
        )
        try git(["add", "Package.swift"], in: repository)

        let result = runRepoAudit(rootURL: repository)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.errorText.contains("Package.swift: telemetry dependency or collection endpoint must not be present by default"))
    }

    func testRepositoryAuditRejectsTelemetryReferencesInXcodeProject() throws {
        let repository = try temporaryGitRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        let dependencyURL = "https://github.com/" + "get" + "sentry" + "/" + "sentry" + "-cocoa"
        try writeFile(
            "PerchHA.xcodeproj/project.pbxproj",
            contents: "repositoryURL = \(dependencyURL);\n",
            in: repository
        )
        try git(["add", "PerchHA.xcodeproj/project.pbxproj"], in: repository)

        let result = runRepoAudit(rootURL: repository)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.errorText.contains("PerchHA.xcodeproj/project.pbxproj: telemetry dependency or collection endpoint must not be present by default"))
    }

    func testRepositoryAuditRejectsTelemetryCollectionEndpoints() throws {
        let repository = try temporaryGitRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        let endpoint = "https://o123." + "ingest." + "sentry.io/api"
        try writeFile("Sources/App/Telemetry.swift", contents: #"let endpoint = "\#(endpoint)""#, in: repository)
        try git(["add", "Sources/App/Telemetry.swift"], in: repository)

        let result = runRepoAudit(rootURL: repository)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.errorText.contains("Sources/App/Telemetry.swift: telemetry dependency or collection endpoint must not be present by default"))
    }

    func testRepositoryAuditUnknownOptionFailsExplicitly() {
        let result = runRepoAudit(arguments: ["--wat"])

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.errorText.contains("unknown option: --wat"))
    }

    func testRepositoryAuditMissingRootValueFailsExplicitly() {
        let result = runRepoAudit(arguments: ["--root"])

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.errorText.contains("missing value for --root"))
    }

    func testRepositoryAuditRejectsNextOptionAsRootValue() {
        let result = runRepoAudit(arguments: ["--root", "--wat"])

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.errorText.contains("missing value for --root"))
    }

    func testRepositoryAuditOutsideGitRepositoryFailsExplicitly() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let result = runRepoAudit(rootURL: directory)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.errorText.contains("git file listing failed:"))
    }

    private func temporaryGitRepository() throws -> URL {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try git(["init", "-q"], in: directory)
        return directory
    }

    private func temporaryDirectory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PerchHARepoAuditTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func writeFile(_ relativePath: String, contents: String, in directory: URL) throws {
        let fileURL = directory.appendingPathComponent(relativePath, isDirectory: false)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: fileURL)
    }

    private func writeProtectedPath(
        _ relativePath: String,
        contents: String,
        in directory: URL,
        addToIndex: Bool
    ) throws {
        try writeFile(relativePath, contents: contents, in: directory)
        if addToIndex {
            try git(["add", "-f", relativePath], in: directory)
        }
    }

    private func runRepoAudit(rootURL: URL) -> RepoAuditCommandResult {
        runRepoAudit(arguments: ["--root", rootURL.path])
    }

    private func runRepoAudit(arguments: [String]) -> RepoAuditCommandResult {
        var output: [String] = []
        var errors: [String] = []
        let exitCode = PerchHARepoAuditCommand.run(
            arguments: arguments,
            standardOutput: { output.append($0) },
            standardError: { errors.append($0) }
        )
        return RepoAuditCommandResult(
            exitCode: exitCode,
            output: output.joined(separator: "\n"),
            errorText: errors.joined()
        )
    }

    private func git(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", directory.path] + arguments
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "git failed"
            throw NSError(
                domain: "PerchHARepoAuditTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }
}

private struct RepoAuditCommandResult {
    let exitCode: Int32
    let output: String
    let errorText: String
}
#endif
