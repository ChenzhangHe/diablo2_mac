import XCTest
@testable import AshenCore

final class PathTests: XCTestCase {
    func testHeapOrders() {
        var h = BinaryHeap<Int>()
        for x in [5, 3, 9, 1, 7, 2] { h.push(x) }
        var out: [Int] = []
        while let x = h.pop() { out.append(x) }
        XCTAssertEqual(out, [1, 2, 3, 5, 7, 9])
    }

    func testPathAroundWall() {
        var map = TileMap(width: 10, height: 10, fill: .floor)
        for y in 0..<8 { map[5, y] = .wall }
        let path = Pathfinder.findPath(on: map, from: GridPoint(1, 1), to: GridPoint(8, 1))
        XCTAssertNotNil(path)
        XCTAssertTrue(path!.allSatisfy { map.isWalkable($0) })
        XCTAssertTrue(path!.contains { $0.y >= 8 })
    }

    func testAllRoomsReachableInDungeon() {
        let level = DungeonGenerator().generate(seed: 11)
        for room in level.rooms {
            XCTAssertNotNil(Pathfinder.findPath(on: level.map, from: level.spawn, to: room.center))
        }
    }

    func testMoverReachesExit() {
        let level = DungeonGenerator().generate(seed: 5)
        var m = Mover(position: Vec2(center: level.spawn), speed: 5)
        XCTAssertTrue(m.moveTo(Vec2(center: level.exit), on: level.map))
        for _ in 0..<(60 * 120) where m.isMoving { m.update(dt: 1.0 / 60, map: level.map) }
        XCTAssertLessThan(m.position.distance(to: Vec2(center: level.exit)), 0.01)
    }

    func testNearestWalkable() {
        var map = TileMap(width: 5, height: 5, fill: .wall)
        map[3, 3] = .floor
        XCTAssertEqual(Pathfinder.nearestWalkable(on: map, to: GridPoint(2, 2)), GridPoint(3, 3))
    }
}
