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
