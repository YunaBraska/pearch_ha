import Foundation
import PerchHASupport

public enum PerchHAXcodePreflightIssue: Error, Equatable, CustomStringConvertible, Sendable {
    case xcodeSelectToolMissing(String)
    case xcrunMissing(String)
    case projectMissing(String)
    case blankSchemeName
    case sharedSchemeMissing(String)
    case developerDirectoryLookupFailed(status: Int32)
    case developerDirectoryMissing
    case commandLineToolsSelected(String)
    case xcodeLicenseNotAccepted
    case xctestUnavailable(status: Int32)
    case xcodebuildUnavailable(status: Int32)
    case projectListingFailed(status: Int32)
    case sharedSchemeNotListed(String)

    public var description: String {
        switch self {
        case let .xcodeSelectToolMissing(path):
            "xcode-select does not exist: \(path)"
        case let .xcrunMissing(path):
            "xcrun does not exist: \(path)"
        case let .projectMissing(path):
            "Xcode project does not exist: \(path)"
        case .blankSchemeName:
            "shared Xcode scheme name is required"
        case let .sharedSchemeMissing(path):
            "shared Xcode scheme does not exist: \(path)"
        case let .developerDirectoryLookupFailed(status):
            "active developer directory lookup failed with status \(status)"
        case .developerDirectoryMissing:
            "active developer directory was not reported by xcode-select"
        case let .commandLineToolsSelected(path):
            "active developer directory points at Command Line Tools, not full Xcode: \(path)"
        case .xcodeLicenseNotAccepted:
            "Xcode license has not been accepted for command-line use"
        case let .xctestUnavailable(status):
            "xctest is unavailable through xcrun (status \(status))"
        case let .xcodebuildUnavailable(status):
            "xcodebuild is unavailable through xcrun (status \(status))"
        case let .projectListingFailed(status):
            "xcodebuild could not list the project (status \(status))"
        case let .sharedSchemeNotListed(name):
            "shared Xcode scheme is not listed by xcodebuild: \(name)"
        }
    }

    public var diagnosticCode: String {
        switch self {
        case .xcodeSelectToolMissing:
            "xcodeSelectToolMissing"
        case .xcrunMissing:
            "xcrunMissing"
        case .projectMissing:
            "projectMissing"
        case .blankSchemeName:
            "blankSchemeName"
        case .sharedSchemeMissing:
            "sharedSchemeMissing"
        case .developerDirectoryLookupFailed:
            "developerDirectoryLookupFailed"
        case .developerDirectoryMissing:
            "developerDirectoryMissing"
        case .commandLineToolsSelected:
            "commandLineToolsSelected"
        case .xcodeLicenseNotAccepted:
            "xcodeLicenseNotAccepted"
        case .xctestUnavailable:
            "xctestUnavailable"
        case .xcodebuildUnavailable:
            "xcodebuildUnavailable"
        case .projectListingFailed:
            "projectListingFailed"
        case .sharedSchemeNotListed:
            "sharedSchemeNotListed"
        }
    }
}

public struct PerchHAXcodePreflightConfiguration: Equatable, Sendable {
    public let projectURL: URL
    public let schemeName: String

    public init(projectURL: URL, schemeName: String) {
        self.projectURL = projectURL
        self.schemeName = schemeName
    }

    public var sharedSchemeURL: URL {
        projectURL
            .appendingPathComponent("xcshareddata", isDirectory: true)
            .appendingPathComponent("xcschemes", isDirectory: true)
            .appendingPathComponent("\(schemeName).xcscheme", isDirectory: false)
    }
}

public struct PerchHAXcodePreflightReport: Equatable, Sendable {
    public let projectAvailable: Bool
    public let sharedSchemeAvailable: Bool
    public let projectListingAvailable: Bool
    public let activeDeveloperDirectory: String?
    public let discoveredXcodeDeveloperDirectories: [String]
    public let fullXcodeSelected: Bool
    public let xctestAvailable: Bool
    public let xcodebuildAvailable: Bool
    public let issues: [PerchHAXcodePreflightIssue]

