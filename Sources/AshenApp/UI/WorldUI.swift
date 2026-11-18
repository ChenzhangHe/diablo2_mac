import AppKit
import SpriteKit
import AshenCore

/// Portal, waypoint or NPC standing in the world.
final class InteractableNode: SKNode {
    let id: Int
    private let label = SKLabelNode(fontNamed: "PingFangSC-Semibold")
    private let highlight: SKShapeNode
    let height: CGFloat

    init(_ it: Interactable) {
        id = it.id
        highlight = SKShapeNode(ellipseOf: CGSize(width: 44, height: 22))
        switch it.kind {
        case .areaExit, .townPortal:
            height = 56
        case .waypoint:
            height = 20
        case .npc:
            height = 46
        }
        super.init()
        highlight.strokeColor = NSColor(white: 1, alpha: 0.8)
        highlight.lineWidth = 2
        highlight.fillColor = .clear
        highlight.isHidden = true
        addChild(highlight)

        switch it.kind {
        case .areaExit, .townPortal:
            let isTP: Bool = { if case .townPortal = it.kind { true } else { false } }()
            let color = isTP ? NSColor(calibratedRed: 0.3, green: 0.6, blue: 1, alpha: 1)
                             : NSColor(calibratedRed: 0.85, green: 0.55, blue: 0.25, alpha: 1)
            let gate = SKShapeNode(ellipseOf: CGSize(width: 30, height: 52))
            gate.position = CGPoint(x: 0, y: 28)
            gate.fillColor = color.withAlphaComponent(0.35)
            gate.strokeColor = color
            gate.lineWidth = 3
            gate.glowWidth = 6
            addChild(gate)
            let inner = SKShapeNode(ellipseOf: CGSize(width: 16, height: 34))
            inner.position = gate.position
            inner.fillColor = color.withAlphaComponent(0.6)
            inner.strokeColor = .clear
            addChild(inner)
            inner.run(.repeatForever(.sequence([.scale(to: 0.6, duration: 0.8), .scale(to: 1, duration: 0.8)])))
        case .waypoint:
            let base = SKShapeNode(ellipseOf: CGSize(width: 56, height: 28))
            base.fillColor = NSColor(calibratedWhite: 0.35, alpha: 1)
            base.strokeColor = NSColor(calibratedRed: 0.4, green: 0.7, blue: 1, alpha: 1)
            base.lineWidth = 2
            addChild(base)
            let rune = SKShapeNode(ellipseOf: CGSize(width: 36, height: 18))
            rune.strokeColor = NSColor(calibratedRed: 0.5, green: 0.85, blue: 1, alpha: 1)
            rune.glowWidth = 5
            rune.fillColor = .clear
            addChild(rune)
            rune.run(.repeatForever(.sequence([.fadeAlpha(to: 0.3, duration: 1.1), .fadeAlpha(to: 1, duration: 1.1)])))
        case .npc(let npcID):
            if npcID == "stash" {
                let chest = SKShapeNode(rectOf: CGSize(width: 30, height: 20), cornerRadius: 3)
                chest.position = CGPoint(x: 0, y: 12)
                chest.fillColor = NSColor(calibratedRed: 0.4, green: 0.25, blue: 0.1, alpha: 1)
                chest.strokeColor = NSColor(calibratedRed: 0.85, green: 0.7, blue: 0.3, alpha: 1)
                addChild(chest)
            } else {
                let shadow = SKShapeNode(ellipseOf: CGSize(width: 26, height: 12))
                shadow.fillColor = NSColor(white: 0, alpha: 0.5); shadow.strokeColor = .clear
                addChild(shadow)
                let robe = SKShapeNode(rectOf: CGSize(width: 18, height: 32), cornerRadius: 7)
                robe.position = CGPoint(x: 0, y: 17)
                robe.fillColor = switch npcID {
                case "smith": NSColor(calibratedRed: 0.35, green: 0.3, blue: 0.25, alpha: 1)
                case "healer": NSColor(calibratedRed: 0.25, green: 0.4, blue: 0.3, alpha: 1)
                default: NSColor(calibratedRed: 0.35, green: 0.3, blue: 0.5, alpha: 1)
                }
                robe.strokeColor = NSColor(white: 0, alpha: 0.6)
                addChild(robe)
                let head = SKShapeNode(circleOfRadius: 6.5)
                head.position = CGPoint(x: 0, y: 39)
                head.fillColor = NSColor(calibratedRed: 0.78, green: 0.64, blue: 0.5, alpha: 1)
                head.strokeColor = NSColor(white: 0, alpha: 0.6)
                addChild(head)
            }
        }

        label.text = it.name
        label.fontSize = 12
        label.fontColor = {
            if case .npc = it.kind { return NSColor(calibratedRed: 0.95, green: 0.85, blue: 0.55, alpha: 1) }
            return NSColor(white: 0.9, alpha: 1)
        }()
        label.position = CGPoint(x: 0, y: height + 10)
        label.zPosition = 9_000
        addChild(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setHighlighted(_ on: Bool) { highlight.isHidden = !on }

    func hitTest(scenePoint p: CGPoint) -> CGFloat? {
        let c = CGPoint(x: position.x, y: position.y + height / 2)
        let d = hypot(p.x - c.x, (p.y - c.y) * 0.8)
        return d < max(26, height * 0.7) ? d : nil
    }
}

/// Simple framed panel with a title and clickable rows.
class MenuPanel: SKNode {
    let size: CGSize
    private(set) var rows: [(String, CGRect)] = []
    private let content = SKNode()

    init(size: CGSize) {
        self.size = size
        super.init()
        zPosition = 26_000
        let bg = SKShapeNode(rectOf: size, cornerRadius: 6)
        bg.fillColor = NSColor(calibratedRed: 0.06, green: 0.05, blue: 0.04, alpha: 0.96)
        bg.strokeColor = NSColor(calibratedRed: 0.45, green: 0.38, blue: 0.25, alpha: 1)
        bg.lineWidth = 2
        addChild(bg)
        addChild(content)
    }

    required init?(coder: NSCoder) { fatalError() }

    func contains(camPoint p: CGPoint) -> Bool {
        abs(p.x - position.x) <= size.width / 2 && abs(p.y - position.y) <= size.height / 2
    }

    func row(at p: CGPoint) -> String? {
        let local = CGPoint(x: p.x - position.x, y: p.y - position.y)
        return rows.first { $0.1.contains(local) }?.0
    }

    /// Rebuild: title, optional body text, rows of (id, text, enabled).
    func set(title: String, body: [String] = [], rows items: [(String, String, Bool)]) {
        content.removeAllChildren()
        rows.removeAll()
        let t = SKLabelNode(fontNamed: "PingFangSC-Semibold")
        t.text = title
        t.fontSize = 16
        t.fontColor = ItemVisuals.text
        t.position = CGPoint(x: 0, y: size.height / 2 - 30)
        content.addChild(t)
        var y = size.height / 2 - 58
        for line in body {
            let l = SKLabelNode(fontNamed: "PingFangSC-Regular")
            l.text = line
            l.fontSize = 13
            l.fontColor = NSColor(white: 0.85, alpha: 1)
            l.position = CGPoint(x: 0, y: y)
            content.addChild(l)
            y -= 20
        }
        if !body.isEmpty { y -= 10 }
        for (id, text, enabled) in items {
            let rect = CGRect(x: -size.width / 2 + 24, y: y - 8, width: size.width - 48, height: 26)
            let box = SKShapeNode(rect: rect, cornerRadius: 3)
            box.fillColor = enabled ? NSColor(calibratedRed: 0.18, green: 0.14, blue: 0.08, alpha: 1) : NSColor(white: 0.08, alpha: 1)
            box.strokeColor = enabled ? NSColor(calibratedRed: 0.55, green: 0.45, blue: 0.25, alpha: 1) : NSColor(white: 0.2, alpha: 1)
            content.addChild(box)
            let l = SKLabelNode(fontNamed: "PingFangSC-Regular")
            l.text = text
            l.fontSize = 13
            l.fontColor = enabled ? .white : NSColor(white: 0.4, alpha: 1)
            l.verticalAlignmentMode = .center
            l.position = CGPoint(x: 0, y: rect.midY)
            content.addChild(l)
            if enabled { rows.append((id, rect)) }
            y -= 32
        }
    }
}
