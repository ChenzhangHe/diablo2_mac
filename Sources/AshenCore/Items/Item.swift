public enum ItemQuality: String, Codable, Sendable, Comparable, CaseIterable {
    case normal, superior, magic, rare, unique, set

    var rank: Int { Self.allCases.firstIndex(of: self)! }
    public static func < (a: ItemQuality, b: ItemQuality) -> Bool { a.rank < b.rank }

    public var displayName: String {
        switch self {
        case .normal: "普通"
        case .superior: "精良"
        case .magic: "魔法"
        case .rare: "稀有"
        case .unique: "传奇"
        case .set: "套装"
        }
    }
}

public struct Item: Codable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let baseID: String
    public var quality: ItemQuality
    public var itemLevel: Int
    public var modifiers: [Modifier] = []
    public var prefixNames: [String] = []
    public var suffixNames: [String] = []
    public var rareName: String?
    public var rolledDefense = 0
    public var sockets = 0

    public init(id: Int, base: ItemBase, quality: ItemQuality = .normal, itemLevel: Int = 1) {
        self.id = id
        baseID = base.id
        self.quality = quality
        self.itemLevel = itemLevel
    }

    public var base: ItemBase { ItemBases.base(baseID)! }

    public var displayName: String {
        switch quality {
        case .normal: return base.name
        case .superior: return "精良的" + base.name
        case .magic: return (prefixNames.first ?? "") + base.name + (suffixNames.first ?? "")
        case .rare, .unique, .set: return rareName ?? base.name
        }
    }

    public func total(_ s: Stat) -> Int { modifiers.filter { $0.stat == s }.reduce(0) { $0 + $1.value } }

    /// Defense after enhanced-defense affixes.
    public var defense: Int {
        guard base.defense != nil else { return 0 }
        return rolledDefense * (100 + total(.enhancedDefense)) / 100 + total(.defense)
    }

    /// Weapon physical damage after enhanced-damage and flat bonuses.
    public var weaponDamage: ClosedRange<Int>? {
        guard let d = base.damage else { return nil }
        let ed = 100 + total(.enhancedDamage)
        let lo = d.lowerBound * ed / 100 + total(.minDamage)
        let hi = max(lo, d.upperBound * ed / 100 + total(.maxDamage))
        return lo...hi
    }

    /// Lines for the tooltip, top to bottom.
    public var tooltipLines: [String] {
        var lines: [String] = []
        if quality == .rare || quality == .unique || quality == .set { lines.append(base.name) }
        if let d = weaponDamage {
            lines.append("伤害: \(d.lowerBound)-\(d.upperBound)")
            lines.append("攻击速度: \((base.attacksPerSecond * 10).rounded() / 10)/秒")
        }
        if base.defense != nil { lines.append("防御: \(defense)") }
        if base.block > 0 { lines.append("格挡几率: \(base.block)%") }
        if base.reqStr > 0 { lines.append("需要力量: \(base.reqStr)") }
        if base.reqDex > 0 { lines.append("需要敏捷: \(base.reqDex)") }
        if requiredLevel > 1 { lines.append("需要等级: \(requiredLevel)") }
        lines.append(contentsOf: modifierLines)
        if sockets > 0 { lines.append("镶孔 (\(sockets))") }
        return lines
    }

    /// Affix lines with elemental min/max pairs merged.
    public var modifierLines: [String] {
        var out: [String] = []
        let pairs: [(Stat, Stat, String)] = [(.fireMin, .fireMax, "火焰"), (.coldMin, .coldMax, "冰霜"),
                                             (.lightningMin, .lightningMax, "闪电"), (.poisonMin, .poisonMax, "毒素")]
        for (lo, hi, name) in pairs where total(hi) > 0 {
            out.append("附加 \(total(lo))-\(total(hi)) \(name)伤害")
        }
        let skip: Set<Stat> = [.fireMin, .fireMax, .coldMin, .coldMax, .lightningMin, .lightningMax, .poisonMin, .poisonMax]
        // Merge duplicates by stat, keep first-seen order.
        var seen: [Stat] = []
        for m in modifiers where !skip.contains(m.stat) && !seen.contains(m.stat) { seen.append(m.stat) }
        for s in seen {
            out.append(Modifier(s, total(s)).text)
        }
        return out
    }

    /// Magic/rare items require roughly the item level of their strongest affix.
    public var requiredLevel: Int {
        guard quality >= .magic else { return 1 }
        let lv = (prefixNames + suffixNames).compactMap { n in Affixes.all.first { $0.name == n }?.level }.max() ?? 1
        return max(1, lv * 3 / 4 + (quality == .rare ? 2 : 0))
    }

    public var isPotion: Bool { base.category == .potion }
}

/// Gold or an item lying on the floor.
public struct GroundItem: Sendable, Identifiable {
    public enum Content: Sendable { case gold(Int), item(Item) }
    public let id: Int
    public var position: Vec2
    public var content: Content

    public var label: String {
        switch content {
        case .gold(let n): "\(n) 金币"
        case .item(let it): it.displayName
        }
    }
}
