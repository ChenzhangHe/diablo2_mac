import AppKit
import SpriteKit
import AshenCore

enum ItemVisuals {
    static let cell: CGFloat = 29
    static let gold = NSColor(calibratedRed: 0.95, green: 0.82, blue: 0.35, alpha: 1)
    static let text = NSColor(calibratedRed: 0.85, green: 0.78, blue: 0.6, alpha: 1)
    static let bad = NSColor(calibratedRed: 1, green: 0.3, blue: 0.25, alpha: 1)

    static func color(_ q: ItemQuality) -> NSColor {
        switch q {
        case .normal: NSColor(white: 0.92, alpha: 1)
        case .superior: NSColor(white: 0.75, alpha: 1)
        case .magic: NSColor(calibratedRed: 0.45, green: 0.55, blue: 1, alpha: 1)
        case .rare: NSColor(calibratedRed: 1, green: 0.95, blue: 0.4, alpha: 1)
        case .unique: NSColor(calibratedRed: 0.78, green: 0.62, blue: 0.35, alpha: 1)
        case .set: NSColor(calibratedRed: 0.3, green: 0.9, blue: 0.3, alpha: 1)
        }
    }

    static func labelColor(_ item: Item) -> NSColor {
        if item.isPotion { return item.baseID == ItemBases.healthPotion.id ? NSColor(calibratedRed: 1, green: 0.45, blue: 0.4, alpha: 1)
                                                                          : NSColor(calibratedRed: 0.5, green: 0.6, blue: 1, alpha: 1) }
        return color(item.quality)
    }

    static func glyph(_ c: ItemCategory) -> String {
        switch c {
        case .weapon: "剑"
        case .shield: "盾"
        case .helm: "盔"
        case .armor: "甲"
        case .gloves: "手"
        case .boots: "靴"
        case .belt: "带"
        case .ring: "戒"
        case .amulet: "符"
        case .potion: "药"
        }
    }

    static func fill(_ item: Item) -> NSColor {
        if item.isPotion { return item.baseID == ItemBases.healthPotion.id ? NSColor(calibratedRed: 0.5, green: 0.05, blue: 0.05, alpha: 1)
                                                                          : NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.5, alpha: 1) }
        switch item.base.category {
        case .weapon: return NSColor(calibratedWhite: 0.32, alpha: 1)
        case .ring, .amulet: return NSColor(calibratedRed: 0.35, green: 0.28, blue: 0.12, alpha: 1)
        default: return NSColor(calibratedRed: 0.28, green: 0.22, blue: 0.17, alpha: 1)
        }
    }

    /// Inventory icon sized to the item's grid footprint. Origin at top-left.
    static func icon(_ item: Item, cell: CGFloat = cell) -> SKNode {
        let s = item.base.size
        let size = CGSize(width: CGFloat(s.w) * cell - 2, height: CGFloat(s.h) * cell - 2)
        let node = SKNode()
        let rect = SKShapeNode(rectOf: size, cornerRadius: 3)
        rect.fillColor = fill(item)
        rect.strokeColor = item.quality >= .magic ? color(item.quality) : NSColor(white: 0, alpha: 0.6)
        rect.lineWidth = item.quality >= .magic ? 1.5 : 1
        rect.position = CGPoint(x: size.width / 2 + 1, y: -size.height / 2 - 1)
        node.addChild(rect)
        let l = SKLabelNode(fontNamed: "PingFangSC-Semibold")
        l.text = glyph(item.base.category)
        l.fontSize = min(size.width, size.height) * 0.55
        l.fontColor = labelColor(item)
        l.verticalAlignmentMode = .center
        l.position = rect.position
        node.addChild(l)
        return node
    }
}

/// An item or gold pile on the floor with its name label.
final class GroundItemNode: SKNode {
    let id: Int
    let label = SKLabelNode(fontNamed: "PingFangSC-Regular")
    private let labelBG: SKShapeNode

