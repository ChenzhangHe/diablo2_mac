import Foundation

/// Experience curve and level-difference scaling.
public enum Experience {
    public static let maxLevel = 40
    public static let statPointsPerLevel = 5
    public static let skillPointsPerLevel = 1
    /// Global tuning knob for monster XP.
    public static let monsterXPMultiplier = 2.5

    /// Total XP required to reach `level` (level 1 = 0).
    public static func total(forLevel level: Int) -> Int {
        guard level > 1 else { return 0 }
        var sum = 0.0
        for l in 1..<level { sum += 60 * pow(Double(l), 1.5) }
        return Int(sum)
    }

    /// Monsters far below the player give much less XP; above-level kills give a little extra.
    public static func scaled(_ xp: Int, monsterLevel: Int, playerLevel: Int) -> Int {
        let diff = monsterLevel - playerLevel
        let factor: Double
        switch diff {
        case ..<(-10): factor = 0.05
        case -10 ..< -5: factor = 1 - Double(-diff - 5) * 0.15
        case -5...5: factor = 1
        default: factor = 1 + min(Double(diff - 5), 5) * 0.05
        }
        return max(1, Int((Double(xp) * factor * monsterXPMultiplier).rounded()))
    }
}
