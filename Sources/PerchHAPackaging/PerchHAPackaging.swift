import Foundation

public enum PerchHAAppBundleManifestError: Error, Equatable, CustomStringConvertible, Sendable {
    case blankField(String)
    case invalidCallbackURLScheme(String)

    public var description: String {
        switch self {
        case let .blankField(name):
            "\(name) is required"
        case let .invalidCallbackURLScheme(value):
            "invalid callback URL scheme: \(value)"
        }
    }
}

public struct PerchHAAppBundleManifest: Equatable, Sendable {
    public let appName: String
    public let bundleIdentifier: String
    public let executableName: String
    public let version: String
    public let buildVersion: String
    public let minimumSystemVersion: String
    public let callbackURLScheme: String

    public init(
        appName: String = "PerchHA",
        bundleIdentifier: String = "dev.perchha.app",
        executableName: String = "PerchHA",
        version: String = "0.1.0",
        buildVersion: String = "1",
        minimumSystemVersion: String = "13.0",
        callbackURLScheme: String = "perchha"
    ) throws {
        self.appName = try Self.required(appName, name: "appName")
        self.bundleIdentifier = try Self.required(bundleIdentifier, name: "bundleIdentifier")
        self.executableName = try Self.required(executableName, name: "executableName")
        self.version = try Self.required(version, name: "version")
        self.buildVersion = try Self.required(buildVersion, name: "buildVersion")
        self.minimumSystemVersion = try Self.required(minimumSystemVersion, name: "minimumSystemVersion")
        let normalizedScheme = try Self.required(callbackURLScheme, name: "callbackURLScheme")
        guard Self.isValidURLScheme(normalizedScheme) else {
            throw PerchHAAppBundleManifestError.invalidCallbackURLScheme(normalizedScheme)
        }
        self.callbackURLScheme = normalizedScheme
    }

    public func propertyListData() throws -> Data {
        let plist = PerchHAInfoPlist(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            executableName: executableName,
            version: version,
            buildVersion: buildVersion,
            minimumSystemVersion: minimumSystemVersion,
            callbackURLScheme: callbackURLScheme
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        return try encoder.encode(plist)
    }

    private static func required(_ value: String, name: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PerchHAAppBundleManifestError.blankField(name)
        }
        return trimmed
    }

    private static func isValidURLScheme(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first,
              CharacterSet.letters.contains(first)
        else {
            return false
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "+-."))
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

public enum PerchHAAppBundleBuildError: Error, Equatable, CustomStringConvertible, Sendable {
    case executableMissing(String)
    case outputExists(String)

    public var description: String {
        switch self {
        case let .executableMissing(path):
            "executable does not exist: \(path)"
        case let .outputExists(path):
            "output app already exists: \(path)"
        }
    }
}

public struct PerchHAAppBundleBuildConfiguration: Equatable, Sendable {
    public let executableURL: URL
    public let outputURL: URL
    public let manifest: PerchHAAppBundleManifest
    public let replaceExisting: Bool

    public init(
        executableURL: URL,
        outputURL: URL,
        manifest: PerchHAAppBundleManifest,
        replaceExisting: Bool = false
    ) {
        self.executableURL = executableURL
        self.outputURL = outputURL
        self.manifest = manifest
        self.replaceExisting = replaceExisting
    }
}

public struct PerchHAAppBundleBuildResult: Equatable, Sendable {
    public let appURL: URL
    public let executableURL: URL
    public let infoPlistURL: URL
}

public struct PerchHAAppBundleBuilder {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func build(_ configuration: PerchHAAppBundleBuildConfiguration) throws -> PerchHAAppBundleBuildResult {
        guard fileManager.fileExists(atPath: configuration.executableURL.path) else {
            throw PerchHAAppBundleBuildError.executableMissing(configuration.executableURL.path)
        }
        if fileManager.fileExists(atPath: configuration.outputURL.path) {
            guard configuration.replaceExisting else {
                throw PerchHAAppBundleBuildError.outputExists(configuration.outputURL.path)
            }
            try fileManager.removeItem(at: configuration.outputURL)
        }

