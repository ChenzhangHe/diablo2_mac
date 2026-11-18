import AppKit
import SpriteKit
import AshenCore

/// Equipment paper-doll + grid inventory. Lives in camera (screen) space.
final class InventoryPanel: SKNode {
    enum Hit: Equatable { case slot(EquipSlot), cell(Int, Int), inside, outside }

    static let size = CGSize(width: 330, height: 500)
    private let cell = ItemVisuals.cell
    private let content = SKNode()
    private var signature = ""
    private let goldLabel = SKLabelNode(fontNamed: "Menlo-Bold")

    /// Slot rectangles in panel-local coordinates (center, size in cells).
    let slotLayout: [EquipSlot: (CGPoint, ItemSize)] = [
        .head: (CGPoint(x: 0, y: 185), ItemSize(2, 2)),
        .neck: (CGPoint(x: 55, y: 200), ItemSize(1, 1)),
        .weapon: (CGPoint(x: -105, y: 125), ItemSize(2, 4)),
        .body: (CGPoint(x: 0, y: 105), ItemSize(2, 3)),
        .offhand: (CGPoint(x: 105, y: 125), ItemSize(2, 4)),
        .hands: (CGPoint(x: -105, y: 25), ItemSize(2, 2)),
        .leftRing: (CGPoint(x: -50, y: 40), ItemSize(1, 1)),
        .waist: (CGPoint(x: 0, y: 40), ItemSize(2, 1)),
        .rightRing: (CGPoint(x: 50, y: 40), ItemSize(1, 1)),
        .feet: (CGPoint(x: 105, y: 25), ItemSize(2, 2)),
    ]
    private var gridOrigin: CGPoint { CGPoint(x: -CGFloat(10) * cell / 2, y: -60) }   // top-left of grid

    override init() {
        super.init()
        zPosition = 25_000
        let bg = SKShapeNode(rectOf: Self.size, cornerRadius: 6)
        bg.fillColor = NSColor(calibratedRed: 0.06, green: 0.05, blue: 0.04, alpha: 0.95)
        bg.strokeColor = NSColor(calibratedRed: 0.45, green: 0.38, blue: 0.25, alpha: 1)
        bg.lineWidth = 2
        addChild(bg)

        let title = SKLabelNode(fontNamed: "PingFangSC-Semibold")
        title.text = "物品栏"
        title.fontSize = 15
        title.fontColor = ItemVisuals.text
        title.position = CGPoint(x: 0, y: Self.size.height / 2 - 24)
        addChild(title)

        for (slot, (c, s)) in slotLayout {
            let r = SKShapeNode(rectOf: CGSize(width: CGFloat(s.w) * cell, height: CGFloat(s.h) * cell), cornerRadius: 3)
            r.position = c
            r.fillColor = NSColor(white: 0, alpha: 0.5)
            r.strokeColor = NSColor(white: 0.3, alpha: 1)
            addChild(r)
            let l = SKLabelNode(fontNamed: "PingFangSC-Regular")
            l.text = slot.displayName
            l.fontSize = 9
            l.fontColor = NSColor(white: 0.35, alpha: 1)
            l.verticalAlignmentMode = .center
            l.position = c
            addChild(l)
        }
        for y in 0..<4 { for x in 0..<10 {
            let r = SKShapeNode(rectOf: CGSize(width: cell, height: cell))
            r.position = CGPoint(x: gridOrigin.x + (CGFloat(x) + 0.5) * cell, y: gridOrigin.y - (CGFloat(y) + 0.5) * cell)
            r.fillColor = NSColor(white: 0, alpha: 0.5)
            r.strokeColor = NSColor(white: 0.22, alpha: 1)
            addChild(r)
        } }
        goldLabel.fontSize = 13
        goldLabel.fontColor = ItemVisuals.gold
        goldLabel.position = CGPoint(x: 0, y: gridOrigin.y - 4 * cell - 26)
        addChild(goldLabel)
        let help = SKLabelNode(fontNamed: "PingFangSC-Regular")
        help.text = "左键 拿起/放下 · 右键 装备/使用 · 拖到外面丢弃"
        help.fontSize = 10
        help.fontColor = NSColor(white: 0.5, alpha: 1)
        help.position = CGPoint(x: 0, y: -Self.size.height / 2 + 12)
        addChild(help)
        addChild(content)
    }

