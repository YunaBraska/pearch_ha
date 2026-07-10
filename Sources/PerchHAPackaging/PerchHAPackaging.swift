import CryptoKit
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
    public let iconFileName: String?

    public init(
        appName: String = "PearchHA",
        bundleIdentifier: String = "dev.perchha.app",
        executableName: String = "PerchHA",
        version: String = "0.1.0",
        buildVersion: String = "1",
        minimumSystemVersion: String = "13.0",
        callbackURLScheme: String = "perchha",
        iconFileName: String? = nil
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
        self.iconFileName = try Self.optional(iconFileName, name: "iconFileName")
    }

    public func propertyListData() throws -> Data {
        let plist = PerchHAInfoPlist(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            executableName: executableName,
            version: version,
            buildVersion: buildVersion,
            minimumSystemVersion: minimumSystemVersion,
            callbackURLScheme: callbackURLScheme,
            iconFileName: iconFileName
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

    private static func optional(_ value: String?, name: String) throws -> String? {
        guard let value else {
            return nil
        }
        return try required(value, name: name)
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
    case iconMissing(String)
    case outputExists(String)

    public var description: String {
        switch self {
        case let .executableMissing(path):
            "executable does not exist: \(path)"
        case let .iconMissing(path):
            "icon file does not exist: \(path)"
        case let .outputExists(path):
            "output app already exists: \(path)"
        }
    }
}

public struct PerchHAAppBundleBuildConfiguration: Equatable, Sendable {
    public let executableURL: URL
    public let outputURL: URL
    public let manifest: PerchHAAppBundleManifest
    public let iconURL: URL?
    public let replaceExisting: Bool

    public init(
        executableURL: URL,
        outputURL: URL,
        manifest: PerchHAAppBundleManifest,
        iconURL: URL? = nil,
        replaceExisting: Bool = false
    ) {
        self.executableURL = executableURL
        self.outputURL = outputURL
        self.manifest = manifest
        self.iconURL = iconURL
        self.replaceExisting = replaceExisting
    }
}

public struct PerchHAAppBundleBuildResult: Equatable, Sendable {
    public let appURL: URL
    public let executableURL: URL
    public let infoPlistURL: URL
}

public enum PerchHAOAuthClientWebsiteError: Error, Equatable, CustomStringConvertible, Sendable {
    case blankField(String)
    case invalidClientID(String)
    case invalidRedirectURI(String)
    case outputExists(String)
    case siteMissing(String)
    case siteUnreadable(String)
    case publishedSiteUnreachable(String)
    case publishedSiteHTTPFailure(String, Int)
    case canonicalLinkMissing(String)
    case redirectDeclarationMissing(String)

    public var description: String {
        switch self {
        case let .blankField(name):
            "\(name) is required"
        case let .invalidClientID(value):
            "invalid OAuth client website URL: \(value)"
        case let .invalidRedirectURI(value):
            "invalid OAuth redirect URI: \(value)"
        case let .outputExists(path):
            "output website file already exists: \(path)"
        case let .siteMissing(path):
            "OAuth client website file does not exist: \(path)"
        case let .siteUnreadable(path):
            "OAuth client website file is unreadable: \(path)"
        case let .publishedSiteUnreachable(url):
            "published OAuth client website is unreachable: \(url)"
        case let .publishedSiteHTTPFailure(url, status):
            "published OAuth client website returned HTTP \(status): \(url)"
        case let .canonicalLinkMissing(value):
            "OAuth client website is missing canonical link: \(value)"
        case let .redirectDeclarationMissing(value):
            "OAuth client website is missing redirect declaration in first 10000 bytes: \(value)"
        }
    }
}

public struct PerchHAOAuthClientWebsiteManifest: Equatable, Sendable {
    public let clientID: String
    public let redirectURI: String
    public let appName: String

    public init(
        clientID: String,
        redirectURI: String,
        appName: String = "PearchHA"
    ) throws {
        let normalizedClientID = try Self.required(clientID, name: "clientID")
        let normalizedRedirectURI = try Self.required(redirectURI, name: "redirectURI")
        let normalizedAppName = try Self.required(appName, name: "appName")
        guard Self.isValidClientWebsiteURL(normalizedClientID) else {
            throw PerchHAOAuthClientWebsiteError.invalidClientID(normalizedClientID)
        }
        guard Self.isValidRedirectURI(normalizedRedirectURI) else {
            throw PerchHAOAuthClientWebsiteError.invalidRedirectURI(normalizedRedirectURI)
        }
        self.clientID = normalizedClientID
        self.redirectURI = normalizedRedirectURI
        self.appName = normalizedAppName
    }

    public func htmlData() -> Data {
        Data(html.utf8)
    }

    public var html: String {
        let escapedClientID = Self.escapeHTML(clientID)
        let escapedRedirectURI = Self.escapeHTML(redirectURI)
        let escapedAppName = Self.escapeHTML(appName)
        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escapedAppName) OAuth Redirect</title>
        <link rel="canonical" href="\(escapedClientID)">
        <link rel="redirect_uri" href="\(escapedRedirectURI)">
        <style>
        :root { color-scheme: light dark; }
        body {
          margin: 0;
          font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", sans-serif;
          background: #f5f5f7;
          color: #111827;
        }
        main {
          max-width: 640px;
          margin: 56px auto;
          padding: 0 24px;
        }
        h1 {
          margin: 0 0 12px;
          font-size: 28px;
          line-height: 1.15;
          font-weight: 700;
        }
        p {
          margin: 0 0 18px;
          font-size: 15px;
          line-height: 1.55;
          color: #374151;
        }
        dl {
          margin: 28px 0 0;
          padding: 0;
        }
        .row {
          padding: 14px 0;
          border-top: 1px solid #d1d5db;
        }
        dt {
          margin: 0 0 6px;
          font-size: 12px;
          line-height: 1.4;
          font-weight: 600;
          color: #6b7280;
        }
        dd {
          margin: 0;
          font-size: 14px;
          line-height: 1.5;
          word-break: break-word;
        }
        code {
          font-family: ui-monospace, SFMono-Regular, SF Mono, Menlo, monospace;
          font-size: 13px;
        }
        @media (prefers-color-scheme: dark) {
          body { background: #111827; color: #f9fafb; }
          p { color: #d1d5db; }
          .row { border-top-color: #374151; }
          dt { color: #9ca3af; }
        }
        </style>
        </head>
        <body>
        <main>
        <h1>\(escapedAppName) OAuth Redirect</h1>
        <p>This page publishes the native redirect declaration required for Home Assistant OAuth sign-in.</p>
        <dl>
        <div class="row">
        <dt>Client website</dt>
        <dd><code>\(escapedClientID)</code></dd>
        </div>
        <div class="row">
        <dt>Redirect URI</dt>
        <dd><code>\(escapedRedirectURI)</code></dd>
        </div>
        </dl>
        </main>
        </body>
        </html>
        """
    }

    fileprivate var canonicalLinkHTML: String {
        #"<link rel="canonical" href="\#(Self.escapeHTML(clientID))">"#
    }

    fileprivate var redirectLinkHTML: String {
        #"<link rel="redirect_uri" href="\#(Self.escapeHTML(redirectURI))">"#
    }

    private static func required(_ value: String, name: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PerchHAOAuthClientWebsiteError.blankField(name)
        }
        return trimmed
    }

    private static func isValidClientWebsiteURL(_ value: String) -> Bool {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host,
              !host.isEmpty
        else {
            return false
        }
        return true
    }

    private static func isValidRedirectURI(_ value: String) -> Bool {
        guard let url = URL(string: value),
              let scheme = url.scheme?.trimmingCharacters(in: .whitespacesAndNewlines),
              !scheme.isEmpty
        else {
            return false
        }
        return true
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

public struct PerchHAOAuthClientWebsiteBuildConfiguration: Equatable, Sendable {
    public let outputURL: URL
    public let manifest: PerchHAOAuthClientWebsiteManifest
    public let replaceExisting: Bool

    public init(
        outputURL: URL,
        manifest: PerchHAOAuthClientWebsiteManifest,
        replaceExisting: Bool = false
    ) {
        self.outputURL = outputURL
        self.manifest = manifest
        self.replaceExisting = replaceExisting
    }
}

public struct PerchHAOAuthClientWebsiteBuildResult: Equatable, Sendable {
    public let siteURL: URL
    public let clientID: String
    public let redirectURI: String
}

public struct PerchHAOAuthClientWebsiteBuilder {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func build(
        _ configuration: PerchHAOAuthClientWebsiteBuildConfiguration
    ) throws -> PerchHAOAuthClientWebsiteBuildResult {
        let outputURL = configuration.outputURL
        if fileManager.fileExists(atPath: outputURL.path) {
            guard configuration.replaceExisting else {
                throw PerchHAOAuthClientWebsiteError.outputExists(outputURL.path)
            }
            try fileManager.removeItem(at: outputURL)
        }
        let parentURL = outputURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
        try configuration.manifest.htmlData().write(to: outputURL, options: .atomic)
        return PerchHAOAuthClientWebsiteBuildResult(
            siteURL: outputURL,
            clientID: configuration.manifest.clientID,
            redirectURI: configuration.manifest.redirectURI
        )
    }
}

public struct PerchHAOAuthClientWebsiteVerificationConfiguration: Equatable, Sendable {
    public let siteURL: URL
    public let manifest: PerchHAOAuthClientWebsiteManifest

    public init(siteURL: URL, manifest: PerchHAOAuthClientWebsiteManifest) {
        self.siteURL = siteURL
        self.manifest = manifest
    }
}

public struct PerchHAOAuthClientWebsiteVerificationResult: Equatable, Sendable {
    public let siteURL: URL
    public let clientID: String
    public let redirectURI: String
}

public struct PerchHAOAuthClientWebsiteVerifier {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func verify(
        _ configuration: PerchHAOAuthClientWebsiteVerificationConfiguration
    ) throws -> PerchHAOAuthClientWebsiteVerificationResult {
        let siteURL = configuration.siteURL
        guard fileManager.fileExists(atPath: siteURL.path) else {
            throw PerchHAOAuthClientWebsiteError.siteMissing(siteURL.path)
        }
        let data: Data
        do {
            data = try Data(contentsOf: siteURL)
        } catch {
            throw PerchHAOAuthClientWebsiteError.siteUnreadable(siteURL.path)
        }
        return try verify(
            data: data,
            siteURL: siteURL,
            manifest: configuration.manifest
        )
    }

    public func verify(
        data: Data,
        siteURL: URL,
        manifest: PerchHAOAuthClientWebsiteManifest
    ) throws -> PerchHAOAuthClientWebsiteVerificationResult {
        let html = String(decoding: data, as: UTF8.self)
        guard html.contains(manifest.canonicalLinkHTML) else {
            throw PerchHAOAuthClientWebsiteError.canonicalLinkMissing(manifest.clientID)
        }
        let prefix = String(decoding: data.prefix(10_000), as: UTF8.self)
        guard prefix.contains(manifest.redirectLinkHTML) else {
            throw PerchHAOAuthClientWebsiteError.redirectDeclarationMissing(manifest.redirectURI)
        }
        return PerchHAOAuthClientWebsiteVerificationResult(
            siteURL: siteURL,
            clientID: manifest.clientID,
            redirectURI: manifest.redirectURI
        )
    }
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
        if let iconURL = configuration.iconURL,
           !fileManager.fileExists(atPath: iconURL.path)
        {
            throw PerchHAAppBundleBuildError.iconMissing(iconURL.path)
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

        if let iconURL = configuration.iconURL {
            try fileManager.copyItem(
                at: iconURL,
                to: resourcesURL.appendingPathComponent(iconURL.lastPathComponent, isDirectory: false)
            )
        }

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

public struct PerchHACommandResult: Equatable, Sendable {
    public let status: Int32
    public let output: String

    public init(status: Int32, output: String) {
        self.status = status
        self.output = output
    }
}

public enum PerchHAReleasePreflightIssue: Error, Equatable, CustomStringConvertible, Sendable {
    case securityToolMissing(String)
    case xcrunMissing(String)
    case blankSigningIdentity
    case adHocSigningIdentity
    case nonDeveloperIDSigningIdentity
    case signingIdentityCheckFailed(status: Int32)
    case signingIdentityNotFound
    case blankNotaryProfile
    case notaryProfileCheckFailed(status: Int32)

    public var description: String {
        switch self {
        case let .securityToolMissing(path):
            "security tool does not exist: \(path)"
        case let .xcrunMissing(path):
            "xcrun does not exist: \(path)"
        case .blankSigningIdentity:
            "Developer ID signing identity is required"
        case .adHocSigningIdentity:
            "ad-hoc signing is not valid for a credentialed release"
        case .nonDeveloperIDSigningIdentity:
            "signing identity must be a Developer ID Application identity"
        case let .signingIdentityCheckFailed(status):
            "Developer ID identity check failed with status \(status)"
        case .signingIdentityNotFound:
            "Developer ID signing identity was not found in the login keychain"
        case .blankNotaryProfile:
            "notary keychain profile is required"
        case let .notaryProfileCheckFailed(status):
            "notary keychain profile check failed with status \(status)"
        }
    }

    public var diagnosticCode: String {
        switch self {
        case .securityToolMissing(_):
            "securityToolMissing"
        case .xcrunMissing(_):
            "xcrunMissing"
        case .blankSigningIdentity:
            "blankSigningIdentity"
        case .adHocSigningIdentity:
            "adHocSigningIdentity"
        case .nonDeveloperIDSigningIdentity:
            "nonDeveloperIDSigningIdentity"
        case .signingIdentityCheckFailed(_):
            "signingIdentityCheckFailed"
        case .signingIdentityNotFound:
            "signingIdentityNotFound"
        case .blankNotaryProfile:
            "blankNotaryProfile"
        case .notaryProfileCheckFailed(_):
            "notaryProfileCheckFailed"
        }
    }
}

public struct PerchHAReleasePreflightConfiguration: Equatable, Sendable {
    public let signingIdentity: String?
    public let notaryProfile: String?

    public init(signingIdentity: String?, notaryProfile: String?) {
        self.signingIdentity = signingIdentity
        self.notaryProfile = notaryProfile
    }
}

public struct PerchHAReleasePreflightReport: Equatable, Sendable {
    public let signingIdentityAvailable: Bool
    public let notaryProfileAvailable: Bool
    public let issues: [PerchHAReleasePreflightIssue]

    public init(
        signingIdentityAvailable: Bool,
        notaryProfileAvailable: Bool,
        issues: [PerchHAReleasePreflightIssue]
    ) {
        self.signingIdentityAvailable = signingIdentityAvailable
        self.notaryProfileAvailable = notaryProfileAvailable
        self.issues = issues
    }

    public var isReadyForCredentialedRelease: Bool {
        issues.isEmpty && signingIdentityAvailable && notaryProfileAvailable
    }

    public func diagnostic(
        configuration: PerchHAReleasePreflightConfiguration
    ) -> PerchHAReleasePreflightDiagnostic {
        PerchHAReleasePreflightDiagnostic(report: self, configuration: configuration)
    }

    public func nextSteps(configuration: PerchHAReleasePreflightConfiguration) -> [String] {
        if isReadyForCredentialedRelease {
            return [
                "Credentialed release preflight passed. Build the signed, notarized DMG with the credentialed packaging command from docs/RELEASE.md."
            ]
        }

        var result: [String] = []
        if issues.contains(where: Self.isDeveloperToolIssue) {
            result.append(
                "Install or select Apple developer tools so both security and xcrun are available before rerunning release preflight."
            )
        }
        if issues.contains(where: Self.isSigningIdentityIssue) {
            result.append(
                "Choose a Developer ID Application signing identity from the login keychain, then rerun release preflight."
            )
        }
        if issues.contains(where: Self.isNotaryProfileIssue) {
            result.append(
                "Create or repair a usable notarytool Keychain profile, then rerun release preflight."
            )
        }
        if result.isEmpty {
            result.append(
                "Rerun release preflight after fixing the reported packaging credentials and toolchain issues."
            )
        }
        return result
    }

    public func suggestedCommands(configuration: PerchHAReleasePreflightConfiguration) -> [String] {
        var commands: [String] = []
        if issues.contains(where: Self.isSigningIdentityIssue) {
            commands.append("security find-identity -p codesigning -v")
        }
        if issues.contains(where: Self.isNotaryProfileIssue) {
            commands.append(
                "xcrun notarytool history --keychain-profile \(PerchHAReleasePreflightGuidance.exampleNotaryProfile) --output-format json --no-progress"
            )
        }
        if isReadyForCredentialedRelease {
            commands.append(PerchHAReleasePreflightGuidance.credentialedPackageCommand)
        } else {
            commands.append(PerchHAReleasePreflightGuidance.preflightCommand(json: true))
        }
        return commands
    }

    private static func isDeveloperToolIssue(_ issue: PerchHAReleasePreflightIssue) -> Bool {
        switch issue {
        case .securityToolMissing, .xcrunMissing:
            true
        default:
            false
        }
    }

    private static func isSigningIdentityIssue(_ issue: PerchHAReleasePreflightIssue) -> Bool {
        switch issue {
        case .blankSigningIdentity, .adHocSigningIdentity, .nonDeveloperIDSigningIdentity, .signingIdentityCheckFailed, .signingIdentityNotFound:
            true
        default:
            false
        }
    }

    private static func isNotaryProfileIssue(_ issue: PerchHAReleasePreflightIssue) -> Bool {
        switch issue {
        case .blankNotaryProfile, .notaryProfileCheckFailed:
            true
        default:
            false
        }
    }
}

public enum PerchHAReleasePreflightPresence: String, Codable, Equatable, Sendable {
    case present
    case missing

    public init(_ value: Bool) {
        self = value ? .present : .missing
    }
}

public enum PerchHAReleasePreflightState: String, Codable, Equatable, Sendable {
    case ready
    case blocked

    public init(_ value: Bool) {
        self = value ? .ready : .blocked
    }
}

public struct PerchHAReleasePreflightDiagnosticIssue: Codable, Equatable, Sendable {
    public let code: String
    public let description: String

    public init(code: String, description: String) {
        self.code = code
        self.description = description
    }
}

public struct PerchHAReleasePreflightDiagnostic: Codable, Equatable, Sendable {
    public let signingIdentity: PerchHAReleasePreflightPresence
    public let notaryProfile: PerchHAReleasePreflightPresence
    public let developerIDIdentity: PerchHAReleasePreflightState
    public let notaryKeychainProfile: PerchHAReleasePreflightState
    public let credentialedRelease: PerchHAReleasePreflightState
    public let issues: [PerchHAReleasePreflightDiagnosticIssue]
    public let nextSteps: [String]
    public let suggestedCommands: [String]

    public init(
        signingIdentity: PerchHAReleasePreflightPresence,
        notaryProfile: PerchHAReleasePreflightPresence,
        developerIDIdentity: PerchHAReleasePreflightState,
        notaryKeychainProfile: PerchHAReleasePreflightState,
        credentialedRelease: PerchHAReleasePreflightState,
        issues: [PerchHAReleasePreflightDiagnosticIssue],
        nextSteps: [String],
        suggestedCommands: [String]
    ) {
        self.signingIdentity = signingIdentity
        self.notaryProfile = notaryProfile
        self.developerIDIdentity = developerIDIdentity
        self.notaryKeychainProfile = notaryKeychainProfile
        self.credentialedRelease = credentialedRelease
        self.issues = issues
        self.nextSteps = nextSteps
        self.suggestedCommands = suggestedCommands
    }

    public init(
        report: PerchHAReleasePreflightReport,
        configuration: PerchHAReleasePreflightConfiguration
    ) {
        signingIdentity = PerchHAReleasePreflightPresence(
            Self.isPresent(configuration.signingIdentity)
        )
        notaryProfile = PerchHAReleasePreflightPresence(
            Self.isPresent(configuration.notaryProfile)
        )
        developerIDIdentity = PerchHAReleasePreflightState(report.signingIdentityAvailable)
        notaryKeychainProfile = PerchHAReleasePreflightState(report.notaryProfileAvailable)
        credentialedRelease = PerchHAReleasePreflightState(report.isReadyForCredentialedRelease)
        issues = report.issues.map {
            PerchHAReleasePreflightDiagnosticIssue(
                code: $0.diagnosticCode,
                description: $0.description
            )
        }
        nextSteps = report.nextSteps(configuration: configuration)
        suggestedCommands = report.suggestedCommands(configuration: configuration)
    }

    private static func isPresent(_ value: String?) -> Bool {
        guard let value else {
            return false
        }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public struct PerchHAReleasePreflightChecker {
    public static let defaultSecurityURL = URL(fileURLWithPath: "/usr/bin/security")

    private let fileManager: FileManager
    private let securityURL: URL
    private let xcrunURL: URL
    private let commandRunner: any PerchHACommandRunning

    public init(
        fileManager: FileManager = .default,
        securityURL: URL = Self.defaultSecurityURL,
        xcrunURL: URL = PerchHANotarySubmitter.defaultXcrunURL,
        commandRunner: any PerchHACommandRunning = PerchHAFoundationCommandRunner()
    ) {
        self.fileManager = fileManager
        self.securityURL = securityURL
        self.xcrunURL = xcrunURL
        self.commandRunner = commandRunner
    }

    public func check(_ configuration: PerchHAReleasePreflightConfiguration) throws -> PerchHAReleasePreflightReport {
        var issues: [PerchHAReleasePreflightIssue] = []
        let signingIdentity = configuration.signingIdentity?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let notaryProfile = configuration.notaryProfile?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let signingIdentityAvailable = try checkSigningIdentity(signingIdentity, issues: &issues)
        let notaryProfileAvailable = try checkNotaryProfile(notaryProfile, issues: &issues)

        return PerchHAReleasePreflightReport(
            signingIdentityAvailable: signingIdentityAvailable,
            notaryProfileAvailable: notaryProfileAvailable,
            issues: issues
        )
    }

    private func checkSigningIdentity(
        _ signingIdentity: String,
        issues: inout [PerchHAReleasePreflightIssue]
    ) throws -> Bool {
        guard !signingIdentity.isEmpty else {
            issues.append(.blankSigningIdentity)
            return false
        }
        guard signingIdentity != "-" else {
            issues.append(.adHocSigningIdentity)
            return false
        }
        guard signingIdentity.hasPrefix("Developer ID Application:") else {
            issues.append(.nonDeveloperIDSigningIdentity)
            return false
        }
        guard fileManager.isExecutableFile(atPath: securityURL.path) else {
            issues.append(.securityToolMissing(securityURL.path))
            return false
        }

        let result = try commandRunner.run(
            executableURL: securityURL,
            arguments: ["find-identity", "-p", "codesigning", "-v"]
        )
        guard result.status == 0 else {
            issues.append(.signingIdentityCheckFailed(status: result.status))
            return false
        }
        guard codeSigningIdentities(in: result.output).contains(signingIdentity) else {
            issues.append(.signingIdentityNotFound)
            return false
        }
        return true
    }

    private func checkNotaryProfile(
        _ notaryProfile: String,
        issues: inout [PerchHAReleasePreflightIssue]
    ) throws -> Bool {
        guard !notaryProfile.isEmpty else {
            issues.append(.blankNotaryProfile)
            return false
        }
        guard fileManager.isExecutableFile(atPath: xcrunURL.path) else {
            issues.append(.xcrunMissing(xcrunURL.path))
            return false
        }

        let result = try commandRunner.run(
            executableURL: xcrunURL,
            arguments: [
                "notarytool",
                "history",
                "--keychain-profile",
                notaryProfile,
                "--output-format",
                "json",
                "--no-progress"
            ]
        )
        guard result.status == 0 else {
            issues.append(.notaryProfileCheckFailed(status: result.status))
            return false
        }
        return true
    }

    private func codeSigningIdentities(in output: String) -> [String] {
        output
            .split(separator: "\n")
            .compactMap { line -> String? in
                guard let firstQuote = line.firstIndex(of: "\""),
                      let lastQuote = line.lastIndex(of: "\""),
                      firstQuote < lastQuote
                else {
                    return nil
                }
                return String(line[line.index(after: firstQuote)..<lastQuote])
            }
    }
}

public enum PerchHAReleasePreflightGuidance {
    public static let exampleSigningIdentity = #"Developer ID Application: Example (TEAMID)"#
    public static let exampleNotaryProfile = "perchha-release"

    public static func preflightCommand(json: Bool) -> String {
        let jsonFlag = json ? " --json" : ""
        return #"swift run perchha-package-app --release-preflight\#(jsonFlag) --sign-identity "\#(exampleSigningIdentity)" --notary-profile \#(exampleNotaryProfile)"#
    }

    public static var credentialedPackageCommand: String {
        #"""
        swift run perchha-package-app --executable .build/release/PerchHA --output .build/PerchHA.app --callback-scheme perchha --replace --verify-launch-services --sign-identity "\#(exampleSigningIdentity)" --verify-signature --package-dmg --verify-dmg --verify-dmg-contents --notary-profile \#(exampleNotaryProfile) --release-manifest .build/perchha-release-manifest.json --snapshot-dir .build/perchha-snapshots/current
        """#
    }
}

public protocol PerchHACommandRunning: Sendable {
    func run(executableURL: URL, arguments: [String]) throws -> PerchHACommandResult
}

public struct PerchHAFoundationCommandRunner: PerchHACommandRunning {
    public init() {}

    public func run(executableURL: URL, arguments: [String]) throws -> PerchHACommandResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return PerchHACommandResult(
            status: process.terminationStatus,
            output: String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }
}

public enum PerchHAReleaseEvidenceError: Error, Equatable, CustomStringConvertible, Sendable {
    case appBundleMissing(String)
    case infoPlistMissing(String)
    case infoPlistUnreadable(String)
    case dmgMissing(String)
    case screenshotDirectoryRequired
    case screenshotDirectoryMissing(String)
    case screenshotsMissing(String)
    case requiredScreenshotMissing(name: String, directory: String)
    case reviewBaselineMissing(String)
    case invalidReleaseStatus(String)

    public var description: String {
        switch self {
        case let .appBundleMissing(path):
            "release app bundle does not exist: \(path)"
        case let .infoPlistMissing(path):
            "release app Info.plist does not exist: \(path)"
        case let .infoPlistUnreadable(path):
            "release app Info.plist is unreadable: \(path)"
        case let .dmgMissing(path):
            "release DMG does not exist: \(path)"
        case .screenshotDirectoryRequired:
            "release screenshot directory is required for retained release evidence"
        case let .screenshotDirectoryMissing(path):
            "release screenshot directory does not exist: \(path)"
        case let .screenshotsMissing(path):
            "release screenshot directory contains no PNG files: \(path)"
        case let .requiredScreenshotMissing(name, directory):
            "release screenshot directory is missing required screenshot evidence \(name): \(directory)"
        case let .reviewBaselineMissing(path):
            "release review baseline does not exist: \(path)"
        case let .invalidReleaseStatus(reason):
            "release evidence status is invalid: \(reason)"
        }
    }
}

public enum PerchHAReleaseEvidenceScreenshots {
    public static let requiredNames = [
        "built-in-controls-light.png",
        "connected-dark-increased-contrast.png",
        "connected-dark.png",
        "connected-light-reduced-motion.png",
        "connected-light.png",
        "connecting-light.png",
        "empty-light.png",
        "error-dark.png",
        "first-run-light.png",
        "history-loaded-light.png",
        "history-loaded-light-increased-contrast.png",
        "reconnecting-light.png",
        "review-contact-sheet.png",
        "settings-about-update-light.png",
        "settings-selection-light.png",
        "signing-in-light.png"
    ]
}

public enum PerchHAReleaseEvidenceReview {
    public static let currentBaselineFilename = "review-baseline-current.json"
    public static let expectedBaselineFilename = "review-baseline-expected.json"
}

public struct PerchHAReleaseEvidenceConfiguration: Equatable, Sendable {
    public let appURL: URL
    public let dmgURL: URL
    public let manifestURL: URL
    public let oauthClientWebsiteURL: URL?
    public let screenshotDirectoryURL: URL?
    public let reviewBaselineURL: URL?
    public let requiredScreenshotNames: [String]
    public let signingIdentity: String?
    public let signatureVerified: Bool
    public let notarySubmitted: Bool
    public let stapled: Bool

    public init(
        appURL: URL,
        dmgURL: URL,
        manifestURL: URL,
        oauthClientWebsiteURL: URL? = nil,
        screenshotDirectoryURL: URL? = nil,
        reviewBaselineURL: URL? = nil,
        requiredScreenshotNames: [String] = [],
        signingIdentity: String? = nil,
        signatureVerified: Bool = false,
        notarySubmitted: Bool = false,
        stapled: Bool = false
    ) {
        self.appURL = appURL
        self.dmgURL = dmgURL
        self.manifestURL = manifestURL
        self.oauthClientWebsiteURL = oauthClientWebsiteURL
        self.screenshotDirectoryURL = screenshotDirectoryURL
        self.reviewBaselineURL = reviewBaselineURL
        self.requiredScreenshotNames = normalizedReleaseScreenshotNames(requiredScreenshotNames)
        self.signingIdentity = signingIdentity
        self.signatureVerified = signatureVerified
        self.notarySubmitted = notarySubmitted
        self.stapled = stapled
    }
}

public struct PerchHAReleaseEvidenceManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let app: PerchHAReleaseEvidenceApp
    public let dmg: PerchHAReleaseEvidenceArtifact
    public let oauthClientWebsite: PerchHAReleaseEvidenceArtifact?
    public let screenshots: [PerchHAReleaseEvidenceArtifact]
    public let reviewBaseline: PerchHAReleaseEvidenceArtifact?
    public let signing: PerchHAReleaseEvidenceSigning
    public let notarization: PerchHAReleaseEvidenceNotarization
}

public struct PerchHAReleaseEvidenceApp: Codable, Equatable, Sendable {
    public let path: String
    public let name: String
    public let bundleIdentifier: String
    public let version: String
    public let buildVersion: String
    public let minimumSystemVersion: String
    public let callbackURLSchemes: [String]
}

public struct PerchHAReleaseEvidenceArtifact: Codable, Equatable, Sendable {
    public let name: String
    public let path: String
    public let sha256: String
    public let byteCount: UInt64
}

public struct PerchHAReleaseEvidenceSigning: Codable, Equatable, Sendable {
    public let identity: String?
    public let adHoc: Bool
    public let signatureVerified: Bool
}

public struct PerchHAReleaseEvidenceNotarization: Codable, Equatable, Sendable {
    public let submitted: Bool
    public let stapled: Bool
}

private func isDeveloperIDApplicationIdentity(_ identity: String?) -> Bool {
    identity?.hasPrefix("Developer ID Application:") == true
}

private func releaseStatusProblem(
    signing: PerchHAReleaseEvidenceSigning,
    notarization: PerchHAReleaseEvidenceNotarization
) -> String? {
    if signing.adHoc && signing.identity != "-" {
        return "ad-hoc signing requires identity '-'"
    }
    if !signing.adHoc && signing.identity == "-" {
        return "identity '-' must be marked ad-hoc"
    }
    if notarization.stapled && !notarization.submitted {
        return "stapled artifact requires submitted notarization"
    }
    if notarization.submitted {
        guard signing.signatureVerified,
              isDeveloperIDApplicationIdentity(signing.identity),
              !signing.adHoc
        else {
            return "notarized artifact requires a verified Developer ID Application signature"
        }
    }
    return nil
}

private func normalizedReleaseScreenshotNames(_ names: [String]) -> [String] {
    var seen = Set<String>()
    var normalized: [String] = []
    for name in names {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && seen.insert(trimmed).inserted {
            normalized.append(trimmed)
        }
    }
    return normalized
}

private func firstMissingRequiredScreenshotName(
    _ requiredNames: [String],
    screenshots: [PerchHAReleaseEvidenceArtifact]
) -> String? {
    let recordedNames = Set(screenshots.map(\.name))
    return requiredNames.first { !recordedNames.contains($0) }
}

private func normalizedReleaseEvidenceURL(_ url: URL, isDirectory: Bool) -> URL {
    URL(fileURLWithPath: url.path, isDirectory: isDirectory)
        .standardizedFileURL
        .resolvingSymlinksInPath()
}

private func releaseEvidenceStoredPath(
    for artifactURL: URL,
    relativeTo manifestDirectoryURL: URL,
    isDirectory: Bool
) -> String {
    let artifactPath = normalizedReleaseEvidenceURL(artifactURL, isDirectory: isDirectory).path
    let manifestDirectoryPath = normalizedReleaseEvidenceURL(manifestDirectoryURL, isDirectory: true).path
    return relativePath(from: manifestDirectoryPath, to: artifactPath)
}

private func resolveReleaseEvidencePath(
    _ storedPath: String,
    manifestURL: URL,
    isDirectory: Bool
) -> URL {
    if NSString(string: storedPath).isAbsolutePath {
        return normalizedReleaseEvidenceURL(
            URL(fileURLWithPath: storedPath, isDirectory: isDirectory),
            isDirectory: isDirectory
        )
    }
    return normalizedReleaseEvidenceURL(
        URL(
            fileURLWithPath: manifestURL.deletingLastPathComponent().path
                .appending("/" + storedPath),
            isDirectory: isDirectory
        ),
        isDirectory: isDirectory
    )
}

private func relativePath(from basePath: String, to targetPath: String) -> String {
    let baseComponents = URL(fileURLWithPath: basePath, isDirectory: true).standardizedFileURL.pathComponents
    let targetComponents = URL(fileURLWithPath: targetPath, isDirectory: false).standardizedFileURL.pathComponents
    let sharedCount = zip(baseComponents, targetComponents).prefix { lhs, rhs in lhs == rhs }.count
    let remainingBase = baseComponents.dropFirst(sharedCount)
    let remainingTarget = targetComponents.dropFirst(sharedCount)
    let upward = Array(repeating: "..", count: remainingBase.count)
    let components = upward + remainingTarget
    if components.isEmpty {
        return "."
    }
    return NSString.path(withComponents: components)
}

public enum PerchHAReleaseEvidenceVerificationError: Error, Equatable, CustomStringConvertible, Sendable {
    case manifestMissing(String)
    case manifestUnreadable(String)
    case unsupportedSchemaVersion(Int)
    case appBundleMissing(String)
    case infoPlistMissing(String)
    case infoPlistUnreadable(String)
    case appMetadataMismatch(field: String, expected: String, actual: String)
    case artifactMissing(String)
    case artifactSHA256Mismatch(path: String, expected: String, actual: String)
    case artifactByteCountMismatch(path: String, expected: UInt64, actual: UInt64)
    case screenshotsMissing(String)
    case requiredScreenshotMissing(name: String, manifest: String)
    case invalidReleaseStatus(String)
    case codeSignatureVerificationFailed(String)
    case xcrunMissing(String)
    case staplerValidationFailed(status: Int32, output: String)

    public var description: String {
        switch self {
        case let .manifestMissing(path):
            "release manifest does not exist: \(path)"
        case let .manifestUnreadable(path):
            "release manifest is unreadable: \(path)"
        case let .unsupportedSchemaVersion(version):
            "unsupported release manifest schema version: \(version)"
        case let .appBundleMissing(path):
            "release manifest app bundle does not exist: \(path)"
        case let .infoPlistMissing(path):
            "release manifest app Info.plist does not exist: \(path)"
        case let .infoPlistUnreadable(path):
            "release manifest app Info.plist is unreadable: \(path)"
        case let .appMetadataMismatch(field, expected, actual):
            "release manifest app \(field) mismatch: expected \(expected), got \(actual)"
        case let .artifactMissing(path):
            "release manifest artifact does not exist: \(path)"
        case let .artifactSHA256Mismatch(path, expected, actual):
            "release manifest artifact SHA-256 mismatch for \(path): expected \(expected), got \(actual)"
        case let .artifactByteCountMismatch(path, expected, actual):
            "release manifest artifact byte count mismatch for \(path): expected \(expected), got \(actual)"
        case let .screenshotsMissing(path):
            "release manifest records no screenshot evidence: \(path)"
        case let .requiredScreenshotMissing(name, manifest):
            "release manifest is missing required screenshot evidence \(name): \(manifest)"
        case let .invalidReleaseStatus(reason):
            "release manifest status is invalid: \(reason)"
        case let .codeSignatureVerificationFailed(reason):
            "release manifest app signature verification failed: \(reason)"
        case let .xcrunMissing(path):
            "xcrun does not exist: \(path)"
        case let .staplerValidationFailed(status, output):
            "release manifest stapled artifact validation failed with status \(status): \(output)"
        }
    }
}

public struct PerchHAReleaseEvidenceVerificationConfiguration: Equatable, Sendable {
    public let manifestURL: URL
    public let requiredScreenshotNames: [String]

    public init(manifestURL: URL, requiredScreenshotNames: [String] = []) {
        self.manifestURL = manifestURL
        self.requiredScreenshotNames = normalizedReleaseScreenshotNames(requiredScreenshotNames)
    }
}

public struct PerchHAReleaseEvidenceVerificationReport: Equatable, Sendable {
    public let manifestURL: URL
    public let appURL: URL
    public let dmgURL: URL
    public let dmgSHA256: String
    public let oauthClientWebsiteURL: URL?
    public let screenshotCount: Int
    public let credentialedReleaseReady: Bool

    public init(
        manifestURL: URL,
        appURL: URL,
        dmgURL: URL,
        dmgSHA256: String,
        oauthClientWebsiteURL: URL?,
        screenshotCount: Int,
        credentialedReleaseReady: Bool
    ) {
        self.manifestURL = manifestURL
        self.appURL = appURL
        self.dmgURL = dmgURL
        self.dmgSHA256 = dmgSHA256
        self.oauthClientWebsiteURL = oauthClientWebsiteURL
        self.screenshotCount = screenshotCount
        self.credentialedReleaseReady = credentialedReleaseReady
    }
}

public enum PerchHAReleaseEvidenceBundleError: Error, Equatable, CustomStringConvertible, Sendable {
    case manifestMissing(String)
    case manifestUnreadable(String)
    case outputExists(String)

    public var description: String {
        switch self {
        case let .manifestMissing(path):
            "release manifest does not exist: \(path)"
        case let .manifestUnreadable(path):
            "release manifest is unreadable: \(path)"
        case let .outputExists(path):
            "release evidence bundle output already exists: \(path)"
        }
    }
}

public struct PerchHAReleaseEvidenceBundleConfiguration: Equatable, Sendable {
    public let manifestURL: URL
    public let outputDirectoryURL: URL
    public let replaceExisting: Bool

    public init(manifestURL: URL, outputDirectoryURL: URL, replaceExisting: Bool = false) {
        self.manifestURL = manifestURL
        self.outputDirectoryURL = outputDirectoryURL
        self.replaceExisting = replaceExisting
    }
}

public struct PerchHAReleaseEvidenceBundleResult: Equatable, Sendable {
    public let bundleDirectoryURL: URL
    public let manifestURL: URL
}

public struct PerchHAReleaseEvidenceVerifier {
    private let fileManager: FileManager
    private let codesignURL: URL
    private let xcrunURL: URL
    private let commandRunner: any PerchHACommandRunning

    public init(
        fileManager: FileManager = .default,
        codesignURL: URL = PerchHACodeSigner.defaultCodesignURL,
        xcrunURL: URL = PerchHANotarySubmitter.defaultXcrunURL,
        commandRunner: any PerchHACommandRunning = PerchHAFoundationCommandRunner()
    ) {
        self.fileManager = fileManager
        self.codesignURL = codesignURL
        self.xcrunURL = xcrunURL
        self.commandRunner = commandRunner
    }

    @discardableResult
    public func verify(
        _ configuration: PerchHAReleaseEvidenceVerificationConfiguration
    ) throws -> PerchHAReleaseEvidenceVerificationReport {
        let manifestURL = normalizedReleaseEvidenceURL(configuration.manifestURL, isDirectory: false)
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw PerchHAReleaseEvidenceVerificationError.manifestMissing(manifestURL.path)
        }
        let manifest: PerchHAReleaseEvidenceManifest
        do {
            manifest = try JSONDecoder().decode(
                PerchHAReleaseEvidenceManifest.self,
                from: Data(contentsOf: manifestURL)
            )
        } catch {
            throw PerchHAReleaseEvidenceVerificationError.manifestUnreadable(manifestURL.path)
        }

        guard manifest.schemaVersion == 1 else {
            throw PerchHAReleaseEvidenceVerificationError.unsupportedSchemaVersion(manifest.schemaVersion)
        }
        try verifyStatus(manifest)
        guard !manifest.screenshots.isEmpty else {
            throw PerchHAReleaseEvidenceVerificationError.screenshotsMissing(manifestURL.path)
        }
        try verifyRequiredScreenshots(
            configuration.requiredScreenshotNames,
            screenshots: manifest.screenshots,
            manifestURL: manifestURL
        )

        let resolvedAppURL = resolveReleaseEvidencePath(manifest.app.path, manifestURL: manifestURL, isDirectory: true)
        let resolvedDmgURL = resolveReleaseEvidencePath(manifest.dmg.path, manifestURL: manifestURL, isDirectory: false)
        let resolvedOAuthClientWebsiteURL = manifest.oauthClientWebsite.map {
            resolveReleaseEvidencePath($0.path, manifestURL: manifestURL, isDirectory: false)
        }
        let actualApp = try appEvidence(resolvedAppURL)
        try verifyApp(expected: manifest.app, expectedURL: resolvedAppURL, actual: actualApp)
        try verifyCodeSignatureIfRecorded(manifest, appURL: resolvedAppURL)
        try verifyStapledArtifactIfRecorded(manifest, dmgURL: resolvedDmgURL)
        try verifyArtifact(manifest.dmg, manifestURL: manifestURL)
        if let oauthClientWebsite = manifest.oauthClientWebsite {
            try verifyArtifact(oauthClientWebsite, manifestURL: manifestURL)
        }
        try manifest.screenshots.forEach { try verifyArtifact($0, manifestURL: manifestURL) }
        if let reviewBaseline = manifest.reviewBaseline {
            try verifyArtifact(reviewBaseline, manifestURL: manifestURL)
        }

        return PerchHAReleaseEvidenceVerificationReport(
            manifestURL: manifestURL,
            appURL: resolvedAppURL,
            dmgURL: resolvedDmgURL,
            dmgSHA256: manifest.dmg.sha256,
            oauthClientWebsiteURL: resolvedOAuthClientWebsiteURL,
            screenshotCount: manifest.screenshots.count,
            credentialedReleaseReady: manifest.signing.signatureVerified
                && isDeveloperIDApplicationIdentity(manifest.signing.identity)
                && !manifest.signing.adHoc
                && manifest.notarization.submitted
                && manifest.notarization.stapled
        )
    }

    private func verifyStatus(_ manifest: PerchHAReleaseEvidenceManifest) throws {
        if let problem = releaseStatusProblem(signing: manifest.signing, notarization: manifest.notarization) {
            throw PerchHAReleaseEvidenceVerificationError.invalidReleaseStatus(problem)
        }
    }

    private func verifyRequiredScreenshots(
        _ requiredNames: [String],
        screenshots: [PerchHAReleaseEvidenceArtifact],
        manifestURL: URL
    ) throws {
        guard !requiredNames.isEmpty else {
            return
        }
        if let name = firstMissingRequiredScreenshotName(requiredNames, screenshots: screenshots) {
            throw PerchHAReleaseEvidenceVerificationError.requiredScreenshotMissing(
                name: name,
                manifest: manifestURL.path
            )
        }
    }

    private func verifyCodeSignatureIfRecorded(
        _ manifest: PerchHAReleaseEvidenceManifest,
        appURL: URL
    ) throws {
        guard manifest.signing.signatureVerified else {
            return
        }
        do {
            _ = try PerchHACodeSignatureVerifier(
                fileManager: fileManager,
                codesignURL: codesignURL,
                commandRunner: commandRunner
            ).verify(
                PerchHACodeSignatureVerificationConfiguration(
                    appURL: appURL
                )
            )
        } catch {
            throw PerchHAReleaseEvidenceVerificationError.codeSignatureVerificationFailed(String(describing: error))
        }
    }

    private func verifyStapledArtifactIfRecorded(
        _ manifest: PerchHAReleaseEvidenceManifest,
        dmgURL: URL
    ) throws {
        guard manifest.notarization.stapled else {
            return
        }
        guard fileManager.isExecutableFile(atPath: xcrunURL.path) else {
            throw PerchHAReleaseEvidenceVerificationError.xcrunMissing(xcrunURL.path)
        }
        let result = try commandRunner.run(
            executableURL: xcrunURL,
            arguments: ["stapler", "validate", dmgURL.path]
        )
        guard result.status == 0 else {
            throw PerchHAReleaseEvidenceVerificationError.staplerValidationFailed(
                status: result.status,
                output: result.output
            )
        }
    }

    private func verifyApp(
        expected: PerchHAReleaseEvidenceApp,
        expectedURL: URL,
        actual: PerchHAReleaseEvidenceApp
    ) throws {
        try verifyAppField("path", expected: expectedURL.path, actual: actual.path)
        try verifyAppField("name", expected: expected.name, actual: actual.name)
        try verifyAppField("bundleIdentifier", expected: expected.bundleIdentifier, actual: actual.bundleIdentifier)
        try verifyAppField("version", expected: expected.version, actual: actual.version)
        try verifyAppField("buildVersion", expected: expected.buildVersion, actual: actual.buildVersion)
        try verifyAppField("minimumSystemVersion", expected: expected.minimumSystemVersion, actual: actual.minimumSystemVersion)
        try verifyAppField(
            "callbackURLSchemes",
            expected: expected.callbackURLSchemes.joined(separator: ","),
            actual: actual.callbackURLSchemes.joined(separator: ",")
        )
    }

    private func verifyAppField(
        _ field: String,
        expected: String,
        actual: String
    ) throws {
        guard expected == actual else {
            throw PerchHAReleaseEvidenceVerificationError.appMetadataMismatch(
                field: field,
                expected: expected,
                actual: actual
            )
        }
    }

    private func verifyArtifact(
        _ expected: PerchHAReleaseEvidenceArtifact,
        manifestURL: URL
    ) throws {
        let url = resolveReleaseEvidencePath(expected.path, manifestURL: manifestURL, isDirectory: false)
        guard fileManager.fileExists(atPath: url.path) else {
            throw PerchHAReleaseEvidenceVerificationError.artifactMissing(url.path)
        }
        let data = try Data(contentsOf: url)
        let actualSHA256 = sha256Hex(data)
        guard expected.sha256 == actualSHA256 else {
            throw PerchHAReleaseEvidenceVerificationError.artifactSHA256Mismatch(
                path: url.path,
                expected: expected.sha256,
                actual: actualSHA256
            )
        }
        let actualByteCount = UInt64(data.count)
        guard expected.byteCount == actualByteCount else {
            throw PerchHAReleaseEvidenceVerificationError.artifactByteCountMismatch(
                path: url.path,
                expected: expected.byteCount,
                actual: actualByteCount
            )
        }
    }

    private func appEvidence(_ appURL: URL) throws -> PerchHAReleaseEvidenceApp {
        let normalizedAppURL = URL(fileURLWithPath: appURL.path, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: normalizedAppURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw PerchHAReleaseEvidenceVerificationError.appBundleMissing(normalizedAppURL.path)
        }
        let infoPlistURL = normalizedAppURL.appendingPathComponent("Contents/Info.plist", isDirectory: false)
        guard fileManager.fileExists(atPath: infoPlistURL.path) else {
            throw PerchHAReleaseEvidenceVerificationError.infoPlistMissing(infoPlistURL.path)
        }

        let value: Any
        do {
            value = try PropertyListSerialization.propertyList(
                from: Data(contentsOf: infoPlistURL),
                options: [],
                format: nil
            )
        } catch {
            throw PerchHAReleaseEvidenceVerificationError.infoPlistUnreadable(infoPlistURL.path)
        }
        guard let plist = value as? [String: Any] else {
            throw PerchHAReleaseEvidenceVerificationError.infoPlistUnreadable(infoPlistURL.path)
        }

        return PerchHAReleaseEvidenceApp(
            path: normalizedAppURL.path,
            name: plist["CFBundleName"] as? String ?? normalizedAppURL.deletingPathExtension().lastPathComponent,
            bundleIdentifier: plist["CFBundleIdentifier"] as? String ?? "",
            version: plist["CFBundleShortVersionString"] as? String ?? "",
            buildVersion: plist["CFBundleVersion"] as? String ?? "",
            minimumSystemVersion: plist["LSMinimumSystemVersion"] as? String ?? "",
            callbackURLSchemes: callbackURLSchemes(from: plist)
        )
    }

    private func callbackURLSchemes(from plist: [String: Any]) -> [String] {
        guard let urlTypes = plist["CFBundleURLTypes"] as? [[String: Any]] else {
            return []
        }
        return urlTypes
            .flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
            .sorted()
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

public struct PerchHAReleaseEvidenceBundler {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func bundle(
        _ configuration: PerchHAReleaseEvidenceBundleConfiguration
    ) throws -> PerchHAReleaseEvidenceBundleResult {
        let manifestURL = normalizedReleaseEvidenceURL(configuration.manifestURL, isDirectory: false)
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw PerchHAReleaseEvidenceBundleError.manifestMissing(manifestURL.path)
        }
        let manifest: PerchHAReleaseEvidenceManifest
        do {
            manifest = try JSONDecoder().decode(
                PerchHAReleaseEvidenceManifest.self,
                from: Data(contentsOf: manifestURL)
            )
        } catch {
            throw PerchHAReleaseEvidenceBundleError.manifestUnreadable(manifestURL.path)
        }

        let outputDirectoryURL = normalizedReleaseEvidenceURL(configuration.outputDirectoryURL, isDirectory: true)
        if fileManager.fileExists(atPath: outputDirectoryURL.path) {
            guard configuration.replaceExisting else {
                throw PerchHAReleaseEvidenceBundleError.outputExists(outputDirectoryURL.path)
            }
            try fileManager.removeItem(at: outputDirectoryURL)
        }
        try fileManager.createDirectory(at: outputDirectoryURL, withIntermediateDirectories: true)

        var copiedDestinations = Set<String>()
        let bundledManifest = try bundledManifest(
            from: manifest,
            manifestURL: manifestURL,
            outputDirectoryURL: outputDirectoryURL,
            copiedDestinations: &copiedDestinations
        )

        let bundledManifestURL = outputDirectoryURL.appendingPathComponent(manifestURL.lastPathComponent, isDirectory: false)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(bundledManifest).write(to: bundledManifestURL)
        return PerchHAReleaseEvidenceBundleResult(
            bundleDirectoryURL: outputDirectoryURL,
            manifestURL: bundledManifestURL
        )
    }

    private func bundledManifest(
        from manifest: PerchHAReleaseEvidenceManifest,
        manifestURL: URL,
        outputDirectoryURL: URL,
        copiedDestinations: inout Set<String>
    ) throws -> PerchHAReleaseEvidenceManifest {
        let bundledAppPath = portableBundleStoredPath(manifest.app.path)
        try copyArtifact(
            storedPath: manifest.app.path,
            destinationStoredPath: bundledAppPath,
            isDirectory: true,
            manifestURL: manifestURL,
            outputDirectoryURL: outputDirectoryURL,
            copiedDestinations: &copiedDestinations
        )
        let bundledApp = PerchHAReleaseEvidenceApp(
            path: bundledAppPath,
            name: manifest.app.name,
            bundleIdentifier: manifest.app.bundleIdentifier,
            version: manifest.app.version,
            buildVersion: manifest.app.buildVersion,
            minimumSystemVersion: manifest.app.minimumSystemVersion,
            callbackURLSchemes: manifest.app.callbackURLSchemes
        )
        let bundledDmg = try bundledArtifact(
            manifest.dmg,
            manifestURL: manifestURL,
            outputDirectoryURL: outputDirectoryURL,
            copiedDestinations: &copiedDestinations
        )
        let bundledOAuthClientWebsite = try manifest.oauthClientWebsite.map {
            try bundledArtifact(
                $0,
                manifestURL: manifestURL,
                outputDirectoryURL: outputDirectoryURL,
                copiedDestinations: &copiedDestinations
            )
        }
        let bundledScreenshots = try manifest.screenshots.map {
            try bundledArtifact(
                $0,
                manifestURL: manifestURL,
                outputDirectoryURL: outputDirectoryURL,
                copiedDestinations: &copiedDestinations
            )
        }
        let bundledReviewBaseline = try manifest.reviewBaseline.map {
            let bundledArtifact = try bundledArtifact(
                $0,
                manifestURL: manifestURL,
                outputDirectoryURL: outputDirectoryURL,
                copiedDestinations: &copiedDestinations
            )
            try copyAdjacentCurrentReviewBaselineIfPresent(
                sourceReviewBaselinePath: $0.path,
                bundledReviewBaselinePath: bundledArtifact.path,
                manifestURL: manifestURL,
                outputDirectoryURL: outputDirectoryURL,
                copiedDestinations: &copiedDestinations
            )
            return bundledArtifact
        }

        return PerchHAReleaseEvidenceManifest(
            schemaVersion: manifest.schemaVersion,
            app: bundledApp,
            dmg: bundledDmg,
            oauthClientWebsite: bundledOAuthClientWebsite,
            screenshots: bundledScreenshots,
            reviewBaseline: bundledReviewBaseline,
            signing: manifest.signing,
            notarization: manifest.notarization
        )
    }

    private func bundledArtifact(
        _ artifact: PerchHAReleaseEvidenceArtifact,
        manifestURL: URL,
        outputDirectoryURL: URL,
        copiedDestinations: inout Set<String>
    ) throws -> PerchHAReleaseEvidenceArtifact {
        let bundledPath = portableBundleStoredPath(artifact.path)
        try copyArtifact(
            storedPath: artifact.path,
            destinationStoredPath: bundledPath,
            isDirectory: false,
            manifestURL: manifestURL,
            outputDirectoryURL: outputDirectoryURL,
            copiedDestinations: &copiedDestinations
        )
        return PerchHAReleaseEvidenceArtifact(
            name: artifact.name,
            path: bundledPath,
            sha256: artifact.sha256,
            byteCount: artifact.byteCount
        )
    }

    private func copyArtifact(
        storedPath: String,
        destinationStoredPath: String,
        isDirectory: Bool,
        manifestURL: URL,
        outputDirectoryURL: URL,
        copiedDestinations: inout Set<String>
    ) throws {
        let sourceURL = resolveReleaseEvidencePath(storedPath, manifestURL: manifestURL, isDirectory: isDirectory)
        let destinationURL = outputDirectoryURL.appendingPathComponent(destinationStoredPath, isDirectory: isDirectory)
        guard copiedDestinations.insert(destinationURL.path).inserted else {
            return
        }
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    private func copyAdjacentCurrentReviewBaselineIfPresent(
        sourceReviewBaselinePath: String,
        bundledReviewBaselinePath: String,
        manifestURL: URL,
        outputDirectoryURL: URL,
        copiedDestinations: inout Set<String>
    ) throws {
        guard sourceReviewBaselinePath.hasSuffix("/" + PerchHAReleaseEvidenceReview.expectedBaselineFilename)
              || sourceReviewBaselinePath == PerchHAReleaseEvidenceReview.expectedBaselineFilename
        else {
            return
        }
        let expectedSourceURL = resolveReleaseEvidencePath(
            sourceReviewBaselinePath,
            manifestURL: manifestURL,
            isDirectory: false
        )
        let currentSourceURL = expectedSourceURL.deletingLastPathComponent()
            .appendingPathComponent(PerchHAReleaseEvidenceReview.currentBaselineFilename, isDirectory: false)
        guard fileManager.fileExists(atPath: currentSourceURL.path) else {
            return
        }
        let sourceParentPath = NSString(string: sourceReviewBaselinePath).deletingLastPathComponent
        let bundledParentPath = NSString(string: bundledReviewBaselinePath).deletingLastPathComponent
        let currentSourcePath = sourceParentPath.isEmpty
            ? PerchHAReleaseEvidenceReview.currentBaselineFilename
            : NSString(string: sourceParentPath).appendingPathComponent(
                PerchHAReleaseEvidenceReview.currentBaselineFilename
            )
        let bundledCurrentPath = bundledParentPath.isEmpty
            ? PerchHAReleaseEvidenceReview.currentBaselineFilename
            : NSString(string: bundledParentPath).appendingPathComponent(
                PerchHAReleaseEvidenceReview.currentBaselineFilename
            )
        try copyArtifact(
            storedPath: currentSourcePath,
            destinationStoredPath: bundledCurrentPath,
            isDirectory: false,
            manifestURL: manifestURL,
            outputDirectoryURL: outputDirectoryURL,
            copiedDestinations: &copiedDestinations
        )
    }

    private func portableBundleStoredPath(_ storedPath: String) -> String {
        let components = NSString(string: storedPath).pathComponents
        var sanitizedComponents: [String] = []
        for component in components {
            switch component {
            case "", "/", ".":
                continue
            case "..":
                if !sanitizedComponents.isEmpty {
                    sanitizedComponents.removeLast()
                }
            default:
                sanitizedComponents.append(component)
            }
        }
        if sanitizedComponents.isEmpty {
            let fallback = NSString(string: storedPath).lastPathComponent
            return fallback.isEmpty || fallback == "." || fallback == "/" ? "artifact" : fallback
        }
        return NSString.path(withComponents: sanitizedComponents)
    }
}

public struct PerchHAReleaseEvidenceWriter {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    @discardableResult
    public func write(_ configuration: PerchHAReleaseEvidenceConfiguration) throws -> PerchHAReleaseEvidenceManifest {
        let appURL = normalizedReleaseEvidenceURL(configuration.appURL, isDirectory: true)
        let dmgURL = normalizedReleaseEvidenceURL(configuration.dmgURL, isDirectory: false)
        let manifestURL = normalizedReleaseEvidenceURL(configuration.manifestURL, isDirectory: false)
        let manifestDirectoryURL = manifestURL.deletingLastPathComponent()

        let absoluteApp = try appEvidence(appURL)
        guard fileManager.fileExists(atPath: dmgURL.path) else {
            throw PerchHAReleaseEvidenceError.dmgMissing(dmgURL.path)
        }
        let signingIdentity = trimmedOptional(configuration.signingIdentity)
        let signing = PerchHAReleaseEvidenceSigning(
            identity: signingIdentity,
            adHoc: signingIdentity == "-",
            signatureVerified: configuration.signatureVerified
        )
        let notarization = PerchHAReleaseEvidenceNotarization(
            submitted: configuration.notarySubmitted,
            stapled: configuration.stapled
        )
        if let problem = releaseStatusProblem(signing: signing, notarization: notarization) {
            throw PerchHAReleaseEvidenceError.invalidReleaseStatus(problem)
        }

        let manifest = PerchHAReleaseEvidenceManifest(
            schemaVersion: 1,
            app: PerchHAReleaseEvidenceApp(
                path: releaseEvidenceStoredPath(
                    for: appURL,
                    relativeTo: manifestDirectoryURL,
                    isDirectory: true
                ),
                name: absoluteApp.name,
                bundleIdentifier: absoluteApp.bundleIdentifier,
                version: absoluteApp.version,
                buildVersion: absoluteApp.buildVersion,
                minimumSystemVersion: absoluteApp.minimumSystemVersion,
                callbackURLSchemes: absoluteApp.callbackURLSchemes
            ),
            dmg: try artifactEvidence(
                dmgURL,
                relativeTo: manifestDirectoryURL
            ),
            oauthClientWebsite: try optionalArtifactEvidence(
                configuration.oauthClientWebsiteURL,
                relativeTo: manifestDirectoryURL
            ),
            screenshots: try screenshotEvidence(
                configuration.screenshotDirectoryURL,
                requiredNames: configuration.requiredScreenshotNames,
                relativeTo: manifestDirectoryURL
            ),
            reviewBaseline: try reviewBaselineEvidence(
                configuration.reviewBaselineURL,
                relativeTo: manifestDirectoryURL
            ),
            signing: signing,
            notarization: notarization
        )

        try fileManager.createDirectory(at: manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        return manifest
    }

    private func appEvidence(_ appURL: URL) throws -> PerchHAReleaseEvidenceApp {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: appURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw PerchHAReleaseEvidenceError.appBundleMissing(appURL.path)
        }
        let infoPlistURL = appURL.appendingPathComponent("Contents/Info.plist", isDirectory: false)
        guard fileManager.fileExists(atPath: infoPlistURL.path) else {
            throw PerchHAReleaseEvidenceError.infoPlistMissing(infoPlistURL.path)
        }

        let value: Any
        do {
            value = try PropertyListSerialization.propertyList(
                from: Data(contentsOf: infoPlistURL),
                options: [],
                format: nil
            )
        } catch {
            throw PerchHAReleaseEvidenceError.infoPlistUnreadable(infoPlistURL.path)
        }
        guard let plist = value as? [String: Any] else {
            throw PerchHAReleaseEvidenceError.infoPlistUnreadable(infoPlistURL.path)
        }

        return PerchHAReleaseEvidenceApp(
            path: appURL.path,
            name: plist["CFBundleName"] as? String ?? appURL.deletingPathExtension().lastPathComponent,
            bundleIdentifier: plist["CFBundleIdentifier"] as? String ?? "",
            version: plist["CFBundleShortVersionString"] as? String ?? "",
            buildVersion: plist["CFBundleVersion"] as? String ?? "",
            minimumSystemVersion: plist["LSMinimumSystemVersion"] as? String ?? "",
            callbackURLSchemes: callbackURLSchemes(from: plist)
        )
    }

    private func screenshotEvidence(
        _ directoryURL: URL?,
        requiredNames: [String],
        relativeTo manifestDirectoryURL: URL
    ) throws -> [PerchHAReleaseEvidenceArtifact] {
        guard let directoryURL else {
            guard requiredNames.isEmpty else {
                throw PerchHAReleaseEvidenceError.screenshotDirectoryRequired
            }
            return []
        }
        let directory = normalizedReleaseEvidenceURL(directoryURL, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw PerchHAReleaseEvidenceError.screenshotDirectoryMissing(directory.path)
        }
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
            .filter { $0.pathExtension.lowercased() == "png" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !urls.isEmpty else {
            throw PerchHAReleaseEvidenceError.screenshotsMissing(directory.path)
        }
        let screenshots = try urls.map { try artifactEvidence($0, relativeTo: manifestDirectoryURL) }
        if let name = firstMissingRequiredScreenshotName(requiredNames, screenshots: screenshots) {
            throw PerchHAReleaseEvidenceError.requiredScreenshotMissing(
                name: name,
                directory: directory.path
            )
        }
        return screenshots
    }

    private func artifactEvidence(
        _ url: URL,
        relativeTo manifestDirectoryURL: URL
    ) throws -> PerchHAReleaseEvidenceArtifact {
        let normalizedURL = normalizedReleaseEvidenceURL(url, isDirectory: false)
        let data = try Data(contentsOf: normalizedURL)
        return PerchHAReleaseEvidenceArtifact(
            name: normalizedURL.lastPathComponent,
            path: releaseEvidenceStoredPath(
                for: normalizedURL,
                relativeTo: manifestDirectoryURL,
                isDirectory: false
            ),
            sha256: sha256Hex(data),
            byteCount: UInt64(data.count)
        )
    }

    private func optionalArtifactEvidence(
        _ url: URL?,
        relativeTo manifestDirectoryURL: URL
    ) throws -> PerchHAReleaseEvidenceArtifact? {
        guard let url else {
            return nil
        }
        return try artifactEvidence(url, relativeTo: manifestDirectoryURL)
    }

    private func reviewBaselineEvidence(
        _ url: URL?,
        relativeTo manifestDirectoryURL: URL
    ) throws -> PerchHAReleaseEvidenceArtifact? {
        guard let url else {
            return nil
        }
        let fileURL = normalizedReleaseEvidenceURL(url, isDirectory: false)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw PerchHAReleaseEvidenceError.reviewBaselineMissing(fileURL.path)
        }
        return try artifactEvidence(fileURL, relativeTo: manifestDirectoryURL)
    }

    private func callbackURLSchemes(from plist: [String: Any]) -> [String] {
        guard let urlTypes = plist["CFBundleURLTypes"] as? [[String: Any]] else {
            return []
        }
        return urlTypes
            .flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
            .sorted()
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func trimmedOptional(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }
}

public enum PerchHACodeSigningError: Error, Equatable, CustomStringConvertible, Sendable {
    case appBundleMissing(String)
    case blankIdentity
    case entitlementsMissing(String)
    case codesignMissing(String)
    case codesignFailed(operation: String, status: Int32, output: String)

    public var description: String {
        switch self {
        case let .appBundleMissing(path):
            "app bundle does not exist: \(path)"
        case .blankIdentity:
            "code-signing identity is required"
        case let .entitlementsMissing(path):
            "entitlements file does not exist: \(path)"
        case let .codesignMissing(path):
            "codesign does not exist: \(path)"
        case let .codesignFailed(operation, status, output):
            "codesign \(operation) failed with status \(status): \(output)"
        }
    }
}

public struct PerchHACodeSigningConfiguration: Equatable, Sendable {
    public let appURL: URL
    public let identity: String
    public let entitlementsURL: URL?
    public let force: Bool
    public let hardenedRuntime: Bool
    public let timestamp: Bool

    public init(
        appURL: URL,
        identity: String,
        entitlementsURL: URL? = nil,
        force: Bool = true,
        hardenedRuntime: Bool = true,
        timestamp: Bool = true
    ) {
        self.appURL = appURL
        self.identity = identity
        self.entitlementsURL = entitlementsURL
        self.force = force
        self.hardenedRuntime = hardenedRuntime
        self.timestamp = timestamp
    }
}

public struct PerchHACodeSigningResult: Equatable, Sendable {
    public let appURL: URL
    public let identity: String
    public let entitlementsURL: URL?
    public let hardenedRuntime: Bool
    public let timestamp: Bool
}

public struct PerchHACodeSigner {
    public static let defaultCodesignURL = URL(fileURLWithPath: "/usr/bin/codesign")

    private let fileManager: FileManager
    private let codesignURL: URL
    private let commandRunner: any PerchHACommandRunning

    public init(
        fileManager: FileManager = .default,
        codesignURL: URL = Self.defaultCodesignURL,
        commandRunner: any PerchHACommandRunning = PerchHAFoundationCommandRunner()
    ) {
        self.fileManager = fileManager
        self.codesignURL = codesignURL
        self.commandRunner = commandRunner
    }

    public func sign(_ configuration: PerchHACodeSigningConfiguration) throws -> PerchHACodeSigningResult {
        let appURL = normalizedFileURL(configuration.appURL)
        let identity = configuration.identity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identity.isEmpty else {
            throw PerchHACodeSigningError.blankIdentity
        }
        try verifyAppBundleExists(appURL)
        guard fileManager.isExecutableFile(atPath: codesignURL.path) else {
            throw PerchHACodeSigningError.codesignMissing(codesignURL.path)
        }

        let entitlementsURL = configuration.entitlementsURL.map { URL(fileURLWithPath: $0.path) }
        if let entitlementsURL {
            guard fileManager.fileExists(atPath: entitlementsURL.path) else {
                throw PerchHACodeSigningError.entitlementsMissing(entitlementsURL.path)
            }
        }

        var arguments: [String] = []
        if configuration.force {
            arguments.append("--force")
        }
        if configuration.timestamp {
            arguments.append("--timestamp")
        }
        if configuration.hardenedRuntime {
            arguments.append(contentsOf: ["--options", "runtime"])
        }
        if let entitlementsURL {
            arguments.append(contentsOf: ["--entitlements", entitlementsURL.path])
        }
        arguments.append(contentsOf: ["--sign", identity, appURL.path])

        let result = try commandRunner.run(executableURL: codesignURL, arguments: arguments)
        guard result.status == 0 else {
            throw PerchHACodeSigningError.codesignFailed(operation: "sign", status: result.status, output: result.output)
        }
        return PerchHACodeSigningResult(
            appURL: appURL,
            identity: identity,
            entitlementsURL: entitlementsURL,
            hardenedRuntime: configuration.hardenedRuntime,
            timestamp: configuration.timestamp
        )
    }

    private func verifyAppBundleExists(_ appURL: URL) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: appURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw PerchHACodeSigningError.appBundleMissing(appURL.path)
        }
    }

    private func normalizedFileURL(_ url: URL) -> URL {
        URL(fileURLWithPath: url.path).standardizedFileURL.resolvingSymlinksInPath()
    }
}

public struct PerchHACodeSignatureVerificationConfiguration: Equatable, Sendable {
    public let appURL: URL
    public let strict: Bool
    public let verboseLevel: Int

    public init(
        appURL: URL,
        strict: Bool = true,
        verboseLevel: Int = 2
    ) {
        self.appURL = appURL
        self.strict = strict
        self.verboseLevel = max(0, verboseLevel)
    }
}

public struct PerchHACodeSignatureVerificationResult: Equatable, Sendable {
    public let appURL: URL
}

public struct PerchHACodeSignatureVerifier {
    private let fileManager: FileManager
    private let codesignURL: URL
    private let commandRunner: any PerchHACommandRunning

    public init(
        fileManager: FileManager = .default,
        codesignURL: URL = PerchHACodeSigner.defaultCodesignURL,
        commandRunner: any PerchHACommandRunning = PerchHAFoundationCommandRunner()
    ) {
        self.fileManager = fileManager
        self.codesignURL = codesignURL
        self.commandRunner = commandRunner
    }

    public func verify(
        _ configuration: PerchHACodeSignatureVerificationConfiguration
    ) throws -> PerchHACodeSignatureVerificationResult {
        let appURL = normalizedFileURL(configuration.appURL)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: appURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw PerchHACodeSigningError.appBundleMissing(appURL.path)
        }
        guard fileManager.isExecutableFile(atPath: codesignURL.path) else {
            throw PerchHACodeSigningError.codesignMissing(codesignURL.path)
        }

        var arguments = ["--verify"]
        if configuration.strict {
            arguments.append("--strict")
        }
        if configuration.verboseLevel > 0 {
            arguments.append("--verbose=\(configuration.verboseLevel)")
        }
        arguments.append(appURL.path)

        let result = try commandRunner.run(executableURL: codesignURL, arguments: arguments)
        guard result.status == 0 else {
            throw PerchHACodeSigningError.codesignFailed(operation: "verify", status: result.status, output: result.output)
        }
        return PerchHACodeSignatureVerificationResult(appURL: appURL)
    }

    private func normalizedFileURL(_ url: URL) -> URL {
        URL(fileURLWithPath: url.path).standardizedFileURL.resolvingSymlinksInPath()
    }
}

public enum PerchHANotaryError: Error, Equatable, CustomStringConvertible, Sendable {
    case artifactMissing(String)
    case blankKeychainProfile
    case stapleRequiresCompletedSubmission
    case xcrunMissing(String)
    case notaryToolFailed(status: Int32, output: String)
    case staplerFailed(status: Int32, output: String)

    public var description: String {
        switch self {
        case let .artifactMissing(path):
            "notary artifact does not exist: \(path)"
        case .blankKeychainProfile:
            "notary keychain profile is required"
        case .stapleRequiresCompletedSubmission:
            "stapling requires waiting for notary completion"
        case let .xcrunMissing(path):
            "xcrun does not exist: \(path)"
        case let .notaryToolFailed(status, output):
            "notarytool submit failed with status \(status): \(output)"
        case let .staplerFailed(status, output):
            "stapler staple failed with status \(status): \(output)"
        }
    }
}

public struct PerchHANotarySubmissionConfiguration: Equatable, Sendable {
    public let artifactURL: URL
    public let keychainProfile: String
    public let waitForCompletion: Bool
    public let timeout: String?
    public let staple: Bool

    public init(
        artifactURL: URL,
        keychainProfile: String,
        waitForCompletion: Bool = true,
        timeout: String? = nil,
        staple: Bool = true
    ) {
        self.artifactURL = artifactURL
        self.keychainProfile = keychainProfile
        self.waitForCompletion = waitForCompletion
        self.timeout = timeout
        self.staple = staple
    }
}

public struct PerchHANotarySubmissionResult: Equatable, Sendable {
    public let artifactURL: URL
    public let keychainProfile: String
    public let waitedForCompletion: Bool
    public let stapled: Bool
}

public struct PerchHANotarySubmitter {
    public static let defaultXcrunURL = URL(fileURLWithPath: "/usr/bin/xcrun")

    private let fileManager: FileManager
    private let xcrunURL: URL
    private let commandRunner: any PerchHACommandRunning

    public init(
        fileManager: FileManager = .default,
        xcrunURL: URL = Self.defaultXcrunURL,
        commandRunner: any PerchHACommandRunning = PerchHAFoundationCommandRunner()
    ) {
        self.fileManager = fileManager
        self.xcrunURL = xcrunURL
        self.commandRunner = commandRunner
    }

    public func submit(_ configuration: PerchHANotarySubmissionConfiguration) throws -> PerchHANotarySubmissionResult {
        let artifactURL = URL(fileURLWithPath: configuration.artifactURL.path)
        let keychainProfile = configuration.keychainProfile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard fileManager.fileExists(atPath: artifactURL.path) else {
            throw PerchHANotaryError.artifactMissing(artifactURL.path)
        }
        guard !keychainProfile.isEmpty else {
            throw PerchHANotaryError.blankKeychainProfile
        }
        guard configuration.waitForCompletion || !configuration.staple else {
            throw PerchHANotaryError.stapleRequiresCompletedSubmission
        }
        guard fileManager.isExecutableFile(atPath: xcrunURL.path) else {
            throw PerchHANotaryError.xcrunMissing(xcrunURL.path)
        }

        var submitArguments = [
            "notarytool",
            "submit",
            artifactURL.path,
            "--keychain-profile",
            keychainProfile,
            "--no-progress"
        ]
        if configuration.waitForCompletion {
            submitArguments.append("--wait")
            if let timeout = configuration.timeout?.trimmingCharacters(in: .whitespacesAndNewlines),
               !timeout.isEmpty {
                submitArguments.append(contentsOf: ["--timeout", timeout])
            }
        }

        let submitResult = try commandRunner.run(executableURL: xcrunURL, arguments: submitArguments)
        guard submitResult.status == 0 else {
            throw PerchHANotaryError.notaryToolFailed(status: submitResult.status, output: submitResult.output)
        }

        if configuration.staple {
            let stapleResult = try commandRunner.run(
                executableURL: xcrunURL,
                arguments: ["stapler", "staple", artifactURL.path]
            )
            guard stapleResult.status == 0 else {
                throw PerchHANotaryError.staplerFailed(status: stapleResult.status, output: stapleResult.output)
            }
        }

        return PerchHANotarySubmissionResult(
            artifactURL: artifactURL,
            keychainProfile: keychainProfile,
            waitedForCompletion: configuration.waitForCompletion,
            stapled: configuration.staple
        )
    }
}

public enum PerchHADMGBuildError: Error, Equatable, CustomStringConvertible, Sendable {
    case appBundleMissing(String)
    case outputExists(String)
    case blankVolumeName
    case hdiutilMissing(String)
    case hdiutilFailed(operation: String, status: Int32, output: String)
    case dmgMissing(String)
    case mountedAppMissing(String)
    case mountedApplicationsShortcutMissing(String)

    public var description: String {
        switch self {
        case let .appBundleMissing(path):
            "app bundle does not exist: \(path)"
        case let .outputExists(path):
            "output DMG already exists: \(path)"
        case .blankVolumeName:
            "DMG volume name is required"
        case let .hdiutilMissing(path):
            "hdiutil does not exist: \(path)"
        case let .hdiutilFailed(operation, status, output):
            "hdiutil \(operation) failed with status \(status): \(output)"
        case let .dmgMissing(path):
            "DMG does not exist: \(path)"
        case let .mountedAppMissing(path):
            "mounted DMG does not contain app bundle: \(path)"
        case let .mountedApplicationsShortcutMissing(path):
            "mounted DMG does not contain Applications shortcut: \(path)"
        }
    }
}

public struct PerchHADMGBuildConfiguration: Equatable, Sendable {
    public let appURL: URL
    public let outputURL: URL
    public let volumeName: String
    public let replaceExisting: Bool
    public let includeApplicationsShortcut: Bool

    public init(
        appURL: URL,
        outputURL: URL,
        volumeName: String = "PearchHA",
        replaceExisting: Bool = false,
        includeApplicationsShortcut: Bool = true
    ) {
        self.appURL = appURL
        self.outputURL = outputURL
        self.volumeName = volumeName
        self.replaceExisting = replaceExisting
        self.includeApplicationsShortcut = includeApplicationsShortcut
    }
}

public struct PerchHADMGBuildResult: Equatable, Sendable {
    public let dmgURL: URL
    public let appURL: URL
    public let volumeName: String
}

public struct PerchHADMGBuilder {
    public static let defaultHdiutilURL = URL(fileURLWithPath: "/usr/bin/hdiutil")

    private let fileManager: FileManager
    private let hdiutilURL: URL
    private let commandRunner: any PerchHACommandRunning

    public init(
        fileManager: FileManager = .default,
        hdiutilURL: URL = Self.defaultHdiutilURL,
        commandRunner: any PerchHACommandRunning = PerchHAFoundationCommandRunner()
    ) {
        self.fileManager = fileManager
        self.hdiutilURL = hdiutilURL
        self.commandRunner = commandRunner
    }

    public func build(_ configuration: PerchHADMGBuildConfiguration) throws -> PerchHADMGBuildResult {
        let appURL = normalizedFileURL(configuration.appURL)
        let outputURL = URL(fileURLWithPath: configuration.outputURL.path)
        let volumeName = configuration.volumeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !volumeName.isEmpty else {
            throw PerchHADMGBuildError.blankVolumeName
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: appURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw PerchHADMGBuildError.appBundleMissing(appURL.path)
        }
        if fileManager.fileExists(atPath: outputURL.path) {
            guard configuration.replaceExisting else {
                throw PerchHADMGBuildError.outputExists(outputURL.path)
            }
            try fileManager.removeItem(at: outputURL)
        }
        guard fileManager.isExecutableFile(atPath: hdiutilURL.path) else {
            throw PerchHADMGBuildError.hdiutilMissing(hdiutilURL.path)
        }
        try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let stagingURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent("perchha-dmg-staging-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? fileManager.removeItem(at: stagingURL)
        }
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        try fileManager.copyItem(at: appURL, to: stagingURL.appendingPathComponent(appURL.lastPathComponent, isDirectory: true))
        if configuration.includeApplicationsShortcut {
            try fileManager.createSymbolicLink(
                at: stagingURL.appendingPathComponent("Applications"),
                withDestinationURL: URL(fileURLWithPath: "/Applications", isDirectory: true)
            )
        }

        let result = try commandRunner.run(
            executableURL: hdiutilURL,
            arguments: [
                "create",
                "-volname", volumeName,
                "-srcfolder", stagingURL.path,
                "-format", "UDZO",
                "-ov",
                outputURL.path
            ]
        )
        guard result.status == 0 else {
            throw PerchHADMGBuildError.hdiutilFailed(operation: "create", status: result.status, output: result.output)
        }
        guard fileManager.fileExists(atPath: outputURL.path) else {
            throw PerchHADMGBuildError.dmgMissing(outputURL.path)
        }
        return PerchHADMGBuildResult(dmgURL: outputURL, appURL: appURL, volumeName: volumeName)
    }

    private func normalizedFileURL(_ url: URL) -> URL {
        URL(fileURLWithPath: url.path).standardizedFileURL.resolvingSymlinksInPath()
    }
}

public struct PerchHADMGVerificationConfiguration: Equatable, Sendable {
    public let dmgURL: URL

    public init(dmgURL: URL) {
        self.dmgURL = dmgURL
    }
}

public struct PerchHADMGVerificationResult: Equatable, Sendable {
    public let dmgURL: URL
}

public struct PerchHADMGVerifier {
    private let fileManager: FileManager
    private let hdiutilURL: URL
    private let commandRunner: any PerchHACommandRunning

    public init(
        fileManager: FileManager = .default,
        hdiutilURL: URL = PerchHADMGBuilder.defaultHdiutilURL,
        commandRunner: any PerchHACommandRunning = PerchHAFoundationCommandRunner()
    ) {
        self.fileManager = fileManager
        self.hdiutilURL = hdiutilURL
        self.commandRunner = commandRunner
    }

    public func verify(_ configuration: PerchHADMGVerificationConfiguration) throws -> PerchHADMGVerificationResult {
        let dmgURL = URL(fileURLWithPath: configuration.dmgURL.path)
        guard fileManager.fileExists(atPath: dmgURL.path) else {
            throw PerchHADMGBuildError.dmgMissing(dmgURL.path)
        }
        guard fileManager.isExecutableFile(atPath: hdiutilURL.path) else {
            throw PerchHADMGBuildError.hdiutilMissing(hdiutilURL.path)
        }
        let result = try commandRunner.run(
            executableURL: hdiutilURL,
            arguments: ["verify", dmgURL.path]
        )
        guard result.status == 0 else {
            throw PerchHADMGBuildError.hdiutilFailed(operation: "verify", status: result.status, output: result.output)
        }
        return PerchHADMGVerificationResult(dmgURL: dmgURL)
    }
}

public struct PerchHADMGContentVerificationConfiguration: Equatable, Sendable {
    public let dmgURL: URL
    public let appBundleName: String
    public let requireApplicationsShortcut: Bool

    public init(
        dmgURL: URL,
        appBundleName: String = "PerchHA.app",
        requireApplicationsShortcut: Bool = true
    ) {
        self.dmgURL = dmgURL
        self.appBundleName = appBundleName
        self.requireApplicationsShortcut = requireApplicationsShortcut
    }
}

public struct PerchHADMGContentVerificationResult: Equatable, Sendable {
    public let dmgURL: URL
    public let mountedAppURL: URL
    public let applicationsShortcutURL: URL?
}

public struct PerchHADMGContentVerifier {
    private let fileManager: FileManager
    private let hdiutilURL: URL
    private let commandRunner: any PerchHACommandRunning

    public init(
        fileManager: FileManager = .default,
        hdiutilURL: URL = PerchHADMGBuilder.defaultHdiutilURL,
        commandRunner: any PerchHACommandRunning = PerchHAFoundationCommandRunner()
    ) {
        self.fileManager = fileManager
        self.hdiutilURL = hdiutilURL
        self.commandRunner = commandRunner
    }

    public func verify(
        _ configuration: PerchHADMGContentVerificationConfiguration
    ) throws -> PerchHADMGContentVerificationResult {
        let dmgURL = URL(fileURLWithPath: configuration.dmgURL.path)
        guard fileManager.fileExists(atPath: dmgURL.path) else {
            throw PerchHADMGBuildError.dmgMissing(dmgURL.path)
        }
        guard fileManager.isExecutableFile(atPath: hdiutilURL.path) else {
            throw PerchHADMGBuildError.hdiutilMissing(hdiutilURL.path)
        }

        let mountpointURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("perchha-dmg-mount-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: mountpointURL, withIntermediateDirectories: true)
        var attached = false
        defer {
            if attached {
                _ = try? commandRunner.run(executableURL: hdiutilURL, arguments: ["detach", mountpointURL.path])
            }
            try? fileManager.removeItem(at: mountpointURL)
        }

        let attachResult = try commandRunner.run(
            executableURL: hdiutilURL,
            arguments: ["attach", "-nobrowse", "-readonly", "-mountpoint", mountpointURL.path, dmgURL.path]
        )
        guard attachResult.status == 0 else {
            throw PerchHADMGBuildError.hdiutilFailed(operation: "attach", status: attachResult.status, output: attachResult.output)
        }
        attached = true

        let appBundleName = configuration.appBundleName.trimmingCharacters(in: .whitespacesAndNewlines)
        let mountedAppURL = mountpointURL.appendingPathComponent(appBundleName, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard !appBundleName.isEmpty,
              fileManager.fileExists(atPath: mountedAppURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw PerchHADMGBuildError.mountedAppMissing(mountedAppURL.path)
        }

        let applicationsShortcutURL = mountpointURL.appendingPathComponent("Applications", isDirectory: true)
        if configuration.requireApplicationsShortcut {
            let shortcutTarget = try? fileManager.destinationOfSymbolicLink(atPath: applicationsShortcutURL.path)
            guard shortcutTarget == "/Applications" else {
                throw PerchHADMGBuildError.mountedApplicationsShortcutMissing(applicationsShortcutURL.path)
            }
        }

        let detachResult = try commandRunner.run(
            executableURL: hdiutilURL,
            arguments: ["detach", mountpointURL.path]
        )
        attached = false
        guard detachResult.status == 0 else {
            throw PerchHADMGBuildError.hdiutilFailed(operation: "detach", status: detachResult.status, output: detachResult.output)
        }

        return PerchHADMGContentVerificationResult(
            dmgURL: dmgURL,
            mountedAppURL: mountedAppURL,
            applicationsShortcutURL: configuration.requireApplicationsShortcut ? applicationsShortcutURL : nil
        )
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
    let iconFileName: String?
    let urlTypes: [PerchHAInfoPlistURLType]

    init(
        appName: String,
        bundleIdentifier: String,
        executableName: String,
        version: String,
        buildVersion: String,
        minimumSystemVersion: String,
        callbackURLScheme: String,
        iconFileName: String?
    ) {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.executableName = executableName
        self.version = version
        self.buildVersion = buildVersion
        self.minimumSystemVersion = minimumSystemVersion
        self.iconFileName = iconFileName
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
        case iconFileName = "CFBundleIconFile"
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
