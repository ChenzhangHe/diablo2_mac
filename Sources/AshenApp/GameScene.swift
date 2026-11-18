import AppKit
import SpriteKit
import AshenCore

final class GameScene: SKScene {
    private let world = SKNode()
    private let cam = SKCameraNode()
    private var vignette: SKSpriteNode?
    private var hudLabel = SKLabelNode(fontNamed: "Menlo")

    private var seed: UInt64 = 1
    private var level: GeneratedLevel!
    private var mover = Mover(position: .zero, speed: 4.5)
    private let player = PlayerNode()
    private var walls: [GridPoint: SKSpriteNode] = [:]
    private var fadedWalls: Set<GridPoint> = []

    private var mouseHeld = false
    private var lastMouseInView: CGPoint?
    private var repathTimer = 0.0

    private var keys = Set<String>()
    private var lastTime: TimeInterval = 0

    override func didMove(to view: SKView) {
        backgroundColor = NSColor(calibratedWhite: 0.02, alpha: 1)
        addChild(world)
        camera = cam
        addChild(cam)

        hudLabel.fontSize = 13
        hudLabel.fontColor = NSColor(calibratedRed: 0.85, green: 0.78, blue: 0.6, alpha: 1)
        hudLabel.horizontalAlignmentMode = .left
        hudLabel.verticalAlignmentMode = .top
        hudLabel.zPosition = 10_001
        cam.addChild(hudLabel)

        buildLevel()
        layoutOverlay()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        layoutOverlay()
    }

    private func layoutOverlay() {
        guard size.width > 0 else { return }
        vignette?.removeFromParent()
        let v = SKSpriteNode(texture: Textures.vignette(size: size, radius: min(size.width, size.height) * 0.62))
        v.size = size
        v.zPosition = 10_000
        cam.addChild(v)
        vignette = v
        hudLabel.position = CGPoint(x: -size.width / 2 + 12, y: size.height / 2 - 12)
    }

    // MARK: - Level

    private func buildLevel() {
        world.removeAllChildren()
        walls.removeAll()
        fadedWalls.removeAll()
        level = DungeonGenerator().generate(seed: seed)
        let map = level.map
        var rng = SeededRNG(seed: seed &* 31)

        for p in map.allPoints {
            let pos = screen(Vec2(center: p))
            switch map[p] {
            case .floor, .door:
                let n = SKSpriteNode(texture: Textures.floors[rng.int(0...3)])
                n.size = CGSize(width: Iso.tileWidth, height: Iso.tileHeight)
                n.position = pos
                n.zPosition = -1
                world.addChild(n)
            case .wall:
                let n = SKSpriteNode(texture: Textures.wall)
                n.size = CGSize(width: Textures.tw, height: Textures.th + Textures.wallHeight)
                n.anchorPoint = Textures.wallAnchor
                n.position = pos
                n.zPosition = depthZ(Vec2(center: p))
                world.addChild(n)
                walls[p] = n
            case .void:
                break
            }
        }

        let portal = SKSpriteNode(texture: Textures.portal)
        portal.position = screen(Vec2(center: level.exit))
        portal.zPosition = -0.5
        portal.run(.repeatForever(.sequence([.fadeAlpha(to: 0.4, duration: 0.9), .fadeAlpha(to: 1, duration: 0.9)])))
        world.addChild(portal)

        mover = Mover(position: Vec2(center: level.spawn), speed: 4.5)
        world.addChild(player)
        if ProcessInfo.processInfo.environment["ASHEN_DEBUG_WALK_TO_EXIT"] != nil {
            mover.moveTo(Vec2(center: level.exit), on: level.map)
        }
        syncPlayer()
        updateHUD()
    }

    private func updateHUD() {
        hudLabel.text = "灰烬圣印 Ashen Sigil · M1   seed \(seed)   左键点击/按住 移动 · WASD 移动 · R 重新生成地图"
    }

    // MARK: - Coordinates

    private func screen(_ p: Vec2) -> CGPoint {
        let s = Iso.toScreen(p)
        return CGPoint(x: s.x, y: s.y)
    }

    private func depthZ(_ p: Vec2) -> CGFloat { CGFloat(Iso.depth(p)) }

    private func syncPlayer() {
        player.position = screen(mover.position)
        player.zPosition = depthZ(mover.position)
        cam.position = player.position
        updateWallFade()
    }

