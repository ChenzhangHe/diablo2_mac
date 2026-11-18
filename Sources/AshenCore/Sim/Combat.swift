public enum AttackOutcome: Equatable, Sendable {
    case miss
    case blocked
    case hit(damage: Double, crit: Bool)
}

/// Combat formulas, modelled on classic ARPG rules (attack rating vs defense, capped resistances).
public enum Combat {
    public static let resistCap = 75
    public static let minHit = 0.05, maxHit = 0.95

    /// Chance to hit = 2 · AR/(AR+DEF) · aLvl/(aLvl+dLvl), clamped to [5%, 95%].
    public static func hitChance(attackRating ar: Double, defense def: Double,
                                 attackerLevel al: Int, defenderLevel dl: Int) -> Double {
        let arTerm = ar / max(1, ar + def)
        let lvlTerm = Double(al) / Double(max(1, al + dl))
        return min(maxHit, max(minHit, 2 * arTerm * lvlTerm))
    }

    /// Apply resistance (or physical damage reduction) to raw damage.
    public static func mitigate(_ amount: Double, type: DamageType, defender: CombatStats) -> Double {
        if type == .physical {
            return amount * (1 - min(50, max(0, defender.damageReduction)) / 100)
        }
        let r = min(resistCap, defender.resist[type])   // negative resist amplifies damage
        return amount * (1 - Double(r) / 100)
    }

    public static func rollDamage(_ a: CombatStats, rng: inout SeededRNG) -> Double {
        a.minDamage + (a.maxDamage - a.minDamage) * rng.unit()
    }

    /// Basic attack: roll to hit, roll block, roll base + elemental damage, crit doubles, then mitigate.
    public static func resolveAttack(attacker a: CombatStats, defender d: CombatStats,
                                     rng: inout SeededRNG) -> AttackOutcome {
        let chance = hitChance(attackRating: a.attackRating, defense: d.defense,
                               attackerLevel: a.level, defenderLevel: d.level)
        guard rng.chance(chance) else { return .miss }
        if d.blockChance > 0 && rng.chance(min(75, d.blockChance) / 100) { return .blocked }
        let crit = rng.chance(a.critChance)
        let mult = crit ? 2.0 : 1.0
        var total = mitigate(rollDamage(a, rng: &rng) * mult, type: a.damageType, defender: d)
        for e in a.elemental {
            let raw = e.min + (e.max - e.min) * rng.unit()
            total += mitigate(raw * mult, type: e.type, defender: d)
        }
        return .hit(damage: max(1, total), crit: crit)
    }
}
