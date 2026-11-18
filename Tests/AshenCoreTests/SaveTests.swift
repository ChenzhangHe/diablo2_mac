import XCTest
@testable import AshenCore

final class SaveTests: XCTestCase {
    private func tempStore() -> SaveStore {
        SaveStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("ashen-test-\(UUID().uuidString)").appendingPathComponent("save.json"))
    }

    func testRoundTripRestoresHero() throws {
        let w = GameWorld(seed: 42)
        w.player.gainXP(Experience.total(forLevel: 8))
        w.player.spendStatPoint(.strength)
        _ = w.player.learnSkill("weapon_mastery")
        w.player.gold = 1234
        var rng = SeededRNG(seed: 5)
        let rare = ItemGenerator().generate(id: 90_000, itemLevel: 10, rng: &rng, forcedQuality: .rare)
        w.player.inventory.add(rare)
        w.player.stash.add(Item(id: 90_001, base: ItemBases.base("ring")!))
        w.player.quests["q_matron"] = .rewarded
        w.player.waypoints.insert("rotroot_hollow")

        let store = tempStore()
        try store.save(w.makeSave())
        let loaded = try XCTUnwrap(try store.load())
        XCTAssertEqual(loaded, w.makeSave().with(savedAt: loaded.savedAt))

        let w2 = GameWorld(save: loaded)
        XCTAssertTrue(w2.area.isTown)
        XCTAssertEqual(w2.player.level, 8)
        XCTAssertEqual(w2.player.gold, 1234)
        XCTAssertEqual(w2.player.attributes, w.player.attributes)
        XCTAssertEqual(w2.player.skills, w.player.skills)
        XCTAssertEqual(w2.player.inventory.items.first, rare)
        XCTAssertEqual(w2.player.stash.items.first?.id, 90_001)
        XCTAssertEqual(w2.player.equipment[.weapon]?.baseID, "short_blade")
        XCTAssertEqual(w2.player.quest("q_matron"), .rewarded)
        XCTAssertTrue(w2.player.waypoints.contains("rotroot_hollow"))
        XCTAssertEqual(w2.player.stats.maxDamage, w.player.stats.maxDamage, accuracy: 1e-9)
        // New items get fresh ids.
        XCTAssertTrue(w2.vendors["smith"]!.items.allSatisfy { $0.id > 90_001 })
        try store.delete()
        XCTAssertNil(try store.load())
    }

    func testMissingSaveLoadsNil() throws {
        XCTAssertNil(try tempStore().load())
    }
}

extension SaveGame {
    func with(savedAt d: Date) -> SaveGame { var c = self; c.savedAt = d; return c }
}
