import XCTest
@testable import AshenCore

final class ItemTests: XCTestCase {
    func testGeneratorIsDeterministic() {
        var a = SeededRNG(seed: 9), b = SeededRNG(seed: 9)
        for i in 0..<50 {
            XCTAssertEqual(ItemGenerator().generate(id: i, itemLevel: 15, rng: &a),
                           ItemGenerator().generate(id: i, itemLevel: 15, rng: &b))
        }
    }

    func testAffixRulesHold() {
        var rng = SeededRNG(seed: 1)
        for i in 0..<2000 {
            let ilvl = rng.int(1...30)
            let it = ItemGenerator().generate(id: i, itemLevel: ilvl, rng: &rng)
            let affixes = (it.prefixNames + it.suffixNames).map { n in Affixes.all.first { $0.name == n }! }
            XCTAssertLessThanOrEqual(it.base.qlvl, ilvl)
            XCTAssertTrue(affixes.allSatisfy { $0.level <= ilvl && $0.categories.contains(it.base.category) })
            XCTAssertEqual(Set(affixes.map(\.group)).count, affixes.count, "duplicate affix group on \(it.displayName)")
            switch it.quality {
            case .magic:
                XCTAssertLessThanOrEqual(it.prefixNames.count, 1); XCTAssertLessThanOrEqual(it.suffixNames.count, 1)
                XCTAssertGreaterThanOrEqual(affixes.count, 1)
            case .rare:
                XCTAssertLessThanOrEqual(it.prefixNames.count, 3); XCTAssertLessThanOrEqual(it.suffixNames.count, 3)
                XCTAssertNotNil(it.rareName)
            default:
                XCTAssertTrue(affixes.isEmpty)
            }
            if it.base.category.isJewelry { XCTAssertGreaterThanOrEqual(it.quality, .magic) }
        }
    }

    func testQualityDistributionIsSane() {
        var rng = SeededRNG(seed: 2)
        var counts: [ItemQuality: Int] = [:]
        for i in 0..<5000 { counts[ItemGenerator().generate(id: i, itemLevel: 10, rng: &rng).quality, default: 0] += 1 }
        XCTAssertGreaterThan(counts[.normal, default: 0], counts[.magic, default: 0])
        XCTAssertGreaterThan(counts[.magic, default: 0], counts[.rare, default: 0])
        XCTAssertGreaterThan(counts[.rare, default: 0], 100)
    }

    func testInventoryFitAndSwap() {
        var inv = Inventory(width: 4, height: 3)
        let sword = Item(id: 1, base: ItemBases.base("short_blade")!)   // 1x3
        let armor = Item(id: 2, base: ItemBases.base("tunic")!)         // 2x3
        let ring = Item(id: 3, base: ItemBases.base("ring")!)           // 1x1
        XCTAssertTrue(inv.add(sword))
        XCTAssertTrue(inv.add(armor))
        XCTAssertTrue(inv.add(ring))
        XCTAssertEqual(inv.entry(at: 0, 2)?.item.id, 1)
        XCTAssertEqual(inv.entry(at: 2, 1)?.item.id, 2)
        XCTAssertFalse(inv.add(Item(id: 4, base: ItemBases.base("tunic")!)))
        // Swap ring with a new ring.
        let r = inv.placeSwapping(Item(id: 5, base: ItemBases.base("ring")!), x: 3, y: 0)
        XCTAssertTrue(r.ok)
        XCTAssertEqual(r.displaced?.id, 3)
        // Can't swap over two items at once.
        XCTAssertFalse(inv.placeSwapping(Item(id: 6, base: ItemBases.base("tunic")!), x: 0, y: 0).ok)
    }

    func testEquippingChangesStats() {
        var p = Player.newHero(at: .zero)
        let before = p.stats.maxDamage
        var axe = Item(id: 1, base: ItemBases.base("short_blade")!, quality: .magic, itemLevel: 20)
        axe.modifiers = [Modifier(.enhancedDamage, 50), Modifier(.life, 20), Modifier(.fireResist, 30), Modifier(.fireMax, 6), Modifier(.fireMin, 2)]
        p.equipment[.weapon] = axe
        p.recalculate()
        XCTAssertGreaterThan(p.stats.maxDamage, before)
        XCTAssertEqual(p.stats.maxLife, 55 + 20)
        XCTAssertEqual(p.stats.resist.fire, 30)
        XCTAssertEqual(p.stats.elemental.first?.type, .fire)
    }

    func testRequirementsBlockEquip() {
        let p = Player.newHero(at: .zero)
        let maul = Item(id: 1, base: ItemBases.base("maul")!)
        XCTAssertFalse(p.canEquip(maul))
        XCTAssertTrue(p.canEquip(Item(id: 2, base: ItemBases.base("short_blade")!)))
    }

    func testMonstersDropLootAndPlayerPicksUp() {
        let w = GameWorld(seed: 3)
        var rng = SeededRNG(seed: 4)
        var id = 10_000
        let item = ItemGenerator().generate(id: 1, itemLevel: 5, rng: &rng, forcedQuality: .magic,
                                            base: ItemBases.base("hood")!)
        w.dropLoot([.item(item), .gold(50)], at: w.player.position + Vec2(0.2, 0.2))
        _ = id; id += 1
        let itemGround = w.groundItems.first { if case .item = $0.content { true } else { false } }!
        w.commandPickUp(itemGround.id)
        for _ in 0..<60 { w.update(dt: 1.0 / 60) }
        XCTAssertEqual(w.player.gold, 50)
        XCTAssertTrue(w.player.inventory.items.contains { $0.id == item.id })
        XCTAssertTrue(w.groundItems.isEmpty)
    }

    func testQuickEquipSwapsIntoInventory() {
        let w = GameWorld(seed: 3)
        var better = Item(id: 999, base: ItemBases.base("short_blade")!, quality: .magic, itemLevel: 5)
        better.modifiers = [Modifier(.enhancedDamage, 40)]
        better.prefixNames = ["锋利的"]
        w.player.inventory.add(better)
        let oldDamage = w.player.stats.maxDamage
        w.inventoryUse(itemID: 999)
        XCTAssertEqual(w.player.equipment[.weapon]?.id, 999)
        XCTAssertEqual(w.player.inventory.items.count, 1)   // old blade went back to the bag
        XCTAssertGreaterThan(w.player.stats.maxDamage, oldDamage)
    }

    func testBlockAndElementalCombat() {
        var a = CombatStats(level: 10, life: 100, minDamage: 10, maxDamage: 10, attackRating: 10_000, defense: 0)
        a.critChance = 0
        a.elemental = [ElementalDamage(.fire, 10, 10)]
        var d = CombatStats(level: 1, life: 100, minDamage: 1, maxDamage: 1, attackRating: 1, defense: 0)
        d.resist.fire = 50
        var rng = SeededRNG(seed: 1)
        var hits: [Double] = []
        for _ in 0..<100 { if case .hit(let dmg, _) = Combat.resolveAttack(attacker: a, defender: d, rng: &rng) { hits.append(dmg) } }
        XCTAssertTrue(hits.allSatisfy { abs($0 - 15) < 1e-9 })
        d.blockChance = 100
        var blocks = 0
        for _ in 0..<100 { if Combat.resolveAttack(attacker: a, defender: d, rng: &rng) == .blocked { blocks += 1 } }
        XCTAssertGreaterThan(blocks, 60)   // capped at 75%
    }
}
