/// How a monster type behaves. Archetypes borrow classic ARPG roles (swarmers that panic,
/// shambling undead, kiting archers, hit-and-run flyers) but every creature here is original.
public enum MonsterBehavior: String, Codable, Sendable {
    case melee        // walk up and hit
    case skittish     // pack fighter; may panic and flee when a packmate dies
    case ranged       // keeps distance, shoots projectiles
    case hitAndRun    // darts in, strikes, darts away
    case shaman       // ranged caster that revives fallen packmates
}

public enum ProjectileVisual: String, Sendable {
    case arrow, fireBolt, coldBolt
}

public struct MonsterKind: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let level: Int
    public let life: ClosedRange<Int>
    public let damage: ClosedRange<Int>
    public let damageType: DamageType
    public let attackRating: Double
    public let defense: Double
    public let resist: Resistances
    public let speed: Double            // tiles/s
    public let attacksPerSecond: Double
    public let reach: Double            // melee reach or ranged preferred distance, tiles
    public let aggroRadius: Double
    public let behavior: MonsterBehavior
    public let packSize: ClosedRange<Int>
    public let xp: Int
    public let radius: Double
    /// RGB tint for placeholder rendering.
    public let color: (Double, Double, Double)
    public let isUndead: Bool
    public var projectile: ProjectileVisual = .arrow
}

public enum Bestiary {
    /// Act I — 灰雾沼泽 (Ashmire Fen)
    public static let murkling = MonsterKind(
        id: "murkling", name: "泥沼小鬼", level: 1, life: 6...11, damage: 1...4, damageType: .physical,
        attackRating: 30, defense: 3, resist: Resistances(),
        speed: 3.3, attacksPerSecond: 1.1, reach: 1.0, aggroRadius: 8, behavior: .skittish,
        packSize: 4...7, xp: 6, radius: 0.25, color: (0.45, 0.55, 0.25), isUndead: false)

    public static let husk = MonsterKind(
        id: "husk", name: "枯骨兵", level: 2, life: 12...19, damage: 2...5, damageType: .physical,
        attackRating: 40, defense: 12, resist: Resistances(poison: 50),
        speed: 2.3, attacksPerSecond: 0.8, reach: 1.1, aggroRadius: 7, behavior: .melee,
        packSize: 3...5, xp: 10, radius: 0.3, color: (0.82, 0.78, 0.66), isUndead: true)

    public static let hollowArcher = MonsterKind(
        id: "hollow_archer", name: "空壳弓手", level: 2, life: 8...13, damage: 1...4, damageType: .physical,
        attackRating: 45, defense: 6, resist: Resistances(poison: 50),
        speed: 2.6, attacksPerSecond: 0.7, reach: 5.5, aggroRadius: 9, behavior: .ranged,
        packSize: 2...4, xp: 10, radius: 0.28, color: (0.6, 0.62, 0.7), isUndead: true)

    public static let gloomBat = MonsterKind(
        id: "gloom_bat", name: "幽暗蝠", level: 1, life: 4...7, damage: 1...3, damageType: .physical,
        attackRating: 35, defense: 10, resist: Resistances(),
        speed: 5.2, attacksPerSecond: 1.0, reach: 0.9, aggroRadius: 9, behavior: .hitAndRun,
        packSize: 3...6, xp: 5, radius: 0.22, color: (0.35, 0.25, 0.45), isUndead: false)

    public static let mireHexer: MonsterKind = {
        var k = MonsterKind(
            id: "mire_hexer", name: "泥沼巫医", level: 3, life: 10...16, damage: 2...6, damageType: .fire,
            attackRating: 40, defense: 5, resist: Resistances(fire: 25),
            speed: 2.6, attacksPerSecond: 0.5, reach: 5, aggroRadius: 9, behavior: .shaman,
            packSize: 1...1, xp: 16, radius: 0.27, color: (0.6, 0.35, 0.2), isUndead: false)
        k.projectile = .fireBolt
        return k
    }()

    public static let fenLurker = MonsterKind(
        id: "fen_lurker", name: "沼泽潜伏者", level: 3, life: 30...42, damage: 4...9, damageType: .physical,
        attackRating: 55, defense: 18, resist: Resistances(cold: 20),
        speed: 2.0, attacksPerSecond: 0.7, reach: 1.2, aggroRadius: 6, behavior: .melee,
        packSize: 2...3, xp: 22, radius: 0.38, color: (0.3, 0.4, 0.3), isUndead: false)

    public static let drownedSister: MonsterKind = {
        var k = MonsterKind(
            id: "drowned_sister", name: "溺亡修女", level: 5, life: 16...24, damage: 3...8, damageType: .cold,
            attackRating: 60, defense: 10, resist: Resistances(cold: 50, poison: 50),
            speed: 2.4, attacksPerSecond: 0.6, reach: 6, aggroRadius: 9, behavior: .ranged,
            packSize: 2...4, xp: 24, radius: 0.28, color: (0.45, 0.6, 0.65), isUndead: true)
        k.projectile = .coldBolt
        return k
    }()

    public static let boneWarden = MonsterKind(
        id: "bone_warden", name: "骸骨卫士", level: 6, life: 32...44, damage: 6...12, damageType: .physical,
        attackRating: 75, defense: 35, resist: Resistances(poison: 75),
        speed: 2.2, attacksPerSecond: 0.9, reach: 1.2, aggroRadius: 7, behavior: .melee,
        packSize: 3...5, xp: 30, radius: 0.32, color: (0.9, 0.86, 0.75), isUndead: true)

    public static let actOne: [MonsterKind] = [murkling, husk, hollowArcher, gloomBat]
    public static let all: [MonsterKind] = [murkling, husk, hollowArcher, gloomBat, mireHexer, fenLurker, drownedSister, boneWarden]
}

extension MonsterKind {
    /// Same monster at a different (area) level. Stats grow per level above the base.
    public func scaled(to level: Int) -> MonsterKind {
        let d = Double(max(0, level - self.level))
        func r(_ x: ClosedRange<Int>, _ k: Double) -> ClosedRange<Int> {
            Int((Double(x.lowerBound) * (1 + k * d)).rounded())...Int((Double(x.upperBound) * (1 + k * d)).rounded())
        }
        var m = MonsterKind(id: id, name: name, level: max(level, self.level), life: r(life, 0.3), damage: r(damage, 0.18),
                            damageType: damageType, attackRating: attackRating * (1 + 0.15 * d), defense: defense * (1 + 0.15 * d),
                            resist: resist, speed: speed, attacksPerSecond: attacksPerSecond, reach: reach,
                            aggroRadius: aggroRadius, behavior: behavior, packSize: packSize,
                            xp: Int((Double(xp) * (1 + 0.35 * d)).rounded()), radius: radius, color: color, isUndead: isUndead)
        m.projectile = projectile
        return m
    }
}
