import XCTest

@testable import HueCore

final class BrightnessTests: XCTestCase {
    func testClampsBelowMinimumToMinimum() {
        XCTAssertEqual(Brightness.clamp(0), Brightness.minimum)
        XCTAssertEqual(Brightness.clamp(-40), Brightness.minimum)
    }

    func testClampsAboveMaximumToMaximum() {
        XCTAssertEqual(Brightness.clamp(255), Brightness.maximum)
        XCTAssertEqual(Brightness.clamp(1000), Brightness.maximum)
    }

    func testKeepsValuesWithinRange() {
        XCTAssertEqual(Brightness.clamp(1), 1)
        XCTAssertEqual(Brightness.clamp(127), 127)
        XCTAssertEqual(Brightness.clamp(254), 254)
    }
}