    public init(
        projectAvailable: Bool,
        sharedSchemeAvailable: Bool,
        projectListingAvailable: Bool,
        activeDeveloperDirectory: String?,
        discoveredXcodeDeveloperDirectories: [String],
        fullXcodeSelected: Bool,
        xctestAvailable: Bool,
        xcodebuildAvailable: Bool,
        issues: [PerchHAXcodePreflightIssue]
    ) {
        self.projectAvailable = projectAvailable
        self.sharedSchemeAvailable = sharedSchemeAvailable
        self.projectListingAvailable = projectListingAvailable
        self.activeDeveloperDirectory = activeDeveloperDirectory
        self.discoveredXcodeDeveloperDirectories = discoveredXcodeDeveloperDirectories
        self.fullXcodeSelected = fullXcodeSelected
        self.xctestAvailable = xctestAvailable
        self.xcodebuildAvailable = xcodebuildAvailable
        self.issues = issues
    }

    public var isReadyForNativeVerification: Bool {
        issues.isEmpty
            && projectAvailable
            && sharedSchemeAvailable
            && projectListingAvailable
            && fullXcodeSelected
            && xctestAvailable
            && xcodebuildAvailable
    }

    public func diagnostic(
        configuration: PerchHAXcodePreflightConfiguration
    ) -> PerchHAXcodePreflightDiagnostic {
        PerchHAXcodePreflightDiagnostic(report: self, configuration: configuration)
    }

    public func nextSteps(configuration: PerchHAXcodePreflightConfiguration) -> [String] {
        if isReadyForNativeVerification {
            return [
                "Full-Xcode native verification looks ready. Run the XCTest coverage gate and the PerchHA xcodebuild app check."
            ]
        }

        var result: [String] = []
        if issues.contains(where: Self.isProjectMetadataIssue) {
            result.append(
                "Restore the checked-in Xcode project and shared scheme, or point --project/--scheme at the correct shared scheme."
            )
        }
        if issues.contains(.xcodeLicenseNotAccepted) {
            result.append(
                "Accept the Xcode license once on this Mac before rerunning native verification."
            )
        }
        if issues.contains(where: Self.isDeveloperDirectoryIssue) {
            if discoveredXcodeDeveloperDirectories.isEmpty {
                result.append(
                    "Install a full Xcode app and select its developer directory before rerunning native verification."
                )
            } else {
                result.append(
                    "Select a discovered full Xcode developer directory before rerunning native verification."
                )
            }
        }
        if issues.contains(where: Self.isDeveloperToolIssue) {
            result.append(
                "Make sure xcrun can find both xctest and xcodebuild from the active developer directory before rerunning native verification."
            )
        }
        if result.isEmpty {
            result.append(
                "Rerun native verification after fixing the reported Xcode project or developer-toolchain issues."
            )
        }
        return result
    }

    public func suggestedCommands(configuration: PerchHAXcodePreflightConfiguration) -> [String] {
        var commands: [String] = []
        if issues.contains(where: Self.isDeveloperDirectoryIssue) {
            commands.append("sudo xcode-select -s \(Self.shellQuoted(suggestedDeveloperDirectorySelectionPath))")
        }
        if issues.contains(.xcodeLicenseNotAccepted) {
            commands.append(sudoPrefixed("xcodebuild -license accept"))
        }
        if issues.contains(where: Self.isDeveloperDirectoryIssue)
            || issues.contains(where: Self.isDeveloperToolIssue)
            || issues.contains(.xcodeLicenseNotAccepted)
        {
            commands.append(prefixed("xcrun --find xctest"))
            commands.append(prefixed("xcrun --find xcodebuild"))
        }
        if isReadyForNativeVerification {
            commands.append(prefixed("swift test --disable-swift-testing --enable-xctest list"))
            commands.append(
                prefixed(
                    "swift test --disable-swift-testing --enable-xctest -Xswiftc -warnings-as-errors --enable-code-coverage"
                )
            )
            commands.append(
                prefixed(
                    "xcodebuild -project \(Self.shellQuoted(configuration.projectURL.path)) -scheme \(Self.shellQuoted(configuration.schemeName)) -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build"
                )
            )
        } else {
            commands.append(
                prefixed(
                    "swift run perchha-xcode-doctor --json --strict --project \(Self.shellQuoted(configuration.projectURL.path)) --scheme \(Self.shellQuoted(configuration.schemeName))"
                )
            )
        }
        return commands
    }

