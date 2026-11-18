import AppKit
import SpriteKit
import AshenCore

func nsColor(_ c: (Double, Double, Double), _ k: Double = 1, alpha: Double = 1) -> NSColor {
    NSColor(calibratedRed: c.0 * k, green: c.1 * k, blue: c.2 * k, alpha: alpha)
}

/// Placeholder hero: shadow, cloaked body, head, with a little walk bob.
final class PlayerNode: SKNode {
    private let body = SKNode()
    private let weapon = SKShapeNode(rectOf: CGSize(width: 3, height: 22), cornerRadius: 1)
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

        weapon.fillColor = NSColor(calibratedWhite: 0.75, alpha: 1)
        weapon.strokeColor = NSColor(white: 0, alpha: 0.6)
        weapon.position = CGPoint(x: 11, y: 24)
        weapon.zRotation = -0.3
        body.addChild(weapon)

        let ember = SKShapeNode(circleOfRadius: 2.5)
        ember.fillColor = NSColor(calibratedRed: 1, green: 0.55, blue: 0.15, alpha: 1)
        ember.strokeColor = .clear; ember.glowWidth = 4
        ember.position = CGPoint(x: 0, y: 22)
        body.addChild(ember)
        addChild(body)
    }

    required init?(coder: NSCoder) { fatalError() }

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

    func swing() {
        weapon.removeAllActions()
        weapon.run(.sequence([.rotate(toAngle: 0.9, duration: 0.06), .rotate(toAngle: -1.4, duration: 0.1),
                              .rotate(toAngle: -0.3, duration: 0.12)]))
    }

    func spin(duration: Double) {
        body.run(.sequence([.rotate(byAngle: -.pi * 2 * duration * 3, duration: duration), .rotate(toAngle: 0, duration: 0)]))
    }

    func setDead(_ dead: Bool) {
        body.removeAllActions()
        body.zRotation = dead ? .pi / 2 : 0
        body.position = dead ? CGPoint(x: -14, y: -4) : .zero
        alpha = dead ? 0.7 : 1
    }
}

/// Placeholder monster drawn from its behavior archetype and tint.
final class MonsterNode: SKNode {
    let id: EntityID
    private let body = SKNode()
    private let outline: SKShapeNode
    private(set) var dead = false
    let bodyHeight: CGFloat
    private var normalStroke = NSColor(white: 0, alpha: 0.7)

