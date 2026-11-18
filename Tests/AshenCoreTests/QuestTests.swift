import XCTest
@testable import AshenCore

final class QuestTests: XCTestCase {
    func testQuestTargetSpawnsInItsArea() {
        let w = GameWorld(seed: 1, startArea: "ashmire_fen")
        let target = w.monsters.first { $0.questID == "q_matron" }
        XCTAssertNotNil(target)
        XCTAssertEqual(target?.rank, .unique)
        XCTAssertEqual(target?.displayName, "泥沼之母")
    }

    func testFullQuestLoop() {
        let w = GameWorld(seed: 1)
        // Talk → active.
        let intro = w.talkQuests("elder")
        XCTAssertTrue(intro.first?.contains("泥沼之母") == true)
        XCTAssertEqual(w.player.quest("q_matron"), .active)
        // Kill the target.
        w.travel(to: "ashmire_fen", arrival: .entrance)
        let idx = w.monsters.firstIndex { $0.questID == "q_matron" }!
        w.apply(.hit(damage: 99_999, crit: false), toMonsterAt: idx)
        XCTAssertEqual(w.player.quest("q_matron"), .complete)
        // Turn in → reward.
        w.travel(to: "reedford", arrival: .exit)
        let points = w.player.skillPoints
        let lines = w.talkQuests("elder")
        XCTAssertTrue(lines.first?.contains("任务完成") == true)
        XCTAssertEqual(w.player.quest("q_matron"), .rewarded)
        XCTAssertEqual(w.player.skillPoints, points + 1)
        // Next talk opens the main quest.
        _ = w.talkQuests("elder")
        XCTAssertEqual(w.player.quest("q_abbess"), .active)
    }

    func testCompletedQuestTargetDoesNotRespawn() {
        let w = GameWorld(seed: 2)
        w.player.quests["q_matron"] = .rewarded
        w.travel(to: "ashmire_fen", arrival: .entrance)
        XCTAssertNil(w.monsters.first { $0.questID == "q_matron" })
    }

    func testRareItemReward() {
        let w = GameWorld(seed: 3)
        w.player.quests["q_bell"] = .complete
        _ = w.talkQuests("smith")
        XCTAssertEqual(w.player.inventory.items.first?.quality, .rare)
    }
}

final class BossTests: XCTestCase {
    func testBossSpawnsInSanctumOnlyWhileQuestOpen() {
        let w = GameWorld(seed: 1, startArea: "abbess_sanctum")
        let boss = w.monsters.first { $0.kind.behavior == .boss }
        XCTAssertNotNil(boss)
        XCTAssertGreaterThan(boss!.stats.maxLife, 500)
        let done = GameWorld(seed: 1)
        done.player.quests["q_abbess"] = .rewarded
        done.travel(to: "abbess_sanctum", arrival: .entrance)
        XCTAssertNil(done.monsters.first { $0.kind.behavior == .boss })
    }

    func testBossUsesAbilities() {
        let w = GameWorld(seed: 2, startArea: "abbess_sanctum")
        let i = w.monsters.firstIndex { $0.kind.behavior == .boss }!
        w.player.mover.position = w.monsters[i].position + Vec2(2, 0)
        w.player.stats.maxLife = 100_000; w.player.stats.life = 100_000
        var novas: Set<String> = []
        for _ in 0..<(60 * 14) {
            w.update(dt: 1.0 / 60)
            for e in w.drainEvents() { if case .nova(let id, _, _) = e { novas.insert(id) } }
        }
        XCTAssertTrue(novas.contains("boss_frost"))
        XCTAssertTrue(novas.contains("boss_summon"))
        XCTAssertGreaterThan(w.monsters.filter { $0.packID == 9_999 && $0.kind.behavior != .boss }.count, 0)
    }

    func testKillingBossCompletesActAndOpensExit() {
        let w = GameWorld(seed: 3, startArea: "abbess_sanctum")
        w.player.quests["q_abbess"] = .active
        let i = w.monsters.firstIndex { $0.kind.behavior == .boss }!
        w.apply(.hit(damage: 1e9, crit: false), toMonsterAt: i)
        XCTAssertEqual(w.player.quest("q_abbess"), .complete)
        XCTAssertTrue(w.interactables.contains { $0.kind == .areaExit(toArea: "reedford", arrival: .entrance) })
        XCTAssertGreaterThanOrEqual(w.groundItems.filter { if case .item = $0.content { true } else { false } }.count, 5)
    }
}