    private static func isProjectMetadataIssue(_ issue: PerchHAXcodePreflightIssue) -> Bool {
        switch issue {
        case .projectMissing, .blankSchemeName, .sharedSchemeMissing:
            true
        case .projectListingFailed, .sharedSchemeNotListed:
            true
        default:
            false
        }
    }

    private static func isDeveloperDirectoryIssue(_ issue: PerchHAXcodePreflightIssue) -> Bool {
        switch issue {
        case .xcodeSelectToolMissing, .developerDirectoryLookupFailed, .developerDirectoryMissing, .commandLineToolsSelected:
            true
        default:
            false
        }
    }

    private static func isDeveloperToolIssue(_ issue: PerchHAXcodePreflightIssue) -> Bool {
        switch issue {
        case .xcrunMissing, .xctestUnavailable, .xcodebuildUnavailable:
            true
        default:
            false
        }
    }

    private static func shellQuoted(_ value: String) -> String {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/._-"))
        if !value.isEmpty && value.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return value
        }
        let escaped = value.replacingOccurrences(of: "'", with: "'\"'\"'")
        return "'\(escaped)'"
    }

    private var suggestedDeveloperDirectorySelectionPath: String {
        discoveredXcodeDeveloperDirectories.first ?? "/Applications/Xcode.app/Contents/Developer"
    }

    private var suggestedDeveloperDirectoryEnvironmentAssignment: String? {
        let path: String?
        if let activeDeveloperDirectory, Self.isFullXcodePath(activeDeveloperDirectory) {
            path = activeDeveloperDirectory
        } else {
            path = discoveredXcodeDeveloperDirectories.first
        }
        guard let path else {
            return nil
        }
        return "DEVELOPER_DIR=\(Self.shellQuoted(path))"
    }

    private func prefixed(_ command: String) -> String {
        guard let assignment = suggestedDeveloperDirectoryEnvironmentAssignment else {
            return command
        }
        return "\(assignment) \(command)"
    }

    private func sudoPrefixed(_ command: String) -> String {
        guard let assignment = suggestedDeveloperDirectoryEnvironmentAssignment else {
            return "sudo \(command)"
        }
        return "sudo env \(assignment) \(command)"
    }

    private static func isFullXcodePath(_ path: String) -> Bool {
        path.contains(".app/Contents/Developer")
    }
}

public enum PerchHAXcodePreflightPresence: String, Codable, Equatable, Sendable {
    case present
    case missing

    public init(_ value: Bool) {
        self = value ? .present : .missing
    }
}

public enum PerchHAXcodePreflightState: String, Codable, Equatable, Sendable {
    case ready
    case blocked

    public init(_ value: Bool) {
        self = value ? .ready : .blocked
    }
}

public struct PerchHAXcodePreflightDiagnosticIssue: Codable, Equatable, Sendable {
    public let code: String
    public let description: String

    public init(code: String, description: String) {
        self.code = code
        self.description = description
    }
}