    init(_ g: GroundItem) {
        id = g.id
        let color: NSColor
        let marker: SKShapeNode
        switch g.content {
        case .gold:
            color = ItemVisuals.gold
            marker = SKShapeNode(ellipseOf: CGSize(width: 12, height: 6))
            marker.fillColor = ItemVisuals.gold
        case .item(let it):
            color = ItemVisuals.labelColor(it)
            marker = SKShapeNode(rectOf: CGSize(width: 12, height: 8), cornerRadius: 2)
            marker.fillColor = ItemVisuals.fill(it)
            marker.strokeColor = color
        }
        label.text = g.label
        label.fontSize = 12
        label.fontColor = color
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: 16)
        let w = label.frame.width + 10
        labelBG = SKShapeNode(rectOf: CGSize(width: w, height: 17), cornerRadius: 2)
        labelBG.fillColor = NSColor(white: 0, alpha: 0.65)
        labelBG.strokeColor = .clear
        labelBG.position = label.position
        super.init()
        marker.zPosition = -200
        labelBG.zPosition = 100
        label.zPosition = 101
        addChild(marker)
        addChild(labelBG)
        addChild(label)
        setScale(0.2)
        run(.scale(to: 1, duration: 0.15))
    }

    required init?(coder: NSCoder) { fatalError() }

    private(set) var labelY: CGFloat = 16

    /// Label rectangle in parent coordinates.
    var labelRect: CGRect {
        let w = label.frame.width + 10
        return CGRect(x: position.x - w / 2, y: position.y + labelY - 9, width: w, height: 18)
    }

    func setLabelY(_ y: CGFloat) {
        labelY = y
        label.position.y = y
        labelBG.position.y = y
    }

    func setHighlighted(_ on: Bool) {
        labelBG.strokeColor = on ? NSColor(white: 1, alpha: 0.8) : .clear
    }

    /// Hit area: label rectangle or marker, in the node's parent space.
    func contains(scenePoint p: CGPoint) -> Bool {
        let local = CGPoint(x: p.x - position.x, y: p.y - position.y)
        let lw = label.frame.width / 2 + 6
        return (abs(local.x) <= lw && abs(local.y - labelY) <= 10) || hypot(local.x, local.y) < 10
    }
}

/// Multi-line item tooltip.
final class Tooltip: SKNode {
    private let bg = SKShapeNode()

    override init() {
        super.init()
        zPosition = 30_000
        isHidden = true
        addChild(bg)
    }

    required init?(coder: NSCoder) { fatalError() }

    private(set) var shownItemID: Int?

    private var boxSize = CGSize.zero

    func show(_ item: Item, player: Player, at p: CGPoint, bounds: CGSize) {
        if shownItemID == item.id && !isHidden {
            place(at: p, bounds: bounds)
            return
        }
        removeAllChildren()
        addChild(bg)
        var rows: [(String, NSColor)] = [(item.displayName, ItemVisuals.labelColor(item))]
        let meets = player.canEquip(item) || EquipSlot.slots(for: item.base.category).isEmpty
        for line in item.tooltipLines {
            let isReq = line.hasPrefix("需要")
            let color: NSColor
            if isReq {
                color = meets ? .white : ItemVisuals.bad
            } else if item.modifierLines.contains(line) {
                color = ItemVisuals.color(.magic)
            } else {
                color = .white
            }
            rows.append((line, color))
        }
        if item.isPotion { rows.append(("右键使用", NSColor(white: 0.7, alpha: 1))) }
        let lh: CGFloat = 17
        var width: CGFloat = 0
        for (i, (t, c)) in rows.enumerated() {
            let l = SKLabelNode(fontNamed: i == 0 ? "PingFangSC-Semibold" : "PingFangSC-Regular")
            l.text = t
            l.fontSize = i == 0 ? 14 : 12
            l.fontColor = c
            l.verticalAlignmentMode = .center
            l.position = CGPoint(x: 0, y: -CGFloat(i) * lh - lh / 2 - 4)
            addChild(l)
            width = max(width, l.frame.width)
        }
        let h = CGFloat(rows.count) * lh + 8
        let w = width + 20
        bg.path = CGPath(roundedRect: CGRect(x: -w / 2, y: -h, width: w, height: h), cornerWidth: 3, cornerHeight: 3, transform: nil)
        bg.fillColor = NSColor(white: 0.02, alpha: 0.92)
        bg.strokeColor = NSColor(white: 0.4, alpha: 0.8)
        boxSize = CGSize(width: w, height: h)
        isHidden = false
        shownItemID = item.id
        place(at: p, bounds: bounds)
    }

    /// Place above the cursor, clamped to screen.
    private func place(at p: CGPoint, bounds: CGSize) {
        let w = boxSize.width, h = boxSize.height
        var pos = CGPoint(x: p.x, y: p.y + h + 14)
        pos.x = min(bounds.width / 2 - w / 2 - 4, max(-bounds.width / 2 + w / 2 + 4, pos.x))
        if pos.y > bounds.height / 2 - 4 { pos.y = p.y - 14 }
        pos.y = max(-bounds.height / 2 + h + 4, pos.y)
        position = pos
    }

    func hide() {
        isHidden = true
        shownItemID = nil
    }
}
