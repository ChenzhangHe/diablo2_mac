import XCTest
@testable import AshenCore

final class TownTests: XCTestCase {
    func testPricesScaleWithQuality() {
        var rng = SeededRNG(seed: 1)
        let base = ItemBases.base("broadsword")!
        let n = ItemGenerator().generate(id: 1, itemLevel: 10, rng: &rng, forcedQuality: .normal, base: base)
        let m = ItemGenerator().generate(id: 2, itemLevel: 10, rng: &rng, forcedQuality: .magic, base: base)
        let r = ItemGenerator().generate(id: 3, itemLevel: 10, rng: &rng, forcedQuality: .rare, base: base)
        XCTAssertLessThan(n.price, m.price)
        XCTAssertLessThan(m.price, r.price)
        XCTAssertLessThan(r.sellPrice, r.price)
    }

    func testVendorsStockedInTown() {
        let w = GameWorld(seed: 1)
        XCTAssertGreaterThan(w.vendors["smith"]?.items.count ?? 0, 5)
        XCTAssertTrue(w.vendors["healer"]!.items.contains { $0.baseID == ItemBases.portalScroll.id })
    }

    func testBuyAndSell() {
        let w = GameWorld(seed: 1)
        let item = w.vendors["smith"]!.items.first { !$0.isPotion }!
        w.buy(from: "smith", itemID: item.id)
        XCTAssertTrue(w.drainEvents().contains(.notEnoughGold))
        w.player.gold = 100_000
        w.buy(from: "smith", itemID: item.id)
        XCTAssertEqual(w.player.gold, 100_000 - item.price)
        XCTAssertTrue(w.player.inventory.items.contains { $0.id == item.id })
        XCTAssertFalse(w.vendors["smith"]!.items.contains { $0.id == item.id })
        w.sell(itemID: item.id, to: "smith")
        XCTAssertEqual(w.player.gold, 100_000 - item.price + item.sellPrice)
        XCTAssertTrue(w.player.inventory.items.isEmpty)
        // Potions are infinite and go to the belt.
        let potion = w.vendors["healer"]!.items.first { $0.baseID == ItemBases.healthPotion.id }!
        let before = w.player.healthPotions, stock = w.vendors["healer"]!.items.count
        w.buy(from: "healer", itemID: potion.id)
        XCTAssertEqual(w.player.healthPotions, before + 1)
        XCTAssertEqual(w.vendors["healer"]!.items.count, stock)
    }

    func testTownPortalRoundTrip() {
        let w = GameWorld(seed: 2, startArea: "rotroot_hollow")
        XCTAssertFalse(GameWorld(seed: 2).castTownPortal(), "no portals from town")
        let spot = w.player.position
        XCTAssertTrue(w.castTownPortal())
        XCTAssertEqual(w.player.portalScrolls, 2)
        let field = w.interactables.first { if case .townPortal = $0.kind { true } else { false } }!
        w.commandInteract(field.id)
        for _ in 0..<120 where !w.area.isTown { w.update(dt: 1.0 / 60) }
        XCTAssertTrue(w.area.isTown)
        let townGate = w.interactables.first { if case .townPortal = $0.kind { true } else { false } }!
        w.commandInteract(townGate.id)
        for _ in 0..<(60 * 10) where w.area.isTown { w.update(dt: 1.0 / 60) }
        XCTAssertEqual(w.area.id, "rotroot_hollow")
        XCTAssertLessThan(w.player.position.distance(to: spot), 0.01)
        XCTAssertFalse(w.interactables.contains { if case .townPortal = $0.kind { true } else { false } })
        XCTAssertNil(w.player.openPortal)
    }

    func testStashMovesItems() {
        let w = GameWorld(seed: 1)
        let ring = Item(id: 777, base: ItemBases.base("ring")!)
        w.player.inventory.add(ring)
        w.moveToStash(itemID: 777)
        XCTAssertTrue(w.player.inventory.items.isEmpty)
        XCTAssertEqual(w.player.stash.items.first?.id, 777)
        w.moveFromStash(itemID: 777)
        XCTAssertEqual(w.player.inventory.items.first?.id, 777)
    }
}
