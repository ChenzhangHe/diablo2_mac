import XCTest
@testable import AshenCore

final class EliteTests: XCTestCase {
    private func arena() -> GeneratedLevel {
        var map = TileMap(width: 20, height: 20, fill: .wall)
        for y in 1..<19 { for x in 1..<19 { map[x, y] = .floor } }
        return GeneratedLevel(map: map, rooms: [Room(x: 1, y: 1, w: 18, h: 18)], spawn: GridPoint(3, 3), exit: GridPoint(16, 16))
    }

    func testUniquePackHasLeaderAndMinions() {
        let w = GameWorld(level: arena())
        let ids = w.spawnPack(kind: Bestiary.murkling, in: Room(x: 8, y: 8, w: 6, h: 6), packID: 1)
        let normalLife = w.monster(ids[0])!.stats.maxLife
        w.makeUniquePack(ids)
        let boss = w.monster(ids[0])!
        XCTAssertEqual(boss.rank, .unique)
        XCTAssertNotNil(boss.uniqueName)
        XCTAssertFalse(boss.affixes.isEmpty)
        XCTAssertGreaterThanOrEqual(boss.stats.maxLife, normalLife * 4)
        XCTAssertEqual(boss.stats.level, Bestiary.murkling.level + 3)
        for id in ids.dropFirst() { XCTAssertEqual(w.monster(id)?.rank, .minion) }
    }

    func testChampionPackCappedAtFour() {
        let w = GameWorld(level: arena())
        var kind = Bestiary.murkling
        kind = MonsterKind(id: kind.id, name: kind.name, level: 1, life: kind.life, damage: kind.damage, damageType: .physical,
                           attackRating: 30, defense: 3, resist: Resistances(), speed: 3, attacksPerSecond: 1, reach: 1,
                           aggroRadius: 8, behavior: .skittish, packSize: 7...7, xp: 6, radius: 0.25, color: kind.color, isUndead: false)
        let ids = w.spawnPack(kind: kind, in: Room(x: 8, y: 8, w: 6, h: 6), packID: 1)
        w.makeChampionPack(ids)
        XCTAssertEqual(w.monsters.filter { $0.rank == .champion }.count, 4)
        XCTAssertEqual(w.monsters.count, 4)
        XCTAssertEqual(Set(w.monsters.flatMap(\.affixes)).count, 1)
    }

    func testAffixesModifyStats() {
        var rng = SeededRNG(seed: 1)
        var m = Monster(id: 1, kind: Bestiary.husk, at: .zero, packID: 0, rng: &rng)
        m.promote(to: .champion, affixes: [.fireTouched, .stoneskin])
        XCTAssertEqual(m.stats.resist.fire, 75)
        XCTAssertEqual(m.stats.elemental.first?.type, .fire)
        XCTAssertEqual(m.stats.damageReduction, 40)
        XCTAssertEqual(m.xpValue, Bestiary.husk.xp * 3)
    }

    func testFrostChillsPlayer() {
        let w = GameWorld(level: arena())
        w.player.stats.defense = 0
        let id = w.spawn(Bestiary.husk, at: w.player.position + Vec2(1, 0))
        let i = w.monsters.firstIndex { $0.id == id }!
        w.monsters[i].promote(to: .champion, affixes: [.frostTouched])
        w.monsters[i].stats.attackRating = 100_000
        for _ in 0..<(60 * 3) { w.update(dt: 1.0 / 60) }
        XCTAssertGreaterThan(w.player.chilledUntil, 0)
    }

    func testPopulatedLevelsContainElites() {
        var elites = 0
        for seed in UInt64(1)...10 { elites += GameWorld(seed: seed).monsters.filter { $0.rank != .normal }.count }
        XCTAssertGreaterThan(elites, 5)
    }
}