    required init?(coder: NSCoder) { fatalError() }

    func refresh(_ p: Player) {
        let sig = p.inventory.entries.map { "\($0.item.id)@\($0.x),\($0.y)" }.joined(separator: ";")
            + "|" + EquipSlot.allCases.map { "\(p.equipment[$0]?.id ?? 0)" }.joined(separator: ",")
        goldLabel.text = "金币: \(p.gold)"
        guard sig != signature else { return }
        signature = sig
        content.removeAllChildren()
        for e in p.inventory.entries {
            let icon = ItemVisuals.icon(e.item, cell: cell)
            icon.position = CGPoint(x: gridOrigin.x + CGFloat(e.x) * cell, y: gridOrigin.y - CGFloat(e.y) * cell)
            content.addChild(icon)
        }
        for (slot, item) in p.equipment {
            guard let (c, s) = slotLayout[slot] else { continue }
            // Center the item's own footprint in the slot box.
            let isz = item.base.size
            let w = CGFloat(min(isz.w, s.w)) * cell, h = CGFloat(min(isz.h, s.h)) * cell
            let icon = ItemVisuals.icon(item, cell: cell * min(1, min(CGFloat(s.w) / CGFloat(isz.w), CGFloat(s.h) / CGFloat(isz.h))))
            icon.position = CGPoint(x: c.x - w / 2, y: c.y + h / 2)
            content.addChild(icon)
        }
    }

    func hit(_ p: CGPoint) -> Hit {
        let local = CGPoint(x: p.x - position.x, y: p.y - position.y)
        guard abs(local.x) <= Self.size.width / 2, abs(local.y) <= Self.size.height / 2 else { return .outside }
        for (slot, (c, s)) in slotLayout {
            if abs(local.x - c.x) <= CGFloat(s.w) * cell / 2 && abs(local.y - c.y) <= CGFloat(s.h) * cell / 2 { return .slot(slot) }
        }
        let gx = Int(floor((local.x - gridOrigin.x) / cell)), gy = Int(floor((gridOrigin.y - local.y) / cell))
        if gx >= 0 && gx < 10 && gy >= 0 && gy < 4 { return .cell(gx, gy) }
        return .inside
    }

    /// For placing a held item, snap its top-left to the cell under the cursor (centered on the item).
    func placementCell(for item: Item, at p: CGPoint) -> (Int, Int) {
        let local = CGPoint(x: p.x - position.x, y: p.y - position.y)
        let s = item.base.size
        let fx = (local.x - gridOrigin.x) / cell - CGFloat(s.w) / 2 + 0.5
        let fy = (gridOrigin.y - local.y) / cell - CGFloat(s.h) / 2 + 0.5
        return (Int(floor(fx)), Int(floor(fy)))
    }
}

/// Character sheet: attributes and derived combat stats.
final class CharacterPanel: SKNode {
    static let size = CGSize(width: 300, height: 500)
    private let lines = SKNode()
    private var buttons: [(Player.AttributeKind, CGRect)] = []
    private var signature = ""