public struct PerchHAXcodePreflightDiagnostic: Codable, Equatable, Sendable {
    public let project: PerchHAXcodePreflightPresence
    public let sharedScheme: PerchHAXcodePreflightPresence
    public let projectListing: PerchHAXcodePreflightState
    public let activeDeveloperDirectory: String?
    public let discoveredXcodeDeveloperDirectories: [String]
    public let fullXcode: PerchHAXcodePreflightState
    public let xctest: PerchHAXcodePreflightState
    public let xcodebuild: PerchHAXcodePreflightState
    public let nativeVerification: PerchHAXcodePreflightState
    public let issues: [PerchHAXcodePreflightDiagnosticIssue]
    public let nextSteps: [String]
    public let suggestedCommands: [String]

    public init(
        project: PerchHAXcodePreflightPresence,
        sharedScheme: PerchHAXcodePreflightPresence,
        projectListing: PerchHAXcodePreflightState,
        activeDeveloperDirectory: String?,
        discoveredXcodeDeveloperDirectories: [String],
        fullXcode: PerchHAXcodePreflightState,
        xctest: PerchHAXcodePreflightState,
        xcodebuild: PerchHAXcodePreflightState,
        nativeVerification: PerchHAXcodePreflightState,
        issues: [PerchHAXcodePreflightDiagnosticIssue],
        nextSteps: [String],
        suggestedCommands: [String]
    ) {
        self.project = project
        self.sharedScheme = sharedScheme
        self.projectListing = projectListing
        self.activeDeveloperDirectory = activeDeveloperDirectory
        self.discoveredXcodeDeveloperDirectories = discoveredXcodeDeveloperDirectories
        self.fullXcode = fullXcode
        self.xctest = xctest
        self.xcodebuild = xcodebuild
        self.nativeVerification = nativeVerification
        self.issues = issues
        self.nextSteps = nextSteps
        self.suggestedCommands = suggestedCommands
    }

    public init(
        report: PerchHAXcodePreflightReport,
        configuration: PerchHAXcodePreflightConfiguration
    ) {
        project = PerchHAXcodePreflightPresence(report.projectAvailable)
        sharedScheme = PerchHAXcodePreflightPresence(report.sharedSchemeAvailable)
        projectListing = PerchHAXcodePreflightState(report.projectListingAvailable)
        activeDeveloperDirectory = report.activeDeveloperDirectory
        discoveredXcodeDeveloperDirectories = report.discoveredXcodeDeveloperDirectories
        fullXcode = PerchHAXcodePreflightState(report.fullXcodeSelected)
        xctest = PerchHAXcodePreflightState(report.xctestAvailable)
        xcodebuild = PerchHAXcodePreflightState(report.xcodebuildAvailable)
        nativeVerification = PerchHAXcodePreflightState(report.isReadyForNativeVerification)
        issues = report.issues.map {
            PerchHAXcodePreflightDiagnosticIssue(
                code: $0.diagnosticCode,
                description: $0.description
            )
        }
        nextSteps = report.nextSteps(configuration: configuration)
        suggestedCommands = report.suggestedCommands(configuration: configuration)
    }
}

public struct PerchHAXcodePreflightChecker {
    public static let defaultXcodeSelectURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
    public static let defaultXcrunURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    public static let defaultApplicationSearchRoots = [URL(fileURLWithPath: "/Applications", isDirectory: true)]
    public static let developerDirectoryEnvironmentKey = "DEVELOPER_DIR"

    private let fileManager: FileManager
    private let xcodeSelectURL: URL
    private let xcrunURL: URL
    private let applicationSearchRoots: [URL]
    private let environment: [String: String]
    private let commandRunner: any PerchHACommandRunning

    public init(
        fileManager: FileManager = .default,
        xcodeSelectURL: URL = Self.defaultXcodeSelectURL,
        xcrunURL: URL = Self.defaultXcrunURL,
        applicationSearchRoots: [URL] = Self.defaultApplicationSearchRoots,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        commandRunner: any PerchHACommandRunning = PerchHAFoundationCommandRunner()
    ) {
        self.fileManager = fileManager
        self.xcodeSelectURL = xcodeSelectURL
        self.xcrunURL = xcrunURL
        self.applicationSearchRoots = applicationSearchRoots
        self.environment = environment
        self.commandRunner = commandRunner
    }

