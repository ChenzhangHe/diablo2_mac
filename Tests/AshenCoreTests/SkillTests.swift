import XCTest
@testable import AshenCore

final class SkillTests: XCTestCase {
    func testEveryTreeHasSixSkillsWithValidPrereqs() {
        for t in Skills.trees {
            let skills = Skills.inTree(t.id)
            XCTAssertEqual(skills.count, 6, t.name)
            for s in skills {
                for pre in s.prerequisites {
                    let p = Skills.def(pre)
                    XCTAssertNotNil(p)
                    XCTAssertEqual(p?.tree, s.tree)
                    XCTAssertLessThan(p!.tier, s.tier, "\(s.name) prereq must be a lower tier")
                }
                for (syn, _) in s.synergies { XCTAssertNotNil(Skills.def(syn)) }
            }
        }
    }

    func testLearningRules() {
        var p = Player.newHero(at: .zero)
        XCTAssertEqual(p.learnSkill("shield_bash"), .some(.noPoints))
        p.gainXP(Experience.total(forLevel: 6))    // level 6, 5 skill points
        XCTAssertEqual(p.learnSkill("ember_charge"), .some(.levelTooLow))
        XCTAssertEqual(p.learnSkill("iron_shout"), .some(.missingPrerequisite("rallying_roar")))
        XCTAssertNil(p.learnSkill("rallying_roar"))
        XCTAssertNil(p.learnSkill("iron_shout"))
        XCTAssertEqual(p.hotbar["rmb"], "rallying_roar")
        XCTAssertEqual(p.hotbar["q"], "iron_shout")
        XCTAssertEqual(p.skillPoints, 3)
    }

    func testPassivesChangeStats() {
        var p = Player.newHero(at: .zero)
        p.gainXP(Experience.total(forLevel: 4))
        let dmg = p.stats.maxDamage, ar = p.stats.attackRating
        p.learnSkill("weapon_mastery")
        XCTAssertGreaterThan(p.stats.maxDamage, dmg)
        XCTAssertGreaterThan(p.stats.attackRating, ar)
        var buckler = Item(id: 1, base: ItemBases.base("buckler")!)
        buckler.rolledDefense = 5
        p.equipment[.offhand] = buckler
        p.recalculate()
        let def = p.stats.defense, block = p.stats.blockChance
        p.learnSkill("bulwark")
        XCTAssertGreaterThan(p.stats.defense, def)
        XCTAssertGreaterThan(p.stats.blockChance, block)
    }

    func testSynergiesBoostNumbers() {
        var book = SkillBook()
        book.levels["flame_strike"] = 5
        let base = book.numbers("flame_strike").fireMax
        book.levels["cinder_nova"] = 5
        XCTAssertEqual(book.numbers("flame_strike").fireMax, base * 1.3, accuracy: 1e-9)
    }

    func testNumbersScaleWithLevel() {
        for s in Skills.all {
            let a = Skills.numbers(s.id, level: 1), b = Skills.numbers(s.id, level: 10)
            let sumA = a.damagePercent + a.fireMax + a.physMax + a.absorb + a.duration + a.radius + a.vulnerability
                + Double(a.modifiers.reduce(0) { $0 + $1.value })
            let sumB = b.damagePercent + b.fireMax + b.physMax + b.absorb + b.duration + b.radius + b.vulnerability
                + Double(b.modifiers.reduce(0) { $0 + $1.value })
            XCTAssertGreaterThan(sumB, sumA, s.name)
        }
    }
}

final class SkillCombatTests: XCTestCase {
    private func arena() -> GeneratedLevel {
        var map = TileMap(width: 20, height: 20, fill: .wall)
        for y in 1..<19 { for x in 1..<19 { map[x, y] = .floor } }
        return GeneratedLevel(map: map, rooms: [Room(x: 1, y: 1, w: 18, h: 18)], spawn: GridPoint(5, 5), exit: GridPoint(16, 16))
    }

    private func hero(level: Int, skills: [String: Int]) -> GameWorld {
        let w = GameWorld(level: arena())
        w.player.gainXP(Experience.total(forLevel: level))
        w.player.skills.levels = skills
        w.player.stats.mana = 500; w.player.stats.maxMana = 500
        return w
    }

    private func tick(_ w: GameWorld, seconds: Double) { for _ in 0..<Int(seconds * 60) { w.update(dt: 1.0 / 60) } }

