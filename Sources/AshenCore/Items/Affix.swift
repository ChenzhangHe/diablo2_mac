/// A single stat effect. Items, skills and buffs all speak in modifiers.
public enum Stat: String, Codable, Sendable, CaseIterable {
    case strength, dexterity, vitality, energy
    case life, mana
    case enhancedDamage          // % to weapon damage
    case minDamage, maxDamage    // flat physical
    case fireMin, fireMax, coldMin, coldMax, lightningMin, lightningMax, poisonMin, poisonMax
    case attackRating
    case enhancedDefense         // % to item defense
    case defense                 // flat
    case fireResist, coldResist, lightningResist, poisonResist, allResist
    case attackSpeed             // %
    case lifeSteal               // %
    case lifeRegen               // per second
    case manaRegen               // per second
    case moveSpeed               // %
    case thorns                  // flat damage to melee attackers
    case goldFind                // %
    case critChance              // %
    case damageReduction         // %
}

public struct Modifier: Codable, Sendable, Equatable {
    public var stat: Stat
    public var value: Int
    public init(_ stat: Stat, _ value: Int) { self.stat = stat; self.value = value }

    /// Human-readable line, e.g. "+15 生命".
    public var text: String {
        switch stat {
        case .strength: "+\(value) 力量"
        case .dexterity: "+\(value) 敏捷"
        case .vitality: "+\(value) 体魄"
        case .energy: "+\(value) 灵力"
        case .life: "+\(value) 生命"
        case .mana: "+\(value) 法力"
        case .enhancedDamage: "+\(value)% 伤害强化"
        case .minDamage: "+\(value) 最小伤害"
        case .maxDamage: "+\(value) 最大伤害"
        case .fireMin, .fireMax, .coldMin, .coldMax, .lightningMin, .lightningMax, .poisonMin, .poisonMax: ""
        case .attackRating: "+\(value) 命中值"
        case .enhancedDefense: "+\(value)% 防御强化"
        case .defense: "+\(value) 防御"
        case .fireResist: "火焰抗性 +\(value)%"
        case .coldResist: "冰霜抗性 +\(value)%"
        case .lightningResist: "闪电抗性 +\(value)%"
        case .poisonResist: "毒素抗性 +\(value)%"
        case .allResist: "所有抗性 +\(value)%"
        case .attackSpeed: "+\(value)% 攻击速度"
        case .lifeSteal: "\(value)% 生命窃取"
        case .lifeRegen: "生命恢复 +\(value)/秒"
        case .manaRegen: "法力恢复 +\(value)/秒"
        case .moveSpeed: "+\(value)% 移动速度"
        case .thorns: "攻击者受到 \(value) 点反伤"
        case .goldFind: "+\(value)% 额外金币"
        case .critChance: "+\(value)% 暴击几率"
        case .damageReduction: "物理伤害减免 \(value)%"
        }
    }
}

/// One roll range of an affix: stat + min...max.
public struct AffixRoll: Codable, Sendable {
    public var stat: Stat
    public var range: ClosedRange<Int>
    public init(_ stat: Stat, _ range: ClosedRange<Int>) { self.stat = stat; self.range = range }
}

/// Prefix or suffix with tiers gated by item level (classic magic-affix model).
public struct Affix: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String           // prefix: "锋利的", suffix: "之活力"
    public let isPrefix: Bool
    public let level: Int             // minimum item level
    public let group: String          // only one affix per group on an item
    public let categories: Set<ItemCategory>
    public let rolls: [AffixRoll]
    public var weight = 100
}

public enum Affixes {
    static let weapons: Set<ItemCategory> = [.weapon]
    static let armorAll: Set<ItemCategory> = [.armor, .helm, .shield, .gloves, .boots, .belt]
    static let jewelry: Set<ItemCategory> = [.ring, .amulet]
    static let anything: Set<ItemCategory> = armorAll.union(jewelry).union(weapons)

    static func p(_ id: String, _ name: String, _ lvl: Int, _ group: String, _ cats: Set<ItemCategory>,
                  _ rolls: [AffixRoll], weight: Int = 100) -> Affix {
        Affix(id: id, name: name, isPrefix: true, level: lvl, group: group, categories: cats, rolls: rolls, weight: weight)
    }