    public func check(
        _ configuration: PerchHAXcodePreflightConfiguration
    ) throws -> PerchHAXcodePreflightReport {
        var issues: [PerchHAXcodePreflightIssue] = []

        let projectAvailable = fileManager.fileExists(atPath: configuration.projectURL.path)
        if !projectAvailable {
            issues.append(.projectMissing(configuration.projectURL.path))
        }

        let trimmedSchemeName = configuration.schemeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let sharedSchemeAvailable: Bool
        if trimmedSchemeName.isEmpty {
            sharedSchemeAvailable = false
            issues.append(.blankSchemeName)
        } else {
            sharedSchemeAvailable = fileManager.fileExists(atPath: configuration.sharedSchemeURL.path)
            if !sharedSchemeAvailable {
                issues.append(.sharedSchemeMissing(configuration.sharedSchemeURL.path))
            }
        }

        let activeDeveloperDirectory = try activeDeveloperDirectory(issues: &issues)
        let discoveredXcodeDeveloperDirectories = discoveredXcodeDeveloperDirectories()
        let fullXcodeSelected = activeDeveloperDirectory.map(Self.isFullXcodeDeveloperDirectory) ?? false
        if let activeDeveloperDirectory, !fullXcodeSelected {
            issues.append(.commandLineToolsSelected(activeDeveloperDirectory))
        }

        let xctestAvailable = try developerToolAvailable(
            "xctest",
            unavailableIssue: { .xctestUnavailable(status: $0) },
            issues: &issues
        )
        let xcodebuildAvailable = try developerToolAvailable(
            "xcodebuild",
            unavailableIssue: { .xcodebuildUnavailable(status: $0) },
            issues: &issues
        )
        let projectListingAvailable = try projectListingAvailable(
            configuration: configuration,
            xcodebuildAvailable: xcodebuildAvailable,
            issues: &issues
        )

        return PerchHAXcodePreflightReport(
            projectAvailable: projectAvailable,
            sharedSchemeAvailable: sharedSchemeAvailable,
            projectListingAvailable: projectListingAvailable,
            activeDeveloperDirectory: activeDeveloperDirectory,
            discoveredXcodeDeveloperDirectories: discoveredXcodeDeveloperDirectories,
            fullXcodeSelected: fullXcodeSelected,
            xctestAvailable: xctestAvailable,
            xcodebuildAvailable: xcodebuildAvailable,
            issues: issues
        )
    }

