#if canImport(XCTest)
import XCTest

func XCTAssertEqual<T: Equatable>(
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

func XCTAssertTrue(
    _ expression: @autoclosure () async throws -> Bool,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) async rethrows {
    XCTAssertTrue(try await expression(), message(), file: file, line: line)
}

func XCTAssertFalse(
    _ expression: @autoclosure () async throws -> Bool,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) async rethrows {
    XCTAssertFalse(try await expression(), message(), file: file, line: line)
}
#endif
