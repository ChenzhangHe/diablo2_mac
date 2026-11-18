/// The authoritative simulation. Rendering only reads from it and feeds it commands.
import Foundation

public final class GameWorld {
    public private(set) var level: GeneratedLevel
    public private(set) var area: AreaDef
    public private(set) var interactables: [Interactable] = []
    public let seed: UInt64
    /// Explored tiles per area (automap).
    public private(set) var explored: [String: Set<GridPoint>] = [:]
    public static let revealRadius = 10
    private var lastRevealCenter: GridPoint?
    /// Vendor stock by NPC id; restocked whenever the player enters town.
    public private(set) var vendors: [String: Inventory] = [:]
    /// Saved state of areas the player has left, so revisiting keeps kills and loot.
    private var visited: [String: AreaState] = [:]
    public var player: Player
    public internal(set) var monsters: [Monster] = []
    public private(set) var projectiles: [Projectile] = []
    public private(set) var groundItems: [GroundItem] = []
    public private(set) var time = 0.0
    private var pendingEvents: [GameEvent] = []
    var rng: SeededRNG
    private var nextID: EntityID = 1

    public static let respawnDelay = 2.5
    public static let corpseLifetime = 30.0

    public init(seed: UInt64, startArea: String = "reedford") {
        self.seed = seed
        rng = SeededRNG(seed: seed ^ 0xA5A5_5A5A)
        area = Areas.def(startArea) ?? Areas.actOne[0]
        level = LevelGenerator.generate(area, seed: Self.areaSeed(seed, area.id))
        player = .newHero(at: Vec2(center: level.spawn))
        giveStartingGear()
        enterFresh()
        player.waypoints.insert(Areas.actOne[0].id)
        if area.isTown { restockVendors() }
    }

    static func areaSeed(_ seed: UInt64, _ id: String) -> UInt64 {
        id.unicodeScalars.reduce(seed &* 0x100000001B3) { ($0 ^ UInt64($1.value)) &* 0x100000001B3 }
    }

    private func giveStartingGear() {
        if let blade = ItemBases.base("short_blade") { player.equipment[.weapon] = Item(id: makeID(), base: blade) }
        if let buckler = ItemBases.base("buckler") {
            var b = Item(id: makeID(), base: buckler)
            b.rolledDefense = 4
            player.equipment[.offhand] = b
        }
        player.recalculate()
        player.stats.life = player.stats.maxLife
        player.stats.mana = player.stats.maxMana
    }

    /// Test/debug constructor with a hand-made level.
    public init(level: GeneratedLevel, seed: UInt64 = 1) {
        self.seed = seed
        rng = SeededRNG(seed: seed)
        area = AreaDef(id: "test", name: "测试", act: 1, level: 1, style: .dungeon, theme: .crypt, size: level.map.width,
                       monsters: [], hasWaypoint: false)
        self.level = level
        player = .newHero(at: Vec2(center: level.spawn))
    }

    public func drainEvents() -> [GameEvent] {
        defer { pendingEvents.removeAll() }
        return pendingEvents
    }

    func emit(_ e: GameEvent) { pendingEvents.append(e) }

    func makeID() -> EntityID { defer { nextID += 1 }; return nextID }

    func reserveIDs(above n: Int) { nextID = max(nextID, n + 1) }

    // MARK: - Spawning

    private func spawnMonsters(kinds: [MonsterKind]) {
        guard !kinds.isEmpty else { return }
        var packID = 0
        for room in level.rooms.dropFirst() {           // keep the spawn room safe
            let packs = room.w * room.h > 60 ? 2 : 1
            for _ in 0..<packs {
                let kind = kinds[rng.int(0...(kinds.count - 1))].scaled(to: max(1, area.level))
                let ids = spawnPack(kind: kind, in: room, packID: packID)
                let roll = rng.unit()
                if roll < 0.08 { makeUniquePack(ids) } else if roll < 0.18 { makeChampionPack(ids) }
                packID += 1
            }
        }
    }

    @discardableResult
    public func spawnPack(kind: MonsterKind, in room: Room, packID: Int) -> [EntityID] {
        var ids: [EntityID] = []
        let count = rng.int(kind.packSize)
        let center = room.center
        for _ in 0..<count {
            for _ in 0..<10 {
                let p = GridPoint(center.x + rng.int(-2...2), center.y + rng.int(-2...2))
                if level.map.isWalkable(p) {
                    let jitter = Vec2(rng.unit() * 0.4 - 0.2, rng.unit() * 0.4 - 0.2)
                    ids.append(spawn(kind, at: Vec2(center: p) + jitter, packID: packID))
                    break
                }
            }
        }
        return ids
    }

    private func randomAffixes(_ count: Int) -> [EliteAffix] {
        var pool = EliteAffix.allCases
        var out: [EliteAffix] = []
        for _ in 0..<count where !pool.isEmpty { out.append(pool.remove(at: rng.int(0...(pool.count - 1)))) }
        return out
    }

    /// First monster becomes a named unique with 1–3 affixes; the rest become its minions.
    public func makeUniquePack(_ ids: [EntityID]) {
        guard let first = ids.first else { return }
        let affixes = randomAffixes(rng.int(1...3))
        let name = UniqueNames.make(rng: &rng)
        for id in ids {
            guard let i = monsters.firstIndex(where: { $0.id == id }) else { continue }
            if id == first { monsters[i].promote(to: .unique, affixes: affixes, name: name) }
            else { monsters[i].promote(to: .minion, affixes: affixes.filter { $0 != .hulking }) }
        }
    }

