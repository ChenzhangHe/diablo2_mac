import AppKit
import SpriteKit
import AshenCore

/// Translucent overlay map of explored tiles (Tab). Lives in camera space, centered on the player.
final class Automap: SKNode {
    private let image = SKSpriteNode()
    private let playerDot = SKShapeNode(circleOfRadius: 3)
    private var drawnCount = -1
    private var drawnArea = ""
    private var origin = CGPoint.zero        // image-space offset of world (0,0)
    static let scale: CGFloat = 0.22         // fraction of normal tile size

    override init() {
        super.init()
        zPosition = 15_000
        image.anchorPoint = .zero
        image.alpha = 0.75
        addChild(image)
        playerDot.fillColor = NSColor(calibratedRed: 1, green: 0.3, blue: 0.2, alpha: 1)
        playerDot.strokeColor = .white
        playerDot.zPosition = 1
        addChild(playerDot)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func iso(_ p: Vec2) -> CGPoint {
        let s = Iso.toScreen(p)
        return CGPoint(x: s.x * Self.scale, y: s.y * Self.scale)
    }

    func update(_ game: GameWorld) {
        let explored = game.exploredHere
        if explored.count != drawnCount || drawnArea != game.area.id { redraw(game, explored) }
        // Keep the player's position at the screen center.
        let pp = iso(game.player.position)
        image.position = CGPoint(x: origin.x - pp.x, y: origin.y - pp.y)
    }

    private func redraw(_ game: GameWorld, _ explored: Set<GridPoint>) {
        drawnCount = explored.count
        drawnArea = game.area.id
        let map = game.level.map
        let w = CGFloat(map.width + map.height) * CGFloat(Iso.tileWidth) / 2 * Self.scale + 20
        let h = CGFloat(map.width + map.height) * CGFloat(Iso.tileHeight) / 2 * Self.scale + 20
        // World (0,0) maps to top-center of the diamond.
        origin = CGPoint(x: -w / 2, y: -h + 10)
        let tw = CGFloat(Iso.tileWidth) * Self.scale, th = CGFloat(Iso.tileHeight) * Self.scale
        image.texture = Textures.image(width: w, height: h, scale: 2) { ctx in
            for p in explored {
                let tile = map[p]
                let c = self.iso(Vec2(center: p))
                let x = c.x - self.origin.x, y = c.y - self.origin.y
                let color: CGColor
                switch tile {
                case .wall, .tree: color = CGColor(red: 0.85, green: 0.78, blue: 0.6, alpha: 0.9)
                case .rock: color = CGColor(red: 0.6, green: 0.55, blue: 0.45, alpha: 0.7)
                case .water: color = CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 0.6)
                case .void: continue
                default:
                    // Only draw floor edges faintly so walls stand out.
                    color = CGColor(red: 0.4, green: 0.36, blue: 0.3, alpha: 0.25)
                }
                ctx.setFillColor(color)
                let path = CGMutablePath()
                path.move(to: CGPoint(x: x, y: y + th / 2)); path.addLine(to: CGPoint(x: x + tw / 2, y: y))
                path.addLine(to: CGPoint(x: x, y: y - th / 2)); path.addLine(to: CGPoint(x: x - tw / 2, y: y))
                path.closeSubpath()
                ctx.addPath(path); ctx.fillPath()
            }
            for it in game.interactables where explored.contains(it.position.grid) {
                let c = self.iso(it.position)
                let color: CGColor = switch it.kind {
                case .waypoint: CGColor(red: 0.4, green: 0.8, blue: 1, alpha: 1)
                case .npc: CGColor(red: 1, green: 0.85, blue: 0.4, alpha: 1)
                default: CGColor(red: 1, green: 0.6, blue: 0.2, alpha: 1)
                }
                ctx.setFillColor(color)
                ctx.fillEllipse(in: CGRect(x: c.x - self.origin.x - 4, y: c.y - self.origin.y - 4, width: 8, height: 8))
            }
        }
        image.size = CGSize(width: w, height: h)
    }
}
