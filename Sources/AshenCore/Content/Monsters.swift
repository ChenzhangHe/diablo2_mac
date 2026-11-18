/// How a monster type behaves. Archetypes borrow classic ARPG roles (swarmers that panic,
/// shambling undead, kiting archers, hit-and-run flyers) but every creature here is original.
public enum MonsterBehavior: String, Codable, Sendable {
    case melee        // walk up and hit
    case skittish     // pack fighter; may panic and flee when a packmate dies
    case ranged       // keeps distance, shoots projectiles
    case hitAndRun    // darts in, strikes, darts away
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

    public static let actOne: [MonsterKind] = [murkling, husk, hollowArcher, gloomBat]
}
