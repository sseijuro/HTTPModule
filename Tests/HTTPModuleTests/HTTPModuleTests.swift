import XCTest
@testable import HTTPModule

final class HTTPModuleTests: XCTestCase {
    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(HTTPModule().text, "Hello, World!")
    }
}
