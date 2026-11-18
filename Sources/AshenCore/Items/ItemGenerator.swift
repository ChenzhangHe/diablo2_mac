/// Rolls bases, qualities and affixes. Mirrors the classic flow:
/// pick base by item level → roll quality → roll affixes from level-gated pools.
public struct ItemGenerator {
    public var magicChance = 0.30
    public var rareChance = 0.06
    public var superiorChance = 0.08

    public init() {}

    public func randomBase(itemLevel: Int, rng: inout SeededRNG) -> ItemBase {
        let pool = ItemBases.all.filter { $0.qlvl <= itemLevel }
        // Favor bases close to the item level.
        let weights = pool.map { 1.0 + Double($0.qlvl) / Double(max(1, itemLevel)) * 2 }
        return pick(pool, weights: weights, rng: &rng)
    }

    public func generate(id: Int, itemLevel: Int, rng: inout SeededRNG, magicFind: Double = 0,
                         forcedQuality: ItemQuality? = nil, base forcedBase: ItemBase? = nil) -> Item {
        let base = forcedBase ?? randomBase(itemLevel: itemLevel, rng: &rng)
        let quality: ItemQuality
        if let q = forcedQuality {
            quality = q
        } else {
            let mf = 1 + magicFind / 100
            let r = rng.unit()
            if r < rareChance * mf { quality = .rare }
            else if r < (rareChance + magicChance) * mf { quality = .magic }
            else if !base.category.isJewelry && r < (rareChance + magicChance + superiorChance) * mf { quality = .superior }
            else { quality = .normal }
        }
        // Jewelry is never plain.
        let q = base.category.isJewelry && quality < .magic ? .magic : quality
        var item = Item(id: id, base: base, quality: q, itemLevel: itemLevel)
        if let d = base.defense { item.rolledDefense = rng.int(d) }

        switch q {
        case .normal:
            if base.maxSockets > 0 && rng.chance(0.25) { item.sockets = rng.int(1...base.maxSockets) }
        case .superior:
            if base.damage != nil { item.modifiers.append(Modifier(.enhancedDamage, rng.int(5...15))) }
            if base.defense != nil { item.modifiers.append(Modifier(.enhancedDefense, rng.int(5...15))) }
        case .magic:
            let both = rng.chance(0.5)
            let prefixFirst = rng.chance(0.5)
            if both || prefixFirst { addAffix(prefix: true, to: &item, rng: &rng) }
            if both || !prefixFirst { addAffix(prefix: false, to: &item, rng: &rng) }
            if item.prefixNames.isEmpty && item.suffixNames.isEmpty { addAffix(prefix: false, to: &item, rng: &rng) }
        case .rare:
            let count = rng.int(3...6)
            var prefixes = 0, suffixes = 0
            for _ in 0..<(count * 3) where prefixes + suffixes < count {
                let wantPrefix = prefixes < 3 && (suffixes >= 3 || rng.chance(0.5))
                if addAffix(prefix: wantPrefix, to: &item, rng: &rng) {
                    if wantPrefix { prefixes += 1 } else { suffixes += 1 }
                }
            }
            item.rareName = RareNames.make(category: base.category, rng: &rng)
        case .unique, .set:
            break
        }
        return item
    }

    @discardableResult
    func addAffix(prefix: Bool, to item: inout Item, rng: inout SeededRNG) -> Bool {
        let used = Set((item.prefixNames + item.suffixNames).compactMap { n in Affixes.all.first { $0.name == n }?.group })
        let pool = Affixes.all.filter {
            $0.isPrefix == prefix && $0.level <= item.itemLevel && $0.categories.contains(item.base.category)
                && !used.contains($0.group)
        }
        guard !pool.isEmpty else { return false }
        let a = pick(pool, weights: pool.map { Double($0.weight) }, rng: &rng)
        for r in a.rolls { item.modifiers.append(Modifier(r.stat, rng.int(r.range))) }
        if prefix { item.prefixNames.append(a.name) } else { item.suffixNames.append(a.name) }
        return true
    }

    private func pick<T>(_ xs: [T], weights: [Double], rng: inout SeededRNG) -> T {
        let total = weights.reduce(0, +)
        var r = rng.unit() * total
        for (x, w) in zip(xs, weights) {
            r -= w
            if r < 0 { return x }
        }
        return xs.last!
    }
}

/// Two-part evocative names for rare items, e.g. "血誓 之握".
enum RareNames {
    static let first = ["血誓", "灰烬", "暮钟", "腐蚀", "裂魂", "冥火", "霜脊", "骸骨", "渊影", "铁棘",
                        "狼嚎", "风暴", "孤星", "朽木", "鸦羽", "赤潮", "幽魂", "龙骨", "荒原", "噬日"]
    static func second(_ c: ItemCategory) -> [String] {
        switch c {
        case .weapon: ["之刃", "之牙", "撕裂者", "之锋", "断骨", "之噬"]
        case .shield: ["壁垒", "之盾", "守望", "之墙"]
        case .helm: ["之冠", "之颅", "面罩", "之瞳"]
        case .armor: ["之甲", "外壳", "之鳞", "之衣"]
        case .gloves: ["之握", "之爪", "之触"]
        case .boots: ["之履", "行者", "之踵"]
        case .belt: ["之环", "束带", "之缚"]
        case .ring: ["之环", "之印", "之圈"]
        case .amulet: ["之心", "之泪", "护身", "之眼"]
        case .potion: [""]
        }
    }

    static func make(category: ItemCategory, rng: inout SeededRNG) -> String {
        let a = first[rng.int(0...(first.count - 1))]
        let s = second(category)
        return a + " " + s[rng.int(0...(s.count - 1))]
    }
}

/// What a dead monster drops ("treasure class" lite).
public enum LootTable {
    public enum Drop: Sendable { case gold(Int), item(Item) }

    public static func roll(monsterLevel: Int, isBoss: Bool = false, goldFind: Double = 0, magicFind: Double = 0,
                            nextID: () -> Int, rng: inout SeededRNG) -> [Drop] {
        var drops: [Drop] = []
        let picks = isBoss ? 5 : 1
        let gen = ItemGenerator()
        for _ in 0..<picks {
            let r = rng.unit()
            if isBoss || r < 0.13 {
                drops.append(.item(gen.generate(id: nextID(), itemLevel: monsterLevel, rng: &rng, magicFind: magicFind)))
            } else if r < 0.36 {
                let base = rng.int(2...(6 + monsterLevel * 3))
                drops.append(.gold(Int(Double(base) * (1 + goldFind / 100))))
            } else if r < 0.46 {
                let potion = rng.chance(0.65) ? ItemBases.healthPotion : ItemBases.manaPotion
                drops.append(.item(Item(id: nextID(), base: potion)))
            }
        }
        return drops
    }
}
