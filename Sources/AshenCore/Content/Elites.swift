public enum MonsterRank: String, Sendable {
    case normal, champion, unique, minion
}

/// Random modifiers on champion / unique monsters (classic elite-affix model, original names).
public enum EliteAffix: String, CaseIterable, Sendable {
    case swift, berserk, stoneskin, hulking, fireTouched, frostTouched, stormTouched, soulDrinker, manaBurn

    public var displayName: String {
        switch self {
        case .swift: "迅捷"
        case .berserk: "狂暴"
        case .stoneskin: "石肤"
        case .hulking: "巨型"
        case .fireTouched: "炎魂"
        case .frostTouched: "寒霜"
        case .stormTouched: "雷殛"
        case .soulDrinker: "噬魂"
        case .manaBurn: "法力燃烧"
        }
    }

    /// Apply to a monster's stats/mover.
    func apply(to m: inout Monster) {
        let lv = Double(m.stats.level)
        switch self {
        case .swift:
            m.mover.speed *= 1.5
            m.stats.attacksPerSecond *= 1.5
        case .berserk:
            m.stats.minDamage *= 1.8; m.stats.maxDamage *= 1.8
            m.stats.attackRating *= 1.3
        case .stoneskin:
            m.stats.defense *= 3
            m.stats.damageReduction = 40
        case .hulking:
            m.stats.maxLife *= 2; m.stats.life = m.stats.maxLife
        case .fireTouched:
            m.stats.elemental.append(ElementalDamage(.fire, 2 + lv, 6 + lv * 2))
            m.stats.resist.fire = 75
        case .frostTouched:
            m.stats.elemental.append(ElementalDamage(.cold, 1 + lv, 4 + lv * 1.5))
            m.stats.resist.cold = 75
        case .stormTouched:
            m.stats.elemental.append(ElementalDamage(.lightning, 1, 10 + lv * 3))
            m.stats.resist.lightning = 75
        case .soulDrinker:
            m.stats.lifeSteal = 35
        case .manaBurn:
            break
        }
    }
}

enum UniqueNames {
    static let first = ["腐牙", "裂颅", "黑沼", "灰脊", "血眼", "骨钟", "泥喉", "朽心", "毒棘", "暗爪", "铁颚", "哀嚎"]
    static let second = ["噬魂者", "屠夫", "王", "行者", "老祖", "领主", "收割者", "饕餮", "守墓人", "长老"]

    static func make(rng: inout SeededRNG) -> String {
        first[rng.int(0...(first.count - 1))] + "·" + second[rng.int(0...(second.count - 1))]
    }
}
