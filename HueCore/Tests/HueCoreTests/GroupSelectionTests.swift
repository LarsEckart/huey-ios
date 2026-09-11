import XCTest

@testable import HueCore

final class GroupSelectionTests: XCTestCase {
    func testKeepsOnlyRoomsAndZones() {
        let groups = [
            makeGroup(name: "Bedroom", type: "Room"),
            makeGroup(name: "Garden", type: "Zone"),
            makeGroup(name: "Lamp", type: "Entertainment"),
        ]

        let visible = GroupSelection.visible(in: groups)

        XCTAssertEqual(visible.map(\.name), ["Bedroom", "Garden"])
    }

    func testReturnsEmptyWhenNothingVisible() {
        let groups = [makeGroup(name: "Lamp", type: "Entertainment")]

        XCTAssertTrue(GroupSelection.visible(in: groups).isEmpty)
    }

    func testSortsByNameCaseInsensitively() {
        let groups = [
            makeGroup(name: "zebra", type: "room", id: "3"),
            makeGroup(name: "Alpha", type: "room", id: "1"),
            makeGroup(name: "midnight", type: "room", id: "2"),
        ]

        let ordered = GroupSelection.visible(in: groups).map(\.name)

        XCTAssertEqual(ordered, ["Alpha", "midnight", "zebra"])
    }

    func testTieBreaksEqualNamesByID() {
        let groups = [
            makeGroup(name: "Office", type: "room", id: "20"),
            makeGroup(name: "Office", type: "room", id: "3"),
        ]

        // Matches the original app: ids tie-break lexicographically, so
        // "20" sorts before "3".
        let ordered = GroupSelection.visible(in: groups).map(\.id)

        XCTAssertEqual(ordered, ["20", "3"])
    }

    private func makeGroup(name: String, type: String, id: String = "1") -> HueGroup {
        HueGroup(id: id, name: name, type: type, anyOn: false, brightness: nil)
    }
}