    private func activeDeveloperDirectory(
        issues: inout [PerchHAXcodePreflightIssue]
    ) throws -> String? {
        if let overridePath = Self.nonBlank(environment[Self.developerDirectoryEnvironmentKey]) {
            return overridePath
        }

        guard fileManager.isExecutableFile(atPath: xcodeSelectURL.path) else {
            issues.append(.xcodeSelectToolMissing(xcodeSelectURL.path))
            return nil
        }

        let result = try commandRunner.run(
            executableURL: xcodeSelectURL,
            arguments: ["-p"]
        )
        guard result.status == 0 else {
            issues.append(.developerDirectoryLookupFailed(status: result.status))
            return nil
        }

        let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            issues.append(.developerDirectoryMissing)
            return nil
        }
        return path
    }

    private func developerToolAvailable(
        _ tool: String,
        unavailableIssue: (Int32) -> PerchHAXcodePreflightIssue,
        issues: inout [PerchHAXcodePreflightIssue]
    ) throws -> Bool {
        guard fileManager.isExecutableFile(atPath: xcrunURL.path) else {
            if !issues.contains(.xcrunMissing(xcrunURL.path)) {
                issues.append(.xcrunMissing(xcrunURL.path))
            }
            return false
        }

        let result = try commandRunner.run(
            executableURL: xcrunURL,
            arguments: ["--find", tool]
        )
        guard result.status == 0, !result.output.isEmpty else {
            if Self.isLicenseFailure(status: result.status, output: result.output) {
                appendLicenseIssueIfNeeded(issues: &issues)
                return false
            }
            issues.append(unavailableIssue(result.status))
            return false
        }
        return true
    }

    private func projectListingAvailable(
        configuration: PerchHAXcodePreflightConfiguration,
        xcodebuildAvailable: Bool,
        issues: inout [PerchHAXcodePreflightIssue]
    ) throws -> Bool {
        guard xcodebuildAvailable else {
            return false
        }
        guard fileManager.fileExists(atPath: configuration.projectURL.path) else {
            return false
        }
        let trimmedSchemeName = configuration.schemeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSchemeName.isEmpty else {
            return false
        }

        let result = try commandRunner.run(
            executableURL: xcrunURL,
            arguments: ["xcodebuild", "-list", "-project", configuration.projectURL.path]
        )
        guard result.status == 0 else {
            if Self.isLicenseFailure(status: result.status, output: result.output) {
                appendLicenseIssueIfNeeded(issues: &issues)
                return false
            }
            issues.append(.projectListingFailed(status: result.status))
            return false
        }
        let schemes = listedSchemes(from: result.output)
        guard schemes.contains(trimmedSchemeName) else {
            issues.append(.sharedSchemeNotListed(trimmedSchemeName))
            return false
        }
        return true
    }

    private func listedSchemes(from output: String) -> [String] {
        var schemes: [String] = []
        var inSchemesSection = false
        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line == "Schemes:" {
                inSchemesSection = true
                continue
            }
            if !inSchemesSection {
                continue
            }
            if line.isEmpty {
                if !schemes.isEmpty {
                    break
                }
                continue
            }
            schemes.append(line)
        }
        return schemes
    }

    private func discoveredXcodeDeveloperDirectories() -> [String] {
        var results: [String] = []
        for root in applicationSearchRoots {
            guard let children = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard child.pathExtension == "app",
                      child.deletingPathExtension().lastPathComponent.hasPrefix("Xcode")
                else {
                    continue
                }
                let developerDirectory = child
                    .appendingPathComponent("Contents", isDirectory: true)
                    .appendingPathComponent("Developer", isDirectory: true)
                let xcodebuildPath = developerDirectory
                    .appendingPathComponent("usr", isDirectory: true)
                    .appendingPathComponent("bin", isDirectory: true)
                    .appendingPathComponent("xcodebuild", isDirectory: false)
                    .path
                guard fileManager.isExecutableFile(atPath: xcodebuildPath) else {
                    continue
                }
                results.append(developerDirectory.path)
            }
        }
        return results
    }

    private static func isFullXcodeDeveloperDirectory(_ path: String) -> Bool {
        path.contains(".app/Contents/Developer")
    }

    private func appendLicenseIssueIfNeeded(issues: inout [PerchHAXcodePreflightIssue]) {
        if !issues.contains(.xcodeLicenseNotAccepted) {
            issues.append(.xcodeLicenseNotAccepted)
        }
    }

    private static func isLicenseFailure(status: Int32, output: String) -> Bool {
        status == 69 && output.localizedCaseInsensitiveContains("license")
    }

    private static func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

public enum PerchHAXcodeDoctorCommand {
    public static func main() -> Int32 {
        run(arguments: Array(CommandLine.arguments.dropFirst()))
    }

