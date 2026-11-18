import XCTest
@testable import AshenCore

final class ProgressionTests: XCTestCase {
    func testCurveIsIncreasing() {
        XCTAssertEqual(Experience.total(forLevel: 1), 0)
        XCTAssertEqual(Experience.total(forLevel: 2), 60)
        var prevGap = 0
        for l in 2...Experience.maxLevel {
            let gap = Experience.total(forLevel: l + 1) - Experience.total(forLevel: l)
            XCTAssertGreaterThan(gap, prevGap)
            prevGap = gap
        }
    }

    func testLevelDifferenceScaling() {
        let even = Experience.scaled(100, monsterLevel: 5, playerLevel: 5)
        XCTAssertEqual(even, Int(100 * Experience.monsterXPMultiplier))
        XCTAssertLessThan(Experience.scaled(100, monsterLevel: 1, playerLevel: 15), even / 10)
        XCTAssertGreaterThan(Experience.scaled(100, monsterLevel: 15, playerLevel: 5), even)
    }

    func testLevelUpGrantsPointsAndRefills() {
        var p = Player.newHero(at: .zero)
        p.stats.life = 1
        XCTAssertEqual(p.gainXP(Experience.total(forLevel: 3)), 2)
        XCTAssertEqual(p.level, 3)
        XCTAssertEqual(p.statPoints, 10)
        XCTAssertEqual(p.skillPoints, 2)
        XCTAssertEqual(p.stats.maxLife, 55 + 2 * HeroClass.emberguard.lifePerLevel)
        XCTAssertEqual(p.stats.life, p.stats.maxLife)
    }

    func testSpendingStatPoints() {
        var p = Player.newHero(at: .zero)
        p.gainXP(100)
        let life = p.stats.maxLife, dmg = p.stats.maxDamage
        p.spendStatPoint(.vitality)
        p.spendStatPoint(.strength)
        XCTAssertEqual(p.stats.maxLife, life + HeroClass.emberguard.lifePerVitality)
        XCTAssertGreaterThan(p.stats.maxDamage, dmg)
        XCTAssertEqual(p.statPoints, 3)
    }
}