    override init() {
        super.init()
        zPosition = 25_000
        let bg = SKShapeNode(rectOf: Self.size, cornerRadius: 6)
        bg.fillColor = NSColor(calibratedRed: 0.06, green: 0.05, blue: 0.04, alpha: 0.95)
        bg.strokeColor = NSColor(calibratedRed: 0.45, green: 0.38, blue: 0.25, alpha: 1)
        bg.lineWidth = 2
        addChild(bg)
        addChild(lines)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Which "+" button (if any) is at a point in camera space.
    func attributeButton(at p: CGPoint) -> Player.AttributeKind? {
        let local = CGPoint(x: p.x - position.x, y: p.y - position.y)
        return buttons.first { $0.1.contains(local) }?.0
    }

    func contains(camPoint p: CGPoint) -> Bool {
        abs(p.x - position.x) <= Self.size.width / 2 && abs(p.y - position.y) <= Self.size.height / 2
    }

    func refresh(_ p: Player) {
        let s = p.stats
        let sig = "\(p.attributes)|\(p.statPoints)|\(Int(s.life))|\(Int(s.mana))|\(p.xp)|\(p.equipment.values.map(\.id).sorted())"
        guard sig != signature else { return }
        signature = sig
        lines.removeAllChildren()
        buttons.removeAll()
        let g = StatCalculator.gearModifiers(p.equipment)
        func attr(_ base: Int, _ st: Stat) -> String { let b = g[st] ?? 0; return b > 0 ? "\(base + b)  (+\(b))" : "\(base)" }
        let elem = s.elemental.map { "\($0.type.displayName) \(Int($0.min))-\(Int($0.max))" }.joined(separator: " ")
        let rows: [(String, String)] = [
            ("职业", p.heroClass.name), ("等级", "\(s.level)"), ("经验", "\(p.xp) / \(p.xpForNextLevel)"),
            ("属性点", p.statPoints > 0 ? "\(p.statPoints)" : "-"), ("", ""),
            ("力量", attr(p.attributes.strength, .strength)), ("敏捷", attr(p.attributes.dexterity, .dexterity)),
            ("体魄", attr(p.attributes.vitality, .vitality)), ("灵力", attr(p.attributes.energy, .energy)), ("", ""),
            ("伤害", "\(Int(s.minDamage))-\(Int(s.maxDamage))" + (elem.isEmpty ? "" : " +" + elem)),
            ("命中值", "\(Int(s.attackRating))"), ("防御", "\(Int(s.defense))"),
            ("攻击速度", "\((s.attacksPerSecond * 100).rounded() / 100)/秒"),
            ("暴击几率", "\(Int((s.critChance * 100).rounded()))%"), ("格挡几率", "\(Int(min(75, s.blockChance)))%"),
            ("生命", "\(Int(s.life))/\(Int(s.maxLife))"), ("法力", "\(Int(s.mana))/\(Int(s.maxMana))"), ("", ""),
            ("火焰抗性", "\(min(75, s.resist.fire))%"), ("冰霜抗性", "\(min(75, s.resist.cold))%"),
            ("闪电抗性", "\(min(75, s.resist.lightning))%"), ("毒素抗性", "\(min(75, s.resist.poison))%"),
            ("生命窃取", "\(Int(s.lifeSteal))%"), ("反伤", "\(Int(s.thorns))"), ("额外金币", "\(Int(p.goldFind))%"),
        ]
        let title = SKLabelNode(fontNamed: "PingFangSC-Semibold")
        title.text = "角色"
        title.fontSize = 15
        title.fontColor = ItemVisuals.text
        title.position = CGPoint(x: 0, y: Self.size.height / 2 - 24)
        lines.addChild(title)
        var y = Self.size.height / 2 - 48
        let attrRows: [String: Player.AttributeKind] = ["力量": .strength, "敏捷": .dexterity, "体魄": .vitality, "灵力": .energy]
        for (k, v) in rows {
            defer { y -= k.isEmpty ? 8 : 17 }
            guard !k.isEmpty else { continue }
            if p.statPoints > 0, let kind = attrRows[k] {
                let b = SKShapeNode(rectOf: CGSize(width: 16, height: 14), cornerRadius: 2)
                b.fillColor = NSColor(calibratedRed: 0.4, green: 0.3, blue: 0.1, alpha: 1)
                b.strokeColor = ItemVisuals.gold
                let bx = -Self.size.width / 2 + 80
                b.position = CGPoint(x: bx, y: y + 4)
                let plus = SKLabelNode(fontNamed: "Menlo-Bold")
                plus.text = "+"; plus.fontSize = 13; plus.fontColor = ItemVisuals.gold
                plus.verticalAlignmentMode = .center
                b.addChild(plus)
                lines.addChild(b)
                buttons.append((kind, CGRect(x: bx - 10, y: y - 5, width: 20, height: 18)))
            }
            let kl = SKLabelNode(fontNamed: "PingFangSC-Regular")
            kl.text = k; kl.fontSize = 12; kl.fontColor = ItemVisuals.text
            kl.horizontalAlignmentMode = .left; kl.position = CGPoint(x: -Self.size.width / 2 + 20, y: y)
            let vl = SKLabelNode(fontNamed: "Menlo")
            vl.text = v; vl.fontSize = 12; vl.fontColor = .white
            vl.horizontalAlignmentMode = .right; vl.position = CGPoint(x: Self.size.width / 2 - 20, y: y)
            lines.addChild(kl); lines.addChild(vl)
        }
    }
}
