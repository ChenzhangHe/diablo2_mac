/// Skill execution: casting, melee skill attacks, charge / whirl movement, novas and buffs.
extension GameWorld {
    public enum CastResult: Equatable { case ok, notLearned, noMana, cooldown, needsShield, needsTarget, busy }

    /// Use a skill. `target` is the monster under the cursor (if any), `point` the cursor in world space.
    @discardableResult
    public func castSkill(_ id: String, target: EntityID?, point: Vec2) -> CastResult {
        guard playerAlive, let def = Skills.def(id) else { return .notLearned }
        guard player.action == .none else { return .busy }
        let lv = player.skills.level(id)
        guard lv > 0, def.isActive else { return .notLearned }
        if def.requiresShield && !player.hasShield { emit(.skillUnavailable("需要盾牌")); return .needsShield }
        if (player.cooldowns[id] ?? 0) > time { emit(.skillUnavailable("冷却中")); return .cooldown }
        let n = player.skills.numbers(id)

        switch def.kind {
        case .meleeAttack:
            // Mana is paid per swing in performMeleeAttack.
            guard let t = target, monster(t)?.isAlive == true else {
                if let near = monster(near: point, within: 1.0) { commandAttack(near.id, skill: id); return .ok }
                return .needsTarget
            }
            commandAttack(t, skill: id)
            return .ok

        case .charge:
            guard let t = target, let m = monster(t), m.isAlive else { return .needsTarget }
            guard spendMana(n.manaCost) else { return .noMana }
            player.target = nil
            player.action = .charging(target: t, until: time + 1.6)
            player.mover.speed = player.mover.speed * 3
            player.mover.moveTo(m.position, on: level.map)
            emit(.skillUsed(id, at: player.position, toward: m.position))
            return .ok

        case .whirl:
            guard spendMana(n.manaCost) else { return .noMana }
            player.target = nil
            var dest = point
            if dest.distance(to: player.position) > 6 { dest = player.position + (dest - player.position).normalized * 6 }
            player.action = .whirling(dest: dest, nextTick: time, until: time + 1.5)
            player.mover.speed = 7
            player.mover.moveTo(dest, on: level.map)
            emit(.skillUsed(id, at: player.position, toward: dest))
            return .ok

        case .nova:
            guard spendMana(n.manaCost) else { return .noMana }
            if n.cooldown > 0 { player.cooldowns[id] = time + n.cooldown }
            performNova(id, n)
            return .ok

        case .buff:
            guard spendMana(n.manaCost) else { return .noMana }
            if n.cooldown > 0 { player.cooldowns[id] = time + n.cooldown }
            player.buffs.removeAll { $0.skillID == id }
            player.buffs.append(Buff(skillID: id, expires: time + n.duration, modifiers: n.modifiers))
            if id == "sunshield" { player.absorbPool = n.absorb }
            let lifeFrac = player.stats.lifeFraction
            player.recalculate()
            if id == "war_horn" { player.stats.life = player.stats.maxLife * lifeFrac }
            emit(.skillUsed(id, at: player.position, toward: player.position))
            return .ok

        case .passive:
            return .notLearned
        }
    }

    private func spendMana(_ cost: Double) -> Bool {
        guard player.stats.mana >= cost else { emit(.notEnoughMana); return false }
        player.stats.mana -= cost
        return true
    }

    /// Player stats modified by a skill's damage / AR / fire bonuses.
    func attackStats(_ n: SkillNumbers) -> CombatStats {
        var a = player.stats
        a.minDamage *= max(0.1, 1 + n.damagePercent / 100)
        a.maxDamage *= max(0.1, 1 + n.damagePercent / 100)
        a.attackRating *= 1 + n.attackRatingPercent / 100
        if n.fireMax > 0 { a.elemental.append(ElementalDamage(.fire, n.fireMin, n.fireMax)) }
        return a
    }

    @discardableResult
    func strike(_ idx: Int, with a: CombatStats) -> AttackOutcome {
        let outcome = Combat.resolveAttack(attacker: a, defender: monsters[idx].stats, rng: &rng)
        apply(outcome, toMonsterAt: idx)
        return outcome
    }

    func stun(_ idx: Int, for d: Double) {
        guard monsters[idx].isAlive else { return }
        monsters[idx].stunnedUntil = max(monsters[idx].stunnedUntil, time + d)
        emit(.stunned(monsters[idx].id))
    }

    func knockback(_ idx: Int, from p: Vec2, distance: Double) {
        guard monsters[idx].isAlive else { return }
        let dir = (monsters[idx].position - p).normalized
        for _ in 0..<5 { monsters[idx].mover.slide(dir * (distance / 5), map: level.map) }
    }