    /// Champions come in packs of up to 4 sharing one affix.
    public func makeChampionPack(_ ids: [EntityID]) {
        let affix = randomAffixes(1)
        for (n, id) in ids.enumerated() {
            guard let i = monsters.firstIndex(where: { $0.id == id }) else { continue }
            if n < 4 { monsters[i].promote(to: .champion, affixes: affix) } else { monsters.remove(at: i) }
        }
    }

    @discardableResult
    public func spawn(_ kind: MonsterKind, at pos: Vec2, packID: Int = -1) -> EntityID {
        let id = makeID()
        monsters.append(Monster(id: id, kind: kind, at: pos, packID: packID, rng: &rng))
        return id
    }

    public func monster(_ id: EntityID) -> Monster? { monsters.first { $0.id == id } }

    // MARK: - Player commands

    public var playerAlive: Bool { player.stats.isAlive }

    public func commandMove(to p: Vec2) {
        guard playerAlive, player.action == .none else { return }
        player.target = nil
        player.mover.moveTo(p, on: level.map)
    }

    public func commandWalk(direction: Vec2, dt: Double) {
        guard playerAlive, player.action == .none else { return }
        player.target = nil
        player.mover.stop()
        player.mover.slide(direction.normalized * (player.mover.speed * dt), map: level.map)
    }

    public func commandAttack(_ id: EntityID, skill: String? = nil) {
        guard playerAlive, player.action == .none, monster(id)?.isAlive == true else { return }
        player.attackSkill = skill
        player.target = .monster(id)
        player.repathTimer = 0
    }

    public func spendStatPoint(_ a: Player.AttributeKind) { player.spendStatPoint(a) }

    public func drinkHealthPotion() {
        guard playerAlive, player.healthPotions > 0 else { return }
        player.healthPotions -= 1
        player.healPool += player.stats.maxLife * 0.45
        emit(.potion(health: true))
    }

    public func drinkManaPotion() {
        guard playerAlive, player.manaPotions > 0 else { return }
        player.manaPotions -= 1
        player.manaPool += player.stats.maxMana * 0.6
        emit(.potion(health: false))
    }

    /// Living monster under a world point (for mouse picking).
    public func monster(near p: Vec2, within r: Double = 0.6) -> Monster? {
        monsters.filter { $0.isAlive && $0.position.distance(to: p) <= r + $0.kind.radius }
            .min { $0.position.distance(to: p) < $1.position.distance(to: p) }
    }

    // MARK: - Tick

    public var exploredHere: Set<GridPoint> { explored[area.id] ?? [] }

    /// Mark tiles around the player as explored.
    func reveal() {
        let c = player.position.grid
        guard c != lastRevealCenter else { return }
        lastRevealCenter = c
        let r = Self.revealRadius
        var set = explored[area.id] ?? []
        for dy in -r...r { for dx in -r...r where dx * dx + dy * dy <= r * r {
            let p = GridPoint(c.x + dx, c.y + dy)
            if level.map.contains(p) && level.map[p] != .void { set.insert(p) }
        } }
        explored[area.id] = set
    }

    public func update(dt: Double) {
        time += dt
        reveal()
        updatePlayer(dt)
        for i in monsters.indices where monsters[i].isAlive { updateMonster(i, dt) }
        separateMonsters()
        updateProjectiles(dt)
        monsters.removeAll { m in m.deathTime.map { time - $0 > Self.corpseLifetime } ?? false }
    }

    private func updatePlayer(_ dt: Double) {
        if let died = player.deathTime {
            if time - died >= Self.respawnDelay { respawnPlayer() }
            return
        }
        // Regen + potion pools
        let heal = min(player.healPool, player.stats.maxLife * 0.45 * dt / 1.5)
        player.healPool -= heal
        let mana = min(player.manaPool, player.stats.maxMana * 0.6 * dt / 1.5)
        player.manaPool -= mana
        player.stats.life = min(player.stats.maxLife, player.stats.life + heal + player.stats.lifeRegen * dt)
        player.stats.mana = min(player.stats.maxMana, player.stats.mana + mana + player.stats.manaRegen * dt)

        player.attackCooldown -= dt
        updateBuffs(dt)
        if updateAction(dt) { return }
        autoPickupGold()
        if case .groundItem(let gid)? = player.target {
            if let g = groundItems.first(where: { $0.id == gid }) {
                if player.position.distance(to: g.position) <= 1.0 {
                    player.mover.stop()
                    player.target = nil
                    pickUp(gid)
                } else if !player.mover.isMoving {
                    if !player.mover.moveTo(g.position, on: level.map) { player.target = nil }
                }
            } else {
                player.target = nil
            }
        }
        if case .interactable(let iid)? = player.target {
            if let it = interactable(iid) {
                if player.position.distance(to: it.position) <= 1.4 {
                    player.mover.stop()
                    player.target = nil
                    interact(it)
                    return
                } else if !player.mover.isMoving {
                    if !player.mover.moveTo(it.position, on: level.map) { player.target = nil }
                }
            } else {
                player.target = nil
            }
        }
        if case .monster(let id)? = player.target {
            guard let idx = monsters.firstIndex(where: { $0.id == id }), monsters[idx].isAlive else {
                player.target = nil
                player.mover.stop()
                player.mover.update(dt: dt, map: level.map)
                return
            }
            let m = monsters[idx]
            let dist = player.position.distance(to: m.position)
            if dist > player.reach + m.kind.radius {
                player.repathTimer -= dt
                if player.repathTimer <= 0 || !player.mover.isMoving {
                    player.mover.moveTo(m.position, on: level.map)
                    player.repathTimer = 0.2
                }
            } else {
                player.mover.stop()
                player.mover.slide((m.position - player.position).normalized * 1e-4, map: level.map)
                if player.attackCooldown <= 0 {
                    player.attackCooldown = 1 / player.stats.attacksPerSecond
                    emit(.swing(attacker: nil, at: player.position, toward: m.position))
                    performMeleeAttack(on: idx)
                }
            }
        }
        let base = player.mover.speed
        if time < player.chilledUntil { player.mover.speed = base * 0.6 }
        player.mover.update(dt: dt, map: level.map)
        player.mover.speed = base
    }

