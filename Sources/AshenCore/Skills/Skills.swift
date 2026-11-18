/// How a skill is used.
public enum SkillKind: String, Sendable {
    case meleeAttack    // replaces basic attack on a target
    case charge         // dash to target, then strike
    case whirl          // spin to a point, hitting everything passed
    case nova           // instant effect around the player
    case buff           // timed self-buff
    case passive        // always on
}

public struct SkillTree: Sendable, Equatable {
    public let id: String
    public let name: String
}

/// Static description of a skill. Numbers scale with skill level (1...20) and synergies.
public struct SkillDef: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let tree: String
    public let tier: Int                 // 0...5 → required level 1/6/12/18/24/30
    public let column: Int               // 0...2 for tree layout
    public let kind: SkillKind
    public let prerequisites: [String]
    public let requiresShield: Bool
    public let summary: String
    /// Synergies: (other skill id, bonus % per level of that skill).
    public let synergies: [(String, Double)]

    public var requiredLevel: Int { [1, 6, 12, 18, 24, 30][tier] }
    public var isActive: Bool { kind != .passive }
}

public enum Skills {
    public static let maxSkillLevel = 20

    public static let trees = [
        SkillTree(id: "shield", name: "盾卫"),
        SkillTree(id: "cries", name: "战吼"),
        SkillTree(id: "arts", name: "灰烬武艺"),
    ]

    public static let all: [SkillDef] = [
        // ---- 盾卫 Shield ----
        SkillDef(id: "shield_bash", name: "盾击", tree: "shield", tier: 0, column: 0, kind: .meleeAttack,
                 prerequisites: [], requiresShield: true,
                 summary: "用盾牌猛击敌人，造成额外伤害，有几率击晕并击退。", synergies: [("bulwark", 6)]),
        SkillDef(id: "bulwark", name: "坚壁", tree: "shield", tier: 0, column: 2, kind: .passive,
                 prerequisites: [], requiresShield: false,
                 summary: "被动：提高防御与格挡几率。", synergies: []),
        SkillDef(id: "ember_ward", name: "余烬护体", tree: "shield", tier: 1, column: 1, kind: .buff,
                 prerequisites: [], requiresShield: false,
                 summary: "包裹灼热余烬：提高火焰抗性，近战攻击者受到火焰反伤。", synergies: []),
        SkillDef(id: "ember_charge", name: "余烬冲锋", tree: "shield", tier: 2, column: 0, kind: .charge,
                 prerequisites: ["shield_bash"], requiresShield: false,
                 summary: "冲向目标并重击，造成大量伤害并击退。", synergies: [("shield_bash", 8)]),
        SkillDef(id: "unyielding", name: "不屈", tree: "shield", tier: 3, column: 2, kind: .passive,
                 prerequisites: ["bulwark"], requiresShield: false,
                 summary: "被动：物理伤害减免与生命恢复。", synergies: []),
        SkillDef(id: "sunshield", name: "日炎壁障", tree: "shield", tier: 4, column: 1, kind: .buff,
                 prerequisites: ["ember_ward", "unyielding"], requiresShield: false,
                 summary: "召唤炽热壁障，吸收一定量的伤害。", synergies: [("bulwark", 5), ("ember_ward", 5)]),

        // ---- 战吼 Warcries ----
        SkillDef(id: "rallying_roar", name: "振奋怒吼", tree: "cries", tier: 0, column: 0, kind: .buff,
                 prerequisites: [], requiresShield: false,
                 summary: "提高伤害与命中值，持续一段时间。", synergies: []),
        SkillDef(id: "dread_howl", name: "恐惧嚎叫", tree: "cries", tier: 0, column: 2, kind: .nova,
                 prerequisites: [], requiresShield: false,
                 summary: "令附近的敌人恐惧逃窜。", synergies: []),
        SkillDef(id: "iron_shout", name: "钢铁呐喊", tree: "cries", tier: 1, column: 1, kind: .buff,
                 prerequisites: ["rallying_roar"], requiresShield: false,
                 summary: "大幅提高防御，持续一段时间。", synergies: []),
        SkillDef(id: "war_horn", name: "战争号角", tree: "cries", tier: 2, column: 0, kind: .buff,
                 prerequisites: ["rallying_roar"], requiresShield: false,
                 summary: "提高最大生命与法力，持续一段时间。", synergies: [("iron_shout", 4)]),
        SkillDef(id: "quake_cry", name: "震地咆哮", tree: "cries", tier: 3, column: 2, kind: .nova,
                 prerequisites: ["dread_howl"], requiresShield: false,
                 summary: "震荡周围的敌人，造成伤害并击晕。", synergies: [("dread_howl", 8), ("rallying_roar", 4)]),
        SkillDef(id: "ash_oath", name: "灰烬誓约", tree: "cries", tier: 4, column: 1, kind: .nova,
                 prerequisites: ["quake_cry", "iron_shout"], requiresShield: false,
                 summary: "诅咒周围的敌人，使其受到的所有伤害提高。", synergies: []),

        // ---- 灰烬武艺 Ember Arts ----
        SkillDef(id: "flame_strike", name: "烈焰斩", tree: "arts", tier: 0, column: 0, kind: .meleeAttack,
                 prerequisites: [], requiresShield: false,
                 summary: "挥出燃烧的一击，附加火焰伤害与命中值。", synergies: [("cinder_nova", 6)]),
        SkillDef(id: "weapon_mastery", name: "武器精通", tree: "arts", tier: 0, column: 2, kind: .passive,
                 prerequisites: [], requiresShield: false,
                 summary: "被动：提高武器伤害、命中值与暴击几率。", synergies: []),
        SkillDef(id: "cleave", name: "顺劈", tree: "arts", tier: 1, column: 1, kind: .meleeAttack,
                 prerequisites: [], requiresShield: false,
                 summary: "横扫前方，攻击扇形范围内的所有敌人。", synergies: [("weapon_mastery", 5)]),
        SkillDef(id: "frenzied_blows", name: "狂热连击", tree: "arts", tier: 2, column: 0, kind: .meleeAttack,
                 prerequisites: ["flame_strike"], requiresShield: false,
                 summary: "每次命中提高攻击速度与移动速度，可叠加。", synergies: []),
        SkillDef(id: "ember_whirl", name: "余烬旋风", tree: "arts", tier: 3, column: 1, kind: .whirl,
                 prerequisites: ["cleave"], requiresShield: false,
                 summary: "旋转着冲向目标位置，攻击沿途所有敌人。", synergies: [("cleave", 5)]),
        SkillDef(id: "cinder_nova", name: "灰烬新星", tree: "arts", tier: 4, column: 2, kind: .nova,
                 prerequisites: ["ember_whirl", "weapon_mastery"], requiresShield: false,
                 summary: "引爆体内余烬，对周围敌人造成大量火焰伤害。", synergies: [("flame_strike", 8)]),
    ]

