import AppKit
import SpriteKit
import AshenCore

/// Bottom HUD: life orb (left), mana orb (right), potion belt, target bar on top.
final class HUD: SKNode {
    private let lifeOrb = Orb(color: NSColor(calibratedRed: 0.75, green: 0.06, blue: 0.05, alpha: 1))
    private let manaOrb = Orb(color: NSColor(calibratedRed: 0.1, green: 0.2, blue: 0.8, alpha: 1))
    private let belt = SKLabelNode(fontNamed: "Menlo-Bold")
    private let xpLabel = SKLabelNode(fontNamed: "Menlo")
    private let targetName = SKLabelNode(fontNamed: "PingFangSC-Semibold")
    private let targetBarBG = SKSpriteNode(color: NSColor(white: 0, alpha: 0.7), size: CGSize(width: 220, height: 22))
    private let targetBar = SKSpriteNode(color: NSColor(calibratedRed: 0.6, green: 0.05, blue: 0.05, alpha: 0.9),
                                         size: CGSize(width: 216, height: 18))
    private let banner = SKLabelNode(fontNamed: "PingFangSC-Semibold")
    private let xpBG = SKSpriteNode(color: NSColor(white: 0, alpha: 0.7), size: CGSize(width: 400, height: 6))
    private let xpFill = SKSpriteNode(color: NSColor(calibratedRed: 0.85, green: 0.7, blue: 0.25, alpha: 1), size: CGSize(width: 400, height: 6))
    private let pointsBadge = SKLabelNode(fontNamed: "PingFangSC-Semibold")

    override init() {
        super.init()
        zPosition = 20_000
        addChild(lifeOrb); addChild(manaOrb)
        for l in [belt, xpLabel] {
            l.fontSize = 13
            l.fontColor = NSColor(calibratedRed: 0.85, green: 0.78, blue: 0.6, alpha: 1)
            l.verticalAlignmentMode = .center
            addChild(l)
        }
        targetBar.anchorPoint = CGPoint(x: 0, y: 0.5)
        targetBarBG.addChild(targetBar)
        targetBar.position = CGPoint(x: -108, y: 0)
        targetName.fontSize = 13
        targetName.fontColor = .white
        targetName.verticalAlignmentMode = .center
        targetName.zPosition = 1
        targetBarBG.addChild(targetName)
        targetBarBG.isHidden = true
        addChild(targetBarBG)

        xpFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        xpFill.position = CGPoint(x: -200, y: 0)
        xpBG.addChild(xpFill)
        addChild(xpBG)
        pointsBadge.fontSize = 12
        pointsBadge.fontColor = NSColor(calibratedRed: 0.95, green: 0.82, blue: 0.35, alpha: 1)
        addChild(pointsBadge)

        banner.fontSize = 54
        banner.fontColor = NSColor(calibratedRed: 0.75, green: 0.1, blue: 0.05, alpha: 1)
        banner.verticalAlignmentMode = .center
        banner.alpha = 0
        addChild(banner)
    }

    required init?(coder: NSCoder) { fatalError() }

    func layout(size: CGSize) {
        let w = size.width / 2, h = size.height / 2
        lifeOrb.position = CGPoint(x: -w + 80, y: -h + 80)
        manaOrb.position = CGPoint(x: w - 80, y: -h + 80)
        belt.position = CGPoint(x: 0, y: -h + 30)
        xpLabel.position = CGPoint(x: 0, y: -h + 14)
        xpBG.position = CGPoint(x: 0, y: -h + 4)
        pointsBadge.position = CGPoint(x: -w + 170, y: -h + 20)
        targetBarBG.position = CGPoint(x: 0, y: h - 40)
    }

    func update(player p: Player, target: Monster?) {
        lifeOrb.set(fraction: p.stats.lifeFraction, text: "\(Int(p.stats.life.rounded(.up)))/\(Int(p.stats.maxLife))")
        manaOrb.set(fraction: p.stats.manaFraction, text: "\(Int(p.stats.mana))/\(Int(p.stats.maxMana))")
        belt.text = "[1] 治疗药剂 ×\(p.healthPotions)    [2] 法力药剂 ×\(p.manaPotions)"
        xpLabel.text = "等级 \(p.stats.level)   经验 \(p.xp) / \(p.xpForNextLevel)"
        xpFill.xScale = CGFloat(max(0, min(1, p.xpIntoLevel)))
        var badges: [String] = []
        if p.statPoints > 0 { badges.append("属性点 \(p.statPoints) [C]") }
        if p.skillPoints > 0 { badges.append("技能点 \(p.skillPoints) [T]") }
        pointsBadge.text = badges.joined(separator: "  ")
        if let t = target, t.isAlive {
            targetBarBG.isHidden = false
            let affixText = t.affixes.map(\.displayName).joined(separator: " ")
            targetName.text = affixText.isEmpty ? t.displayName : "\(t.displayName)  ·  \(affixText)"
            targetName.fontColor = switch t.rank {
            case .unique: NSColor(calibratedRed: 0.95, green: 0.8, blue: 0.35, alpha: 1)
            case .champion: NSColor(calibratedRed: 0.5, green: 0.6, blue: 1, alpha: 1)
            default: .white
            }
            targetBarBG.size.width = max(220, targetName.frame.width + 24)
            targetBar.xScale = CGFloat(t.stats.lifeFraction)
        } else {
            targetBarBG.isHidden = true
        }
    }

    func showBanner(_ text: String, color: NSColor) {
        banner.text = text
        banner.fontColor = color
        banner.removeAllActions()
        banner.run(.sequence([.fadeIn(withDuration: 0.4), .wait(forDuration: 1.4), .fadeOut(withDuration: 0.6)]))
    }
}

/// A liquid-filled glass orb.
final class Orb: SKNode {
    private let fill: SKSpriteNode
    private let label = SKLabelNode(fontNamed: "Menlo-Bold")
    private let radius: CGFloat = 56

    init(color: NSColor) {
        fill = SKSpriteNode(color: color, size: CGSize(width: radius * 2, height: radius * 2))
        super.init()
        let back = SKShapeNode(circleOfRadius: radius + 4)
        back.fillColor = NSColor(calibratedWhite: 0.05, alpha: 0.9)
        back.strokeColor = NSColor(calibratedRed: 0.45, green: 0.38, blue: 0.25, alpha: 1)
        back.lineWidth = 3
        addChild(back)

        let crop = SKCropNode()
        let mask = SKShapeNode(circleOfRadius: radius)
        mask.fillColor = .white
        crop.maskNode = mask
        fill.anchorPoint = CGPoint(x: 0.5, y: 0)
        fill.position = CGPoint(x: 0, y: -radius)
        crop.addChild(fill)
        addChild(crop)

        let shine = SKShapeNode(ellipseOf: CGSize(width: radius * 0.9, height: radius * 0.5))
        shine.fillColor = NSColor(white: 1, alpha: 0.12); shine.strokeColor = .clear
        shine.position = CGPoint(x: -radius * 0.2, y: radius * 0.45)
        addChild(shine)

        label.fontSize = 12
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: -radius - 16)
        addChild(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    func set(fraction: Double, text: String) {
        fill.yScale = CGFloat(max(0, min(1, fraction)))
        label.text = text
    }
}