    func apply(_ outcome: AttackOutcome, toMonsterAt idx: Int) {
        let pos = monsters[idx].position
        switch outcome {
        case .miss:
            emit(.miss(at: pos))
        case .blocked:
            emit(.blocked(at: pos))
        case .hit(let raw, let crit):
            let dmg = raw * (time < monsters[idx].vulnerableUntil ? 1 + monsters[idx].vulnerability / 100 : 1)
            if player.stats.lifeSteal > 0 {
                player.stats.life = min(player.stats.maxLife, player.stats.life + dmg * player.stats.lifeSteal / 100)
            }
            monsters[idx].stats.life -= dmg
            emit(.damage(at: pos, amount: Int(dmg.rounded()), crit: crit, toPlayer: false))
            if monsters[idx].ai == .idle { aggroPack(of: idx) }
            if !monsters[idx].isAlive { killMonster(idx) }
        }
    }

    private func killMonster(_ idx: Int) {
        monsters[idx].stats.life = 0
        monsters[idx].deathTime = time
        monsters[idx].mover.stop()
        let m = monsters[idx]
        if let q = m.questID, [.notStarted, .active].contains(player.quest(q)) { setQuest(q, .complete) }
        let xp = Experience.scaled(m.xpValue, monsterLevel: m.stats.level, playerLevel: player.level)
        emit(.monsterDied(m.id, at: m.position, xp: xp))
        if player.gainXP(xp) > 0 { emit(.levelUp(player.level)) }
        let picks = m.rank == .unique ? 3 : (m.rank == .champion ? 2 : 1)
        if m.kind.behavior == .boss {
            emit(.bossDefeated(m.displayName))
            interactables.append(Interactable(id: makeID(), kind: .areaExit(toArea: Areas.actOne[0].id, arrival: .entrance),
                                              position: m.position + Vec2(1.2, 1.2), name: "返回 芦苇渡口"))
        }
        dropLoot(LootTable.roll(monsterLevel: m.stats.level, isBoss: m.kind.behavior == .boss, picks: picks, guaranteedItem: m.rank == .unique,
                                goldFind: player.goldFind, magicFind: m.rank == .normal ? 0 : 50,
                                nextID: { self.makeID() }, rng: &rng), at: m.position)
        if m.affixes.contains(.fireTouched) {
            // Death explosion.
            emit(.nova("monster_fire", at: m.position, radius: 2))
            if playerAlive && player.position.distance(to: m.position) <= 2 {
                let raw = Double(rng.int(3...(8 + m.stats.level * 3)))
                damagePlayer(.hit(damage: Combat.mitigate(raw, type: .fire, defender: player.stats), crit: false))
            }
        }
        // Skittish packmates nearby may panic.
        for j in monsters.indices where monsters[j].isAlive && monsters[j].packID == m.packID
            && monsters[j].kind.behavior == .skittish && monsters[j].position.distance(to: m.position) < 6 {
            if rng.chance(0.35) { monsters[j].ai = .flee(until: time + 1.5 + rng.unit()) }
        }
    }

    private func aggroPack(of idx: Int) {
        let pack = monsters[idx].packID
        for j in monsters.indices where monsters[j].isAlive && monsters[j].ai == .idle
            && (j == idx || (pack >= 0 && monsters[j].packID == pack)) {
            monsters[j].ai = .chase
        }
    }

    private func damagePlayer(_ outcome: AttackOutcome) {
        guard playerAlive else { return }
        switch outcome {
        case .miss:
            emit(.miss(at: player.position))
        case .blocked:
            emit(.blocked(at: player.position))
        case .hit(let raw, let crit):
            var dmg = raw
            if player.absorbPool > 0 {
                let a = min(player.absorbPool, dmg)
                player.absorbPool -= a
                dmg -= a
                if player.absorbPool <= 0 { player.buffs.removeAll { $0.skillID == "sunshield" } }
                if dmg <= 0 { emit(.absorbed(at: player.position)); return }
            }
            player.stats.life -= dmg
            emit(.damage(at: player.position, amount: Int(dmg.rounded()), crit: crit, toPlayer: true))
            if player.stats.life <= 0 {
                player.stats.life = 0
                player.deathTime = time
                player.target = nil
                player.mover.stop()
                player.healPool = 0
                emit(.playerDied)
            }
        }
    }

