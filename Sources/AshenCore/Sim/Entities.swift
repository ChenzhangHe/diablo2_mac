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
    public var stunnedUntil = 0.0
    public var vulnerableUntil = 0.0
    public var vulnerability = 0.0

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
    case groundItem(Int)
}

public struct Player: Sendable {
    public var heroClass = HeroClass.emberguard
    public var mover: Mover
    public var stats: CombatStats
    public var attributes: Attributes
    public var statPoints = 0
    public var skillPoints = 0
    public var skills = SkillBook()
    public var buffs: [Buff] = []
    /// Skill bound to each hotbar key ("rmb", "q", "w", "e", "r").
    public var hotbar: [String: String] = [:]
    public static let hotbarKeys = ["rmb", "q", "w", "e", "r"]
    public var cooldowns: [String: Double] = [:]
    public var absorbPool = 0.0
    public var frenzyStacks = 0
    public var frenzyExpires = 0.0
    /// Skill used for melee attacks on the current target (nil = basic attack).
    public var attackSkill: String?
    public var action: PlayerAction = .none
    public var equipment: [EquipSlot: Item] = [:]
    public var inventory = Inventory()
    /// Item held on the mouse cursor (classic inventory juggling).
    public var cursor: Item?
    public var gold = 0
    public var goldFind = 0.0
    public var reach = 1.3
    public var target: PlayerTarget?
    public var attackCooldown = 0.0
    public var repathTimer = 0.0
    /// Potions heal over time, like classic ARPGs.
    public var healthPotions = 6
    public var manaPotions = 4
    public static let beltCapacity = 12
    public var healPool = 0.0
    public var manaPool = 0.0
    public var deathTime: Double?
    public var xp = 0

    public var position: Vec2 { mover.position }
    public var level: Int { stats.level }
    public var xpForNextLevel: Int { Experience.total(forLevel: level + 1) }
    public var xpIntoLevel: Double {
        let lo = Experience.total(forLevel: level), hi = xpForNextLevel
        return level >= Experience.maxLevel ? 1 : Double(xp - lo) / Double(max(1, hi - lo))
    }

    /// Add XP; returns number of levels gained. Leveling refills life and mana.
    @discardableResult
    public mutating func gainXP(_ amount: Int) -> Int {
        guard level < Experience.maxLevel else { return 0 }
        xp += amount
        var gained = 0
        while level < Experience.maxLevel && xp >= xpForNextLevel {
            stats.level += 1
            statPoints += Experience.statPointsPerLevel
            skillPoints += Experience.skillPointsPerLevel
            gained += 1
        }
        if gained > 0 {
            recalculate()
            stats.life = stats.maxLife
            stats.mana = stats.maxMana
        }
        return gained
    }

    public var hasShield: Bool { equipment[.offhand]?.base.category == .shield }

    /// Spend a skill point. Newly learned active skills auto-bind to a free hotbar key.
    @discardableResult
    public mutating func learnSkill(_ id: String) -> SkillBook.LearnError? {
        if let err = skills.learnError(id, characterLevel: level, points: skillPoints) { return err }
        let wasNew = skills.level(id) == 0
        skills.levels[id, default: 0] += 1
        skillPoints -= 1
        if wasNew, Skills.def(id)?.isActive == true, let free = Player.hotbarKeys.first(where: { hotbar[$0] == nil }) {
            hotbar[free] = id
        }
        recalculate()
        return nil
    }

    public enum AttributeKind: CaseIterable, Sendable { case strength, dexterity, vitality, energy }

    public mutating func spendStatPoint(_ a: AttributeKind) {
        guard statPoints > 0 else { return }
        statPoints -= 1
        switch a {
        case .strength: attributes.strength += 1
        case .dexterity: attributes.dexterity += 1
        case .vitality:
            attributes.vitality += 1
            stats.life += heroClass.lifePerVitality
        case .energy:
            attributes.energy += 1
            stats.mana += heroClass.manaPerEnergy
        }
        recalculate()
    }

    public static func newHero(at pos: Vec2, heroClass: HeroClass = .emberguard) -> Player {
        let attrs = heroClass.start
        let (s, move, _) = StatCalculator.compute(heroClass: heroClass, level: 1, attributes: attrs, equipment: [:], current: nil)
        var p = Player(heroClass: heroClass, mover: Mover(position: pos, speed: move), stats: s, attributes: attrs)
        p.recalculate()
        return p
    }

    /// Re-derive combat stats after gear/attribute/level changes.
    public mutating func recalculate() {
        var extra = skills.passiveModifiers + buffs.flatMap(\.modifiers)
        if frenzyStacks > 0 {
            extra.append(Modifier(.attackSpeed, frenzyStacks * 8))
            extra.append(Modifier(.moveSpeed, frenzyStacks * 5))
        }
        let r = StatCalculator.compute(heroClass: heroClass, level: stats.level, attributes: attributes,
                                       equipment: equipment, extra: extra, current: stats)
        stats = r.stats
        mover.speed = r.moveSpeed
        goldFind = r.goldFind
    }

    public func canEquip(_ item: Item) -> Bool {
        !EquipSlot.slots(for: item.base.category).isEmpty
            && StatCalculator.meetsRequirements(item, attributes: attributes, equipment: equipment, level: level)
    }

    /// Slot an item would go to: first empty matching slot, else the first matching slot.
    public func preferredSlot(for item: Item) -> EquipSlot? {
        let slots = EquipSlot.slots(for: item.base.category)
        return slots.first { equipment[$0] == nil } ?? slots.first
    }
}

public enum PlayerAction: Sendable, Equatable {
    case none
    case charging(target: EntityID, until: Double)
    case whirling(dest: Vec2, nextTick: Double, until: Double)
}

public struct Buff: Sendable, Equatable {
    public let skillID: String
    public var expires: Double
    public var modifiers: [Modifier]
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
    case levelUp(Int)
    case playerDied
    case playerRespawned
    case potion(health: Bool)
    case blocked(at: Vec2)
    case itemDropped(Int)
    case pickedUp(String)
    case inventoryFull
    case cannotEquip(String)
    case absorbed(at: Vec2)
    case skillUsed(String, at: Vec2, toward: Vec2)
    case nova(String, at: Vec2, radius: Double)
    case stunned(EntityID)
    case notEnoughMana
    case skillUnavailable(String)
}
