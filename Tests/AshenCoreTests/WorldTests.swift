import XCTest
@testable import AshenCore

final class WorldTests: XCTestCase {
    func testRNGIsDeterministic() {
        var a = SeededRNG(seed: 42), b = SeededRNG(seed: 42)
        for _ in 0..<100 { XCTAssertEqual(a.next(), b.next()) }
    }

    func testDungeonIsDeterministic() {
        let g = DungeonGenerator()
        let a = g.generate(seed: 7), b = g.generate(seed: 7)
        XCTAssertEqual(a.rooms, b.rooms)
        XCTAssertEqual(a.spawn, b.spawn)
    }

    func testDungeonIsFullyConnected() {
        for seed in UInt64(1)...30 {
            let level = DungeonGenerator().generate(seed: seed)
            let floors = Set(level.map.allPoints.filter { level.map.isWalkable($0) })
            XCTAssertGreaterThan(level.rooms.count, 4, "seed \(seed)")
            XCTAssertEqual(level.map.reachable(from: level.spawn), floors, "seed \(seed)")
            XCTAssertTrue(floors.contains(level.exit))
        }
    }

    func testFloorsAreEnclosedByWalls() {
        let level = DungeonGenerator().generate(seed: 3)
        for p in level.map.allPoints where level.map.isWalkable(p) {
            for d in GridPoint.neighbors8 { XCTAssertNotEqual(level.map[p + d], .void) }
        }
    }

    func testIsoRoundTrip() {
        for p in [Vec2(0, 0), Vec2(3.5, 7.25), Vec2(-2, 10)] {
            let s = Iso.toScreen(p)
            let w = Iso.toWorld(screenX: s.x, screenY: s.y)
            XCTAssertEqual(w.x, p.x, accuracy: 1e-9)
            XCTAssertEqual(w.y, p.y, accuracy: 1e-9)
        }
    }
}