    private func respawnPlayer() {
        player.deathTime = nil
        player.action = .none
        player.buffs.removeAll()
        player.absorbPool = 0
        player.frenzyStacks = 0
        player.recalculate()
        player.stats.life = player.stats.maxLife
        player.stats.mana = player.stats.maxMana
        var mover = Mover(position: Vec2(center: level.spawn), speed: player.mover.speed)
        mover.radius = player.mover.radius
        player.mover = mover
        for i in monsters.indices where monsters[i].isAlive {
            monsters[i].ai = .idle
            monsters[i].mover.moveTo(monsters[i].home, on: level.map)
        }
        emit(.playerRespawned)
    }

    // MARK: - Monster AI

    func canSee(_ from: Vec2, _ to: Vec2) -> Bool {
        Pathfinder.clearLine(on: level.map, from: from, to: to, radius: 0.05)
    }

    private func updateMonster(_ i: Int, _ dt: Double) {
        monsters[i].cooldown -= dt
        if time < monsters[i].stunnedUntil {
            monsters[i].mover.stop()
            return
        }
        let kind = monsters[i].kind
        let pos = monsters[i].position
        let ppos = player.position
        let dist = pos.distance(to: ppos)

        if !playerAlive {
            monsters[i].mover.update(dt: dt, map: level.map)
            return
        }

        switch monsters[i].ai {
        case .idle:
            if dist <= kind.aggroRadius && canSee(pos, ppos) { aggroPack(of: i) }

        case .flee(let until), .retreat(let until):
            if time >= until {
                monsters[i].ai = .chase
            } else {
                monsters[i].repathTimer -= dt
                if monsters[i].repathTimer <= 0 {
                    let away = (pos - ppos).normalized
                    monsters[i].mover.moveTo(pos + away * 3, on: level.map)
                    monsters[i].repathTimer = 0.3
                }
            }

        case .chase, .attack:
            let ranged = kind.behavior == .ranged || kind.behavior == .shaman
            if kind.behavior == .shaman { tryResurrect(i) }
            if kind.behavior == .boss { bossAbilities(i); if !playerAlive { break } }
            let range = ranged ? kind.reach : kind.reach + kind.radius + player.mover.radius
            let inRange = dist <= range && (!ranged || canSee(pos, ppos))
            if ranged && dist < 2.5 {
                // Kite away from the player.
                monsters[i].repathTimer -= dt
                if monsters[i].repathTimer <= 0 {
                    monsters[i].mover.moveTo(pos + (pos - ppos).normalized * 3, on: level.map)
                    monsters[i].repathTimer = 0.5
                }
                if monsters[i].cooldown <= 0 && canSee(pos, ppos) { monsterAttack(i) }
            } else if inRange {
                monsters[i].ai = .attack
                monsters[i].mover.stop()
                if monsters[i].cooldown <= 0 { monsterAttack(i) }
            } else {
                monsters[i].ai = .chase
                monsters[i].repathTimer -= dt
                if monsters[i].repathTimer <= 0 || !monsters[i].mover.isMoving {
                    monsters[i].mover.moveTo(ppos, on: level.map)
                    monsters[i].repathTimer = 0.35 + rng.unit() * 0.2
                }
                // Give up if the player escaped far away.
                if dist > kind.aggroRadius * 2.5 {
                    monsters[i].ai = .idle
                    monsters[i].mover.moveTo(monsters[i].home, on: level.map)
                }
            }
        }
        monsters[i].mover.update(dt: dt, map: level.map)
    }

    /// Shamans bring a dead packmate (or any nearby fallen non-undead) back to life.
    private func tryResurrect(_ i: Int) {
        guard monsters[i].resurrectCooldown <= time else { return }
        let pos = monsters[i].position
        guard let j = monsters.indices.first(where: {
            !monsters[$0].isAlive && monsters[$0].deathTime != nil && !monsters[$0].kind.isUndead
                && monsters[$0].kind.behavior != .shaman && monsters[$0].rank != .unique
                && monsters[$0].position.distance(to: pos) < 7 && monsters[$0].resurrections < 2
        }) else { return }
        monsters[i].resurrectCooldown = time + 4
        monsters[j].stats.life = monsters[j].stats.maxLife
        monsters[j].deathTime = nil
        monsters[j].resurrections += 1
        monsters[j].ai = .chase
        emit(.resurrected(monsters[j].id, by: monsters[i].id))
    }

    private func monsterAttack(_ i: Int) {
        let m = monsters[i]
        monsters[i].cooldown = 1 / m.stats.attacksPerSecond * (0.85 + rng.unit() * 0.3)
        emit(.swing(attacker: m.id, at: m.position, toward: player.position))
        if m.kind.behavior == .ranged || m.kind.behavior == .shaman {
            let dir = (player.position - m.position).normalized
            let speed = m.kind.projectile == .arrow ? 9.0 : 6.5
            projectiles.append(Projectile(id: makeID(), position: m.position + dir * 0.4, velocity: dir * speed,
                                          remaining: m.kind.reach + 3, faction: .monsters,
                                          attacker: m.stats, radius: m.kind.projectile == .arrow ? 0.15 : 0.25,
                                          visual: m.kind.projectile))
        } else {
            let outcome = Combat.resolveAttack(attacker: m.stats, defender: player.stats, rng: &rng)
            damagePlayer(outcome)
            if case .hit(let dmg, _) = outcome {
                if m.affixes.contains(.frostTouched) { player.chilledUntil = time + 2.5 }
                if m.affixes.contains(.manaBurn) { player.stats.mana = max(0, player.stats.mana - dmg) }
                if m.stats.lifeSteal > 0 {
                    monsters[i].stats.life = min(monsters[i].stats.maxLife, monsters[i].stats.life + dmg * m.stats.lifeSteal / 100)
                }
            }
            if case .hit = outcome, player.stats.thorns > 0 {
                apply(.hit(damage: player.stats.thorns, crit: false), toMonsterAt: i)
                if !monsters[i].isAlive { return }
            }
            if m.kind.behavior == .hitAndRun {
                monsters[i].ai = .retreat(until: time + 0.7 + rng.unit() * 0.6)
                monsters[i].repathTimer = 0
            }
        }
    }

