/// The authoritative simulation. Rendering only reads from it and feeds it commands.
public final class GameWorld {
    public private(set) var level: GeneratedLevel
    public var player: Player
    public private(set) var monsters: [Monster] = []
    public private(set) var projectiles: [Projectile] = []
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
        if populate { spawnMonsters(kinds: monsterKinds) }
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
        case .hit(let dmg, let crit):
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
        player.xp += m.kind.xp
        emit(.monsterDied(m.id, at: m.position, xp: m.kind.xp))
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
        player.mover = Mover(position: Vec2(center: level.spawn), speed: player.mover.speed)
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
            damagePlayer(Combat.resolveAttack(attacker: m.stats, defender: player.stats, rng: &rng))
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
