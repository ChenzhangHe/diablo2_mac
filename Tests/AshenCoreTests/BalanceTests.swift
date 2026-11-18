import XCTest
@testable import AshenCore

/// Headless bot that clears areas, to sanity-check difficulty and progression pace.
final class BalanceTests: XCTestCase {
    struct Result { var kills = 0; var deaths = 0; var seconds = 0.0; var level = 1; var potionsUsed = 0 }

    @discardableResult
    func clear(_ w: GameWorld, maxSeconds: Double = 900) -> Result {
        var r = Result()
        let dt = 1.0 / 30
        var t = 0.0
        while t < maxSeconds {
            t += dt
            if w.player.statPoints > 0 { w.player.spendStatPoint(w.player.statPoints % 2 == 0 ? .vitality : .strength) }
            if w.player.skillPoints > 0 {
                for id in ["weapon_mastery", "flame_strike", "bulwark", "rallying_roar"] where w.player.learnSkill(id) == nil { break }
            }
            if w.playerAlive && w.player.stats.lifeFraction < 0.4 && w.player.healPool <= 0 && w.player.healthPotions > 0 {
                w.drinkHealthPotion(); r.potionsUsed += 1
            }
            if w.playerAlive && w.player.target == nil && w.player.action == .none {
                let alive = w.monsters.filter(\.isAlive)
                if alive.isEmpty { break }
                let near = alive.min { $0.position.distance(to: w.player.position) < $1.position.distance(to: w.player.position) }!
                w.commandAttack(near.id, skill: w.player.skills.level("flame_strike") > 0 ? "flame_strike" : nil)
            }
            // Pick up potions/gold lying around.
            w.update(dt: dt)
            for e in w.drainEvents() {
                if case .monsterDied = e { r.kills += 1 }
                if e == .playerDied { r.deaths += 1 }
            }
        }
        r.seconds = t
        r.level = w.player.level
        return r
    }

    func testFirstAreaIsBeatableByAFreshHero() {
        let w = GameWorld(seed: 7, startArea: "ashmire_fen")
        let r = clear(w)
        print("BALANCE fen: kills=\(r.kills) deaths=\(r.deaths) level=\(r.level) time=\(Int(r.seconds))s potions=\(r.potionsUsed) left=\(w.monsters.filter(\.isAlive).count)")
        XCTAssertLessThanOrEqual(r.deaths, 3, "first area too hard")
        XCTAssertGreaterThanOrEqual(r.level, 3, "first area should give a few levels")
    }

    /// Slow (~20 s). Run with ASHEN_BALANCE=1 swift test --filter BalanceTests
    func testProgressThroughAct() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ASHEN_BALANCE"] != nil, "set ASHEN_BALANCE=1")
        let w = GameWorld(seed: 11, startArea: "ashmire_fen")
        var report: [String] = []
        for area in ["ashmire_fen", "rotroot_hollow", "seeping_caves", "abbey_grounds", "abbey_crypt"] {
            if w.area.id != area { w.travel(to: area, arrival: .entrance) }
            w.player.healthPotions = max(w.player.healthPotions, 8)
            let r = clear(w, maxSeconds: 1200)
            report.append("\(area): kills=\(r.kills) deaths=\(r.deaths) lvl=\(r.level) t=\(Int(r.seconds))s")
        }
        w.travel(to: "abbess_sanctum", arrival: .entrance)
        w.player.healthPotions = 12
        let boss = clear(w, maxSeconds: 600)
        report.append("boss: deaths=\(boss.deaths) lvl=\(boss.level) t=\(Int(boss.seconds))s won=\(w.player.quest("q_abbess") == .complete)")
        print("BALANCE act:\n  " + report.joined(separator: "\n  "))
    }
}