    /// Cheap soft-body separation so packs don't stack on one tile.
    private func separateMonsters() {
        let alive = monsters.indices.filter { monsters[$0].isAlive }
        for a in 0..<alive.count {
            for b in (a + 1)..<max(a + 1, alive.count) {
                let i = alive[a], j = alive[b]
                let d = monsters[j].position - monsters[i].position
                let minD = monsters[i].kind.radius + monsters[j].kind.radius
                let len = d.length
                if len < minD && len > 1e-4 {
                    let push = d.normalized * ((minD - len) / 2)
                    monsters[i].mover.slide(push * -1, map: level.map)
                    monsters[j].mover.slide(push, map: level.map)
                }
            }
            // Also don't overlap the player.
            let i = alive[a]
            let d = monsters[i].position - player.position
            let minD = monsters[i].kind.radius + player.mover.radius
            if playerAlive && d.length < minD && d.length > 1e-4 {
                monsters[i].mover.slide(d.normalized * (minD - d.length), map: level.map)
            }
        }
    }

    // MARK: - Areas & interaction

    struct AreaState {
        var level: GeneratedLevel
        var monsters: [Monster]
        var groundItems: [GroundItem]
        var interactables: [Interactable]
    }

    public enum Arrival: Sendable, Equatable { case entrance, exit, waypoint, position(Vec2) }

    /// Populate the current (new) area: monsters, portals, waypoint, NPCs.
    private func enterFresh() {
        monsters = []
        groundItems = []
        projectiles = []
        interactables = []
        spawnMonsters(kinds: area.monsters)
        guard let idx = Areas.index(of: area.id) else { return }
        let all = Areas.actOne
        if idx + 1 < all.count, area.style != .arena {
            let next = all[idx + 1]
            interactables.append(Interactable(id: makeID(), kind: .areaExit(toArea: next.id, arrival: .entrance),
                                              position: Vec2(center: level.exit), name: "前往 " + next.name))
        }
        if idx > 0 {
            let prev = all[idx - 1]
            interactables.append(Interactable(id: makeID(), kind: .areaExit(toArea: prev.id, arrival: .exit),
                                              position: Vec2(center: level.spawn) + Vec2(-0.6, -0.6), name: "返回 " + prev.name))
        }
        if let wp = level.waypoint {
            interactables.append(Interactable(id: makeID(), kind: .waypoint, position: Vec2(center: wp), name: "传送小站"))
        }
        for (key, spot) in level.markers {
            guard let npc = NPCs.byMarker[key] else { continue }
            interactables.append(Interactable(id: makeID(), kind: .npc(npc.id), position: Vec2(center: spot), name: npc.name))
        }
        // Keep monsters away from the entrance.
        monsters.removeAll { $0.position.distance(to: Vec2(center: level.spawn)) < 8 }
        spawnQuestTargets()
        if area.style == .arena && [.notStarted, .active].contains(player.quest("q_abbess")) { spawnBoss() }
    }

    private func spawnBoss() {
        let spot = level.markers["boss"] ?? level.exit
        let id = spawn(Bestiary.abbess, at: Vec2(center: spot), packID: 9_999)
        guard let i = monsters.firstIndex(where: { $0.id == id }) else { return }
        monsters[i].promote(to: .unique, affixes: [], name: "溺亡院长 莫尔薇")
        monsters[i].questID = "q_abbess"
        monsters[i].abilityTimers = ["nova": time + 5, "summon": time + 8]
    }

    /// Boss specials: cold nova, summoning, enrage.
    private func bossAbilities(_ i: Int) {
        let m = monsters[i]
        let dist = m.position.distance(to: player.position)
        if !m.enraged && m.stats.lifeFraction < 0.5 {
            monsters[i].enraged = true
            monsters[i].mover.speed *= 1.4
            monsters[i].stats.attacksPerSecond *= 1.4
            emit(.nova("boss_enrage", at: m.position, radius: 1.5))
        }
        if time >= m.abilityTimers["nova", default: 0] && dist < 5 {
            monsters[i].abilityTimers["nova"] = time + (m.enraged ? 5 : 7)
            emit(.nova("boss_frost", at: m.position, radius: 4))
            if dist <= 4 {
                let raw = Double(rng.int(10...(22 + m.stats.level)))
                damagePlayer(.hit(damage: Combat.mitigate(raw, type: .cold, defender: player.stats), crit: false))
                player.chilledUntil = time + 3
            }
        }
        if time >= m.abilityTimers["summon", default: 0] {
            monsters[i].abilityTimers["summon"] = time + 12
            let alive = monsters.filter { $0.isAlive && $0.packID == 9_999 && $0.id != m.id }.count
            if alive < 6 {
                for k in 0..<2 {
                    let a = Double(k) * .pi + rng.unit()
                    var p = m.position + Vec2(cos(a), sin(a)) * 1.5
                    if !level.map.isWalkable(p.grid) { p = m.position }
                    let id = spawn(Bestiary.drownedSister.scaled(to: area.level), at: p, packID: 9_999)
                    if let j = monsters.firstIndex(where: { $0.id == id }) {
                        monsters[j].promote(to: .minion, affixes: [])
                        monsters[j].ai = .chase
                    }
                }
                emit(.nova("boss_summon", at: m.position, radius: 2))
            }
        }
    }