    public static func run(
        arguments: [String],
        standardOutput: (String) -> Void = { print($0) },
        standardError: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) }
    ) -> Int32 {
        do {
            if arguments.contains("--help") || arguments.contains("-h") || arguments.first == "help" {
                standardOutput(PerchHAXcodeDoctorHelp.text)
                return 0
            }

            let options = try PerchHAXcodeDoctorOptions(arguments: arguments)
            let checker = PerchHAXcodePreflightChecker()
            let report = try checker.check(options.configuration)
            let diagnostic = report.diagnostic(configuration: options.configuration)

            if options.json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(diagnostic)
                standardOutput(String(decoding: data, as: UTF8.self))
            } else {
                render(diagnostic: diagnostic).forEach(standardOutput)
            }

            if options.strict && !report.isReadyForNativeVerification {
                return 1
            }
            return 0
        } catch {
            standardError("perchha-xcode-doctor: \(error)\n")
            return 1
        }
    }

    private static func render(diagnostic: PerchHAXcodePreflightDiagnostic) -> [String] {
        var lines = [
            "native verification: \(diagnostic.nativeVerification.rawValue)",
            "- project: \(diagnostic.project.rawValue)",
            "- shared scheme: \(diagnostic.sharedScheme.rawValue)",
            "- project listing: \(diagnostic.projectListing.rawValue)",
            "- active developer directory: \(diagnostic.activeDeveloperDirectory ?? "<unavailable>")",
            "- discovered Xcode developer directories: \(diagnostic.discoveredXcodeDeveloperDirectories.isEmpty ? "<none>" : diagnostic.discoveredXcodeDeveloperDirectories.joined(separator: ", "))",
            "- full Xcode: \(diagnostic.fullXcode.rawValue)",
            "- xctest: \(diagnostic.xctest.rawValue)",
            "- xcodebuild: \(diagnostic.xcodebuild.rawValue)"
        ]

        if !diagnostic.issues.isEmpty {
            lines.append("")
            lines.append("Issues:")
            diagnostic.issues.forEach { lines.append("- \($0.description)") }
        }

        if !diagnostic.nextSteps.isEmpty {
            lines.append("")
            lines.append("Next steps:")
            diagnostic.nextSteps.forEach { lines.append("- \($0)") }
        }

        if !diagnostic.suggestedCommands.isEmpty {
            lines.append("")
            lines.append("Suggested commands:")
            diagnostic.suggestedCommands.forEach { lines.append("- \($0)") }
        }

        return lines
    }
}

private enum PerchHAXcodeDoctorHelp {
    static let text = """
    Usage:
      perchha-xcode-doctor [--project PATH] [--scheme NAME] [--json] [--strict]

    Options:
      --project PATH   Xcode project to verify. Default: PerchHA.xcodeproj
      --scheme NAME    Shared scheme name to verify. Default: PerchHA
      --json           Print machine-readable diagnostic JSON.
      --strict         Exit non-zero when native verification is blocked.
    """
}

private struct PerchHAXcodeDoctorOptions {
    let configuration: PerchHAXcodePreflightConfiguration
    let json: Bool
    let strict: Bool

    init(arguments: [String]) throws {
        let options: PerchHACommandLineOptions
        do {
            options = try PerchHACommandLineOptions(
                arguments: arguments,
                valueOptions: ["--project", "--scheme"],
                flagOptions: ["--json", "--strict"]
            )
        } catch let error as PerchHACommandLineParseError {
            throw PerchHAXcodeDoctorError.parseError(error)
        }

        let projectPath = options.value(for: "--project") ?? "PerchHA.xcodeproj"
        let schemeName = options.value(for: "--scheme") ?? "PerchHA"
        configuration = PerchHAXcodePreflightConfiguration(
            projectURL: URL(fileURLWithPath: projectPath, isDirectory: true),
            schemeName: schemeName
        )
        json = options.has("--json")
        strict = options.has("--strict")
    }
}

private enum PerchHAXcodeDoctorError: Error, CustomStringConvertible {
    case parseError(PerchHACommandLineParseError)

    var description: String {
        switch self {
        case let .parseError(parseError):
            switch parseError {
            case let .unknownOption(option):
                "unknown option \(option)"
            case let .invalidArgument(argument):
                "invalid argument \(argument)"
            case let .missingValue(option):
                "missing value for \(option)"
            }
        }
    }
}
