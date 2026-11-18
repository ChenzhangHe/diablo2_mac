import AppKit
import SpriteKit
import AshenCore

final class GameScene: SKScene {
    private let worldNode = SKNode()
    private let cam = SKCameraNode()
    private var vignette: SKSpriteNode?
    private let infoLabel = SKLabelNode(fontNamed: "Menlo")
    private let hud = HUD()

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
    }

    // MARK: - Level

    private func buildLevel() {
        worldNode.removeAllChildren()
        walls.removeAll()
        fadedWalls.removeAll()
        monsterNodes.removeAll()
        projectileNodes.removeAll()

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
        syncWorld()
        infoLabel.text = "灰烬圣印 Ashen Sigil · M2   seed \(seed)   左键 移动/攻击 · 1/2 药剂 · R 新地图"
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

        hud.update(player: p, target: hovered.flatMap { game.monster($0) } ?? targetMonster())
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
            case .playerRespawned:
                player.setDead(false)
            case .potion:
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

    private func updateHover() {
        let h = monsterUnderMouse()
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
        mouseHeld = true
        lastMouseInView = view?.convert(event.locationInWindow, from: nil)
        if let id = monsterUnderMouse() {
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