    /// Quest uniques live in the spawn spot farthest from the entrance.
    private func spawnQuestTargets() {
        for q in Quests.all where q.area == area.id && !q.isMain
            && [.notStarted, .active].contains(player.quest(q.id)) {
            let d = level.map.distances(from: level.spawn)
            let spot = level.rooms.map(\.center).filter { d[$0] != nil }.max { d[$0]! < d[$1]! } ?? level.exit
            let kind = q.targetKind.scaled(to: max(1, area.level) + 1)
            let id = spawn(kind, at: Vec2(center: spot), packID: 9_000)
            guard let i = monsters.firstIndex(where: { $0.id == id }) else { continue }
            monsters[i].promote(to: .unique, affixes: q.targetAffixes, name: q.targetName)
            monsters[i].questID = q.id
            // A few guards.
            for _ in 0..<3 {
                let gid = spawn(q.targetKind.scaled(to: max(1, area.level)), at: Vec2(center: spot) + Vec2(rng.unit() - 0.5, rng.unit() - 0.5), packID: 9_000)
                if let gi = monsters.firstIndex(where: { $0.id == gid }) { monsters[gi].promote(to: .minion, affixes: []) }
            }
        }
    }

    /// Talking to an NPC advances their quests. Returns lines to show.
    public func talkQuests(_ npc: String) -> [String] {
        var lines: [String] = []
        for q in Quests.given(by: npc) {
            switch player.quest(q.id) {
            case .notStarted:
                // Main quest only opens once the side quest chain has begun.
                setQuest(q.id, .active)
                lines.append("【新任务】\(q.name)")
                lines.append(q.intro)
                lines.append(q.rewardText)
                return lines
            case .complete:
                setQuest(q.id, .rewarded)
                grant(q.reward)
                lines.append("【任务完成】\(q.name)")
                lines.append(q.completion)
                lines.append(q.rewardText)
                return lines
            case .active, .rewarded:
                continue
            }
        }
        return lines
    }

    func setQuest(_ id: String, _ st: QuestState) {
        player.quests[id] = st
        emit(.questUpdated(id, st))
    }

    func grant(_ r: QuestReward) {
        switch r {
        case .skillPoint: player.skillPoints += 1
        case .statPoints(let n): player.statPoints += n
        case .experience(let n): if player.gainXP(n) > 0 { emit(.levelUp(player.level)) }
        case .rareItem(let lvl):
            let it = ItemGenerator().generate(id: makeID(), itemLevel: max(lvl, player.level), rng: &rng, forcedQuality: .rare,
                                             base: ItemBases.all.filter { $0.category == .weapon && $0.qlvl <= max(lvl, player.level) }.last)
            if !player.inventory.add(it) { dropLoot([.item(it)], at: player.position) }
        }
    }

    /// Move the player to another area. Leaving saves the current one.
    public func travel(to areaID: String, arrival: Arrival) {
        guard let target = Areas.def(areaID) else { return }
        visited[area.id] = AreaState(level: level, monsters: monsters, groundItems: groundItems, interactables: interactables)
        area = target
        if let saved = visited[areaID] {
            level = saved.level
            monsters = saved.monsters
            groundItems = saved.groundItems
            interactables = saved.interactables
            projectiles = []
        } else {
            level = LevelGenerator.generate(target, seed: Self.areaSeed(seed, target.id))
            enterFresh()
        }
        let spot: Vec2
        switch arrival {
        case .entrance: spot = arrivalSpot(near: level.spawn)
        case .exit: spot = arrivalSpot(near: level.exit)
        case .waypoint: spot = arrivalSpot(near: level.waypoint ?? level.spawn)
        case .position(let p): spot = p
        }
        var mover = Mover(position: spot, speed: player.mover.speed)
        mover.radius = player.mover.radius
        player.mover = mover
        player.target = nil
        player.action = .none
        if target.hasWaypoint { player.waypoints.insert(target.id) }
        if target.isTown {
            player.stats.life = player.stats.maxLife   // the camp's fire mends you
            restockVendors()
            if let portal = player.openPortal,
               !interactables.contains(where: { if case .townPortal = $0.kind { true } else { false } }) {
                interactables.append(Interactable(id: makeID(), kind: .townPortal(backArea: portal.area, backPosition: portal.position),
                                                  position: Vec2(center: level.spawn) + Vec2(1.5, -1.5),
                                                  name: "传送门 → " + (Areas.def(portal.area)?.name ?? "")))
            }
        }
        lastRevealCenter = nil
        emit(.areaEntered(target.id))
    }

    /// A walkable tile next to `p`, so the player doesn't land on top of a portal.
    private func arrivalSpot(near p: GridPoint) -> Vec2 {
        let d = level.map.distances(from: p)
        let ring = d.filter { $0.value == 2 }.map(\.key).sorted { ($0.x, $0.y) < ($1.x, $1.y) }
        return Vec2(center: ring.first ?? p)
    }

