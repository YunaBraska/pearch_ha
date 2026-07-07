import Foundation
import PerchHAUI

public struct PerchHAGitHubReleaseUpdateChecker: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private let owner: String
    private let repository: String
    private let transport: Transport

    public init(
        owner: String = "YunaBraska",
        repository: String = "pearch_ha",
        transport: @escaping Transport = Self.liveTransport
    ) {
        self.owner = owner
        self.repository = repository
        self.transport = transport
    }

    public func checkLatest(currentVersion: String) async -> PerchHAReleaseUpdateCheckResult {
        let normalizedCurrentVersion = currentVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCurrentVersion.isEmpty else {
            return .failed("current version is unavailable")
        }
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/latest") else {
            return .failed("update URL is invalid")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("PerchHA/\(normalizedCurrentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await transport(request)
            guard response.statusCode == 200 else {
                return .failed("GitHub release check failed with HTTP \(response.statusCode)")
            }
            let release = try JSONDecoder().decode(GitHubReleaseDTO.self, from: data)
            let latestVersion = release.tagName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !latestVersion.isEmpty else {
                return .failed("GitHub latest release did not include a version tag")
            }
            let downloadURL = preferredDownloadURL(from: release.assets) ?? release.htmlURL
            if Self.isNewerRelease(currentVersion: normalizedCurrentVersion, latestVersion: latestVersion) {
                return .updateAvailable(
                    PerchHAReleaseUpdate(
                        currentVersion: normalizedCurrentVersion,
                        latestVersion: latestVersion,
                        releaseURL: release.htmlURL,
                        downloadURL: downloadURL
                    )
                )
            }
            return .upToDate(
                currentVersion: normalizedCurrentVersion,
                latestVersion: latestVersion,
                releaseURL: release.htmlURL
            )
        } catch let error as DecodingError {
            return .failed("GitHub latest release response was invalid: \(error)")
        } catch let error as URLError {
            return .failed(Self.networkFailureDescription(error))
        } catch {
            return .failed("GitHub release check failed: \(error.localizedDescription)")
        }
    }

    public static func isNewerRelease(currentVersion: String, latestVersion: String) -> Bool {
        let currentParts = versionParts(from: currentVersion)
        let latestParts = versionParts(from: latestVersion)
        let count = max(currentParts.count, latestParts.count)
        for index in 0..<count {
            let current = currentParts.indices.contains(index) ? currentParts[index] : 0
            let latest = latestParts.indices.contains(index) ? latestParts[index] : 0
            if latest != current {
                return latest > current
            }
        }
        return false
    }

    public static func liveTransport(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }

    private func preferredDownloadURL(from assets: [GitHubReleaseAssetDTO]) -> URL? {
        let preferredSuffixes = [".dmg", ".zip"]
        for suffix in preferredSuffixes {
            if let asset = assets.first(where: { $0.name.lowercased().hasSuffix(suffix) }) {
                return asset.browserDownloadURL
            }
        }
        return nil
    }

    private static func versionParts(from version: String) -> [Int] {
        let separators = CharacterSet.decimalDigits.inverted
        return version
            .components(separatedBy: separators)
            .compactMap { Int($0) }
    }

    private static func networkFailureDescription(_ error: URLError) -> String {
        switch error.code {
        case .timedOut:
            return "GitHub release check timed out"
        case .notConnectedToInternet, .networkConnectionLost:
            return "GitHub release check needs an internet connection"
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return "GitHub release host is unreachable"
        default:
            return "GitHub release check failed: \(error.localizedDescription)"
        }
    }
}

private struct GitHubReleaseDTO: Decodable {
    let tagName: String
    let htmlURL: URL
    let assets: [GitHubReleaseAssetDTO]

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }
}

private struct GitHubReleaseAssetDTO: Decodable {
    let name: String
    let browserDownloadURL: URL

    private enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}
