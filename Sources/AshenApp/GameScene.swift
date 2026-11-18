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
    private var playerPos = Vec2.zero
    private let player = PlayerNode()

    private var keys = Set<String>()
    private var lastTime: TimeInterval = 0
    private let moveSpeed = 4.5  // tiles per second

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
            case .void:
                break
            }
        }

        let portal = SKSpriteNode(texture: Textures.portal)
        portal.position = screen(Vec2(center: level.exit))
        portal.zPosition = -0.5
        portal.run(.repeatForever(.sequence([.fadeAlpha(to: 0.4, duration: 0.9), .fadeAlpha(to: 1, duration: 0.9)])))
        world.addChild(portal)

        playerPos = Vec2(center: level.spawn)
        world.addChild(player)
        syncPlayer()
        updateHUD()
    }

    private func updateHUD() {
        hudLabel.text = "灰烬圣印 Ashen Sigil · M0   seed \(seed)   WASD/方向键 移动 · R 重新生成地图"
    }

    // MARK: - Coordinates

    private func screen(_ p: Vec2) -> CGPoint {
        let s = Iso.toScreen(p)
        return CGPoint(x: s.x, y: s.y)
    }

    private func depthZ(_ p: Vec2) -> CGFloat { CGFloat(Iso.depth(p)) }

    private func syncPlayer() {
        player.position = screen(playerPos)
        player.zPosition = depthZ(playerPos)
        cam.position = player.position
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
            let step = dir.normalized * (moveSpeed * dt)
            tryMove(Vec2(step.x, 0))
            tryMove(Vec2(0, step.y))
            player.setWalking(true)
        } else {
            player.setWalking(false)
        }
        syncPlayer()
    }

    private func tryMove(_ delta: Vec2) {
        let next = playerPos + delta
        let r = 0.28
        let corners = [Vec2(next.x - r, next.y - r), Vec2(next.x + r, next.y - r),
                       Vec2(next.x - r, next.y + r), Vec2(next.x + r, next.y + r)]
        if corners.allSatisfy({ level.map.isWalkable($0.grid) }) { playerPos = next }
    }

    // MARK: - Input

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
        ember.position = CGPoint(x: 0, y: 22)
        body.addChild(ember)
        addChild(body)
    }

    required init?(coder: NSCoder) { fatalError() }

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
