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
