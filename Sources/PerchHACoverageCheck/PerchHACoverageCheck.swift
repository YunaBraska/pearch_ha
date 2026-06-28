import Foundation
import PerchHASupport

public enum PerchHACoverageCheckCommand {
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
                standardOutput(CoverageCheckError.help)
                return 0
            }
            let report = try CoverageCheck(arguments: arguments).run()
            report.lines.forEach(standardOutput)
            return 0
        } catch {
            standardError("perchha-coverage-check: \(error)\n")
            return 1
        }
    }
}

struct CoverageCheck {
    let arguments: [String]

    func run() throws -> CoverageReport {
        let options = try CoverageOptions(arguments: arguments)
        let jsonURL = URL(fileURLWithPath: options.coverageJSONPath)
        let data = try Data(contentsOf: jsonURL)
        let coverage = try CoverageJSON(data: data)
        let checks = try options.thresholds.map { threshold in
            try coverage.check(threshold)
        }

        let failures = checks.filter { !$0.passed }
        guard failures.isEmpty else {
            throw CoverageCheckError.thresholdsFailed(failures.map(\.failureDescription))
        }

        return CoverageReport(
            lines: ["Coverage gate passed."]
                + checks.map(\.successDescription)
        )
    }
}

struct CoverageReport: Equatable {
    let lines: [String]
}

enum CoverageMetric: String, Equatable {
    case line = "line"
    case branch = "branch"
}

struct CoverageThreshold: Equatable {
    let targetName: String
    let metric: CoverageMetric
    let minimumPercent: Double
}

struct CoverageThresholdResult: Equatable {
    let threshold: CoverageThreshold
    let actualPercent: Double
    let covered: Double
    let total: Double

    var passed: Bool {
        actualPercent >= threshold.minimumPercent
    }

    var successDescription: String {
        "- \(threshold.targetName) \(threshold.metric.rawValue): \(format(actualPercent))% >= \(format(threshold.minimumPercent))% (\(formatCount(covered))/\(formatCount(total)))"
    }

    var failureDescription: String {
        "\(threshold.targetName) \(threshold.metric.rawValue) coverage \(format(actualPercent))% is below \(format(threshold.minimumPercent))% (\(formatCount(covered))/\(formatCount(total)))"
    }

    private func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func formatCount(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return format(value)
    }
}

struct CoverageOptions {
    let coverageJSONPath: String
    let thresholds: [CoverageThreshold]

    init(arguments: [String]) throws {
        var coverageJSONPath: String?
        var thresholds: [CoverageThreshold] = []
        do {
            let options = try PerchHACommandLineOptions(
                arguments: arguments,
                valueOptions: ["--coverage-json", "--line-target", "--branch-target"],
                flagOptions: []
            )
            coverageJSONPath = options.value(for: "--coverage-json")
            thresholds = try options.values(for: "--line-target").map {
                try Self.threshold(from: $0, metric: .line)
            }
            thresholds += try options.values(for: "--branch-target").map {
                try Self.threshold(from: $0, metric: .branch)
            }
        } catch let error as PerchHACommandLineParseError {
            throw CoverageCheckError(parseError: error)
        }

        guard let coverageJSONPath, !coverageJSONPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CoverageCheckError.missingOption("--coverage-json")
        }
        guard !thresholds.isEmpty else {
            throw CoverageCheckError.noThresholds
        }

        self.coverageJSONPath = coverageJSONPath
        self.thresholds = thresholds
    }

    private static func threshold(from value: String, metric: CoverageMetric) throws -> CoverageThreshold {
        let parts = value.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            throw CoverageCheckError.invalidThreshold(value)
        }
        let targetName = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetName.isEmpty else {
            throw CoverageCheckError.invalidThreshold(value)
        }
        guard let minimumPercent = Double(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)),
              minimumPercent >= 0,
              minimumPercent <= 100
        else {
            throw CoverageCheckError.invalidThreshold(value)
        }
        return CoverageThreshold(
            targetName: targetName,
            metric: metric,
            minimumPercent: minimumPercent
        )
    }
}

struct CoverageJSON {
    let files: [CoverageFile]

    init(data: Data) throws {
        let value = try JSONSerialization.jsonObject(with: data)
        guard let root = value as? [String: Any],
              let dataEntries = root["data"] as? [[String: Any]]
        else {
            throw CoverageCheckError.invalidCoverageJSON("missing data array")
        }

        files = try dataEntries.flatMap { dataEntry -> [CoverageFile] in
            guard let fileEntries = dataEntry["files"] as? [[String: Any]] else {
                return []
            }
            return try fileEntries.map(CoverageFile.init(entry:))
        }
    }

