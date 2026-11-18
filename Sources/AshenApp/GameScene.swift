import AppKit
import SpriteKit
import AshenCore

final class GameScene: SKScene {
    private let worldNode = SKNode()
    private let cam = SKCameraNode()
    private var vignette: SKSpriteNode?
    private let infoLabel = SKLabelNode(fontNamed: "Menlo")
    private let hud = HUD()
    private let inventoryPanel = InventoryPanel()
    private let characterPanel = CharacterPanel()
    private let tooltip = Tooltip()
    private var cursorIcon: SKNode?
    private var cursorItemID: Int?
    private var groundNodes: [Int: GroundItemNode] = [:]
    private var hoveredGround: Int?
    private let messages = SKNode()

    private var seed: UInt64 = 1
    private var game: GameWorld!
    private let player = PlayerNode()
    private var monsterNodes: [EntityID: MonsterNode] = [:]
    private var projectileNodes: [EntityID: SKNode] = [:]
    private var walls: [GridPoint: SKSpriteNode] = [:]
    private var fadedWalls: Set<GridPoint> = []

    private var keys = Set<String>()
    private var lastTime: TimeInterval = 0
    private var mouseHeld = false
    private var lastMouseInView: CGPoint?
    private var repathTimer = 0.0
    private var hovered: EntityID?
    private let debugAutofight = ProcessInfo.processInfo.environment["ASHEN_DEBUG_AUTOFIGHT"] != nil

    override func didMove(to view: SKView) {
        backgroundColor = NSColor(calibratedWhite: 0.02, alpha: 1)
        view.window?.acceptsMouseMovedEvents = true
        addChild(worldNode)
        camera = cam
        addChild(cam)

        infoLabel.fontSize = 12
        infoLabel.fontColor = NSColor(calibratedRed: 0.85, green: 0.78, blue: 0.6, alpha: 0.8)
        infoLabel.horizontalAlignmentMode = .left
        infoLabel.verticalAlignmentMode = .top
        infoLabel.zPosition = 20_001
        cam.addChild(infoLabel)
        cam.addChild(hud)
        inventoryPanel.isHidden = true
        characterPanel.isHidden = true
        cam.addChild(inventoryPanel)
        cam.addChild(characterPanel)
        cam.addChild(tooltip)
        messages.zPosition = 20_002
        cam.addChild(messages)

        buildLevel()
        layoutOverlay()
    }

    override func didChangeSize(_ oldSize: CGSize) { layoutOverlay() }

    private func layoutOverlay() {
        guard size.width > 0 else { return }
        vignette?.removeFromParent()
        let v = SKSpriteNode(texture: Textures.vignette(size: size, radius: min(size.width, size.height) * 0.62))
        v.size = size
        v.zPosition = 10_000
        cam.addChild(v)
        vignette = v
        infoLabel.position = CGPoint(x: -size.width / 2 + 12, y: size.height / 2 - 12)
        hud.layout(size: size)
        inventoryPanel.position = CGPoint(x: size.width / 2 - InventoryPanel.size.width / 2 - 12, y: 30)
        characterPanel.position = CGPoint(x: -size.width / 2 + CharacterPanel.size.width / 2 + 12, y: 30)
        messages.position = CGPoint(x: 0, y: -size.height / 2 + 90)
    }

    // MARK: - Level