    public func interactable(_ id: Int) -> Interactable? { interactables.first { $0.id == id } }

    public func commandInteract(_ id: Int) {
        guard playerAlive, player.action == .none, let it = interactable(id) else { return }
        player.target = .interactable(id)
        if player.position.distance(to: it.position) > 1.4 { player.mover.moveTo(it.position, on: level.map) }
    }

    func interact(_ it: Interactable) {
        switch it.kind {
        case .areaExit(let to, let arrival):
            travel(to: to, arrival: arrival)
        case .waypoint:
            player.waypoints.insert(area.id)
            emit(.openWaypoints)
        case .npc(let npc):
            emit(.talk(npc))
        case .townPortal(let backArea, let backPos):
            if area.isTown {
                interactables.removeAll { if case .townPortal = $0.kind { true } else { false } }
                travel(to: backArea, arrival: .position(backPos))
                interactables.removeAll { if case .townPortal = $0.kind { true } else { false } }
                player.openPortal = nil
            } else {
                travel(to: Areas.actOne[0].id, arrival: .entrance)
            }
        }
    }

    /// Read a town portal scroll: opens a gate here back to camp.
    @discardableResult
    public func castTownPortal() -> Bool {
        guard playerAlive, !area.isTown, player.portalScrolls > 0 else { return false }
        player.portalScrolls -= 1
        interactables.removeAll { if case .townPortal = $0.kind { true } else { false } }
        player.openPortal = (area.id, player.position)
        interactables.append(Interactable(id: makeID(), kind: .townPortal(backArea: area.id, backPosition: player.position),
                                          position: player.position + Vec2(0.8, -0.8), name: "传送门 → 芦苇渡口"))
        return true
    }

    // MARK: - Trade

    public func restockVendors() {
        let lvl = max(2, player.level + 1)
        var smith = Inventory(width: 10, height: 8)
        let gen = ItemGenerator()
        for i in 0..<14 {
            let q: ItemQuality = i < 5 ? .magic : (rng.chance(0.3) ? .superior : .normal)
            let it = gen.generate(id: makeID(), itemLevel: lvl, rng: &rng, forcedQuality: q)
            if !it.base.category.isJewelry || q == .magic { smith.add(it) }
        }
        vendors["smith"] = smith
        var healer = Inventory(width: 10, height: 8)
        for _ in 0..<10 { healer.add(Item(id: makeID(), base: ItemBases.healthPotion)) }
        for _ in 0..<10 { healer.add(Item(id: makeID(), base: ItemBases.manaPotion)) }
        for _ in 0..<5 { healer.add(Item(id: makeID(), base: ItemBases.portalScroll)) }
        for _ in 0..<3 { healer.add(gen.generate(id: makeID(), itemLevel: lvl, rng: &rng, forcedQuality: .magic,
                                                 base: rng.chance(0.5) ? ItemBases.base("ring") : ItemBases.base("amulet"))) }
        vendors["healer"] = healer
    }

    /// Put a consumable into the belt counters, or the item into the bag.
    @discardableResult
    func stow(_ it: Item) -> Bool {
        switch it.baseID {
        case ItemBases.healthPotion.id where player.healthPotions < Player.beltCapacity: player.healthPotions += 1
        case ItemBases.manaPotion.id where player.manaPotions < Player.beltCapacity: player.manaPotions += 1
        case ItemBases.portalScroll.id: player.portalScrolls += 1
        default: return player.inventory.add(it)
        }
        return true
    }

    public func buy(from npc: String, itemID: Int) {
        guard var stock = vendors[npc], let it = stock.items.first(where: { $0.id == itemID }) else { return }
        guard player.gold >= it.price else { emit(.notEnoughGold); return }
        // Consumables are restocked infinitely: buy a copy.
        let bought = it.isPotion ? Item(id: makeID(), base: it.base) : it
        guard stow(bought) else { emit(.inventoryFull); return }
        player.gold -= it.price
        if !it.isPotion { stock.remove(id: itemID); vendors[npc] = stock }
        emit(.bought(it.displayName))
    }

    public func sell(itemID: Int, to npc: String) {
        guard let it = player.inventory.remove(id: itemID) else { return }
        player.gold += it.sellPrice
        if !it.isPotion, var stock = vendors[npc] { stock.add(it); vendors[npc] = stock }
        emit(.sold(it.displayName, it.sellPrice))
    }

    // MARK: - Stash

    /// Move an item between bag and stash.
    public func moveToStash(itemID: Int) {
        guard let e = player.inventory.entries.first(where: { $0.item.id == itemID }) else { return }
        guard player.stash.firstFit(e.item.base.size) != nil else { emit(.inventoryFull); return }
        player.inventory.remove(id: itemID)
        player.stash.add(e.item)
    }

    public func moveFromStash(itemID: Int) {
        guard let e = player.stash.entries.first(where: { $0.item.id == itemID }) else { return }
        guard player.inventory.firstFit(e.item.base.size) != nil else { emit(.inventoryFull); return }
        player.stash.remove(id: itemID)
        player.inventory.add(e.item)
    }

    /// Waypoint travel to an already discovered area.
    public func useWaypoint(to areaID: String) {
        guard player.waypoints.contains(areaID) else { return }
        travel(to: areaID, arrival: .waypoint)
    }

    // MARK: - Items