    func check(_ threshold: CoverageThreshold) throws -> CoverageThresholdResult {
        let matchingFiles = files.filter { $0.belongs(to: threshold.targetName) }
        guard !matchingFiles.isEmpty else {
            throw CoverageCheckError.targetMissing(threshold.targetName)
        }

        let availableMetrics = matchingFiles.compactMap { $0.totals(for: threshold.metric) }
        guard !availableMetrics.isEmpty else {
            throw CoverageCheckError.metricUnavailable(threshold.targetName, threshold.metric)
        }

        let totals = availableMetrics.reduce(CoverageMetricTotals()) { partial, metricTotals in
            partial.adding(metricTotals)
        }
        return CoverageThresholdResult(
            threshold: threshold,
            actualPercent: totals.percent,
            covered: totals.covered,
            total: totals.total
        )
    }
}

struct CoverageFile {
    let filename: String
    let lines: CoverageMetricTotals?
    let branches: CoverageMetricTotals?

    init(entry: [String: Any]) throws {
        guard let filename = entry["filename"] as? String else {
            throw CoverageCheckError.invalidCoverageJSON("file entry missing filename")
        }
        guard let summary = entry["summary"] as? [String: Any] else {
            throw CoverageCheckError.invalidCoverageJSON("file entry missing summary")
        }
        self.filename = filename
        lines = Self.metricTotals(named: "lines", in: summary)
        branches = Self.metricTotals(named: "branches", in: summary)
    }

    func belongs(to targetName: String) -> Bool {
        filename.contains("/Sources/\(targetName)/")
            || filename.hasPrefix("Sources/\(targetName)/")
    }

    func totals(for metric: CoverageMetric) -> CoverageMetricTotals? {
        switch metric {
        case .line:
            lines
        case .branch:
            branches
        }
    }

    private static func metricTotals(named name: String, in summary: [String: Any]) -> CoverageMetricTotals? {
        guard let entry = summary[name] as? [String: Any] else {
            return nil
        }
        return CoverageMetricTotals(
            covered: number(entry["covered"]),
            total: number(entry["count"])
        )
    }

    private static func number(_ value: Any?) -> Double {
        switch value {
        case let value as Double:
            value
        case let value as Int:
            Double(value)
        case let value as NSNumber:
            value.doubleValue
        default:
            0
        }
    }
}

struct CoverageMetricTotals: Equatable {
    let covered: Double
    let total: Double

    init(covered: Double = 0, total: Double = 0) {
        self.covered = covered
        self.total = total
    }

    var percent: Double {
        total == 0 ? 100 : covered / total * 100
    }

    func adding(_ other: CoverageMetricTotals) -> CoverageMetricTotals {
        CoverageMetricTotals(
            covered: covered + other.covered,
            total: total + other.total
        )
    }
}

enum CoverageCheckError: Error, Equatable, CustomStringConvertible {
    case unknownOption(String)
    case missingOption(String)
    case missingValue(String)
    case noThresholds
    case invalidThreshold(String)
    case invalidCoverageJSON(String)
    case targetMissing(String)
    case metricUnavailable(String, CoverageMetric)
    case thresholdsFailed([String])

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
        case let .missingOption(option):
            "missing required option: \(option)"
        case let .missingValue(option):
            "missing value for \(option)"
        case .noThresholds:
            "at least one --line-target or --branch-target is required"
        case let .invalidThreshold(value):
            "invalid threshold: \(value); expected TargetName=Percent"
        case let .invalidCoverageJSON(reason):
            "invalid coverage JSON: \(reason)"
        case let .targetMissing(target):
            "coverage JSON does not contain Sources/\(target)"
        case let .metricUnavailable(target, metric):
            "coverage JSON does not contain \(metric.rawValue) coverage for Sources/\(target)"
        case let .thresholdsFailed(failures):
            "coverage thresholds failed:\n\(failures.map { "- \($0)" }.joined(separator: "\n"))"
        }
    }

    static let help = """
    Usage:
      perchha-coverage-check --coverage-json PATH --line-target PerchHACore=95 --line-target PerchHAClient=95 --branch-target PerchHACore=90
    """
}
