import XCTest
@testable import AshenCore

final class AreaTests: XCTestCase {
    func testActOneProgression() {
        let areas = Areas.actOne
        XCTAssertTrue(areas.first!.isTown)
        XCTAssertEqual(areas.last!.style, .arena)
        let levels = areas.map(\.level)
        XCTAssertEqual(levels, levels.sorted(), "area levels should not decrease")
        XCTAssertEqual(Set(areas.map(\.id)).count, areas.count)
        for a in areas where !a.isTown && a.style != .arena { XCTAssertFalse(a.monsters.isEmpty, a.name) }
    }

    func testMonsterScaling() {
        let base = Bestiary.husk
        let hi = base.scaled(to: base.level + 5)
        XCTAssertEqual(hi.level, base.level + 5)
        XCTAssertGreaterThan(hi.life.lowerBound, base.life.lowerBound)
        XCTAssertGreaterThan(hi.damage.upperBound, base.damage.upperBound)
        XCTAssertGreaterThan(hi.xp, base.xp)
        // Never scales below base.
        XCTAssertEqual(base.scaled(to: 1).level, base.level)
    }

    func testShamanResurrects() {
        var map = TileMap(width: 20, height: 20, fill: .wall)
        for y in 1..<19 { for x in 1..<19 { map[x, y] = .floor } }
        let level = GeneratedLevel(map: map, rooms: [Room(x: 1, y: 1, w: 18, h: 18)], spawn: GridPoint(2, 2), exit: GridPoint(16, 16))
        let w = GameWorld(level: level)
        let imp = w.spawn(Bestiary.murkling, at: Vec2(center: GridPoint(8, 8)), packID: 1)
        w.spawn(Bestiary.mireHexer, at: Vec2(center: GridPoint(10, 8)), packID: 1)
        let idx = w.monsters.firstIndex { $0.id == imp }!
        w.apply(.hit(damage: 999, crit: false), toMonsterAt: idx)
        XCTAssertFalse(w.monster(imp)!.isAlive)
        var revived = false
        for _ in 0..<(60 * 8) {
            w.update(dt: 1.0 / 60)
            if w.drainEvents().contains(where: { if case .resurrected(imp, _) = $0 { true } else { false } }) { revived = true; break }
        }
        XCTAssertTrue(revived)
        XCTAssertTrue(w.monster(imp)!.isAlive)
    }
}
