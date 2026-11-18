import XCTest
@testable import AshenCore

final class CombatTests: XCTestCase {
    func testHitChanceIsClamped() {
        XCTAssertEqual(Combat.hitChance(attackRating: 1, defense: 10_000, attackerLevel: 1, defenderLevel: 50), 0.05)
        XCTAssertEqual(Combat.hitChance(attackRating: 10_000, defense: 0, attackerLevel: 50, defenderLevel: 1), 0.95)
        // Equal AR/DEF and level → 50%
        XCTAssertEqual(Combat.hitChance(attackRating: 100, defense: 100, attackerLevel: 5, defenderLevel: 5), 0.5, accuracy: 1e-9)
    }

    func testResistanceIsCapped() {
        var d = CombatStats(level: 1, life: 10, minDamage: 1, maxDamage: 1, attackRating: 1, defense: 1)
        d.resist.fire = 200
        XCTAssertEqual(Combat.mitigate(100, type: .fire, defender: d), 25, accuracy: 1e-9)
        d.resist.cold = -50
        XCTAssertEqual(Combat.mitigate(100, type: .cold, defender: d), 150, accuracy: 1e-9)
        XCTAssertEqual(Combat.mitigate(100, type: .physical, defender: d), 100, accuracy: 1e-9)
    }

    /// Open arena with the player at one end.
    private func arena() -> GeneratedLevel {
        var map = TileMap(width: 20, height: 20, fill: .wall)
        for y in 1..<19 { for x in 1..<19 { map[x, y] = .floor } }
        let room = Room(x: 1, y: 1, w: 18, h: 18)
        return GeneratedLevel(map: map, rooms: [room], spawn: GridPoint(3, 3), exit: GridPoint(16, 16))
    }

    func testPlayerKillsMonster() {
        let w = GameWorld(level: arena())
        let id = w.spawn(Bestiary.murkling, at: Vec2(center: GridPoint(8, 8)))
        w.commandAttack(id)
        for _ in 0..<(60 * 30) where w.monster(id)?.isAlive == true { w.update(dt: 1.0 / 60) }
        XCTAssertEqual(w.monster(id)?.isAlive, false)
        XCTAssertEqual(w.player.xp, Experience.scaled(Bestiary.murkling.xp, monsterLevel: 1, playerLevel: 1))
        XCTAssertTrue(w.drainEvents().contains { if case .monsterDied = $0 { true } else { false } })
    }

    func testMonsterAggroesAndHurtsPlayer() {
        let w = GameWorld(level: arena())
        w.player.stats.lifeRegen = 0
        w.spawn(Bestiary.husk, at: Vec2(center: GridPoint(7, 7)))
        let before = w.player.stats.life
        for _ in 0..<(60 * 20) { w.update(dt: 1.0 / 60) }
        XCTAssertLessThan(w.player.stats.life, before)
    }

    func testArcherShootsProjectiles() {
        let w = GameWorld(level: arena())
        w.spawn(Bestiary.hollowArcher, at: Vec2(center: GridPoint(8, 3)))
        var sawProjectile = false
        for _ in 0..<(60 * 5) { w.update(dt: 1.0 / 60); if !w.projectiles.isEmpty { sawProjectile = true } }
        XCTAssertTrue(sawProjectile)
    }

    func testPlayerDiesAndRespawns() {
        let w = GameWorld(level: arena())
        w.player.stats.life = 1
        w.player.stats.lifeRegen = 0
        for _ in 0..<6 { w.spawn(Bestiary.husk, at: Vec2(center: GridPoint(4, 4))) }
        var died = false, respawned = false
        for _ in 0..<(60 * 20) {
            w.update(dt: 1.0 / 60)
            for e in w.drainEvents() {
                if e == .playerDied { died = true }
                if e == .playerRespawned { respawned = true }
            }
            if respawned { break }
        }
        XCTAssertTrue(died)
        XCTAssertTrue(respawned)
        XCTAssertEqual(w.player.stats.life, w.player.stats.maxLife)
    }

    func testHealthPotionHealsOverTime() {
        let w = GameWorld(level: arena())
        w.player.stats.lifeRegen = 0
        w.player.stats.life = 10
        w.drinkHealthPotion()
        XCTAssertEqual(w.player.healthPotions, 5)
        for _ in 0..<(60 * 3) { w.update(dt: 1.0 / 60) }
        XCTAssertEqual(w.player.stats.life, 10 + 55 * 0.45, accuracy: 0.5)
    }

    func testPopulatedWorldHasMonsters() {
        let w = GameWorld(seed: 1, startArea: "rotroot_hollow")
        XCTAssertGreaterThan(w.monsters.count, 10)
        XCTAssertTrue(w.monsters.allSatisfy { w.level.map.isWalkable($0.position.grid) })
    }
}