    public func dropLoot(_ drops: [LootTable.Drop], at pos: Vec2) {
        for (n, d) in drops.enumerated() {
            let angle = Double(n) * 2.4 + rng.unit()
            var p = pos + Vec2(cos(angle), sin(angle)) * (0.3 + 0.35 * Double(n % 3))
            if !level.map.isWalkable(p.grid) { p = pos }
            let id = makeID()
            switch d {
            case .gold(let g): groundItems.append(GroundItem(id: id, position: p, content: .gold(g)))
            case .item(let it): groundItems.append(GroundItem(id: id, position: p, content: .item(it)))
            }
            emit(.itemDropped(id))
        }
    }

    public func commandPickUp(_ groundID: Int) {
        guard playerAlive, let g = groundItems.first(where: { $0.id == groundID }) else { return }
        player.target = .groundItem(groundID)
        if player.position.distance(to: g.position) > 1.0 { player.mover.moveTo(g.position, on: level.map) }
    }

    private func autoPickupGold() {
        for g in groundItems {
            if case .gold = g.content, player.position.distance(to: g.position) < 0.7 { pickUp(g.id) }
        }
    }

    private func pickUp(_ gid: Int) {
        guard let i = groundItems.firstIndex(where: { $0.id == gid }) else { return }
        switch groundItems[i].content {
        case .gold(let n):
            player.gold += n
            groundItems.remove(at: i)
            emit(.pickedUp("\(n) 金币"))
        case .item(let it):
            if !stow(it) {
                emit(.inventoryFull)
                return
            }
            groundItems.remove(at: i)
            emit(.pickedUp(it.displayName))
        }
    }

    public func groundItem(near p: Vec2, within r: Double = 0.5) -> GroundItem? {
        groundItems.filter { $0.position.distance(to: p) <= r }.min { $0.position.distance(to: p) < $1.position.distance(to: p) }
    }

    /// Drop the cursor item at the player's feet.
    public func dropCursor() {
        guard let it = player.cursor else { return }
        player.cursor = nil
        let id = makeID()
        groundItems.append(GroundItem(id: id, position: player.position + Vec2(0.3, 0.3), content: .item(it)))
        emit(.itemDropped(id))
    }

    /// Lift an inventory item onto the cursor (or swap with the cursor item if it fits there).
    public func inventoryClick(x: Int, y: Int) {
        if let held = player.cursor {
            let r = player.inventory.placeSwapping(held, x: x, y: y)
            if r.ok { player.cursor = r.displaced }
        } else if let e = player.inventory.entry(at: x, y) {
            player.cursor = player.inventory.remove(id: e.item.id)
        }
    }

    /// Click an equipment slot: equip cursor item there (swapping), or lift the equipped item.
    public func equipmentClick(_ slot: EquipSlot) {
        if let held = player.cursor {
            guard EquipSlot.slots(for: held.base.category).contains(slot) else { return }
            guard player.canEquip(held) else { emit(.cannotEquip(held.displayName)); return }
            player.cursor = player.equipment[slot]
            player.equipment[slot] = held
        } else if let it = player.equipment.removeValue(forKey: slot) {
            player.cursor = it
        }
        player.recalculate()
    }

    /// Right-click: use a potion or quick-equip from the inventory.
    public func inventoryUse(itemID: Int) {
        guard let e = player.inventory.entries.first(where: { $0.item.id == itemID }) else { return }
        let it = e.item
        if it.baseID == ItemBases.healthPotion.id {
            player.inventory.remove(id: it.id); player.healthPotions += 1; drinkHealthPotion(); return
        }
        if it.baseID == ItemBases.manaPotion.id {
            player.inventory.remove(id: it.id); player.manaPotions += 1; drinkManaPotion(); return
        }
        guard let slot = player.preferredSlot(for: it) else { return }
        guard player.canEquip(it) else { emit(.cannotEquip(it.displayName)); return }
        player.inventory.remove(id: it.id)
        if let old = player.equipment[slot] {
            if !player.inventory.place(old, x: e.x, y: e.y) && !player.inventory.add(old) {
                // No room for the old item: undo.
                player.inventory.place(it, x: e.x, y: e.y)
                emit(.inventoryFull)
                return
            }
        }
        player.equipment[slot] = it
        player.recalculate()
    }

    /// Right-click on an equipped item: move it to the inventory.
    public func unequip(_ slot: EquipSlot) {
        guard let it = player.equipment[slot] else { return }
        guard player.inventory.add(it) else { emit(.inventoryFull); return }
        player.equipment[slot] = nil
        player.recalculate()
    }

    // MARK: - Projectiles

    private func updateProjectiles(_ dt: Double) {
        var keep: [Projectile] = []
        for var p in projectiles {
            let step = p.velocity * dt
            p.position = p.position + step
            p.remaining -= step.length
            if p.remaining <= 0 || !level.map.isWalkable(p.position.grid) { continue }
            switch p.faction {
            case .monsters:
                if playerAlive && p.position.distance(to: player.position) < p.radius + player.mover.radius {
                    damagePlayer(Combat.resolveAttack(attacker: p.attacker, defender: player.stats, rng: &rng))
                    continue
                }
            case .player:
                if let idx = monsters.firstIndex(where: {
                    $0.isAlive && $0.position.distance(to: p.position) < p.radius + $0.kind.radius
                }) {
                    apply(Combat.resolveAttack(attacker: p.attacker, defender: monsters[idx].stats, rng: &rng),
                          toMonsterAt: idx)
                    continue
                }
            }
            keep.append(p)
        }
        projectiles = keep
    }
}