        let contentsURL = configuration.outputURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        try fileManager.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

        let bundledExecutableURL = macOSURL.appendingPathComponent(configuration.manifest.executableName, isDirectory: false)
        try fileManager.copyItem(at: configuration.executableURL, to: bundledExecutableURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundledExecutableURL.path)

        let infoPlistURL = contentsURL.appendingPathComponent("Info.plist", isDirectory: false)
        try configuration.manifest.propertyListData().write(to: infoPlistURL, options: .atomic)

        let pkgInfoURL = contentsURL.appendingPathComponent("PkgInfo", isDirectory: false)
        try Data("APPL????".utf8).write(to: pkgInfoURL, options: .atomic)

        return PerchHAAppBundleBuildResult(
            appURL: configuration.outputURL,
            executableURL: bundledExecutableURL,
            infoPlistURL: infoPlistURL
        )
    }
}

public enum PerchHALaunchServicesVerificationError: Error, Equatable, CustomStringConvertible, Sendable {
    case appBundleMissing(String)
    case infoPlistMissing(String)
    case infoPlistUnreadable(String)
    case callbackSchemeMissing(String)
    case callbackRoleMissing(String)
    case invalidCallbackURL(String)
    case launchServicesToolMissing(String)
    case launchServicesDumpFailed(status: Int32, output: String)
    case launchServicesBundleMissing(String)
    case launchServicesSchemeMissing(String)
    case launchServicesRoleMissing(String)

    public var description: String {
        switch self {
        case let .appBundleMissing(path):
            "app bundle does not exist: \(path)"
        case let .infoPlistMissing(path):
            "Info.plist does not exist: \(path)"
        case let .infoPlistUnreadable(path):
            "Info.plist is unreadable: \(path)"
        case let .callbackSchemeMissing(scheme):
            "app bundle does not declare callback URL scheme: \(scheme)"
        case let .callbackRoleMissing(role):
            "app bundle does not declare callback URL role: \(role)"
        case let .invalidCallbackURL(scheme):
            "invalid callback URL for scheme: \(scheme)"
        case let .launchServicesToolMissing(path):
            "LaunchServices registration tool does not exist: \(path)"
        case let .launchServicesDumpFailed(status, output):
            "LaunchServices dump failed with status \(status): \(output)"
        case let .launchServicesBundleMissing(path):
            "LaunchServices dump does not include app bundle: \(path)"
        case let .launchServicesSchemeMissing(scheme):
            "LaunchServices dump does not include callback URL scheme: \(scheme)"
        case let .launchServicesRoleMissing(role):
            "LaunchServices dump does not include callback URL role: \(role)"
        }
    }
}

public struct PerchHALaunchServicesVerificationConfiguration: Equatable, Sendable {
    public let appURL: URL
    public let callbackURLScheme: String
    public let registerBundle: Bool

    public init(
        appURL: URL,
        callbackURLScheme: String,
        registerBundle: Bool = true
    ) {
        self.appURL = appURL
        self.callbackURLScheme = callbackURLScheme
        self.registerBundle = registerBundle
    }
}

public struct PerchHALaunchServicesVerificationResult: Equatable, Sendable {
    public let appURL: URL
    public let callbackURL: URL
    public let registeredApplicationURL: URL
    public let callbackRole: String
}

public struct PerchHALaunchServicesVerifier {
    public static let defaultURLTypeRole = "Viewer"
    public static let defaultToolURL = URL(
        fileURLWithPath: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    )

    private let fileManager: FileManager
    private let toolURL: URL

    public init(
        fileManager: FileManager = .default,
        toolURL: URL = PerchHALaunchServicesVerifier.defaultToolURL
    ) {
        self.fileManager = fileManager
        self.toolURL = toolURL
    }