    public static func def(_ id: String) -> SkillDef? { all.first { $0.id == id } }
    public static func inTree(_ tree: String) -> [SkillDef] { all.filter { $0.tree == tree } }
}

/// Numbers for each skill at a given level. Kept in one place for balancing.
public struct SkillNumbers: Sendable {
    public var manaCost: Double = 0
    public var damagePercent: Double = 0       // bonus % physical damage on the attack
    public var attackRatingPercent: Double = 0
    public var fireMin: Double = 0, fireMax: Double = 0
    public var physMin: Double = 0, physMax: Double = 0
    public var radius: Double = 0
    public var duration: Double = 0
    public var stunChance: Double = 0
    public var stunDuration: Double = 0
    public var modifiers: [Modifier] = []      // passive / buff stat bonuses
    public var absorb: Double = 0
    public var vulnerability: Double = 0       // % extra damage taken
    public var cooldown: Double = 0

    /// Human-readable lines for tooltips.
    public var lines: [String] {
        var out: [String] = []
        if manaCost > 0 { out.append("法力消耗: \(Int(manaCost.rounded()))") }
        if damagePercent != 0 { out.append("伤害: +\(Int(damagePercent))%") }
        if attackRatingPercent != 0 { out.append("命中值: +\(Int(attackRatingPercent))%") }
        if physMax > 0 { out.append("伤害: \(Int(physMin))-\(Int(physMax))") }
        if fireMax > 0 { out.append("火焰伤害: \(Int(fireMin))-\(Int(fireMax))") }
        if radius > 0 { out.append("半径: \((radius * 10).rounded() / 10) 码") }
        if stunChance > 0 { out.append("击晕几率: \(Int(stunChance * 100))%") }
        if stunDuration > 0 { out.append("击晕/恐惧时间: \((stunDuration * 10).rounded() / 10) 秒") }
        if absorb > 0 { out.append("吸收伤害: \(Int(absorb))") }
        if vulnerability > 0 { out.append("敌人受到伤害: +\(Int(vulnerability))%") }
        out.append(contentsOf: modifiers.map(\.text))
        if duration > 0 { out.append("持续时间: \(Int(duration)) 秒") }
        if cooldown > 0 { out.append("冷却: \((cooldown * 10).rounded() / 10) 秒") }
        return out
    }
}

