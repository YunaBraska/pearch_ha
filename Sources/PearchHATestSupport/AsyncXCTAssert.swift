#if canImport(XCTest)
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
#endif