    static func s(_ id: String, _ name: String, _ lvl: Int, _ group: String, _ cats: Set<ItemCategory>,
                  _ rolls: [AffixRoll], weight: Int = 100) -> Affix {
        Affix(id: id, name: name, isPrefix: false, level: lvl, group: group, categories: cats, rolls: rolls, weight: weight)
    }

    public static let all: [Affix] = [
        // ---- Prefixes ----
        p("keen1", "锋利的", 1, "ed", weapons, [.init(.enhancedDamage, 10...20)]),
        p("keen2", "残忍的", 9, "ed", weapons, [.init(.enhancedDamage, 21...40)]),
        p("keen3", "屠戮的", 18, "ed", weapons, [.init(.enhancedDamage, 41...65)]),
        p("precise1", "精准的", 1, "ar", weapons.union([.gloves, .ring, .amulet]), [.init(.attackRating, 10...20)]),
        p("precise2", "鹰眼的", 8, "ar", weapons.union([.gloves, .ring, .amulet]), [.init(.attackRating, 21...50)]),
        p("precise3", "必中的", 17, "ar", weapons.union([.gloves, .ring, .amulet]), [.init(.attackRating, 51...100)]),
        p("honed1", "淬炼的", 1, "ed_ar", weapons, [.init(.enhancedDamage, 10...20), .init(.attackRating, 10...20)], weight: 60),
        p("sturdy1", "坚固的", 1, "edef", armorAll, [.init(.enhancedDefense, 10...25)]),
        p("sturdy2", "加固的", 9, "edef", armorAll, [.init(.enhancedDefense, 26...50)]),
        p("sturdy3", "坚不可摧的", 18, "edef", armorAll, [.init(.enhancedDefense, 51...80)]),
        p("plated1", "镶板的", 1, "def", armorAll, [.init(.defense, 3...8)]),
        p("plated2", "铁壁的", 10, "def", armorAll, [.init(.defense, 9...20)]),
        p("searing1", "灼热的", 2, "fire", weapons.union([.ring, .gloves]), [.init(.fireMin, 1...2), .init(.fireMax, 3...6)]),
        p("searing2", "熔火的", 12, "fire", weapons.union([.ring, .gloves]), [.init(.fireMin, 3...6), .init(.fireMax, 8...16)]),
        p("frigid1", "冰冷的", 3, "cold", weapons.union([.ring, .gloves]), [.init(.coldMin, 1...2), .init(.coldMax, 2...5)]),
        p("frigid2", "冻骨的", 13, "cold", weapons.union([.ring, .gloves]), [.init(.coldMin, 3...5), .init(.coldMax, 7...14)]),
        p("storm1", "雷鸣的", 4, "lightning", weapons.union([.ring, .gloves]), [.init(.lightningMin, 1...1), .init(.lightningMax, 5...10)]),
        p("storm2", "雷暴的", 14, "lightning", weapons.union([.ring, .gloves]), [.init(.lightningMin, 1...2), .init(.lightningMax, 15...28)]),
        p("venom1", "淬毒的", 3, "poison", weapons, [.init(.poisonMin, 2...4), .init(.poisonMax, 4...8)]),
        p("lucid1", "澄澈的", 1, "mana", armorAll.union(jewelry), [.init(.mana, 5...10)]),
        p("lucid2", "深邃的", 10, "mana", armorAll.union(jewelry), [.init(.mana, 11...25)]),
        p("ember1", "余烬护佑的", 1, "fres", armorAll.union(jewelry), [.init(.fireResist, 5...12)]),
        p("ember2", "炎魔护佑的", 12, "fres", armorAll.union(jewelry), [.init(.fireResist, 13...25)]),
        p("frost1", "霜护的", 1, "cres", armorAll.union(jewelry), [.init(.coldResist, 5...12)]),
        p("frost2", "冰川护佑的", 12, "cres", armorAll.union(jewelry), [.init(.coldResist, 13...25)]),
        p("ground1", "接地的", 1, "lres", armorAll.union(jewelry), [.init(.lightningResist, 5...12)]),
        p("ground2", "避雷的", 12, "lres", armorAll.union(jewelry), [.init(.lightningResist, 13...25)]),
        p("antidote1", "解毒的", 1, "pres", armorAll.union(jewelry), [.init(.poisonResist, 5...12)]),
        p("antidote2", "百毒不侵的", 12, "pres", armorAll.union(jewelry), [.init(.poisonResist, 13...25)]),
        p("prism1", "棱彩的", 12, "allres", [.shield, .amulet, .ring], [.init(.allResist, 4...8)], weight: 40),
        p("prism2", "虹光的", 20, "allres", [.shield, .amulet], [.init(.allResist, 9...15)], weight: 30),

        // ---- Suffixes ----
        s("vigor1", "之活力", 1, "life", armorAll.union(jewelry), [.init(.life, 3...10)]),
        s("vigor2", "之生机", 8, "life", armorAll.union(jewelry), [.init(.life, 11...25)]),
        s("vigor3", "之不朽", 18, "life", [.armor, .shield, .amulet, .belt], [.init(.life, 26...45)]),
        s("might1", "之蛮力", 1, "str", anything, [.init(.strength, 1...4)]),
        s("might2", "之巨力", 10, "str", anything, [.init(.strength, 5...9)]),
        s("grace1", "之灵巧", 1, "dex", anything, [.init(.dexterity, 1...4)]),
        s("grace2", "之疾风", 10, "dex", anything, [.init(.dexterity, 5...9)]),
        s("stam1", "之坚韧", 1, "vit", anything, [.init(.vitality, 1...4)]),
        s("stam2", "之磐石", 10, "vit", anything, [.init(.vitality, 5...9)]),
        s("mind1", "之心智", 1, "eng", anything, [.init(.energy, 1...4)]),
        s("mind2", "之睿智", 10, "eng", anything, [.init(.energy, 5...9)]),
        s("haste1", "之迅捷", 3, "ias", weapons.union([.gloves]), [.init(.attackSpeed, 8...12)]),
        s("haste2", "之狂风", 14, "ias", weapons.union([.gloves]), [.init(.attackSpeed, 15...25)]),
        s("leech1", "之汲取", 5, "ls", weapons.union([.ring, .gloves]), [.init(.lifeSteal, 2...4)]),
        s("leech2", "之吸血", 15, "ls", weapons.union([.ring]), [.init(.lifeSteal, 5...8)]),
        s("mend1", "之再生", 1, "regen", [.armor, .helm, .ring, .amulet, .belt], [.init(.lifeRegen, 1...2)]),
        s("mend2", "之复苏", 12, "regen", [.armor, .helm, .ring, .amulet, .belt], [.init(.lifeRegen, 3...5)]),
        s("clarity1", "之清明", 1, "mregen", [.helm, .ring, .amulet], [.init(.manaRegen, 1...2)]),
        s("swift1", "之疾行", 1, "frw", [.boots], [.init(.moveSpeed, 10...10)]),
        s("swift2", "之奔袭", 10, "frw", [.boots], [.init(.moveSpeed, 20...20)]),
        s("swift3", "之流星", 20, "frw", [.boots], [.init(.moveSpeed, 30...30)]),
        s("thorns1", "之荆棘", 1, "thorns", [.armor, .shield], [.init(.thorns, 1...3)]),
        s("thorns2", "之铁蒺藜", 10, "thorns", [.armor, .shield], [.init(.thorns, 4...10)]),
        s("fortune1", "之财富", 1, "gf", [.gloves, .boots, .ring, .amulet, .helm], [.init(.goldFind, 10...40)]),
        s("hawk1", "之锐目", 6, "crit", weapons.union([.gloves, .amulet]), [.init(.critChance, 2...5)]),
        s("warding1", "之守护", 8, "dr", [.armor, .shield, .belt], [.init(.damageReduction, 3...6)]),
        s("bonus_dmg1", "之锋刃", 1, "maxdmg", weapons.union([.ring, .gloves]), [.init(.maxDamage, 1...3)]),
        s("bonus_dmg2", "之裂骨", 10, "maxdmg", weapons.union([.ring, .gloves]), [.init(.maxDamage, 4...8)]),
    ]
}
