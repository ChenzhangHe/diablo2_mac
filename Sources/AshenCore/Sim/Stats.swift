public enum DamageType: String, Codable, CaseIterable, Sendable {
    case physical, fire, cold, lightning, poison

    public var displayName: String {
        switch self {
        case .physical: "物理"
        case .fire: "火焰"
        case .cold: "冰霜"
        case .lightning: "闪电"
        case .poison: "毒素"
        }
    }
}

/// Resistances in percent. Effective value is capped at `Combat.resistCap`.
public struct Resistances: Codable, Sendable, Equatable {
    public var fire = 0, cold = 0, lightning = 0, poison = 0
    public init(fire: Int = 0, cold: Int = 0, lightning: Int = 0, poison: Int = 0) {
        self.fire = fire; self.cold = cold; self.lightning = lightning; self.poison = poison
    }
    public subscript(_ t: DamageType) -> Int {
        get {
            switch t {
            case .physical: 0
            case .fire: fire
            case .cold: cold
            case .lightning: lightning
            case .poison: poison
            }
        }
        set {
            switch t {
            case .physical: break
            case .fire: fire = newValue
            case .cold: cold = newValue
            case .lightning: lightning = newValue
            case .poison: poison = newValue
            }
        }
    }
}

public struct ElementalDamage: Codable, Sendable, Equatable {
    public var type: DamageType
    public var min: Double
    public var max: Double
    public init(_ type: DamageType, _ min: Double, _ max: Double) { self.type = type; self.min = min; self.max = max }
}

/// Everything combat needs to know about a combatant.
public struct CombatStats: Codable, Sendable {
    public var level: Int
    public var maxLife: Double
    public var life: Double
    public var maxMana: Double = 0
    public var mana: Double = 0
    public var minDamage: Double
    public var maxDamage: Double
    public var damageType: DamageType = .physical
    public var attackRating: Double
    public var defense: Double
    public var resist = Resistances()
    public var attacksPerSecond: Double = 1
    public var critChance: Double = 0.05
    public var lifeRegen: Double = 0      // per second
    public var manaRegen: Double = 0      // per second
    /// Physical damage reduction in percent (capped at 50).
    public var damageReduction: Double = 0
    /// Extra typed damage added to every attack (from affixes / skills).
    public var elemental: [ElementalDamage] = []
    public var lifeSteal: Double = 0      // percent of damage dealt
    public var thorns: Double = 0         // flat damage returned to melee attackers
    public var blockChance: Double = 0    // percent

    public init(level: Int, life: Double, minDamage: Double, maxDamage: Double,
                attackRating: Double, defense: Double) {
        self.level = level
        self.maxLife = life
        self.life = life
        self.minDamage = minDamage
        self.maxDamage = maxDamage
        self.attackRating = attackRating
        self.defense = defense
    }

    public var isAlive: Bool { life > 0 }
    public var lifeFraction: Double { maxLife > 0 ? max(0, life / maxLife) : 0 }
    public var manaFraction: Double { maxMana > 0 ? max(0, mana / maxMana) : 0 }
}
