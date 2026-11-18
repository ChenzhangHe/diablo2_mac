public struct Attributes: Codable, Sendable, Equatable {
    public var strength: Int
    public var dexterity: Int
    public var vitality: Int
    public var energy: Int
    public init(strength: Int, dexterity: Int, vitality: Int, energy: Int) {
        self.strength = strength; self.dexterity = dexterity; self.vitality = vitality; self.energy = energy
    }
}

/// Per-class growth constants (classic ARPG style: attributes + per-level gains).
public struct HeroClass: Sendable {
    public let id: String
    public let name: String
    public let start: Attributes
    public let baseLife: Double
    public let lifePerLevel: Double
    public let lifePerVitality: Double
    public let baseMana: Double
    public let manaPerLevel: Double
    public let manaPerEnergy: Double

    public static let emberguard = HeroClass(
        id: "emberguard", name: "烬卫", start: Attributes(strength: 30, dexterity: 20, vitality: 25, energy: 10),
        baseLife: -20, lifePerLevel: 3, lifePerVitality: 3, baseMana: 5, manaPerLevel: 1, manaPerEnergy: 1)
}

public enum StatCalculator {
    /// Sum of all modifiers on equipped items whose requirements are met.
    public static func gearModifiers(_ equipment: [EquipSlot: Item]) -> [Stat: Int] {
        var out: [Stat: Int] = [:]
        for item in equipment.values { for m in item.modifiers { out[m.stat, default: 0] += m.value } }
        return out
    }

    /// Rebuild combat stats from class, level, attributes and gear. Keeps current life/mana (clamped).
    public static func compute(heroClass c: HeroClass, level: Int, attributes base: Attributes,
                               equipment: [EquipSlot: Item], extra: [Modifier] = [],
                               current: CombatStats?) -> (stats: CombatStats, moveSpeed: Double, goldFind: Double) {
        var g = gearModifiers(equipment)
        for m in extra { g[m.stat, default: 0] += m.value }
        func v(_ s: Stat) -> Int { g[s] ?? 0 }
        let str = base.strength + v(.strength)
        let dex = base.dexterity + v(.dexterity)
        let vit = base.vitality + v(.vitality)
        let eng = base.energy + v(.energy)

        let weapon = equipment[.weapon]
        let wd = weapon?.weaponDamage ?? 1...3
        // Item ED is baked into weaponDamage; skill ED stacks additively with strength.
        let skillEDValue = extra.filter { $0.stat == .enhancedDamage }.reduce(0) { $0 + $1.value }
        let strBonus = 1 + Double(str + skillEDValue) / 100
        let minD = Double(wd.lowerBound) * strBonus
        let maxD = Double(wd.upperBound) * strBonus

        let maxLife = (c.baseLife + Double(level - 1) * c.lifePerLevel + Double(vit) * c.lifePerVitality + Double(v(.life)))
            * (1 + Double(v(.lifePercent)) / 100)
        let maxMana = (c.baseMana + Double(level - 1) * c.manaPerLevel + Double(eng) * c.manaPerEnergy + Double(v(.mana)))
            * (1 + Double(v(.manaPercent)) / 100)
        // Skill/buff enhanced defense applies to total armor (gear ED is already inside item.defense).
        let skillED = extra.filter { $0.stat == .enhancedDefense }.reduce(0) { $0 + $1.value }
        let gearArmor = equipment.values.reduce(0) { $0 + $1.defense }
        let armor = gearArmor * (100 + skillED) / 100 + extra.filter { $0.stat == .defense }.reduce(0) { $0 + $1.value }

        var s = CombatStats(level: level, life: maxLife, minDamage: minD, maxDamage: maxD,
                            attackRating: Double(dex * 5 + level * 5 + v(.attackRating)),
                            defense: Double(armor + dex / 4))
        s.maxMana = maxMana
        s.mana = maxMana
        if let cur = current {
            s.life = min(maxLife, cur.life)
            s.mana = min(maxMana, cur.mana)
        }
        let aps = weapon?.base.attacksPerSecond ?? 1.6
        s.attacksPerSecond = aps * (1 + Double(v(.attackSpeed)) / 100)
        s.critChance = 0.05 + Double(v(.critChance)) / 100
        s.lifeRegen = 0.4 + Double(v(.lifeRegen))
        s.manaRegen = 0.3 + Double(eng) * 0.02 + Double(v(.manaRegen))
        s.damageReduction = Double(v(.damageReduction))
        s.lifeSteal = Double(v(.lifeSteal))
        s.thorns = Double(v(.thorns))
        let shield = equipment[.offhand]?.base.category == .shield
        s.blockChance = shield ? Double(equipment[.offhand]!.base.block) + Double(dex) / 10 + Double(v(.blockChance)) : 0
        let all = v(.allResist)
        s.resist = Resistances(fire: v(.fireResist) + all, cold: v(.coldResist) + all,
                               lightning: v(.lightningResist) + all, poison: v(.poisonResist) + all)
        let elems: [(DamageType, Stat, Stat)] = [(.fire, .fireMin, .fireMax), (.cold, .coldMin, .coldMax),
                                                 (.lightning, .lightningMin, .lightningMax), (.poison, .poisonMin, .poisonMax)]
        for (t, lo, hi) in elems where v(hi) > 0 { s.elemental.append(ElementalDamage(t, Double(v(lo)), Double(v(hi)))) }

        let move = 4.5 * (1 + Double(v(.moveSpeed)) / 100)
        return (s, move, Double(v(.goldFind)))
    }

    public static func meetsRequirements(_ item: Item, attributes a: Attributes, equipment: [EquipSlot: Item], level: Int) -> Bool {
        // Gear bonuses count toward requirements, excluding the item being replaced is a refinement for later.
        let g = gearModifiers(equipment)
        return a.strength + (g[.strength] ?? 0) >= item.base.reqStr
            && a.dexterity + (g[.dexterity] ?? 0) >= item.base.reqDex
            && level >= item.requiredLevel
    }
}