    private func buildLevel() {
        worldNode.removeAllChildren()
        walls.removeAll()
        fadedWalls.removeAll()
        monsterNodes.removeAll()
        projectileNodes.removeAll()
        groundNodes.removeAll()

        game = GameWorld(seed: seed)
        let map = game.level.map
        var rng = SeededRNG(seed: seed &* 31)

        for p in map.allPoints {
            let pos = screen(Vec2(center: p))
            switch map[p] {
            case .floor, .door:
                let n = SKSpriteNode(texture: Textures.floors[rng.int(0...3)])
                n.size = CGSize(width: Iso.tileWidth, height: Iso.tileHeight)
                n.position = pos
                n.zPosition = -1
                worldNode.addChild(n)
            case .wall:
                let n = SKSpriteNode(texture: Textures.wall)
                n.size = CGSize(width: Textures.tw, height: Textures.th + Textures.wallHeight)
                n.anchorPoint = Textures.wallAnchor
                n.position = pos
                n.zPosition = depthZ(Vec2(center: p))
                worldNode.addChild(n)
                walls[p] = n
            case .void:
                break
            }
        }

        let portal = SKSpriteNode(texture: Textures.portal)
        portal.position = screen(Vec2(center: game.level.exit))
        portal.zPosition = -0.5
        portal.run(.repeatForever(.sequence([.fadeAlpha(to: 0.4, duration: 0.9), .fadeAlpha(to: 1, duration: 0.9)])))
        worldNode.addChild(portal)

        player.setDead(false)
        worldNode.addChild(player)
        if ProcessInfo.processInfo.environment["ASHEN_DEBUG_WALK_TO_EXIT"] != nil {
            game.commandMove(to: Vec2(center: game.level.exit))
        }
        if ProcessInfo.processInfo.environment["ASHEN_DEBUG_LOOT"] != nil { debugLoot() }
        syncWorld()
        infoLabel.text = "灰烬圣印 Ashen Sigil · M3   seed \(seed)   左键 移动/攻击/拾取 · 1/2 药剂 · I 物品栏 · C 角色 · R 新地图"
    }

    private func debugLoot() {
        var rng = SeededRNG(seed: 77)
        let gen = ItemGenerator()
        for i in 0..<8 {
            let q: ItemQuality = i % 3 == 0 ? .rare : .magic
            game.player.inventory.add(gen.generate(id: 50_000 + i, itemLevel: 12, rng: &rng, forcedQuality: q))
        }
        var drops: [LootTable.Drop] = [.gold(37)]
        for i in 0..<4 { drops.append(.item(gen.generate(id: 60_000 + i, itemLevel: 8, rng: &rng))) }
        game.dropLoot(drops, at: game.player.position + Vec2(1.5, 1.5))
        game.player.gainXP(500)
        inventoryPanel.isHidden = false
        characterPanel.isHidden = false
        DispatchQueue.main.async { [self] in
            // Hover the first inventory item so the tooltip shows.
            let cp = CGPoint(x: inventoryPanel.position.x - 130, y: inventoryPanel.position.y - 75)
            if let v = view { lastMouseInView = v.convert(CGPoint(x: cp.x + cam.position.x, y: cp.y + cam.position.y), from: self) }
        }
    }

    // MARK: - Coordinates

    private func screen(_ p: Vec2) -> CGPoint {
        let s = Iso.toScreen(p)
        return CGPoint(x: s.x, y: s.y)
    }

    private func depthZ(_ p: Vec2) -> CGFloat { CGFloat(Iso.depth(p)) }

    // MARK: - Loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastTime == 0 ? 0 : min(currentTime - lastTime, 0.05)
        lastTime = currentTime

        var dir = Vec2.zero
        if keys.contains("w") || keys.contains("up") { dir = dir + Vec2(-1, -1) }
        if keys.contains("s") || keys.contains("down") { dir = dir + Vec2(1, 1) }
        if keys.contains("a") || keys.contains("left") { dir = dir + Vec2(-1, 1) }
        if keys.contains("d") || keys.contains("right") { dir = dir + Vec2(1, -1) }

        if dir.length > 0 {
            game.commandWalk(direction: dir, dt: dt)
        } else if mouseHeld && game.player.target == nil {
            repathTimer -= dt
            if repathTimer <= 0, let t = mouseWorldPoint() {
                game.commandMove(to: t)
                repathTimer = 0.12
            }
        }

        if debugAutofight, game.player.target == nil, let m = game.monsters.filter({ $0.isAlive })
            .min(by: { $0.position.distance(to: game.player.position) < $1.position.distance(to: game.player.position) }) {
            game.commandAttack(m.id)
        }

