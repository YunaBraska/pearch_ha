import Foundation
import PerchHAPackaging

@main
struct PerchHAPackageAppCommand {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.contains("--help") || arguments.contains("-h") {
            print(help)
            return
        }
        let options = try CommandOptions(arguments: arguments)
        let manifest = try PerchHAAppBundleManifest(
            bundleIdentifier: options.value(for: "--bundle-id") ?? "dev.perchha.app",
            version: options.value(for: "--version") ?? "0.1.0",
            buildVersion: options.value(for: "--build-version") ?? "1",
            minimumSystemVersion: options.value(for: "--minimum-system-version") ?? "13.0",
            callbackURLScheme: options.value(for: "--callback-scheme") ?? "perchha"
        )
        let result = try PerchHAAppBundleBuilder().build(
            PerchHAAppBundleBuildConfiguration(
                executableURL: URL(fileURLWithPath: options.value(for: "--executable") ?? ".build/debug/PerchHA"),
                outputURL: URL(fileURLWithPath: options.value(for: "--output") ?? ".build/PerchHA.app"),
                manifest: manifest,
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
    }

    private static let help = """
    Usage:
      perchha-package-app [--executable PATH] [--output PATH] [--callback-scheme SCHEME] [--replace] [--verify-launch-services]

    Options:
      --executable PATH             SwiftPM-built PerchHA executable. Default: .build/debug/PerchHA
      --output PATH                 Output .app bundle. Default: .build/PerchHA.app
      --callback-scheme SCHEME      OAuth callback URL scheme. Default: perchha
      --bundle-id ID                Bundle identifier. Default: dev.perchha.app
      --version VERSION             CFBundleShortVersionString. Default: 0.1.0
      --build-version VERSION       CFBundleVersion. Default: 1
      --minimum-system-version VER  LSMinimumSystemVersion. Default: 13.0
      --replace                     Remove an existing output bundle before writing.
      --verify-launch-services      Register the bundle and verify macOS records its callback scheme claim.
    """
}

private struct CommandOptions {
    let flags: Set<String>
    private let values: [String: String]

    init(arguments: [String]) throws {
        let valueOptions: Set<String> = [
            "--executable",
            "--output",
            "--callback-scheme",
            "--bundle-id",
            "--version",
            "--build-version",
            "--minimum-system-version"
        ]
        var flags = Set<String>()
        var values: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if valueOptions.contains(argument) {
                let valueIndex = index + 1
                guard valueIndex < arguments.count else {
                    throw CommandError.missingValue(argument)
                }
                values[argument] = arguments[valueIndex]
                index += 2
            } else if argument == "--replace" || argument == "--verify-launch-services" {
                flags.insert(argument)
                index += 1
            } else {
                throw CommandError.unknownOption(argument)
            }
        }
        self.flags = flags
        self.values = values
    }

    func value(for option: String) -> String? {
        values[option]
    }
}

private enum CommandError: Error, CustomStringConvertible {
    case missingValue(String)
    case unknownOption(String)

    var description: String {
        switch self {
        case let .missingValue(option):
            "missing value for \(option)"
        case let .unknownOption(option):
            "unknown option: \(option)"
        }
    }
}
