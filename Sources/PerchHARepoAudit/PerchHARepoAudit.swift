import Foundation
import PerchHASupport

public enum PerchHARepoAuditCommand {
    public static func main() -> Int32 {
        run(arguments: Array(CommandLine.arguments.dropFirst()))
    }

    public static func run(
        arguments: [String],
        standardOutput: (String) -> Void = { print($0) },
        standardError: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) }
    ) -> Int32 {
        do {
            if arguments.contains("--help") || arguments.contains("-h") {
                standardOutput(RepoAuditHelp.text)
                return 0
            }
            let options = try RepoAuditOptions(arguments: arguments)
            let report = try RepoAudit(rootURL: options.rootURL).run()
            report.lines.forEach(standardOutput)
            return 0
        } catch {
            standardError("perchha-repo-audit: \(error)\n")
            return 1
        }
    }
}

private enum RepoAuditHelp {
    static let text = """
    Usage:
      perchha-repo-audit [--root PATH]
    """
}

private struct RepoAuditOptions {
    let rootURL: URL

    init(arguments: [String]) throws {
        var rootPath = FileManager.default.currentDirectoryPath
        do {
            let options = try PerchHACommandLineOptions(
                arguments: arguments,
                valueOptions: ["--root"],
                flagOptions: []
            )
            if let configuredRootPath = options.value(for: "--root") {
                rootPath = configuredRootPath
            }
        } catch let error as PerchHACommandLineParseError {
            throw RepoAuditError(parseError: error)
        }
        rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
    }
}

private struct RepoAudit {
    let rootURL: URL

    func run() throws -> RepoAuditReport {
        let paths = try GitFileList(rootURL: rootURL).trackedAndUnignoredPaths()
        let violations = paths.compactMap(RepoAuditViolation.init(path:))
            + (try TelemetryAudit(rootURL: rootURL).violations(in: paths))
        guard violations.isEmpty else {
            throw RepoAuditError.violations(violations)
        }
        return RepoAuditReport(lines: [
            "Repository audit passed.",
            "- inspected paths: \(paths.count)",
            "- protected paths: clean"
        ])
    }
}

private struct GitFileList {
    let rootURL: URL

    func trackedAndUnignoredPaths() throws -> [String] {
        let cached = try runGit(["ls-files", "-z"])
        let unignored = try runGit(["ls-files", "--others", "--exclude-standard", "-z"])
        return Array(Set(parseNullSeparated(cached) + parseNullSeparated(unignored))).sorted()
    }

    private func runGit(_ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", rootURL.path] + arguments
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "git failed"
            throw RepoAuditError.gitFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return data
    }

    private func parseNullSeparated(_ data: Data) -> [String] {
        String(decoding: data, as: UTF8.self)
            .split(separator: "\0", omittingEmptySubsequences: true)
            .map(String.init)
    }
}

private struct RepoAuditViolation: Equatable, CustomStringConvertible {
    let path: String
    let reason: String

    init(path: String, reason: String) {
        self.path = path
        self.reason = reason
    }

    init?(path: String) {
        if Self.isForbiddenEnvironmentPath(path) {
            self.path = path
            reason = "local environment files must stay ignored"
        } else if path.hasPrefix("Fixtures/private/") {
            self.path = path
            reason = "private fixture captures must stay ignored"
        } else if path.hasPrefix(".build/") || path.hasPrefix("DerivedData/") {
            self.path = path
            reason = "build output must stay ignored"
        } else if let suffixReason = Self.forbiddenCredentialArtifactReason(path) {
            self.path = path
            reason = suffixReason
        } else {
            return nil
        }
    }

    var description: String {
        "\(path): \(reason)"
    }

    private static func isForbiddenEnvironmentPath(_ path: String) -> Bool {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.hasPrefix(".env") && name != ".env.example"
    }

    private static func forbiddenCredentialArtifactReason(_ path: String) -> String? {
        let lowercased = path.lowercased()
        let forbiddenSuffixes = [
            ".mobileprovision",
            ".p12",
            ".pem",
            ".p8",
            ".pfx"
        ]
        if forbiddenSuffixes.contains(where: lowercased.hasSuffix) {
            return "credential artifact must not be committed"
        }
        let name = URL(fileURLWithPath: lowercased).lastPathComponent
        if name == "id_rsa" || name == "id_ed25519" || name.hasSuffix(".key") {
            return "private key material must not be committed"
        }
        return nil
    }
}

private struct TelemetryAudit {
    let rootURL: URL

    func violations(in paths: [String]) throws -> [RepoAuditViolation] {
        var violations: [RepoAuditViolation] = []
        for path in paths where Self.isScannable(path) {
            let fileURL = rootURL.appendingPathComponent(path, isDirectory: false)
            let data = try Data(contentsOf: fileURL)
            guard let content = String(data: data, encoding: .utf8) else {
                continue
            }
            if let reason = Self.forbiddenTelemetryReason(in: content) {
                violations.append(RepoAuditViolation(path: path, reason: reason))
            }
        }
        return violations
    }

