import Foundation
import PerchHAClient
import PerchHAPackaging
import PerchHASupport

@main
struct PerchHAPackageAppCommand {
    private static let defaultAppIconURL = URL(fileURLWithPath: "Xcode/PerchHA/PearchHA.icns", isDirectory: false)

    static func main() {
        do {
            try run()
        } catch {
            FileHandle.standardError.write(Data("perchha-package-app: \(error)\n".utf8))
            Foundation.exit(1)
        }
    }

    private static func run() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.first == "help" || arguments.contains("--help") || arguments.contains("-h") {
            print(help)
            return
        }
        let options = try parseOptions(arguments: arguments)
        try validateOAuthSiteOptions(options)
        if options.flags.contains("--verify-published-oauth-site") {
            try verifyPublishedOAuthSite(options: options)
            return
        }
        if let path = options.value(for: "--verify-oauth-site") {
            try verifyOAuthSite(path: path, options: options)
            return
        }
        if let path = options.value(for: "--write-oauth-site") {
            try writeOAuthSite(path: path, options: options)
            return
        }
        let releaseEvidenceBundlePath = options.value(for: "--bundle-release-evidence")
        let signingIdentity = try signingIdentity(from: options)
        let additionalRequiredScreenshotNames = try additionalRequiredScreenshotNames(from: options)
        try validateReleaseEvidenceOptions(
            options,
            signingIdentity: signingIdentity,
            additionalRequiredScreenshotNames: additionalRequiredScreenshotNames
        )
        let requiredScreenshotNames = releaseRequiredScreenshotNames(
            additionalRequiredScreenshotNames
        )
        if let releaseManifestPath = options.value(for: "--verify-release-manifest") {
            _ = try verifyReleaseManifest(
                path: releaseManifestPath,
                requiredScreenshotNames: requiredScreenshotNames
            )
            if let releaseEvidenceBundlePath {
                try bundleReleaseEvidence(
                    manifestPath: releaseManifestPath,
                    bundlePath: releaseEvidenceBundlePath,
                    requiredScreenshotNames: requiredScreenshotNames,
                    replaceExisting: options.flags.contains("--replace")
                )
            }
            return
        }
        if options.flags.contains("--release-preflight") {
            try releasePreflight(options: options, signingIdentity: signingIdentity)
            return
        }
        let iconURL = FileManager.default.fileExists(atPath: defaultAppIconURL.path)
            ? defaultAppIconURL
            : nil
        let manifest = try PerchHAAppBundleManifest(
            bundleIdentifier: options.value(for: "--bundle-id") ?? "dev.perchha.app",
            version: options.value(for: "--version") ?? "0.1.0",
            buildVersion: options.value(for: "--build-version") ?? "1",
            minimumSystemVersion: options.value(for: "--minimum-system-version") ?? "13.0",
            callbackURLScheme: options.value(for: "--callback-scheme") ?? "perchha",
            iconFileName: iconURL?.deletingPathExtension().lastPathComponent
        )
        let result = try PerchHAAppBundleBuilder().build(
            PerchHAAppBundleBuildConfiguration(
                executableURL: URL(fileURLWithPath: options.value(for: "--executable") ?? ".build/debug/PerchHA"),
                outputURL: URL(fileURLWithPath: options.value(for: "--output") ?? ".build/PerchHA.app"),
                manifest: manifest,
                iconURL: iconURL,
                replaceExisting: options.flags.contains("--replace")
            )
        )
        print("created \(result.appURL.path)")
        if options.flags.contains("--verify-launch-services") {
            let verification = try PerchHALaunchServicesVerifier().verify(
                PerchHALaunchServicesVerificationConfiguration(
                    appURL: result.appURL,
                    callbackURLScheme: manifest.callbackURLScheme
                )
            )
            print("LaunchServices callback claim verified: \(verification.callbackURL.absoluteString) -> \(verification.registeredApplicationURL.path) (\(verification.callbackRole))")
        }
        if let signingIdentity {
            let isAdHocSignature = signingIdentity == "-"
            let signing = try PerchHACodeSigner(
                codesignURL: URL(fileURLWithPath: options.value(for: "--codesign") ?? PerchHACodeSigner.defaultCodesignURL.path)
            ).sign(
                PerchHACodeSigningConfiguration(
                    appURL: result.appURL,
                    identity: signingIdentity,
                    entitlementsURL: options.value(for: "--sign-entitlements").map { URL(fileURLWithPath: $0) },
                    hardenedRuntime: !isAdHocSignature && !options.flags.contains("--sign-without-hardened-runtime"),
                    timestamp: !isAdHocSignature && !options.flags.contains("--sign-without-timestamp")
                )
            )
            print("signed \(signing.appURL.path) with \(signing.identity)")
        }
        if signingIdentity != nil || options.flags.contains("--verify-signature") {
            let verification = try PerchHACodeSignatureVerifier(
                codesignURL: URL(fileURLWithPath: options.value(for: "--codesign") ?? PerchHACodeSigner.defaultCodesignURL.path)
            ).verify(
                PerchHACodeSignatureVerificationConfiguration(appURL: result.appURL)
            )
            print("signature verified: \(verification.appURL.path)")
        }
        let dmgOutputURL = URL(
            fileURLWithPath: options.value(for: "--dmg-output")
                ?? result.appURL.deletingPathExtension().appendingPathExtension("dmg").path
        )
        let hdiutilURL = URL(fileURLWithPath: options.value(for: "--hdiutil") ?? PerchHADMGBuilder.defaultHdiutilURL.path)
        let signatureVerified = signingIdentity != nil || options.flags.contains("--verify-signature")
        if options.flags.contains("--package-dmg") {
            let dmg = try PerchHADMGBuilder(hdiutilURL: hdiutilURL).build(
                PerchHADMGBuildConfiguration(
                    appURL: result.appURL,
                    outputURL: dmgOutputURL,
                    volumeName: options.value(for: "--dmg-volume-name") ?? manifest.appName,
                    replaceExisting: options.flags.contains("--replace")
                )
            )
            print("created \(dmg.dmgURL.path)")
        }
        if options.flags.contains("--verify-dmg") {
            let verification = try PerchHADMGVerifier(hdiutilURL: hdiutilURL).verify(
                PerchHADMGVerificationConfiguration(dmgURL: dmgOutputURL)
            )
            print("DMG verified: \(verification.dmgURL.path)")
        }
        if options.flags.contains("--verify-dmg-contents") {
            let verification = try PerchHADMGContentVerifier(hdiutilURL: hdiutilURL).verify(
                PerchHADMGContentVerificationConfiguration(
                    dmgURL: dmgOutputURL,
                    appBundleName: result.appURL.lastPathComponent
                )
            )
            print("DMG contents verified: \(verification.mountedAppURL.lastPathComponent)")
        }
        var notarySubmitted = false
        var stapled = false
        if let notaryProfile = options.value(for: "--notary-profile") {
            let shouldWait = !options.flags.contains("--notary-no-wait")
            let submission = try PerchHANotarySubmitter(
                xcrunURL: URL(fileURLWithPath: options.value(for: "--xcrun") ?? PerchHANotarySubmitter.defaultXcrunURL.path)
            ).submit(
                PerchHANotarySubmissionConfiguration(
                    artifactURL: dmgOutputURL,
                    keychainProfile: notaryProfile,
                    waitForCompletion: shouldWait,
                    timeout: options.value(for: "--notary-timeout"),
                    staple: shouldWait && !options.flags.contains("--skip-staple")
                )
            )
            notarySubmitted = true
            stapled = submission.stapled
            let stapleStatus = submission.stapled ? "stapled" : "not stapled"
            print("notary submission complete: \(submission.artifactURL.path) (\(stapleStatus))")
        }
        if let releaseManifestPath = options.value(for: "--release-manifest") {
            let snapshotDirectoryURL = options.value(for: "--snapshot-dir").map {
                URL(fileURLWithPath: $0, isDirectory: true)
            }
            let manifest = try PerchHAReleaseEvidenceWriter().write(
                PerchHAReleaseEvidenceConfiguration(
                    appURL: result.appURL,
                    dmgURL: dmgOutputURL,
                    manifestURL: URL(fileURLWithPath: releaseManifestPath),
                    oauthClientWebsiteURL: options.value(for: "--oauth-site").map {
                        URL(fileURLWithPath: $0, isDirectory: false)
                    },
                    screenshotDirectoryURL: snapshotDirectoryURL,
                    reviewBaselineURL: snapshotDirectoryURL?.appendingPathComponent(
                        PerchHAReleaseEvidenceReview.expectedBaselineFilename,
                        isDirectory: false
                    ),
                    requiredScreenshotNames: requiredScreenshotNames,
                    signingIdentity: signingIdentity,
                    signatureVerified: signatureVerified,
                    notarySubmitted: notarySubmitted,
                    stapled: stapled
                )
            )
            print("release manifest written: \(releaseManifestPath) (\(manifest.dmg.sha256))")
            let verification = try PerchHAReleaseEvidenceVerifier().verify(
                PerchHAReleaseEvidenceVerificationConfiguration(
                    manifestURL: URL(fileURLWithPath: releaseManifestPath, isDirectory: false),
                    requiredScreenshotNames: requiredScreenshotNames
                )
            )
            let oauthSiteSuffix = verification.oauthClientWebsiteURL.map { ", oauth site: \($0.path)" } ?? ""
            print("release manifest verified: \(releaseManifestPath) (\(verification.screenshotCount) screenshots\(oauthSiteSuffix))")
            if let releaseEvidenceBundlePath {
                try bundleReleaseEvidence(
                    manifestPath: releaseManifestPath,
                    bundlePath: releaseEvidenceBundlePath,
                    requiredScreenshotNames: requiredScreenshotNames,
                    replaceExisting: options.flags.contains("--replace")
                )
            }
        }
    }

    private static let help = """
    perchha-package-app

    Usage:
      perchha-package-app help
      perchha-package-app --write-oauth-site PATH [--oauth-env PATH] [--replace]
      perchha-package-app --verify-oauth-site PATH [--oauth-env PATH]
      perchha-package-app --verify-published-oauth-site [--oauth-env PATH]
      perchha-package-app [--executable PATH] [--output PATH] [--callback-scheme SCHEME] [--replace] [--verify-launch-services] [--sign-identity IDENTITY|--sign-ad-hoc] [--verify-signature] [--package-dmg] [--verify-dmg] [--verify-dmg-contents] [--release-manifest PATH] [--verify-release-manifest PATH] [--bundle-release-evidence PATH] [--oauth-site PATH] [--require-screenshot NAME] [--notary-profile PROFILE]

    Options:
      --write-oauth-site PATH       Write a deployable OAuth client-website HTML artifact from exported OAuth env values or an env file.
      --verify-oauth-site PATH      Verify an OAuth client-website HTML artifact against exported OAuth env values or an env file.
      --verify-published-oauth-site Fetch the configured OAuth client website URL and verify the published HTML declaration against the configured redirect URI.
      --oauth-env PATH              Env file path used for OAuth site generation or verification. Default: .env.local or PERCHHA_ENV_FILE.
      --executable PATH             SwiftPM-built PerchHA executable. Default: .build/debug/PerchHA
      --output PATH                 Output .app bundle. Default: .build/PerchHA.app
      --dmg-output PATH             Output DMG path. Default: app output path with .dmg extension
      --dmg-volume-name NAME        DMG volume name. Default: PerchHA
      --hdiutil PATH                hdiutil executable. Default: /usr/bin/hdiutil
      --security PATH               security executable. Default: /usr/bin/security
      --codesign PATH               codesign executable. Default: /usr/bin/codesign
      --xcrun PATH                  xcrun executable. Default: /usr/bin/xcrun
      --callback-scheme SCHEME      OAuth callback URL scheme. Default: perchha
      --bundle-id ID                Bundle identifier. Default: dev.perchha.app
      --version VERSION             CFBundleShortVersionString. Default: 0.1.0
      --build-version VERSION       CFBundleVersion. Default: 1
      --minimum-system-version VER  LSMinimumSystemVersion. Default: 13.0
      --replace                     Remove an existing output bundle before writing.
      --verify-launch-services      Register the bundle and verify macOS records its callback scheme claim.
      --sign-identity IDENTITY      Sign the app bundle with a Developer ID or local signing identity.
      --sign-ad-hoc                 Sign the app bundle with the local ad-hoc identity for smoke checks.
      --sign-entitlements PATH      Entitlements plist used during signing.
      --sign-without-timestamp      Disable timestamping for non-ad-hoc signatures.
      --sign-without-hardened-runtime
                                   Disable hardened runtime for non-ad-hoc signatures.
      --verify-signature            Verify the app bundle code signature.
      --package-dmg                 Create a compressed read-only DMG containing the app and Applications shortcut.
      --verify-dmg                  Verify the DMG with hdiutil.
      --verify-dmg-contents         Mount the DMG read-only and verify it contains the app and Applications shortcut.
      --release-manifest PATH       Write a JSON release evidence manifest with app metadata and artifact hashes.
      --verify-release-manifest PATH
                                   Verify an existing release evidence manifest against current artifacts.
                                   PerchHA's canonical smoke screenshot set is required by default.
      --bundle-release-evidence PATH
                                   Copy the manifest and referenced artifacts into one portable evidence directory, then verify the bundled manifest.
      --oauth-site PATH             Optional OAuth client-website artifact to retain and verify in the release manifest.
      --require-screenshot NAME    Require an additional screenshot artifact name during release manifest writing or verification. Repeat for each extra screenshot.
      --snapshot-dir PATH           Screenshot directory to include in the release manifest. Required with --release-manifest.
      --release-preflight           Check Developer ID identity and notary profile readiness without building.
      --json                        Print release preflight as machine-readable redacted JSON.
      --notary-profile PROFILE      Submit the DMG with xcrun notarytool using a stored Keychain profile. Actual submission requires --package-dmg and a Developer ID --sign-identity.
      --notary-timeout DURATION     Wait timeout passed to notarytool, for example 30m.
      --notary-no-wait              Submit without waiting for notary completion.
      --skip-staple                 Do not staple after a completed notary submission.
    """

    private static func signingIdentity(from options: CommandOptions) throws -> String? {
        let explicitIdentity = options.value(for: "--sign-identity")
        let usesAdHocSignature = options.flags.contains("--sign-ad-hoc")
        if explicitIdentity != nil && usesAdHocSignature {
            throw CommandError.conflictingOptions("--sign-identity", "--sign-ad-hoc")
        }
        return explicitIdentity ?? (usesAdHocSignature ? "-" : nil)
    }

    private static func validateReleaseEvidenceOptions(
        _ options: CommandOptions,
        signingIdentity: String?,
        additionalRequiredScreenshotNames: [String]
    ) throws {
        let isReleasePreflight = options.flags.contains("--release-preflight")
        let verifiesOrWritesReleaseManifest = options.value(for: "--verify-release-manifest") != nil
            || options.value(for: "--release-manifest") != nil
        if options.flags.contains("--json") && !isReleasePreflight {
            throw CommandError.requiresOption("--json", "--release-preflight")
        }
        if !additionalRequiredScreenshotNames.isEmpty && !verifiesOrWritesReleaseManifest {
            throw CommandError.requiresOption(
                "--require-screenshot",
                "--verify-release-manifest or --release-manifest"
            )
        }
        if options.value(for: "--verify-release-manifest") != nil && options.value(for: "--release-manifest") != nil {
            throw CommandError.conflictingOptions("--verify-release-manifest", "--release-manifest")
        }
        if options.value(for: "--verify-release-manifest") != nil && isReleasePreflight {
            throw CommandError.conflictingOptions("--verify-release-manifest", "--release-preflight")
        }
        if options.value(for: "--release-manifest") != nil && !options.flags.contains("--package-dmg") {
            throw CommandError.requiresOption("--release-manifest", "--package-dmg")
        }
        if options.value(for: "--release-manifest") != nil && options.value(for: "--snapshot-dir") == nil {
            throw CommandError.requiresOption("--release-manifest", "--snapshot-dir")
        }
        if options.value(for: "--bundle-release-evidence") != nil
            && options.value(for: "--release-manifest") == nil
            && options.value(for: "--verify-release-manifest") == nil {
            throw CommandError.requiresOption(
                "--bundle-release-evidence",
                "--release-manifest or --verify-release-manifest"
            )
        }
        if options.value(for: "--oauth-site") != nil && options.value(for: "--release-manifest") == nil {
            throw CommandError.requiresOption("--oauth-site", "--release-manifest")
        }
        if options.value(for: "--snapshot-dir") != nil && options.value(for: "--release-manifest") == nil {
            throw CommandError.requiresOption("--snapshot-dir", "--release-manifest")
        }
        if options.value(for: "--notary-profile") != nil && !isReleasePreflight && !options.flags.contains("--package-dmg") {
            throw CommandError.requiresOption("--notary-profile", "--package-dmg")
        }
        if options.value(for: "--notary-profile") != nil && !isReleasePreflight {
            guard let signingIdentity else {
                throw CommandError.requiresOption("--notary-profile", "--sign-identity")
            }
            guard signingIdentity != "-" else {
                throw CommandError.conflictingOptions("--notary-profile", "--sign-ad-hoc")
            }
            guard signingIdentity.hasPrefix("Developer ID Application:") else {
                throw CommandError.invalidOption(
                    "--sign-identity",
                    "must be a Developer ID Application identity when --notary-profile is used"
                )
            }
        }
        if options.value(for: "--notary-timeout") != nil && options.value(for: "--notary-profile") == nil {
            throw CommandError.requiresOption("--notary-timeout", "--notary-profile")
        }
        if options.value(for: "--notary-timeout") != nil && options.flags.contains("--notary-no-wait") {
            throw CommandError.conflictingOptions("--notary-timeout", "--notary-no-wait")
        }
        if options.flags.contains("--notary-no-wait") && options.value(for: "--notary-profile") == nil {
            throw CommandError.requiresOption("--notary-no-wait", "--notary-profile")
        }
        if options.flags.contains("--skip-staple") && options.value(for: "--notary-profile") == nil {
            throw CommandError.requiresOption("--skip-staple", "--notary-profile")
        }
    }

    private static func validateOAuthSiteOptions(_ options: CommandOptions) throws {
        let writePath = options.value(for: "--write-oauth-site")
        let verifyPath = options.value(for: "--verify-oauth-site")
        let verifiesPublishedSite = options.flags.contains("--verify-published-oauth-site")
        if writePath != nil && verifyPath != nil {
            throw CommandError.conflictingOptions("--write-oauth-site", "--verify-oauth-site")
        }
        if verifiesPublishedSite && writePath != nil {
            throw CommandError.conflictingOptions("--verify-published-oauth-site", "--write-oauth-site")
        }
        if verifiesPublishedSite && verifyPath != nil {
            throw CommandError.conflictingOptions("--verify-published-oauth-site", "--verify-oauth-site")
        }
        if options.value(for: "--oauth-env") != nil && writePath == nil && verifyPath == nil {
            if !verifiesPublishedSite {
                throw CommandError.requiresOption("--oauth-env", "--write-oauth-site or --verify-oauth-site or --verify-published-oauth-site")
            }
        }
    }

    private static func additionalRequiredScreenshotNames(from options: CommandOptions) throws -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for value in options.values(for: "--require-screenshot") {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw CommandError.invalidOption("--require-screenshot", "must not be empty")
            }
            if seen.insert(trimmed).inserted {
                names.append(trimmed)
            }
        }
        return names
    }

    private static func releaseRequiredScreenshotNames(_ additionalNames: [String]) -> [String] {
        var seen = Set(PerchHAReleaseEvidenceScreenshots.requiredNames)
        var names = PerchHAReleaseEvidenceScreenshots.requiredNames
        for name in additionalNames where seen.insert(name).inserted {
            names.append(name)
        }
        return names
    }

    private static func verifyReleaseManifest(
        path: String,
        requiredScreenshotNames: [String]
    ) throws -> PerchHAReleaseEvidenceVerificationReport {
        let report = try PerchHAReleaseEvidenceVerifier().verify(
            PerchHAReleaseEvidenceVerificationConfiguration(
                manifestURL: URL(fileURLWithPath: path, isDirectory: false),
                requiredScreenshotNames: requiredScreenshotNames
            )
        )
        let credentialed = report.credentialedReleaseReady ? "credentialed-ready" : "local-only"
        let oauthSiteSuffix = report.oauthClientWebsiteURL.map { ", oauth site: \($0.path)" } ?? ""
        print("release manifest verified: \(report.manifestURL.path) (\(report.dmgSHA256), \(report.screenshotCount) screenshots, \(credentialed)\(oauthSiteSuffix))")
        return report
    }

    private static func bundleReleaseEvidence(
        manifestPath: String,
        bundlePath: String,
        requiredScreenshotNames: [String],
        replaceExisting: Bool
    ) throws {
        let result = try PerchHAReleaseEvidenceBundler().bundle(
            PerchHAReleaseEvidenceBundleConfiguration(
                manifestURL: URL(fileURLWithPath: manifestPath, isDirectory: false),
                outputDirectoryURL: URL(fileURLWithPath: bundlePath, isDirectory: true),
                replaceExisting: replaceExisting
            )
        )
        let verification = try PerchHAReleaseEvidenceVerifier().verify(
            PerchHAReleaseEvidenceVerificationConfiguration(
                manifestURL: result.manifestURL,
                requiredScreenshotNames: requiredScreenshotNames
            )
        )
        let oauthSiteSuffix = verification.oauthClientWebsiteURL.map { ", oauth site: \($0.path)" } ?? ""
        print("release evidence bundle created: \(result.bundleDirectoryURL.path)")
        print("release evidence bundle verified: \(verification.manifestURL.path) (\(verification.screenshotCount) screenshots\(oauthSiteSuffix))")
    }

    private static func releasePreflight(options: CommandOptions, signingIdentity: String?) throws {
        let configuration = PerchHAReleasePreflightConfiguration(
            signingIdentity: signingIdentity,
            notaryProfile: options.value(for: "--notary-profile")
        )
        let report = try PerchHAReleasePreflightChecker(
            securityURL: URL(fileURLWithPath: options.value(for: "--security") ?? PerchHAReleasePreflightChecker.defaultSecurityURL.path),
            xcrunURL: URL(fileURLWithPath: options.value(for: "--xcrun") ?? PerchHANotarySubmitter.defaultXcrunURL.path)
        ).check(configuration)

        if options.flags.contains("--json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(report.diagnostic(configuration: configuration))
            print(String(data: data, encoding: .utf8) ?? "{}")
        } else {
            print("Release preflight:")
            print("- Developer ID identity: \(report.signingIdentityAvailable ? "ready" : "blocked")")
            print("- Notary keychain profile: \(report.notaryProfileAvailable ? "ready" : "blocked")")
            if !report.issues.isEmpty {
                print("Issues:")
                report.issues.forEach { print("- \($0.description)") }
            }
            let nextSteps = report.nextSteps(configuration: configuration)
            if !nextSteps.isEmpty {
                print("Next steps:")
                nextSteps.forEach { print("- \($0)") }
            }
            let suggestedCommands = report.suggestedCommands(configuration: configuration)
            if !suggestedCommands.isEmpty {
                print("Suggested commands:")
                suggestedCommands.forEach { print("- \($0)") }
            }
        }
        guard report.isReadyForCredentialedRelease else {
            throw CommandError.releasePreflightFailed(report.issues.map(\.description))
        }
        if !options.flags.contains("--json") {
            print("Credentialed release preflight passed.")
        }
    }

    private static func writeOAuthSite(path: String, options: CommandOptions) throws {
        let manifest = try oauthSiteManifest(options: options)
        let outputURL = URL(fileURLWithPath: path, isDirectory: false)
        let result = try PerchHAOAuthClientWebsiteBuilder().build(
            PerchHAOAuthClientWebsiteBuildConfiguration(
                outputURL: outputURL,
                manifest: manifest,
                replaceExisting: options.flags.contains("--replace")
            )
        )
        let verification = try PerchHAOAuthClientWebsiteVerifier().verify(
            PerchHAOAuthClientWebsiteVerificationConfiguration(
                siteURL: outputURL,
                manifest: manifest
            )
        )
        print("OAuth client website written: \(result.siteURL.path)")
        print("OAuth client website verified: \(verification.clientID) -> \(verification.redirectURI)")
    }

    private static func verifyOAuthSite(path: String, options: CommandOptions) throws {
        let manifest = try oauthSiteManifest(options: options)
        let verification = try PerchHAOAuthClientWebsiteVerifier().verify(
            PerchHAOAuthClientWebsiteVerificationConfiguration(
                siteURL: URL(fileURLWithPath: path, isDirectory: false),
                manifest: manifest
            )
        )
        print("OAuth client website verified: \(verification.siteURL.path)")
        print("OAuth redirect declaration verified: \(verification.clientID) -> \(verification.redirectURI)")
    }

    private static func verifyPublishedOAuthSite(options: CommandOptions) throws {
        let manifest = try oauthSiteManifest(options: options)
        guard let siteURL = URL(string: manifest.clientID) else {
            throw PerchHAOAuthClientWebsiteError.invalidClientID(manifest.clientID)
        }
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = PublishedOAuthSiteFetchBox()
        let task = URLSession.shared.dataTask(with: siteURL) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                resultBox.store(.failure(error))
                return
            }
            guard let data,
                  let response = response as? HTTPURLResponse else {
                resultBox.store(.failure(PerchHAOAuthClientWebsiteError.publishedSiteUnreachable(manifest.clientID)))
                return
            }
            resultBox.store(.success((data, response)))
        }
        task.resume()
        semaphore.wait()
        let payload: (Data, HTTPURLResponse)
        do {
            payload = try resultBox.load()?.get() ?? {
                throw PerchHAOAuthClientWebsiteError.publishedSiteUnreachable(manifest.clientID)
            }()
        } catch {
            if let knownError = error as? PerchHAOAuthClientWebsiteError {
                throw knownError
            }
            throw PerchHAOAuthClientWebsiteError.publishedSiteUnreachable(manifest.clientID)
        }
        guard (200...299).contains(payload.1.statusCode) else {
            throw PerchHAOAuthClientWebsiteError.publishedSiteHTTPFailure(manifest.clientID, payload.1.statusCode)
        }
        let verification = try PerchHAOAuthClientWebsiteVerifier().verify(
            data: payload.0,
            siteURL: siteURL,
            manifest: manifest
        )
        print("Published OAuth client website verified: \(verification.clientID)")
        print("Published OAuth redirect declaration verified: \(verification.redirectURI)")
    }

    private static func oauthSiteManifest(options: CommandOptions) throws -> PerchHAOAuthClientWebsiteManifest {
        let environment = try HAOAuthClientWebsiteEnvironment.fromEnvironment(
            ProcessInfo.processInfo.environment,
            environmentFilePath: options.value(for: "--oauth-env")
        )
        return try PerchHAOAuthClientWebsiteManifest(
            clientID: environment.clientID,
            redirectURI: environment.redirectURI
        )
    }

    private static func parseOptions(arguments: [String]) throws -> CommandOptions {
        do {
            let parsed = try PerchHACommandLineOptions(
                arguments: arguments,
                valueOptions: [
                    "--write-oauth-site",
                    "--verify-oauth-site",
                    "--oauth-env",
                    "--executable",
                    "--output",
                    "--callback-scheme",
                    "--bundle-id",
                    "--version",
                    "--build-version",
                    "--minimum-system-version",
                    "--dmg-output",
                    "--dmg-volume-name",
                    "--hdiutil",
                    "--security",
                    "--codesign",
                    "--xcrun",
                    "--sign-identity",
                    "--sign-entitlements",
                    "--notary-profile",
                    "--notary-timeout",
                    "--release-manifest",
                    "--verify-release-manifest",
                    "--bundle-release-evidence",
                    "--oauth-site",
                    "--require-screenshot",
                    "--snapshot-dir"
                ],
                flagOptions: [
                    "--replace",
                    "--verify-published-oauth-site",
                    "--verify-launch-services",
                    "--package-dmg",
                    "--verify-dmg",
                    "--verify-dmg-contents",
                    "--sign-ad-hoc",
                    "--sign-without-timestamp",
                    "--sign-without-hardened-runtime",
                    "--verify-signature",
                    "--release-preflight",
                    "--notary-no-wait",
                    "--skip-staple",
                    "--json"
                ]
            )
            return CommandOptions(parsed: parsed)
        } catch let error as PerchHACommandLineParseError {
            throw CommandError(parseError: error)
        }
    }
}