    /// The swing used against the current target: a skill if one is set and affordable, else a basic attack.
    func performMeleeAttack(on idx: Int) {
        let id = player.attackSkill
        let n = id.map { player.skills.numbers($0) } ?? SkillNumbers()
        let usable = id != nil && player.stats.mana >= n.manaCost
            && !(Skills.def(id!)?.requiresShield == true && !player.hasShield)
        guard usable, let skill = id else {
            if id != nil && player.stats.mana < n.manaCost { emit(.notEnoughMana) }
            strike(idx, with: player.stats)
            return
        }
        player.stats.mana -= n.manaCost
        emit(.skillUsed(skill, at: player.position, toward: monsters[idx].position))
        let a = attackStats(n)
        switch skill {
        case "shield_bash":
            if case .hit = strike(idx, with: a) {
                if rng.chance(n.stunChance) { stun(idx, for: n.stunDuration) }
                knockback(idx, from: player.position, distance: 0.8)
            }
        case "cleave":
            let center = monsters[idx].position
            let fwd = (center - player.position).normalized
            for j in monsters.indices where monsters[j].isAlive {
                let d = monsters[j].position - player.position
                let inArc = j == idx || (d.length <= n.radius + monsters[j].kind.radius
                                         && (d.normalized.x * fwd.x + d.normalized.y * fwd.y) > 0.1)
                if inArc { strike(j, with: a) }
            }
        case "frenzied_blows":
            if case .hit = strike(idx, with: a) {
                player.frenzyStacks = min(5, player.frenzyStacks + 1)
                player.frenzyExpires = time + n.duration
                player.recalculate()
            }
        default: // flame_strike and any other plain skill attack
            strike(idx, with: a)
        }
    }

    func performNova(_ id: String, _ n: SkillNumbers) {
        emit(.nova(id, at: player.position, radius: n.radius))
        let inRange = monsters.indices.filter {
            monsters[$0].isAlive && monsters[$0].position.distance(to: player.position) <= n.radius + monsters[$0].kind.radius
        }
        for i in inRange {
            switch id {
            case "dread_howl":
                monsters[i].ai = .flee(until: time + n.stunDuration)
                monsters[i].repathTimer = 0
            case "quake_cry":
                let raw = n.physMin + (n.physMax - n.physMin) * rng.unit()
                apply(.hit(damage: max(1, Combat.mitigate(raw, type: .physical, defender: monsters[i].stats)), crit: false),
                      toMonsterAt: i)
                stun(i, for: n.stunDuration)
            case "ash_oath":
                monsters[i].vulnerableUntil = time + n.duration
                monsters[i].vulnerability = n.vulnerability
                if monsters[i].ai == .idle { monsters[i].ai = .chase }
            case "cinder_nova":
                let raw = n.fireMin + (n.fireMax - n.fireMin) * rng.unit()
                apply(.hit(damage: max(1, Combat.mitigate(raw, type: .fire, defender: monsters[i].stats)), crit: false),
                      toMonsterAt: i)
            default:
                break
            }
        }
    }

    /// Expire buffs and frenzy stacks.
    func updateBuffs(_ dt: Double) {
        var changed = false
        if player.buffs.contains(where: { $0.expires <= time }) {
            if player.buffs.contains(where: { $0.skillID == "sunshield" && $0.expires <= time }) { player.absorbPool = 0 }
            player.buffs.removeAll { $0.expires <= time }
            changed = true
        }
        if player.frenzyStacks > 0 && time >= player.frenzyExpires {
            player.frenzyStacks = 0
            changed = true
        }
        if changed { player.recalculate() }
    }

    /// Drive charge / whirl. Returns true if the action consumed this tick.
    func updateAction(_ dt: Double) -> Bool {
        switch player.action {
        case .none:
            return false

        case .charging(let tid, let until):
            guard let idx = monsters.firstIndex(where: { $0.id == tid }), monsters[idx].isAlive, time < until else {
                endAction(); return true
            }
            let m = monsters[idx]
            if player.position.distance(to: m.position) <= player.reach + m.kind.radius {
                let n = player.skills.numbers("ember_charge")
                emit(.swing(attacker: nil, at: player.position, toward: m.position))
                if case .hit = strike(idx, with: attackStats(n)) {
                    knockback(idx, from: player.position, distance: 1.5)
                    if rng.chance(n.stunChance) { stun(idx, for: n.stunDuration) }
                }
                endAction()
                player.target = .monster(tid)
                player.attackCooldown = 0.3
                return true
            }
            if !player.mover.isMoving { player.mover.moveTo(m.position, on: level.map) }
            player.mover.update(dt: dt, map: level.map)
            return true

        case .whirling(let dest, let nextTick, let until):
            if time >= nextTick {
                let n = player.skills.numbers("ember_whirl")
                let a = attackStats(n)
                for j in monsters.indices where monsters[j].isAlive
                    && monsters[j].position.distance(to: player.position) <= n.radius + monsters[j].kind.radius {
                    strike(j, with: a)
                }
                player.action = .whirling(dest: dest, nextTick: time + 0.2, until: until)
            }
            player.mover.update(dt: dt, map: level.map)
            if !player.mover.isMoving || time >= until { endAction() }
            return true
        }
    }

    private func endAction() {
        player.action = .none
        player.mover.stop()
        player.recalculate()   // restores normal move speed
    }
}