    init(monster m: Monster) {
        id = m.id
        let k = m.kind
        let scale = CGFloat(k.radius / 0.28)
        let shadow = SKShapeNode(ellipseOf: CGSize(width: 24 * scale, height: 11 * scale))
        shadow.fillColor = NSColor(white: 0, alpha: 0.45); shadow.strokeColor = .clear

        let shape: SKShapeNode
        switch k.behavior {
        case .hitAndRun:   // bat: wings
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -16, y: 4)); p.addLine(to: CGPoint(x: -4, y: 0)); p.addLine(to: CGPoint(x: 0, y: 6))
            p.addLine(to: CGPoint(x: 4, y: 0)); p.addLine(to: CGPoint(x: 16, y: 4)); p.addLine(to: CGPoint(x: 6, y: -6))
            p.addLine(to: CGPoint(x: 0, y: -3)); p.addLine(to: CGPoint(x: -6, y: -6)); p.closeSubpath()
            shape = SKShapeNode(path: p)
            shape.position = CGPoint(x: 0, y: 30)
            bodyHeight = 40
        case .skittish:    // small hunched imp
            shape = SKShapeNode(ellipseOf: CGSize(width: 16 * scale, height: 20 * scale))
            shape.position = CGPoint(x: 0, y: 11 * scale)
            bodyHeight = 26 * scale
        default:           // humanoid
            shape = SKShapeNode(rectOf: CGSize(width: 14 * scale, height: 30 * scale), cornerRadius: 4)
            shape.position = CGPoint(x: 0, y: 16 * scale)
            bodyHeight = 40 * scale
        }
        shape.fillColor = nsColor(k.color)
        shape.strokeColor = NSColor(white: 0, alpha: 0.7)
        outline = shape

        super.init()
        addChild(shadow)
        body.addChild(shape)

        // Eyes
        for dx in [-3.0, 3.0] {
            let eye = SKShapeNode(circleOfRadius: 1.5)
            eye.fillColor = k.isUndead ? NSColor(calibratedRed: 0.4, green: 0.8, blue: 1, alpha: 1)
                                       : NSColor(calibratedRed: 1, green: 0.25, blue: 0.1, alpha: 1)
            eye.strokeColor = .clear
            eye.glowWidth = 2
            eye.position = CGPoint(x: dx, y: shape.position.y + (k.behavior == .hitAndRun ? 1 : bodyHeight * 0.3))
            body.addChild(eye)
        }
        if k.behavior == .ranged {
            let bow = SKShapeNode(rectOf: CGSize(width: 2, height: 26), cornerRadius: 1)
            bow.fillColor = NSColor(calibratedRed: 0.45, green: 0.3, blue: 0.15, alpha: 1)
            bow.strokeColor = .clear
            bow.position = CGPoint(x: 10, y: 18)
            body.addChild(bow)
        }
        switch m.rank {
        case .unique:
            body.setScale(1.35)
            shape.glowWidth = 3
            shape.strokeColor = NSColor(calibratedRed: 0.95, green: 0.8, blue: 0.35, alpha: 1)
            normalStroke = shape.strokeColor
        case .champion:
            body.setScale(1.2)
            shape.glowWidth = 2
            shape.strokeColor = NSColor(calibratedRed: 0.45, green: 0.55, blue: 1, alpha: 1)
            normalStroke = shape.strokeColor
        case .minion:
            body.setScale(1.08)
        case .normal:
            break
        }
        if let affix = m.affixes.first(where: { [.fireTouched, .frostTouched, .stormTouched].contains($0) }) {
            let c: NSColor = switch affix {
            case .fireTouched: NSColor(calibratedRed: 1, green: 0.4, blue: 0.1, alpha: 0.8)
            case .frostTouched: NSColor(calibratedRed: 0.4, green: 0.7, blue: 1, alpha: 0.8)
            default: NSColor(calibratedRed: 0.9, green: 0.9, blue: 0.4, alpha: 0.8)
            }
            let glow = SKShapeNode(ellipseOf: CGSize(width: 34, height: 16))
            glow.strokeColor = c; glow.glowWidth = 4; glow.fillColor = c.withAlphaComponent(0.15)
            glow.zPosition = -0.1
            addChild(glow)
        }
        if k.behavior == .hitAndRun {
            body.run(.repeatForever(.sequence([.moveBy(x: 0, y: 4, duration: 0.2), .moveBy(x: 0, y: -4, duration: 0.2)])))
        }
        addChild(body)
    }

    required init?(coder: NSCoder) { fatalError() }

    func face(_ dir: Vec2) {
        let screenDX = dir.x - dir.y
        if abs(screenDX) > 0.05 { body.xScale = screenDX < 0 ? -1 : 1 }
    }

    func setHighlighted(_ on: Bool) {
        outline.lineWidth = on ? 2.5 : 1
        outline.strokeColor = on ? NSColor(calibratedRed: 1, green: 0.85, blue: 0.5, alpha: 1) : normalStroke
    }

    func flashHit() {
        body.removeAction(forKey: "flash")
        body.run(.sequence([.colorize(with: .white, colorBlendFactor: 1, duration: 0), .fadeAlpha(to: 0.5, duration: 0.05),
                            .fadeAlpha(to: 1, duration: 0.08)]), withKey: "flash")
    }

    func lunge(toward dir: CGVector) {
        body.run(.sequence([.moveBy(x: dir.dx * 6, y: dir.dy * 6, duration: 0.07),
                            .moveBy(x: -dir.dx * 6, y: -dir.dy * 6, duration: 0.1)]))
    }

    func die() {
        guard !dead else { return }
        dead = true
        body.removeAllActions()
        setHighlighted(false)
        outline.fillColor = outline.fillColor.blended(withFraction: 0.6, of: .black) ?? outline.fillColor
        body.run(.group([.rotate(toAngle: .pi / 2, duration: 0.25), .moveBy(x: -10, y: -6, duration: 0.25)]))
        zPosition = -0.3   // corpses lie on the floor
    }
}