private struct CommandOptions {
    let flags: Set<String>
    private let parsed: PerchHACommandLineOptions

    init(parsed: PerchHACommandLineOptions) {
        self.flags = parsed.flags
        self.parsed = parsed
    }

    func value(for option: String) -> String? {
        parsed.value(for: option)
    }

    func values(for option: String) -> [String] {
        parsed.values(for: option)
    }
}

private final class PublishedOAuthSiteFetchBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<(Data, HTTPURLResponse), Error>?

    func store(_ result: Result<(Data, HTTPURLResponse), Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
    }

    func load() -> Result<(Data, HTTPURLResponse), Error>? {
        lock.lock()
        let result = self.result
        lock.unlock()
        return result
    }
}

private enum CommandError: Error, CustomStringConvertible {
    case missingValue(String)
    case unknownOption(String)
    case conflictingOptions(String, String)
    case requiresOption(String, String)
    case invalidOption(String, String)
    case releasePreflightFailed([String])

    init(parseError: PerchHACommandLineParseError) {
        switch parseError {
        case let .missingValue(option):
            self = .missingValue(option)
        case let .unknownOption(option), let .invalidArgument(option):
            self = .unknownOption(option)
        }
    }

    var description: String {
        switch self {
        case let .missingValue(option):
            "missing value for \(option)"
        case let .unknownOption(option):
            "unknown option: \(option)"
        case let .conflictingOptions(first, second):
            "conflicting options: \(first) and \(second)"
        case let .requiresOption(option, required):
            "\(option) requires \(required)"
        case let .invalidOption(option, reason):
            "\(option) \(reason)"
        case let .releasePreflightFailed(issues):
            "release preflight failed: \(issues.joined(separator: "; "))"
        }
    }
}