extension Skills {
    /// Numbers for `id` at level `lv` with synergy multiplier `syn` (1.0 = none).
    public static func numbers(_ id: String, level lv: Int, synergy syn: Double = 1) -> SkillNumbers {
        let L = Double(max(1, lv))
        var n = SkillNumbers()
        switch id {
        case "shield_bash":
            n.manaCost = 2
            n.damagePercent = (20 + 15 * (L - 1)) * syn
            n.attackRatingPercent = 15 + 5 * L
            n.stunChance = min(0.6, 0.15 + 0.02 * L); n.stunDuration = 0.8 + 0.05 * L
        case "bulwark":
            n.modifiers = [Modifier(.enhancedDefense, Int(20 + 10 * L)), Modifier(.blockChance, Int(min(20, 4 + L)))]
        case "ember_ward":
            n.manaCost = 8; n.duration = 60 + 6 * L
            n.modifiers = [Modifier(.fireResist, Int(min(60, 15 + 3 * L))), Modifier(.thorns, Int(4 + 3 * L))]
        case "ember_charge":
            n.manaCost = 9 + 0.5 * L
            n.damagePercent = (80 + 25 * (L - 1)) * syn
            n.attackRatingPercent = 50 + 10 * L
            n.stunChance = 0.5; n.stunDuration = 0.6
        case "unyielding":
            n.modifiers = [Modifier(.damageReduction, Int(min(35, 5 + 1.5 * L))), Modifier(.lifeRegen, Int(1 + L / 2))]
        case "sunshield":
            n.manaCost = 25; n.duration = 20; n.cooldown = 30
            n.absorb = (60 + 30 * (L - 1)) * syn

        case "rallying_roar":
            n.manaCost = 6; n.duration = 30 + 4 * L
            n.modifiers = [Modifier(.enhancedDamage, Int(25 + 8 * L)), Modifier(.attackRating, Int(20 * L))]
        case "dread_howl":
            n.manaCost = 4; n.radius = 4 + 0.4 * L; n.stunDuration = 2 + 0.3 * L
        case "iron_shout":
            n.manaCost = 7; n.duration = 30 + 4 * L
            n.modifiers = [Modifier(.enhancedDefense, Int(80 + 15 * L))]
        case "war_horn":
            n.manaCost = 12; n.duration = 40 + 6 * L
            let pct = Int((25 + 3 * L) * syn)
            n.modifiers = [Modifier(.lifePercent, pct), Modifier(.manaPercent, pct)]
        case "quake_cry":
            n.manaCost = 12 + 0.5 * L; n.radius = 3.5; n.stunChance = 1; n.stunDuration = 1 + 0.1 * L
            n.physMin = (6 + 5 * (L - 1)) * syn; n.physMax = (10 + 7 * (L - 1)) * syn
        case "ash_oath":
            n.manaCost = 10; n.radius = 5 + 0.3 * L; n.duration = 8 + L
            n.vulnerability = min(100, 25 + 5 * L)

        case "flame_strike":
            n.manaCost = 2 + 0.25 * L
            n.attackRatingPercent = 20 + 10 * L
            n.fireMin = (2 + 3 * (L - 1)) * syn; n.fireMax = (5 + 5 * (L - 1)) * syn
        case "weapon_mastery":
            n.modifiers = [Modifier(.enhancedDamage, Int(15 + 7 * L)), Modifier(.attackRating, Int(15 * L)),
                           Modifier(.critChance, Int(min(25, 2 + L)))]
        case "cleave":
            n.manaCost = 4 + 0.25 * L
            n.damagePercent = (-25 + 10 * (L - 1)) * syn
            n.radius = 1.8 + 0.05 * L
        case "frenzied_blows":
            n.manaCost = 3
            n.damagePercent = 10 + 6 * L
            n.attackRatingPercent = 30 + 6 * L
            n.duration = 4    // stack lifetime
        case "ember_whirl":
            n.manaCost = 14 + 0.5 * L
            n.damagePercent = (-10 + 8 * (L - 1)) * syn
            n.attackRatingPercent = 20 + 5 * L
            n.radius = 1.4
        case "cinder_nova":
            n.manaCost = 16 + L
            n.radius = 3 + 0.1 * L
            n.fireMin = (14 + 8 * (L - 1)) * syn; n.fireMax = (24 + 12 * (L - 1)) * syn
            n.cooldown = 0.6
        default:
            break
        }
        return n
    }
}

/// A player's learned skills.
public struct SkillBook: Codable, Sendable, Equatable {
    public var levels: [String: Int] = [:]

    public init() {}

    public func level(_ id: String) -> Int { levels[id] ?? 0 }

    public enum LearnError: Error, Equatable { case noPoints, levelTooLow, missingPrerequisite(String), maxed, unknown }

    /// nil when the skill can be learned.
    public func learnError(_ id: String, characterLevel: Int, points: Int) -> LearnError? {
        guard let d = Skills.def(id) else { return .unknown }
        if points <= 0 { return .noPoints }
        if level(id) >= Skills.maxSkillLevel { return .maxed }
        // Classic rule: skill level can't exceed (character level − required level + 1).
        if characterLevel < d.requiredLevel + level(id) { return .levelTooLow }
        if let missing = d.prerequisites.first(where: { level($0) == 0 }) { return .missingPrerequisite(missing) }
        return nil
    }

    /// Synergy multiplier: 1 + Σ(bonus% × level of the other skill)/100.
    public func synergy(_ id: String) -> Double {
        guard let d = Skills.def(id) else { return 1 }
        return 1 + d.synergies.reduce(0) { $0 + $1.1 * Double(level($1.0)) } / 100
    }

    public func numbers(_ id: String) -> SkillNumbers {
        Skills.numbers(id, level: level(id), synergy: synergy(id))
    }

    /// Stat bonuses from learned passives.
    public var passiveModifiers: [Modifier] {
        Skills.all.filter { $0.kind == .passive && level($0.id) > 0 }.flatMap { numbers($0.id).modifiers }
    }
}
