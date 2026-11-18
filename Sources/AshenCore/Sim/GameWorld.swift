/// The authoritative simulation. Rendering only reads from it and feeds it commands.
import Foundation

public final class GameWorld {
    public private(set) var level: GeneratedLevel
    public var player: Player
    public private(set) var monsters: [Monster] = []
    public private(set) var projectiles: [Projectile] = []
    public private(set) var groundItems: [GroundItem] = []
    public private(set) var time = 0.0
    private var pendingEvents: [GameEvent] = []
    private var rng: SeededRNG
    private var nextID: EntityID = 1

    public static let respawnDelay = 2.5
    public static let corpseLifetime = 30.0

    public init(seed: UInt64, monsterKinds: [MonsterKind] = Bestiary.actOne, populate: Bool = true) {
        rng = SeededRNG(seed: seed ^ 0xA5A5_5A5A)
        level = DungeonGenerator().generate(seed: seed)
        player = .newHero(at: Vec2(center: level.spawn))
        giveStartingGear()
        if populate { spawnMonsters(kinds: monsterKinds) }
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
        rng = SeededRNG(seed: seed)
        self.level = level
        player = .newHero(at: Vec2(center: level.spawn))
    }

    public func drainEvents() -> [GameEvent] {
        defer { pendingEvents.removeAll() }
        return pendingEvents
    }

    private func emit(_ e: GameEvent) { pendingEvents.append(e) }

    private func makeID() -> EntityID { defer { nextID += 1 }; return nextID }

    // MARK: - Spawning

    private func spawnMonsters(kinds: [MonsterKind]) {
        var packID = 0
        for room in level.rooms.dropFirst() {           // keep the spawn room safe
            let packs = room.w * room.h > 60 ? 2 : 1
            for _ in 0..<packs {
                let kind = kinds[rng.int(0...(kinds.count - 1))]
                spawnPack(kind: kind, in: room, packID: packID)
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
        guard playerAlive else { return }
        player.target = nil
        player.mover.moveTo(p, on: level.map)
    }

    public func commandWalk(direction: Vec2, dt: Double) {
        guard playerAlive else { return }
        player.target = nil
        player.mover.stop()
        player.mover.slide(direction.normalized * (player.mover.speed * dt), map: level.map)
    }

    public func commandAttack(_ id: EntityID) {
        guard playerAlive, monster(id)?.isAlive == true else { return }
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

    public func update(dt: Double) {
        time += dt
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
                    let outcome = Combat.resolveAttack(attacker: player.stats, defender: m.stats, rng: &rng)
                    apply(outcome, toMonsterAt: idx)
                }
            }
        }
        player.mover.update(dt: dt, map: level.map)
    }

    private func apply(_ outcome: AttackOutcome, toMonsterAt idx: Int) {
        let pos = monsters[idx].position
        switch outcome {
        case .miss:
            emit(.miss(at: pos))
        case .blocked:
            emit(.blocked(at: pos))
        case .hit(let dmg, let crit):
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
        let xp = Experience.scaled(m.kind.xp, monsterLevel: m.stats.level, playerLevel: player.level)
        emit(.monsterDied(m.id, at: m.position, xp: xp))
        if player.gainXP(xp) > 0 { emit(.levelUp(player.level)) }
        dropLoot(LootTable.roll(monsterLevel: m.kind.level, goldFind: player.goldFind,
                                nextID: { self.makeID() }, rng: &rng), at: m.position)
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
        case .hit(let dmg, let crit):
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

    private func canSee(_ from: Vec2, _ to: Vec2) -> Bool {
        Pathfinder.clearLine(on: level.map, from: from, to: to, radius: 0.05)
    }

    private func updateMonster(_ i: Int, _ dt: Double) {
        monsters[i].cooldown -= dt
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
            let range = kind.behavior == .ranged ? kind.reach : kind.reach + kind.radius + player.mover.radius
            let inRange = dist <= range && (kind.behavior != .ranged || canSee(pos, ppos))
            if kind.behavior == .ranged && dist < 2.5 {
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

    private func monsterAttack(_ i: Int) {
        let m = monsters[i]
        monsters[i].cooldown = 1 / m.stats.attacksPerSecond * (0.85 + rng.unit() * 0.3)
        emit(.swing(attacker: m.id, at: m.position, toward: player.position))
        if m.kind.behavior == .ranged {
            let dir = (player.position - m.position).normalized
            projectiles.append(Projectile(id: makeID(), position: m.position + dir * 0.4, velocity: dir * 9,
                                          remaining: m.kind.reach + 3, faction: .monsters,
                                          attacker: m.stats, radius: 0.15))
        } else {
            let outcome = Combat.resolveAttack(attacker: m.stats, defender: player.stats, rng: &rng)
            damagePlayer(outcome)
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
            if it.baseID == ItemBases.healthPotion.id && player.healthPotions < Player.beltCapacity {
                player.healthPotions += 1
            } else if it.baseID == ItemBases.manaPotion.id && player.manaPotions < Player.beltCapacity {
                player.manaPotions += 1
            } else if !player.inventory.add(it) {
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