    /// Walls standing between the camera and the player turn translucent.
    private func updateWallFade() {
        let pg = mover.position.grid
        let pd = Iso.depth(mover.position)
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

    // MARK: - Loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastTime == 0 ? 0 : min(currentTime - lastTime, 0.05)
        lastTime = currentTime

        // Screen-relative directions mapped into world space.
        var dir = Vec2.zero
        if keys.contains("w") || keys.contains("up") { dir = dir + Vec2(-1, -1) }
        if keys.contains("s") || keys.contains("down") { dir = dir + Vec2(1, 1) }
        if keys.contains("a") || keys.contains("left") { dir = dir + Vec2(-1, 1) }
        if keys.contains("d") || keys.contains("right") { dir = dir + Vec2(1, -1) }

        if dir.length > 0 {
            mover.stop()
            mover.slide(dir.normalized * (mover.speed * dt), map: level.map)
            player.setWalking(true)
        } else {
            if mouseHeld {
                repathTimer -= dt
                if repathTimer <= 0, let target = mouseWorldTarget() {
                    mover.moveTo(target, on: level.map)
                    repathTimer = 0.12
                }
            }
            mover.update(dt: dt, map: level.map)
            player.setWalking(mover.isMoving)
        }
        player.face(mover.facing)
        syncPlayer()
    }

    // MARK: - Input

    private func mouseWorldTarget() -> Vec2? {
        guard let v = view, let mp = lastMouseInView else { return nil }
        let sp = v.convert(mp, to: self)
        let wp = convert(sp, to: world)
        return Iso.toWorld(screenX: Double(wp.x), screenY: Double(wp.y))
    }

    override func mouseDown(with event: NSEvent) {
        mouseHeld = true
        lastMouseInView = view?.convert(event.locationInWindow, from: nil)
        if let t = mouseWorldTarget(), mover.moveTo(t, on: level.map) {
            showClickMarker(at: mover.waypoints.last ?? t)
        }
        repathTimer = 0.25
    }

    override func mouseDragged(with event: NSEvent) {
        lastMouseInView = view?.convert(event.locationInWindow, from: nil)
    }

    override func mouseUp(with event: NSEvent) {
        mouseHeld = false
    }

    private func showClickMarker(at p: Vec2) {
        let m = SKShapeNode(ellipseOf: CGSize(width: 28, height: 14))
        m.strokeColor = NSColor(calibratedRed: 1, green: 0.7, blue: 0.3, alpha: 0.9)
        m.lineWidth = 2
        m.position = screen(p)
        m.zPosition = -0.4
        world.addChild(m)
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
        if k == "r", !event.isARepeat {
            seed &+= 1
            buildLevel()
            return
        }
        keys.insert(k)
    }

    override func keyUp(with event: NSEvent) {
        if let k = keyName(event) { keys.remove(k) }
    }
}

/// Placeholder hero: shadow, cloaked body, head, with a little walk bob.
final class PlayerNode: SKNode {
    private let body = SKNode()
    private var walking = false

    override init() {
        super.init()
        let shadow = SKShapeNode(ellipseOf: CGSize(width: 26, height: 12))
        shadow.fillColor = NSColor(white: 0, alpha: 0.5); shadow.strokeColor = .clear
        addChild(shadow)

        let cloak = SKShapeNode(rectOf: CGSize(width: 18, height: 30), cornerRadius: 7)
        cloak.fillColor = NSColor(calibratedRed: 0.45, green: 0.12, blue: 0.08, alpha: 1)
        cloak.strokeColor = NSColor(white: 0, alpha: 0.6)
        cloak.position = CGPoint(x: 0, y: 17)
        body.addChild(cloak)

        let head = SKShapeNode(circleOfRadius: 6.5)
        head.fillColor = NSColor(calibratedRed: 0.78, green: 0.64, blue: 0.5, alpha: 1)
        head.strokeColor = NSColor(white: 0, alpha: 0.6)
        head.position = CGPoint(x: 0, y: 38)
        body.addChild(head)

        let ember = SKShapeNode(circleOfRadius: 2.5)
        ember.fillColor = NSColor(calibratedRed: 1, green: 0.55, blue: 0.15, alpha: 1)
        ember.strokeColor = .clear; ember.glowWidth = 4
        ember.position = CGPoint(x: 5, y: 22)
        body.addChild(ember)
        addChild(body)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Flip the figure to face left/right on screen.
    func face(_ dir: Vec2) {
        let screenDX = dir.x - dir.y
        if abs(screenDX) > 0.05 { body.xScale = screenDX < 0 ? -1 : 1 }
    }

    func setWalking(_ w: Bool) {
        guard w != walking else { return }
        walking = w
        body.removeAction(forKey: "bob")
        if w {
            body.run(.repeatForever(.sequence([.moveTo(y: 3, duration: 0.14), .moveTo(y: 0, duration: 0.14)])), withKey: "bob")
        } else {
            body.run(.moveTo(y: 0, duration: 0.1))
        }
    }
}