        game.update(dt: dt)
        handleEvents()
        updateHover()
        syncWorld()
    }

    private func syncWorld() {
        let p = game.player
        player.position = screen(p.position)
        player.zPosition = depthZ(p.position)
        player.face(p.mover.facing)
        player.setWalking(p.mover.isMoving && game.playerAlive)
        cam.position = player.position
        updateWallFade()

        var alive = Set<EntityID>()
        for m in game.monsters {
            alive.insert(m.id)
            let node = monsterNodes[m.id] ?? {
                let n = MonsterNode(monster: m)
                worldNode.addChild(n)
                monsterNodes[m.id] = n
                return n
            }()
            node.position = screen(m.position)
            if m.isAlive {
                node.zPosition = depthZ(m.position)
                node.face(m.mover.facing)
            } else {
                node.die()
            }
        }
        for (id, node) in monsterNodes where !alive.contains(id) {
            node.run(.sequence([.fadeOut(withDuration: 0.5), .removeFromParent()]))
            monsterNodes[id] = nil
        }

        var live = Set<EntityID>()
        for pr in game.projectiles {
            live.insert(pr.id)
            let node = projectileNodes[pr.id] ?? {
                let n = SKShapeNode(rectOf: CGSize(width: 16, height: 2))
                n.fillColor = NSColor(calibratedRed: 0.9, green: 0.85, blue: 0.7, alpha: 1)
                n.strokeColor = .clear
                worldNode.addChild(n)
                projectileNodes[pr.id] = n
                return n
            }()
            node.position = screen(pr.position) + CGPoint(x: 0, y: 20)
            node.zPosition = depthZ(pr.position)
            let v = Iso.toScreen(pr.velocity)
            node.zRotation = atan2(CGFloat(v.y), CGFloat(v.x))
        }
        for (id, node) in projectileNodes where !live.contains(id) {
            node.removeFromParent()
            projectileNodes[id] = nil
        }

        var present = Set<Int>()
        for g in game.groundItems {
            present.insert(g.id)
            if groundNodes[g.id] == nil {
                let n = GroundItemNode(g)
                n.position = screen(g.position)
                n.zPosition = 8_000
                // Stack labels so they never overlap.
                var y: CGFloat = 16
                for _ in 0..<12 {
                    n.setLabelY(y)
                    if !groundNodes.values.contains(where: { $0.labelRect.intersects(n.labelRect) }) { break }
                    y += 19
                }
                worldNode.addChild(n)
                groundNodes[g.id] = n
            }
        }
        for (id, n) in groundNodes where !present.contains(id) {
            n.removeFromParent()
            groundNodes[id] = nil
        }

        hud.update(player: p, target: hovered.flatMap { game.monster($0) } ?? targetMonster())
        if !inventoryPanel.isHidden { inventoryPanel.refresh(p) }
        if !characterPanel.isHidden { characterPanel.refresh(p) }
        syncCursorAndTooltip()
    }

    private func syncCursorAndTooltip() {
        let p = game.player
        if p.cursor?.id != cursorItemID {
            cursorIcon?.removeFromParent()
            cursorIcon = nil
            cursorItemID = p.cursor?.id
            if let it = p.cursor {
                let icon = ItemVisuals.icon(it)
                icon.zPosition = 31_000
                icon.alpha = 0.9
                cam.addChild(icon)
                cursorIcon = icon
            }
        }
        guard let cp = mouseCamPoint() else { return }
        if let icon = cursorIcon, let it = p.cursor {
            icon.position = CGPoint(x: cp.x - CGFloat(it.base.size.w) * ItemVisuals.cell / 2,
                                    y: cp.y + CGFloat(it.base.size.h) * ItemVisuals.cell / 2)
        }
        // Tooltip for whatever is under the mouse.
        var item: Item?
        if p.cursor == nil && !inventoryPanel.isHidden {
            switch inventoryPanel.hit(cp) {
            case .cell(let x, let y): item = p.inventory.entry(at: x, y)?.item
            case .slot(let s): item = p.equipment[s]
            default: break
            }
        }
        if item == nil, p.cursor == nil, let gid = hoveredGround, let g = game.groundItems.first(where: { $0.id == gid }),
           case .item(let it) = g.content { item = it }
        if let item {
            tooltip.show(item, player: p, at: cp, bounds: size)
        } else {
            tooltip.hide()
        }
    }

    private func message(_ text: String, color: NSColor = ItemVisuals.text) {
        let l = SKLabelNode(fontNamed: "PingFangSC-Regular")
        l.text = text
        l.fontSize = 13
        l.fontColor = color
        for c in messages.children { c.position.y += 18 }
        messages.addChild(l)
        l.run(.sequence([.wait(forDuration: 2), .fadeOut(withDuration: 0.6), .removeFromParent()]))
    }

    private func targetMonster() -> Monster? {
        if case .monster(let id)? = game.player.target { return game.monster(id) }
        return nil
    }

    private func handleEvents() {
        for e in game.drainEvents() {
            switch e {
            case .damage(let at, let amount, let crit, let toPlayer):
                floatText("\(amount)\(crit ? "!" : "")", at: at,
                          color: toPlayer ? NSColor(calibratedRed: 1, green: 0.3, blue: 0.25, alpha: 1)
                                          : (crit ? NSColor(calibratedRed: 1, green: 0.85, blue: 0.2, alpha: 1) : .white),
                          size: crit ? 20 : 15)
                if !toPlayer, let id = game.monster(near: at, within: 0.1)?.id { monsterNodes[id]?.flashHit() }
            case .miss(let at):
                floatText("未命中", at: at, color: NSColor(white: 0.7, alpha: 1), size: 12)
            case .swing(let attacker, let at, let toward):
                let d = Iso.toScreen((toward - at).normalized)
                if let a = attacker {
                    monsterNodes[a]?.lunge(toward: CGVector(dx: d.x / 32, dy: d.y / 32))
                } else {
                    player.swing()
                }
            case .monsterDied(_, let at, let xp):
                floatText("+\(xp) 经验", at: at, color: NSColor(calibratedRed: 0.6, green: 0.8, blue: 1, alpha: 1), size: 12, rise: 50)
            case .playerDied:
                player.setDead(true)
                hud.showBanner("你倒下了", color: NSColor(calibratedRed: 0.75, green: 0.1, blue: 0.05, alpha: 1))
            case .levelUp(let lv):
                hud.showBanner("升级！等级 \(lv)", color: ItemVisuals.gold)
                message("获得 5 属性点、1 技能点（C 打开角色面板分配）", color: ItemVisuals.gold)
                let ring = SKShapeNode(circleOfRadius: 20)
                ring.strokeColor = ItemVisuals.gold; ring.lineWidth = 3; ring.glowWidth = 6
                ring.position = player.position; ring.zPosition = 9_500
                worldNode.addChild(ring)
                ring.run(.sequence([.group([.scale(to: 4, duration: 0.6), .fadeOut(withDuration: 0.6)]), .removeFromParent()]))
            case .playerRespawned:
                player.setDead(false)
            case .blocked(let at):
                floatText("格挡", at: at, color: NSColor(calibratedRed: 0.7, green: 0.8, blue: 1, alpha: 1), size: 13)
            case .pickedUp(let name):
                message("拾取: \(name)")
            case .inventoryFull:
                message("物品栏已满", color: ItemVisuals.bad)
            case .cannotEquip(let name):
                message("无法装备 \(name)：属性不足", color: ItemVisuals.bad)
            case .potion, .itemDropped, .absorbed, .skillUsed, .nova, .stunned, .notEnoughMana, .skillUnavailable:
                break
            }
        }
    }

    private func floatText(_ text: String, at p: Vec2, color: NSColor, size: CGFloat, rise: CGFloat = 36) {
        let l = SKLabelNode(fontNamed: "Menlo-Bold")
        l.text = text
        l.fontSize = size
        l.fontColor = color
        l.position = screen(p) + CGPoint(x: CGFloat.random(in: -8...8), y: 42)
        l.zPosition = 9_000
        worldNode.addChild(l)
        l.run(.sequence([.group([.moveBy(x: 0, y: rise, duration: 0.8), .sequence([.wait(forDuration: 0.4),
                                                                                   .fadeOut(withDuration: 0.4)])]),
                         .removeFromParent()]))
    }

    private func updateWallFade() {
        let pg = game.player.position.grid
        let pd = Iso.depth(game.player.position)
        var now: Set<GridPoint> = []
        for dy in -1...5 { for dx in -1...5 {
            let g = GridPoint(pg.x + dx, pg.y + dy)
            guard let node = walls[g] else { continue }
            let wd = Iso.depth(Vec2(center: g))
            let sx = abs(node.position.x - player.position.x)
            let sy = player.position.y - node.position.y
            if wd > pd && sx < CGFloat(Iso.tileWidth) * 1.6 && sy < Textures.wallHeight + 70 { now.insert(g) }
        } }
        for g in fadedWalls.subtracting(now) { walls[g]?.alpha = 1 }
        for g in now.subtracting(fadedWalls) { walls[g]?.alpha = 0.3 }
        fadedWalls = now
    }

    // MARK: - Input

    private func mouseScenePoint() -> CGPoint? {
        guard let v = view, let mp = lastMouseInView else { return nil }
        return convert(v.convert(mp, to: self), to: worldNode)
    }

    private func mouseWorldPoint() -> Vec2? {
        mouseScenePoint().map { Iso.toWorld(screenX: Double($0.x), screenY: Double($0.y)) }
    }

    /// Pick by screen distance to the monster's body, since sprites stand up off the floor.
    private func monsterUnderMouse() -> EntityID? {
        guard let sp = mouseScenePoint() else { return nil }
        var best: (EntityID, CGFloat)?
        for m in game.monsters where m.isAlive {
            guard let node = monsterNodes[m.id] else { continue }
            let c = node.position + CGPoint(x: 0, y: node.bodyHeight / 2)
            let d = hypot(c.x - sp.x, (c.y - sp.y) * 0.8)
            if d < max(18, node.bodyHeight * 0.6), d < (best?.1 ?? .infinity) { best = (m.id, d) }
        }
        return best?.0
    }

    private func groundItemUnderMouse() -> Int? {
        guard let sp = mouseScenePoint() else { return nil }
        return groundNodes.values.filter { $0.contains(scenePoint: sp) }
            .min { hypot($0.position.x - sp.x, $0.position.y - sp.y) < hypot($1.position.x - sp.x, $1.position.y - sp.y) }?.id
    }

    private func mouseCamPoint() -> CGPoint? {
        guard let v = view, let mp = lastMouseInView else { return nil }
        return convert(v.convert(mp, to: self), to: cam)
    }

    /// True if the mouse is over an open UI panel.
    private func mouseOverUI() -> Bool {
        guard let cp = mouseCamPoint() else { return false }
        if !inventoryPanel.isHidden && inventoryPanel.hit(cp) != .outside { return true }
        if !characterPanel.isHidden && characterPanel.contains(camPoint: cp) { return true }
        return false
    }

    private func updateHover() {
        let g = mouseOverUI() ? nil : groundItemUnderMouse()
        if g != hoveredGround {
            if let old = hoveredGround { groundNodes[old]?.setHighlighted(false) }
            if let g { groundNodes[g]?.setHighlighted(true) }
            hoveredGround = g
        }
        let h = (mouseOverUI() || g != nil) ? nil : monsterUnderMouse()
        if h != hovered {
            if let old = hovered { monsterNodes[old]?.setHighlighted(false) }
            if let h { monsterNodes[h]?.setHighlighted(true) }
            hovered = h
        }
    }

    override func mouseMoved(with event: NSEvent) {
        lastMouseInView = view?.convert(event.locationInWindow, from: nil)
    }

    override func mouseDown(with event: NSEvent) {
        lastMouseInView = view?.convert(event.locationInWindow, from: nil)
        if let cp = mouseCamPoint(), !inventoryPanel.isHidden {
            let hit = inventoryPanel.hit(cp)
            switch hit {
            case .slot(let s):
                game.equipmentClick(s); return
            case .cell(let x, let y):
                if let held = game.player.cursor {
                    let (px, py) = inventoryPanel.placementCell(for: held, at: cp)
                    game.inventoryClick(x: px, y: py)
                } else {
                    game.inventoryClick(x: x, y: y)
                }
                return
            case .inside:
                return
            case .outside:
                break
            }
        }
        if let cp = mouseCamPoint(), !characterPanel.isHidden, characterPanel.contains(camPoint: cp) {
            if let a = characterPanel.attributeButton(at: cp) { game.spendStatPoint(a) }
            return
        }
        if mouseOverUI() { return }
        if game.player.cursor != nil {
            game.dropCursor()
            return
        }
        mouseHeld = true
        if let gid = groundItemUnderMouse() {
            game.commandPickUp(gid)
            mouseHeld = false
        } else if let id = monsterUnderMouse() {
            game.commandAttack(id)
        } else if let t = mouseWorldPoint() {
            game.commandMove(to: t)
            if let dest = game.player.mover.waypoints.last { showClickMarker(at: dest) }
        }
        repathTimer = 0.25
    }

    override func mouseDragged(with event: NSEvent) {
        lastMouseInView = view?.convert(event.locationInWindow, from: nil)
    }

    override func mouseUp(with event: NSEvent) { mouseHeld = false }

    override func rightMouseDown(with event: NSEvent) {
        lastMouseInView = view?.convert(event.locationInWindow, from: nil)
        guard let cp = mouseCamPoint(), !inventoryPanel.isHidden, game.player.cursor == nil else { return }
        switch inventoryPanel.hit(cp) {
        case .cell(let x, let y):
            if let e = game.player.inventory.entry(at: x, y) { game.inventoryUse(itemID: e.item.id) }
        case .slot(let s):
            game.unequip(s)
        default:
            break
        }
    }

    private func showClickMarker(at p: Vec2) {
        let m = SKShapeNode(ellipseOf: CGSize(width: 28, height: 14))
        m.strokeColor = NSColor(calibratedRed: 1, green: 0.7, blue: 0.3, alpha: 0.9)
        m.lineWidth = 2
        m.position = screen(p)
        m.zPosition = -0.4
        worldNode.addChild(m)
        m.run(.sequence([.group([.scale(to: 0.3, duration: 0.35), .fadeOut(withDuration: 0.35)]), .removeFromParent()]))
    }

    private func keyName(_ e: NSEvent) -> String? {
        switch e.keyCode {
        case 123: return "left"
        case 124: return "right"
        case 125: return "down"
        case 126: return "up"
        default: return e.charactersIgnoringModifiers?.lowercased()
        }
    }

    override func keyDown(with event: NSEvent) {
        guard let k = keyName(event) else { return }
        if !event.isARepeat {
            switch k {
            case "r": seed &+= 1; buildLevel(); return
            case "1": game.drinkHealthPotion(); return
            case "2": game.drinkManaPotion(); return
            case "i", "b": inventoryPanel.isHidden.toggle(); return
            case "c": characterPanel.isHidden.toggle(); return
            case "\u{1b}": inventoryPanel.isHidden = true; characterPanel.isHidden = true; return
            default: break
            }
        }
        keys.insert(k)
    }

    override func keyUp(with event: NSEvent) {
        if let k = keyName(event) { keys.remove(k) }
    }
}

extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
}
