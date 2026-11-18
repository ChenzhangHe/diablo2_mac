public typealias EntityID = Int

public enum AIState: Sendable, Equatable {
    case idle
    case chase
    case attack
    case flee(until: Double)
    case retreat(until: Double)   // hit-and-run back-off
}

public struct Monster: Sendable, Identifiable {
    public let id: EntityID
    public let kind: MonsterKind
    public var mover: Mover
    public var stats: CombatStats
    public var ai: AIState = .idle
    public var cooldown = 0.0
    public var repathTimer = 0.0
    public var packID: Int
    public var home: Vec2
    public var deathTime: Double?

    public var position: Vec2 { mover.position }
    public var isAlive: Bool { stats.isAlive }

    init(id: EntityID, kind: MonsterKind, at pos: Vec2, packID: Int, rng: inout SeededRNG) {
        self.id = id
        self.kind = kind
        self.packID = packID
        home = pos
        mover = Mover(position: pos, speed: kind.speed)
        mover.radius = kind.radius
        var s = CombatStats(level: kind.level, life: Double(rng.int(kind.life)),
                            minDamage: Double(kind.damage.lowerBound), maxDamage: Double(kind.damage.upperBound),
                            attackRating: kind.attackRating, defense: kind.defense)
        s.damageType = kind.damageType
        s.resist = kind.resist
        s.attacksPerSecond = kind.attacksPerSecond
        s.critChance = 0
        stats = s
    }
}

public enum PlayerTarget: Sendable, Equatable {
    case monster(EntityID)
}

public struct Player: Sendable {
    public var mover: Mover
    public var stats: CombatStats
    public var reach = 1.3
    public var target: PlayerTarget?
    public var attackCooldown = 0.0
    public var repathTimer = 0.0
    /// Potions heal over time, like classic ARPGs.
    public var healthPotions = 6
    public var manaPotions = 4
    public var healPool = 0.0
    public var manaPool = 0.0
    public var deathTime: Double?
    public var xp = 0

    public var position: Vec2 { mover.position }

    public static func newHero(at pos: Vec2) -> Player {
        var s = CombatStats(level: 1, life: 55, minDamage: 2, maxDamage: 7, attackRating: 90, defense: 15)
        s.maxMana = 15; s.mana = 15
        s.attacksPerSecond = 1.6
        s.lifeRegen = 0.4
        s.manaRegen = 0.5
        return Player(mover: Mover(position: pos, speed: 4.5), stats: s)
    }
}

public enum Faction: Sendable { case player, monsters }

public struct Projectile: Sendable, Identifiable {
    public let id: EntityID
    public var position: Vec2
    public var velocity: Vec2
    public var remaining: Double        // tiles left to travel
    public let faction: Faction
    public let attacker: CombatStats
    public let radius: Double
}

/// Things that happened this tick — consumed by the renderer for feedback (numbers, flashes, sounds).
public enum GameEvent: Sendable, Equatable {
    case damage(at: Vec2, amount: Int, crit: Bool, toPlayer: Bool)
    case miss(at: Vec2)
    case swing(attacker: EntityID?, at: Vec2, toward: Vec2)   // nil attacker = player
    case monsterDied(EntityID, at: Vec2, xp: Int)
    case playerDied
    case playerRespawned
    case potion(health: Bool)
}