    private static func isScannable(_ path: String) -> Bool {
        let lowercased = path.lowercased()
        let name = URL(fileURLWithPath: lowercased).lastPathComponent
        if name == "package.swift" || name == "package.resolved" {
            return true
        }
        return [
            ".swift",
            ".m",
            ".mm",
            ".h",
            ".plist",
            ".json",
            ".yml",
            ".yaml",
            ".pbxproj",
            ".xcconfig",
            ".entitlements"
        ].contains { lowercased.hasSuffix($0) }
    }

    private static func forbiddenTelemetryReason(in content: String) -> String? {
        if containsForbiddenImport(in: content) {
            return "telemetry SDK import must not be present by default"
        }
        if containsForbiddenNeedle(in: content) {
            return "telemetry dependency or collection endpoint must not be present by default"
        }
        return nil
    }

    private static func containsForbiddenImport(in content: String) -> Bool {
        for line in content.split(whereSeparator: \.isNewline).map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if importedModule(from: trimmed).map(isForbiddenTelemetryModule) == true {
                return true
            }
        }
        return false
    }

    private static func importedModule(from line: String) -> String? {
        let tokens = line
            .replacingOccurrences(of: ";", with: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .map(String.init)
        if let importIndex = tokens.firstIndex(of: "import"),
           tokens.indices.contains(importIndex + 1) {
            return tokens[importIndex + 1]
                .split(whereSeparator: { $0 == "." || $0 == ";" })
                .first
                .map(String.init)
        }
        if line.hasPrefix("#import ") {
            guard let start = line.firstIndex(where: { $0 == "<" || $0 == "\"" }) else {
                return nil
            }
            let remainder = line[line.index(after: start)...]
            return remainder.split(whereSeparator: { $0 == "/" || $0 == ">" || $0 == "\"" }).first.map(String.init)
        }
        return nil
    }

    private static func isForbiddenTelemetryModule(_ module: String) -> Bool {
        forbiddenTelemetryModules.contains(module)
    }

    private static var forbiddenTelemetryModules: [String] {
        [
            ["Sentry"],
            ["Sentry", "SwiftUI"],
            ["Firebase"],
            ["Firebase", "Analytics"],
            ["Telemetry", "Deck"],
            ["Post", "Hog"],
            ["Amplitude"],
            ["Mixpanel"],
            ["Segment"],
            ["Bugsnag"],
            ["App", "Center"],
            ["Datadog"],
            ["New", "Relic"],
            ["Countly"],
            ["Matomo", "Tracker"],
            ["Rollbar"]
        ].map { $0.joined() }
    }

    private static func containsForbiddenNeedle(in content: String) -> Bool {
        let lowercased = content.lowercased()
        return forbiddenNeedles.contains(where: lowercased.contains)
    }

    private static var forbiddenNeedles: [String] {
        [
            ["sentry", "-cocoa"],
            ["get", "sentry"],
            ["telemetry", "deck"],
            ["post", "hog"],
            ["amplitude", "-swift"],
            ["mixpanel", "-swift"],
            ["segmentio", "/", "analytics-swift"],
            ["firebase", "-ios-sdk"],
            ["bugsnag", "-cocoa"],
            ["appcenter", "-sdk-apple"],
            ["datadog", "-sdk-apple"],
            ["new", "relic"],
            ["api", ".", "segment", ".", "io"],
            ["api2", ".", "amplitude", ".", "com"],
            ["api", ".", "mixpanel", ".", "com"],
            ["ingest", ".", "sentry", ".", "io"],
            ["app", ".", "post", "hog", ".", "com"],
            ["telemetry", "deck", ".", "com"],
            ["firebaselogging", ".", "googleapis", ".", "com"],
            ["google", "-analytics", ".", "com"],
            ["datadoghq", ".", "com"],
            ["api", ".", "rollbar", ".", "com"],
            ["notify", ".", "bugsnag", ".", "com"]
        ].map { $0.joined() }
    }
}

private struct RepoAuditReport {
    let lines: [String]
}

private enum RepoAuditError: Error, CustomStringConvertible {
    case unknownOption(String)
    case missingValue(String)
    case gitFailed(String)
    case violations([RepoAuditViolation])

    init(parseError: PerchHACommandLineParseError) {
        switch parseError {
        case let .unknownOption(option), let .invalidArgument(option):
            self = .unknownOption(option)
        case let .missingValue(option):
            self = .missingValue(option)
        }
    }

    var description: String {
        switch self {
        case let .unknownOption(option):
            "unknown option: \(option)"
        case let .missingValue(option):
            "missing value for \(option)"
        case let .gitFailed(message):
            "git file listing failed: \(message)"
        case let .violations(violations):
            "repository audit failed:\n\(violations.map { "- \($0.description)" }.joined(separator: "\n"))"
        }
    }
}
