#if canImport(XCTest)
import Foundation
import XCTest

public func assertEqualAsync<T: Equatable>(
    _ expression1: @autoclosure () async throws -> T,
    _ expression2: @autoclosure () async throws -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) async rethrows {
    let value1 = try await expression1()
    let value2 = try await expression2()
    XCTAssertEqual(value1, value2, message(), file: file, line: line)
}

public func assertTrueAsync(
    _ expression: @autoclosure () async throws -> Bool,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) async rethrows {
    let value = try await expression()
    XCTAssertTrue(value, message(), file: file, line: line)
}

public func assertFalseAsync(
    _ expression: @autoclosure () async throws -> Bool,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) async rethrows {
    let value = try await expression()
    XCTAssertFalse(value, message(), file: file, line: line)
}

public func waitUntil(
    _ message: String,
    initialYields: Int = 100,
    pollCount: Int = 0,
    pollIntervalNanoseconds: UInt64 = 10_000_000,
    condition: @escaping () async -> Bool
) async throws {
    for _ in 0..<initialYields {
        if await condition() {
            return
        }
        await Task.yield()
    }
    for _ in 0..<pollCount {
        if await condition() {
            return
        }
        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
    }
    if await condition() {
        return
    }
    throw WaitFailure(message)
}

public struct WaitFailure: Error, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}
#endif