    public func verify(
        _ configuration: PerchHALaunchServicesVerificationConfiguration
    ) throws -> PerchHALaunchServicesVerificationResult {
        let appURL = normalizedFileURL(configuration.appURL)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: appURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw PerchHALaunchServicesVerificationError.appBundleMissing(appURL.path)
        }

        let infoPlistURL = appURL.appendingPathComponent("Contents/Info.plist", isDirectory: false)
        guard fileManager.fileExists(atPath: infoPlistURL.path) else {
            throw PerchHALaunchServicesVerificationError.infoPlistMissing(infoPlistURL.path)
        }
        let urlType = try infoPlistCallbackURLType(
            infoPlistURL: infoPlistURL,
            callbackURLScheme: configuration.callbackURLScheme
        )
        guard let urlType else {
            throw PerchHALaunchServicesVerificationError.callbackSchemeMissing(configuration.callbackURLScheme)
        }
        guard urlType.role == Self.defaultURLTypeRole else {
            throw PerchHALaunchServicesVerificationError.callbackRoleMissing(Self.defaultURLTypeRole)
        }

        let callbackURL = try callbackURL(scheme: configuration.callbackURLScheme)
        let dump = try launchServicesDump(appURL: appURL, shouldRegister: configuration.registerBundle)
        try verifyLaunchServicesDump(dump, appURL: appURL, callbackURLScheme: configuration.callbackURLScheme)
        return PerchHALaunchServicesVerificationResult(
            appURL: appURL,
            callbackURL: callbackURL,
            registeredApplicationURL: appURL,
            callbackRole: urlType.role
        )
    }

    private func infoPlistCallbackURLType(
        infoPlistURL: URL,
        callbackURLScheme: String
    ) throws -> PerchHAInfoPlistURLTypeSnapshot? {
        let value: Any
        do {
            value = try PropertyListSerialization.propertyList(
                from: Data(contentsOf: infoPlistURL),
                options: [],
                format: nil
            )
        } catch {
            throw PerchHALaunchServicesVerificationError.infoPlistUnreadable(infoPlistURL.path)
        }
        guard let plist = value as? [String: Any],
              let urlTypes = plist["CFBundleURLTypes"] as? [[String: Any]]
        else {
            return nil
        }
        for urlType in urlTypes {
            guard let schemes = urlType["CFBundleURLSchemes"] as? [String] else {
                continue
            }
            if schemes.contains(where: { $0.caseInsensitiveCompare(callbackURLScheme) == .orderedSame }) {
                return PerchHAInfoPlistURLTypeSnapshot(
                    schemes: schemes,
                    role: urlType["CFBundleTypeRole"] as? String ?? ""
                )
            }
        }
        return nil
    }

    private func callbackURL(scheme: String) throws -> URL {
        guard let url = URL(string: "\(scheme)://auth") else {
            throw PerchHALaunchServicesVerificationError.invalidCallbackURL(scheme)
        }
        return url
    }

    private func launchServicesDump(appURL: URL, shouldRegister: Bool) throws -> String {
        guard fileManager.isExecutableFile(atPath: toolURL.path) else {
            throw PerchHALaunchServicesVerificationError.launchServicesToolMissing(toolURL.path)
        }
        if shouldRegister {
            _ = try launchServicesOutput(arguments: ["-f", appURL.path])
        }
        return try launchServicesOutput(arguments: ["-dump"])
    }

