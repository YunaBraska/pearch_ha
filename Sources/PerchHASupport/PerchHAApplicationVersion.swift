import Foundation

public struct PerchHAApplicationVersionInfo: Equatable, Sendable {
    public let marketingVersion: String?
    public let buildVersion: String?

    public init(marketingVersion: String?, buildVersion: String?) {
        self.marketingVersion = Self.normalized(marketingVersion)
        self.buildVersion = Self.normalized(buildVersion)
    }

    public var releaseVersion: String {
        marketingVersion ?? buildVersion ?? "1.0"
    }

    public var displayText: String {
        switch (marketingVersion, buildVersion) {
        case let (marketing?, build?) where marketing == build:
            marketing
        case let (marketing?, build?):
            "\(marketing) (\(build))"
        case let (marketing?, nil):
            marketing
        case let (nil, build?):
            build
        case (nil, nil):
            "1.0"
        }
    }

    public static func fromInfoDictionary(_ info: [String: Any]?) -> PerchHAApplicationVersionInfo {
        PerchHAApplicationVersionInfo(
            marketingVersion: info?["CFBundleShortVersionString"] as? String,
            buildVersion: info?["CFBundleVersion"] as? String
        )
    }

    public static func currentBundle() -> PerchHAApplicationVersionInfo {
        fromInfoDictionary(Bundle.main.infoDictionary)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return nil
        }
        return value
    }
}