    func testCastRequiresLearnedSkillAndMana() {
        let w = hero(level: 5, skills: [:])
        XCTAssertEqual(w.castSkill("rallying_roar", target: nil, point: .zero), .notLearned)
        w.player.skills.levels["rallying_roar"] = 1
        w.player.stats.mana = 0
        XCTAssertEqual(w.castSkill("rallying_roar", target: nil, point: .zero), .noMana)
    }

    func testBuffAppliesAndExpires() {
        let w = hero(level: 5, skills: ["rallying_roar": 1])
        let base = w.player.stats.maxDamage
        XCTAssertEqual(w.castSkill("rallying_roar", target: nil, point: .zero), .ok)
        XCTAssertGreaterThan(w.player.stats.maxDamage, base)
        tick(w, seconds: 40)
        XCTAssertEqual(w.player.stats.maxDamage, base, accuracy: 1e-9)
    }

    func testCinderNovaHitsEverythingInRadius() {
        let w = hero(level: 30, skills: ["cinder_nova": 10])
        let near = (0..<4).map { i in w.spawn(Bestiary.husk, at: w.player.position + Vec2(cos(Double(i)) * 1.5, sin(Double(i)) * 1.5)) }
        let far = w.spawn(Bestiary.husk, at: w.player.position + Vec2(9, 9))
        XCTAssertEqual(w.castSkill("cinder_nova", target: nil, point: .zero), .ok)
        for id in near { XCTAssertFalse(w.monster(id)!.isAlive) }
        XCTAssertTrue(w.monster(far)!.isAlive)
        XCTAssertEqual(w.castSkill("cinder_nova", target: nil, point: .zero), .cooldown)
    }

    func testQuakeCryStuns() {
        let w = hero(level: 20, skills: ["quake_cry": 1])
        var kind = Bestiary.husk
        kind = MonsterKind(id: kind.id, name: kind.name, level: 1, life: 500...500, damage: kind.damage, damageType: .physical,
                           attackRating: 1, defense: 0, resist: Resistances(), speed: 2, attacksPerSecond: 1, reach: 1,
                           aggroRadius: 8, behavior: .melee, packSize: 1...1, xp: 1, radius: 0.3, color: kind.color, isUndead: true)
        let id = w.spawn(kind, at: w.player.position + Vec2(1.5, 0))
        w.castSkill("quake_cry", target: nil, point: .zero)
        let m = w.monster(id)!
        XCTAssertLessThan(m.stats.life, 500)
        XCTAssertGreaterThan(m.stunnedUntil, w.time)
        let pos = m.position
        tick(w, seconds: 0.5)
        XCTAssertEqual(w.monster(id)!.position, pos)   // stunned monsters don't move
    }

    func testChargeClosesDistanceAndHits() {
        let w = hero(level: 12, skills: ["shield_bash": 1, "ember_charge": 5])
        w.player.stats.attackRating = 100_000
        let id = w.spawn(Bestiary.husk, at: w.player.position + Vec2(5, 0))
        XCTAssertEqual(w.castSkill("ember_charge", target: id, point: .zero), .ok)
        tick(w, seconds: 1.0)
        XCTAssertEqual(w.player.action, .none)
        XCTAssertLessThan(w.player.position.distance(to: w.monster(id)!.position), 2.5)
        XCTAssertLessThan(w.monster(id)!.stats.life, w.monster(id)!.stats.maxLife)
    }

    func testAshOathAmplifiesDamage() {
        let w = hero(level: 24, skills: ["ash_oath": 5])
        let id = w.spawn(Bestiary.husk, at: w.player.position + Vec2(1.5, 0))
        w.castSkill("ash_oath", target: nil, point: .zero)
        let idx = w.monsters.firstIndex { $0.id == id }!
        let before = w.monsters[idx].stats.life
        w.apply(.hit(damage: 4, crit: false), toMonsterAt: idx)
        XCTAssertEqual(before - w.monsters[idx].stats.life, 4 * 1.5, accuracy: 1e-9)
    }

    func testSunshieldAbsorbs() {
        let w = hero(level: 24, skills: ["sunshield": 1])
        w.castSkill("sunshield", target: nil, point: .zero)
        XCTAssertEqual(w.player.absorbPool, 60)
        let life = w.player.stats.life
        w.player.stats.lifeRegen = 0
        for _ in 0..<4 { w.spawn(Bestiary.husk, at: w.player.position + Vec2(1, 0)) }
        tick(w, seconds: 2)
        XCTAssertLessThan(w.player.absorbPool, 60)
        XCTAssertEqual(w.player.stats.life, life, accuracy: 0.001, "absorb should soak the first hits")
    }
}