    private func launchServicesOutput(arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = toolURL
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw PerchHALaunchServicesVerificationError.launchServicesDumpFailed(
                status: process.terminationStatus,
                output: output.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return output
    }

    private func verifyLaunchServicesDump(
        _ dump: String,
        appURL: URL,
        callbackURLScheme: String
    ) throws {
        guard let appPathRange = dump.range(of: appURL.path) else {
            throw PerchHALaunchServicesVerificationError.launchServicesBundleMissing(appURL.path)
        }
        let appClaimSlice = String(dump[appPathRange.lowerBound...].prefix(12_000))
        let binding = NSRegularExpression.escapedPattern(for: "\(callbackURLScheme):")
        guard appClaimSlice.range(
            of: "claimed schemes:\\s*.*\(binding)",
            options: [.regularExpression, .caseInsensitive]
        ) != nil else {
            throw PerchHALaunchServicesVerificationError.launchServicesSchemeMissing(callbackURLScheme)
        }

        guard let claimBlock = launchServicesClaimBlock(
            in: appClaimSlice,
            binding: binding
        ) else {
            throw PerchHALaunchServicesVerificationError.launchServicesSchemeMissing(callbackURLScheme)
        }
        guard claimBlock.range(
            of: "roles:\\s*\(Self.defaultURLTypeRole)",
            options: [.regularExpression, .caseInsensitive]
        ) != nil else {
            throw PerchHALaunchServicesVerificationError.launchServicesRoleMissing(Self.defaultURLTypeRole)
        }
    }

    private func launchServicesClaimBlock(in dumpSlice: String, binding: String) -> String? {
        let separator = "---------------------------------------------------------------------------------"
        let blocks = dumpSlice.components(separatedBy: separator)
        return blocks.first { block in
            block.range(
                of: "bindings:\\s*.*\(binding)",
                options: [.regularExpression, .caseInsensitive]
            ) != nil
        }
    }

    private func normalizedFileURL(_ url: URL) -> URL {
        URL(fileURLWithPath: url.path).standardizedFileURL.resolvingSymlinksInPath()
    }
}

private struct PerchHAInfoPlistURLTypeSnapshot: Equatable, Sendable {
    let schemes: [String]
    let role: String
}

private struct PerchHAInfoPlist: Encodable {
    let developmentRegion = "en"
    let executableName: String
    let bundleIdentifier: String
    let infoDictionaryVersion = "6.0"
    let appName: String
    let packageType = "APPL"
    let version: String
    let buildVersion: String
    let minimumSystemVersion: String
    let highResolutionCapable = true
    let agentApplication = true
    let urlTypes: [PerchHAInfoPlistURLType]

    init(
        appName: String,
        bundleIdentifier: String,
        executableName: String,
        version: String,
        buildVersion: String,
        minimumSystemVersion: String,
        callbackURLScheme: String
    ) {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.executableName = executableName
        self.version = version
        self.buildVersion = buildVersion
        self.minimumSystemVersion = minimumSystemVersion
        self.urlTypes = [
            PerchHAInfoPlistURLType(
                name: "\(bundleIdentifier).oauth",
                schemes: [callbackURLScheme]
            )
        ]
    }

    private enum CodingKeys: String, CodingKey {
        case developmentRegion = "CFBundleDevelopmentRegion"
        case executableName = "CFBundleExecutable"
        case bundleIdentifier = "CFBundleIdentifier"
        case infoDictionaryVersion = "CFBundleInfoDictionaryVersion"
        case appName = "CFBundleName"
        case packageType = "CFBundlePackageType"
        case version = "CFBundleShortVersionString"
        case buildVersion = "CFBundleVersion"
        case minimumSystemVersion = "LSMinimumSystemVersion"
        case highResolutionCapable = "NSHighResolutionCapable"
        case agentApplication = "LSUIElement"
        case urlTypes = "CFBundleURLTypes"
    }
}

private struct PerchHAInfoPlistURLType: Encodable {
    let role = PerchHALaunchServicesVerifier.defaultURLTypeRole
    let name: String
    let schemes: [String]

    private enum CodingKeys: String, CodingKey {
        case role = "CFBundleTypeRole"
        case name = "CFBundleURLName"
        case schemes = "CFBundleURLSchemes"
    }
}
