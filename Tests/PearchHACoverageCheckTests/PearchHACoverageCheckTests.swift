#if canImport(XCTest)
import XCTest
import PearchHACoverageCheck

final class PearchHACoverageCheckTests: XCTestCase {
    func testBranchTargetFailsWhenMatchingFilesHaveNoBranchMetric() throws {
        let result = try runCoverageCheck(
            coverageJSON: """
            {"data":[{"files":[{"filename":"/tmp/project/Sources/PearchHACore/Foo.swift","summary":{"lines":{"count":10,"covered":10}}}]}]}
            """,
            arguments: ["--branch-target", "PearchHACore=90"]
        )

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.errorText.contains("branch coverage for Sources/PearchHACore"))
    }

    func testBranchTargetAggregatesAvailableBranchMetrics() throws {
        let result = try runCoverageCheck(
            coverageJSON: """
            {"data":[{"files":[{"filename":"/tmp/project/Sources/PearchHACore/Foo.swift","summary":{"lines":{"count":10,"covered":10},"branches":{"count":6,"covered":5}}},{"filename":"/tmp/project/Sources/PearchHACore/Bar.swift","summary":{"lines":{"count":10,"covered":10},"branches":{"count":4,"covered":4}}},{"filename":"/tmp/project/Sources/PearchHAClient/Client.swift","summary":{"lines":{"count":10,"covered":10},"branches":{"count":20,"covered":1}}}]}]}
            """,
            arguments: ["--branch-target", "PearchHACore=90"]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("- PearchHACore branch: 90.00% >= 90.00% (9/10)"))
    }

    func testAvailableZeroCountBranchMetricPassesAsFullCoverage() throws {
        let result = try runCoverageCheck(
            coverageJSON: """
            {"data":[{"files":[{"filename":"Sources/PearchHACore/Foo.swift","summary":{"lines":{"count":1,"covered":1},"branches":{"count":0,"covered":0}}}]}]}
            """,
            arguments: ["--branch-target", "PearchHACore=100"]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("- PearchHACore branch: 100.00% >= 100.00% (0/0)"))
    }

    func testMalformedCoverageJSONFailsExplicitly() throws {
        let result = try runCoverageCheck(
            coverageJSON: "{}",
            arguments: ["--line-target", "PearchHACore=95"]
        )

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.errorText.contains("invalid coverage JSON: missing data array"))
    }

    func testMissingTargetFailsExplicitly() throws {
        let result = try runCoverageCheck(
            coverageJSON: #"{"data":[{"files":[]}]}"#,
            arguments: ["--line-target", "PearchHACore=95"]
        )

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.errorText.contains("coverage JSON does not contain Sources/PearchHACore"))
    }

    func testInvalidThresholdFailsBeforeReadingCoverageFile() {
        let result = PearchHACoverageCheckCommand.run(
            arguments: ["--coverage-json", "/path/that/does/not/exist.json", "--line-target", "PearchHACore=bad"],
            standardOutput: { _ in XCTFail("invalid threshold should not print success") },
            standardError: { _ in }
        )

        XCTAssertEqual(result, 1)
    }

    func testCoverageJSONOptionRejectsNextOptionAsValue() {
        var errors: [String] = []

        let exitCode = PearchHACoverageCheckCommand.run(
            arguments: ["--coverage-json", "--line-target", "PearchHACore=95"],
            standardOutput: { _ in XCTFail("missing coverage path should not print success") },
            standardError: { errors.append($0) }
        )

        XCTAssertEqual(exitCode, 1)
        XCTAssertTrue(errors.joined().contains("missing value for --coverage-json"))
    }

    private func runCoverageCheck(coverageJSON: String, arguments: [String]) throws -> CoverageCheckResult {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let jsonURL = directory.appendingPathComponent("coverage.json", isDirectory: false)
        try Data(coverageJSON.utf8).write(to: jsonURL)
        var output: [String] = []
        var errors: [String] = []
        let exitCode = PearchHACoverageCheckCommand.run(
            arguments: ["--coverage-json", jsonURL.path] + arguments,
            standardOutput: { output.append($0) },
            standardError: { errors.append($0) }
        )
        return CoverageCheckResult(exitCode: exitCode, output: output.joined(separator: "\n"), errorText: errors.joined())
    }

    private func temporaryDirectory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PearchHACoverageCheckTests-\(UUID().uuidString)", isDirectory: true)
    }
}

private struct CoverageCheckResult {
    let exitCode: Int32
    let output: String
    let errorText: String
}
#endif
