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
    private let skillPanel = SkillPanel()
    private let hotbar = Hotbar()
    private let aura = SKShapeNode(ellipseOf: CGSize(width: 54, height: 27))
    private let tooltip = Tooltip()
    private var cursorIcon: SKNode?
    private var cursorItemID: Int?
    private var groundNodes: [Int: GroundItemNode] = [:]
    private var interactNodes: [Int: InteractableNode] = [:]
    private var hoveredInteract: Int?
    private var hoveredGround: Int?
    private let messages = SKNode()
    private let menuPanel = MenuPanel(size: CGSize(width: 360, height: 400))
    private var menuMode: String?        // "waypoint" or "npc:<id>"
    private let gridPanel = GridPanel()
    private let automap = Automap()
    /// "shop:<npc>" or "stash" while trading/stashing.
    private var tradeMode: String?

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
        skillPanel.isHidden = true
        cam.addChild(skillPanel)
        cam.addChild(hotbar)
        menuPanel.isHidden = true
        cam.addChild(menuPanel)
        gridPanel.isHidden = true
        cam.addChild(gridPanel)
        automap.isHidden = true
        cam.addChild(automap)
        aura.lineWidth = 2
        aura.glowWidth = 4
        aura.fillColor = .clear
        aura.isHidden = true
        worldNode.addChild(aura)
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
        messages.position = CGPoint(x: 0, y: -size.height / 2 + 120)
        skillPanel.position = CGPoint(x: 0, y: 30)
        gridPanel.position = CGPoint(x: -size.width / 2 + gridPanel.size.width / 2 + 12, y: 30)
        hotbar.position = CGPoint(x: 0, y: -size.height / 2 + 72)
    }

    // MARK: - Level

    private let env = ProcessInfo.processInfo.environment
    /// Debug runs never touch the real save file.
    private var savingEnabled: Bool { !env.keys.contains { $0.hasPrefix("ASHEN_") } || env["ASHEN_SAVE"] != nil }
    private var saveTimer = 0.0

    func saveNow() {
        guard savingEnabled, game != nil else { return }
        do { try SaveStore.default.save(game.makeSave()) } catch { message("存档失败: \(error.localizedDescription)", color: ItemVisuals.bad) }
    }

    /// Continue from the save file if present, else start a new game in camp.
    private func buildLevel(newGame: Bool = false) {
        if !newGame, savingEnabled, let save = try? SaveStore.default.load() {
            game = GameWorld(save: save)
            seed = save.seed
            buildArea()
            message("已读取存档 · \(save.summary)", color: ItemVisuals.gold)
            syncWorld()
            return
        }
        let start = env["ASHEN_START_AREA"] ?? "reedford"
        if newGame || !savingEnabled { seed = newGame ? UInt64(Date().timeIntervalSince1970) : seed }
        game = GameWorld(seed: seed, startArea: start)
        buildArea()
        if ProcessInfo.processInfo.environment["ASHEN_DEBUG_WALK_TO_EXIT"] != nil {
            game.commandMove(to: Vec2(center: game.level.exit))
        }
        if ProcessInfo.processInfo.environment["ASHEN_DEBUG_LOOT"] != nil { debugLoot() }
        if ProcessInfo.processInfo.environment["ASHEN_DEBUG_SKILLS"] != nil { debugSkills() }
        if ProcessInfo.processInfo.environment["ASHEN_DEBUG_AUTOMAP"] != nil { automap.isHidden = false }
        if ProcessInfo.processInfo.environment["ASHEN_DEBUG_SHOP"] != nil {
            game.player.gold = 800
            openTrade("shop:smith")
            DispatchQueue.main.async { [self] in
                let cp = CGPoint(x: gridPanel.position.x - 120, y: gridPanel.position.y + 100)
                if let v = view { lastMouseInView = v.convert(CGPoint(x: cp.x + cam.position.x, y: cp.y + cam.position.y), from: self) }
            }
        }
        syncWorld()
    }

    /// Rebuild all nodes for the world's current area.
    private func buildArea() {
        worldNode.removeAllChildren()
        walls.removeAll()
        fadedWalls.removeAll()
        monsterNodes.removeAll()
        projectileNodes.removeAll()
        groundNodes.removeAll()
        interactNodes.removeAll()
        hoveredInteract = nil

        let map = game.level.map
        let theme = game.area.theme
        var rng = SeededRNG(seed: seed &* 31 &+ UInt64(map.width))
        let floors = ThemeTextures.floors(theme)
        let tileSize = CGSize(width: Iso.tileWidth, height: Iso.tileHeight)

        func floor(_ p: GridPoint, _ tex: SKTexture) {
            let n = SKSpriteNode(texture: tex)
            n.size = tileSize
            n.position = screen(Vec2(center: p))
            n.zPosition = -1
            worldNode.addChild(n)
        }

        for p in map.allPoints {
            let pos = screen(Vec2(center: p))
            switch map[p] {
            case .floor, .door:
                floor(p, floors[rng.int(0...3)])
            case .path:
                floor(p, ThemeTextures.path(theme)[rng.int(0...1)])
            case .water:
                floor(p, ThemeTextures.water(theme))
            case .rock:
                floor(p, floors[rng.int(0...3)])
                let n = SKSpriteNode(texture: ThemeTextures.rock(theme))
                n.size = CGSize(width: Textures.tw, height: Textures.th + ThemeTextures.rockHeight)
                n.anchorPoint = ThemeTextures.rockAnchor
                n.position = pos
                n.zPosition = depthZ(Vec2(center: p))
                worldNode.addChild(n)
            case .tree:
                floor(p, floors[rng.int(0...3)])
                let n = SKSpriteNode(texture: ThemeTextures.trees(theme)[rng.int(0...2)])
                n.size = CGSize(width: Textures.tw, height: ThemeTextures.treeHeight)
                n.anchorPoint = ThemeTextures.treeAnchor
                n.position = pos + CGPoint(x: CGFloat(rng.unit() * 8 - 4), y: 0)
                n.zPosition = depthZ(Vec2(center: p))
                worldNode.addChild(n)
                walls[p] = n
            case .wall:
                let n = SKSpriteNode(texture: ThemeTextures.wall(theme))
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

        for it in game.interactables {
            let n = InteractableNode(it)
            n.position = screen(it.position)
            n.zPosition = depthZ(it.position)
            worldNode.addChild(n)
            interactNodes[it.id] = n
        }

        player.setDead(!game.playerAlive)
        worldNode.addChild(player)
        worldNode.addChild(aura)
        infoLabel.text = "灰烬圣印 · \(game.area.name)" + (game.area.isTown ? "" : "  (区域等级 \(game.area.level))")
            + "    左键 移动/攻击/拾取/交互 · 右键/QWER 技能 · 1/2 药剂 · I 物品 · C 角色 · T 技能"
        hud.showBanner(game.area.name, color: ItemVisuals.text)
    }

    private func debugSkills() {
        game.player.gainXP(Experience.total(forLevel: 24))
        for id in ["rallying_roar", "weapon_mastery", "flame_strike", "cleave", "dread_howl", "quake_cry", "bulwark",
                   "ember_ward", "unyielding", "ember_whirl", "cinder_nova", "shield_bash", "iron_shout"] {
            _ = game.player.learnSkill(id)
        }
        game.player.hotbar = ["rmb": "flame_strike", "q": "cinder_nova", "w": "quake_cry", "e": "rallying_roar", "r": "ember_whirl"]
        skillPanel.isHidden = false
        // Spawn a pack next to the player and blast it after a moment.
        for i in 0..<5 {
            let a = Double(i) * 1.2
            game.spawn(Bestiary.murkling, at: game.player.position + Vec2(cos(a) * 2, sin(a) * 2))
        }
        run(.sequence([.wait(forDuration: 1.3), .run { [self] in
            _ = game.castSkill("rallying_roar", target: nil, point: game.player.position)
            _ = game.castSkill("cinder_nova", target: nil, point: game.player.position)
        }]))
        DispatchQueue.main.async { [self] in
            let cp = CGPoint(x: skillPanel.position.x + 140, y: skillPanel.position.y + 135)
            if let v = view { lastMouseInView = v.convert(CGPoint(x: cp.x + cam.position.x, y: cp.y + cam.position.y), from: self) }
        }
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

        if mouseHeld && game.player.target == nil {
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
        saveTimer += dt
        if saveTimer > 60 { saveTimer = 0; saveNow() }
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
                let n: SKShapeNode
                switch pr.visual {
                case .arrow:
                    n = SKShapeNode(rectOf: CGSize(width: 16, height: 2))
                    n.fillColor = NSColor(calibratedRed: 0.9, green: 0.85, blue: 0.7, alpha: 1)
                    n.strokeColor = .clear
                case .fireBolt:
                    n = SKShapeNode(ellipseOf: CGSize(width: 14, height: 9))
                    n.fillColor = NSColor(calibratedRed: 1, green: 0.5, blue: 0.1, alpha: 1)
                    n.strokeColor = NSColor(calibratedRed: 1, green: 0.85, blue: 0.3, alpha: 1)
                    n.glowWidth = 6
                case .coldBolt:
                    n = SKShapeNode(ellipseOf: CGSize(width: 14, height: 8))
                    n.fillColor = NSColor(calibratedRed: 0.5, green: 0.8, blue: 1, alpha: 1)
                    n.strokeColor = .white
                    n.glowWidth = 5
                }
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

        var liveIt = Set<Int>()
        for it in game.interactables {
            liveIt.insert(it.id)
            if interactNodes[it.id] == nil {
                let n = InteractableNode(it)
                n.position = screen(it.position)
                n.zPosition = depthZ(it.position)
                worldNode.addChild(n)
                interactNodes[it.id] = n
            }
        }
        for (id, n) in interactNodes where !liveIt.contains(id) { n.removeFromParent(); interactNodes[id] = nil }

        hud.update(player: p, target: hovered.flatMap { game.monster($0) } ?? targetMonster())
        if !inventoryPanel.isHidden { inventoryPanel.refresh(p) }
        if !characterPanel.isHidden { characterPanel.refresh(p) }
        if !skillPanel.isHidden { skillPanel.refresh(p) }
        if let inv = tradeInventory {
            let title = tradeMode == "stash" ? "储物箱" : (NPCs.def(tradeNPC ?? "")?.name ?? "商店")
            let footer = tradeMode == "stash" ? "左键取出 · 背包中右键存入" : "左键购买 · 背包中右键出售 · 金币 \(p.gold)"
            gridPanel.show(title: title, footer: footer, inventory: inv)
        }
        hotbar.update(p, time: game.time)
        if !automap.isHidden { automap.update(game) }
        updateAura(p)
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
        var extra: [(String, NSColor)] = []
        if item == nil, p.cursor == nil, !gridPanel.isHidden, let (x, y) = gridPanel.cell(at: cp),
           let e = tradeInventory?.entry(at: x, y) {
            item = e.item
            if tradeNPC != nil { extra = [("价格: \(e.item.price) 金币", p.gold >= e.item.price ? ItemVisuals.gold : ItemVisuals.bad)] }
        } else if let it = item, tradeNPC != nil, p.inventory.items.contains(where: { $0.id == it.id }) {
            extra = [("出售价格: \(it.sellPrice) 金币", ItemVisuals.gold)]
        }
        if let item {
            tooltip.show(item, player: p, at: cp, bounds: size, extra: extra)
        } else if !skillPanel.isHidden, let sid = skillPanel.skill(at: cp), let d = Skills.def(sid) {
            tooltip.showLines(key: "skill\(sid)\(p.skills.level(sid))\(p.level)\(p.hasShield)", title: d.name,
                              titleColor: SkillVisuals.color(d.tree), rows: SkillVisuals.tooltipRows(d, player: p), at: cp, bounds: size)
        } else {
            tooltip.hide()
        }
    }

    private func updateAura(_ p: Player) {
        aura.position = player.position
        aura.zPosition = player.zPosition - 0.01
        let ids = Set(p.buffs.map(\.skillID))
        if ids.isEmpty || !game.playerAlive { aura.isHidden = true; return }
        aura.isHidden = false
        if ids.contains("sunshield") {
            aura.strokeColor = NSColor(calibratedRed: 1, green: 0.85, blue: 0.3, alpha: 0.9)
        } else if ids.contains("ember_ward") {
            aura.strokeColor = NSColor(calibratedRed: 1, green: 0.4, blue: 0.1, alpha: 0.8)
        } else if ids.contains("rallying_roar") {
            aura.strokeColor = NSColor(calibratedRed: 0.9, green: 0.2, blue: 0.15, alpha: 0.7)
        } else {
            aura.strokeColor = NSColor(calibratedRed: 0.6, green: 0.7, blue: 0.9, alpha: 0.7)
        }
    }

    /// World circle of `radius` tiles as an iso ellipse.
    private func isoEllipse(radius r: Double) -> CGSize {
        CGSize(width: r * 2 * Iso.tileWidth / 2 * 2.0.squareRoot(), height: r * 2 * Iso.tileHeight / 2 * 2.0.squareRoot())
    }

    private func novaEffect(_ id: String, at p: Vec2, radius: Double) {
        let color: NSColor
        switch id {
        case "cinder_nova", "monster_fire": color = NSColor(calibratedRed: 1, green: 0.45, blue: 0.1, alpha: 1)
        case "quake_cry": color = NSColor(calibratedRed: 0.75, green: 0.6, blue: 0.4, alpha: 1)
        case "dread_howl", "boss_summon": color = NSColor(calibratedRed: 0.6, green: 0.3, blue: 0.8, alpha: 1)
        case "boss_frost": color = NSColor(calibratedRed: 0.5, green: 0.85, blue: 1, alpha: 1)
        case "boss_enrage": color = NSColor(calibratedRed: 1, green: 0.15, blue: 0.1, alpha: 1)
        default: color = NSColor(calibratedRed: 0.5, green: 0.15, blue: 0.15, alpha: 1)
        }
        let full = isoEllipse(radius: radius)
        let ring = SKShapeNode(ellipseOf: full)
        ring.strokeColor = color
        ring.lineWidth = 4
        ring.glowWidth = 8
        ring.fillColor = color.withAlphaComponent(0.15)
        ring.position = screen(p)
        ring.zPosition = 8_500
        ring.setScale(0.1)
        worldNode.addChild(ring)
        ring.run(.sequence([.group([.scale(to: 1, duration: 0.3), .sequence([.wait(forDuration: 0.15), .fadeOut(withDuration: 0.35)])]),
                            .removeFromParent()]))
        if id == "cinder_nova" {
            for i in 0..<14 {
                let a = Double(i) / 14 * 2 * .pi
                let ember = SKShapeNode(circleOfRadius: 3)
                ember.fillColor = NSColor(calibratedRed: 1, green: 0.6, blue: 0.2, alpha: 1)
                ember.strokeColor = .clear
                ember.glowWidth = 3
                ember.position = screen(p)
                ember.zPosition = 8_600
                worldNode.addChild(ember)
                let d = Iso.toScreen(Vec2(cos(a), sin(a)) * radius)
                ember.run(.sequence([.group([.moveBy(x: d.x, y: d.y + 10, duration: 0.35), .fadeOut(withDuration: 0.4)]), .removeFromParent()]))
            }
        }
    }

    private func skillEffect(_ id: String, at: Vec2, toward: Vec2) {
        guard let d = Skills.def(id) else { return }
        let color = SkillVisuals.color(d.tree)
        switch d.kind {
        case .buff:
            let ring = SKShapeNode(ellipseOf: CGSize(width: 50, height: 25))
            ring.strokeColor = color; ring.lineWidth = 3; ring.glowWidth = 6
            ring.position = screen(at); ring.zPosition = 8_500
            worldNode.addChild(ring)
            ring.run(.sequence([.group([.moveBy(x: 0, y: 50, duration: 0.5), .fadeOut(withDuration: 0.5)]), .removeFromParent()]))
            floatText(d.name, at: at, color: color, size: 14, rise: 30)
        case .meleeAttack, .charge, .whirl:
            let dir = Iso.toScreen((toward - at).normalized)
            let arc = SKShapeNode(ellipseOf: CGSize(width: 46, height: 20))
            arc.strokeColor = id == "flame_strike" ? NSColor(calibratedRed: 1, green: 0.5, blue: 0.1, alpha: 1) : color
            arc.lineWidth = 3; arc.glowWidth = 5
            arc.position = screen(at) + CGPoint(x: dir.x * 0.8, y: dir.y * 0.8 + 18)
            arc.zPosition = 8_500
            arc.zRotation = atan2(CGFloat(dir.y), CGFloat(dir.x))
            worldNode.addChild(arc)
            arc.run(.sequence([.group([.scale(to: id == "cleave" ? 2.2 : 1.4, duration: 0.15), .fadeOut(withDuration: 0.2)]), .removeFromParent()]))
            if d.kind == .whirl { player.spin(duration: 1.2) }
        default:
            break
        }
    }

    // MARK: - Menus

    private func closeMenu() {
        menuPanel.isHidden = true
        menuMode = nil
    }

    private func openTrade(_ mode: String) {
        closeMenu()
        tradeMode = mode
        gridPanel.isHidden = false
        characterPanel.isHidden = true
        inventoryPanel.isHidden = false
    }

    private func closeTrade() {
        tradeMode = nil
        gridPanel.isHidden = true
    }

    private var tradeNPC: String? {
        guard let m = tradeMode, m.hasPrefix("shop:") else { return nil }
        return String(m.dropFirst(5))
    }

    /// Inventory currently shown in the left grid.
    private var tradeInventory: Inventory? {
        if tradeMode == "stash" { return game.player.stash }
        return tradeNPC.flatMap { game.vendors[$0] }
    }

    private func openWaypointMenu() {
        let rows = Areas.actOne.filter(\.hasWaypoint).map { a in
            (a.id, (a.id == game.area.id ? "▸ " : "") + a.name + (game.player.waypoints.contains(a.id) ? "" : "  (未发现)"),
             game.player.waypoints.contains(a.id) && a.id != game.area.id)
        }
        menuPanel.set(title: "传送小站 · 第一幕", body: ["选择目的地"], rows: rows + [("close", "离开", true)])
        menuMode = "waypoint"
        menuPanel.isHidden = false
    }

    private func openNPCMenu(_ id: String) {
        guard let npc = NPCs.def(id) else { return }
        var rows: [(String, String, Bool)] = []
        if npc.services.contains(.trade) { rows.append(("trade", "交易", true)) }
        if npc.services.contains(.heal) { rows.append(("heal", "治疗", true)) }
        if npc.services.contains(.stash) { rows.append(("stash", "打开储物箱", true)) }
        rows.append(("close", "离开", true))
        let questLines = game.talkQuests(id)
        let body = questLines.isEmpty ? wrap(npc.greeting, 20) : questLines.flatMap { wrap($0, 20) }
        menuPanel.set(title: npc.name, body: body, rows: rows)
        menuMode = "npc:" + id
        menuPanel.isHidden = false
    }

    private func wrap(_ text: String, _ width: Int) -> [String] {
        var lines: [String] = [], cur = ""
        for ch in text {
            cur.append(ch)
            if cur.count >= width { lines.append(cur); cur = "" }
        }
        if !cur.isEmpty { lines.append(cur) }
        return lines
    }

    private func menuSelect(_ row: String) {
        guard let mode = menuMode else { return }
        if row == "close" { closeMenu(); return }
        if mode == "waypoint" {
            closeMenu()
            game.useWaypoint(to: row)
            return
        }
        switch row {
        case "heal":
            game.player.stats.life = game.player.stats.maxLife
            game.player.stats.mana = game.player.stats.maxMana
            message("你感到焕然一新", color: ItemVisuals.gold)
        case "trade":
            openTrade("shop:" + mode.dropFirst(4))
        case "stash":
            openTrade("stash")
        default:
            break
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
            case .nova(let id, let at, let r):
                novaEffect(id, at: at, radius: r)
            case .skillUsed(let id, let at, let toward):
                skillEffect(id, at: at, toward: toward)
            case .stunned(let id):
                if let n = monsterNodes[id] {
                    let stars = SKLabelNode(fontNamed: "Menlo-Bold")
                    stars.text = "✦ ✦"
                    stars.fontSize = 11
                    stars.fontColor = ItemVisuals.gold
                    stars.position = CGPoint(x: 0, y: n.bodyHeight + 8)
                    n.addChild(stars)
                    stars.run(.sequence([.wait(forDuration: 1), .fadeOut(withDuration: 0.3), .removeFromParent()]))
                }
            case .absorbed(let at):
                floatText("吸收", at: at, color: ItemVisuals.gold, size: 12)
            case .notEnoughMana:
                message("法力不足", color: NSColor(calibratedRed: 0.5, green: 0.6, blue: 1, alpha: 1))
            case .skillUnavailable(let why):
                message(why, color: ItemVisuals.bad)
            case .resurrected(let id, _):
                if let old = monsterNodes.removeValue(forKey: id) { old.removeFromParent() }  // rebuilt alive next sync
                if let m = game.monster(id) {
                    floatText("复活", at: m.position, color: NSColor(calibratedRed: 0.8, green: 0.4, blue: 1, alpha: 1), size: 12)
                }
            case .questUpdated(let qid, let st):
                if st == .complete, let q = Quests.def(qid) {
                    let giver = NPCs.def(q.giver)?.name ?? q.giver
                    hud.showBanner("任务目标完成", color: ItemVisuals.gold)
                    message("\(q.name)：返回营地找 \(giver)", color: ItemVisuals.gold)
                }
            case .bossDefeated(let name):
                hud.showBanner("\(name) 已被击败", color: ItemVisuals.gold)
                message("第一枚碎印落入你手中。返回营地向长老复命。", color: ItemVisuals.gold)
            case .notEnoughGold:
                message("金币不足", color: ItemVisuals.bad)
            case .bought(let name):
                message("购买: \(name)")
            case .sold(let name, let g):
                message("出售: \(name)  +\(g) 金币", color: ItemVisuals.gold)
            case .areaEntered:
                closeMenu()
                closeTrade()
                saveNow()
                buildArea()
            case .openWaypoints:
                openWaypointMenu()
            case .talk(let npc):
                openNPCMenu(npc)
            case .potion, .itemDropped:
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
        if !skillPanel.isHidden && skillPanel.contains(camPoint: cp) { return true }
        if !menuPanel.isHidden && menuPanel.contains(camPoint: cp) { return true }
        if !gridPanel.isHidden && gridPanel.contains(camPoint: cp) { return true }
        return false
    }

    private func interactableUnderMouse() -> Int? {
        guard let sp = mouseScenePoint() else { return nil }
        return interactNodes.values.compactMap { n in n.hitTest(scenePoint: sp).map { (n.id, $0) } }.min { $0.1 < $1.1 }?.0
    }

    private func updateHover() {
        let ih = mouseOverUI() ? nil : interactableUnderMouse()
        if ih != hoveredInteract {
            if let old = hoveredInteract { interactNodes[old]?.setHighlighted(false) }
            if let ih { interactNodes[ih]?.setHighlighted(true) }
            hoveredInteract = ih
        }
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
        if let cp = mouseCamPoint(), !menuPanel.isHidden {
            if menuPanel.contains(camPoint: cp) {
                if let r = menuPanel.row(at: cp) { menuSelect(r) }
                return
            }
            closeMenu()
        }
        if let cp = mouseCamPoint(), !gridPanel.isHidden, gridPanel.contains(camPoint: cp) {
            if let (x, y) = gridPanel.cell(at: cp), let e = tradeInventory?.entry(at: x, y) {
                if let npc = tradeNPC { game.buy(from: npc, itemID: e.item.id) } else { game.moveFromStash(itemID: e.item.id) }
            }
            return
        }
        if let cp = mouseCamPoint(), !skillPanel.isHidden, skillPanel.contains(camPoint: cp) {
            if let sid = skillPanel.skill(at: cp), let err = game.player.learnSkill(sid) {
                message(learnErrorText(err), color: ItemVisuals.bad)
            }
            return
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
        } else if let iid = interactableUnderMouse(), monsterUnderMouse() == nil {
            game.commandInteract(iid)
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

    private func learnErrorText(_ e: SkillBook.LearnError) -> String {
        switch e {
        case .noPoints: "没有技能点"
        case .levelTooLow: "等级不足"
        case .missingPrerequisite(let id): "需要先学习 \(Skills.def(id)?.name ?? id)"
        case .maxed: "已达最高等级"
        case .unknown: "未知技能"
        }
    }

    private func bindHoveredSkill(to key: String) -> Bool {
        guard !skillPanel.isHidden, let cp = mouseCamPoint(), let sid = skillPanel.skill(at: cp),
              game.player.skills.level(sid) > 0, Skills.def(sid)?.isActive == true else { return false }
        for (k, v) in game.player.hotbar where v == sid { game.player.hotbar[k] = nil }
        game.player.hotbar[key] = sid
        return true
    }

    private func castHotbar(_ key: String) {
        guard let id = game.player.hotbar[key] else { return }
        let r = game.castSkill(id, target: monsterUnderMouse(), point: mouseWorldPoint() ?? game.player.position)
        if r == .needsTarget { message("需要目标", color: ItemVisuals.bad) }
    }

    override func rightMouseDown(with event: NSEvent) {
        lastMouseInView = view?.convert(event.locationInWindow, from: nil)
        if bindHoveredSkill(to: "rmb") { return }
        if !mouseOverUI() && game.player.cursor == nil { castHotbar("rmb"); return }
        guard let cp = mouseCamPoint(), !inventoryPanel.isHidden, game.player.cursor == nil else { return }
        switch inventoryPanel.hit(cp) {
        case .cell(let x, let y):
            guard let e = game.player.inventory.entry(at: x, y) else { break }
            if let npc = tradeNPC { game.sell(itemID: e.item.id, to: npc) }
            else if tradeMode == "stash" { game.moveToStash(itemID: e.item.id) }
            else { game.inventoryUse(itemID: e.item.id) }
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
        if event.keyCode == 96 && env["ASHEN_DEV"] != nil { buildLevel(newGame: true); return }   // F5 (dev only)
        if ["q", "w", "e", "r"].contains(k) {
            if !bindHoveredSkill(to: k) { castHotbar(k) }
            return
        }
        if !event.isARepeat {
            switch k {
            case "t": skillPanel.isHidden.toggle(); return
            case "\t": automap.isHidden.toggle(); return
            case "1": game.drinkHealthPotion(); return
            case "2": game.drinkManaPotion(); return
            case "i", "b": inventoryPanel.isHidden.toggle(); if inventoryPanel.isHidden { closeTrade() }; return
            case "p":
                if !game.castTownPortal() {
                    message(game.area.isTown ? "营地中无法使用" : "没有回城卷轴", color: ItemVisuals.bad)
                }
                return
            case "c": characterPanel.isHidden.toggle(); return
            case "\u{1b}": closeMenu(); closeTrade(); inventoryPanel.isHidden = true; characterPanel.isHidden = true; skillPanel.isHidden = true; return
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
