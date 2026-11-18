import AppKit
import SpriteKit
import AshenCore

enum SkillVisuals {
    static func color(_ tree: String) -> NSColor {
        switch tree {
        case "shield": NSColor(calibratedRed: 0.55, green: 0.6, blue: 0.75, alpha: 1)
        case "cries": NSColor(calibratedRed: 0.8, green: 0.55, blue: 0.25, alpha: 1)
        default: NSColor(calibratedRed: 0.9, green: 0.35, blue: 0.15, alpha: 1)
        }
    }

    /// Two-character badge for a skill.
    static let shortNames: [String: String] = [
        "shield_bash": "盾击", "bulwark": "坚壁", "ember_ward": "护体", "ember_charge": "冲锋", "unyielding": "不屈",
        "sunshield": "日炎", "rallying_roar": "振奋", "dread_howl": "恐惧", "iron_shout": "钢铁", "war_horn": "号角",
        "quake_cry": "震地", "ash_oath": "誓约", "flame_strike": "烈焰", "weapon_mastery": "精通", "cleave": "顺劈",
        "frenzied_blows": "狂热", "ember_whirl": "旋风", "cinder_nova": "新星",
    ]
    static func badge(_ d: SkillDef) -> String { shortNames[d.id] ?? String(d.name.prefix(2)) }

    static func tooltipRows(_ d: SkillDef, player p: Player) -> [(String, NSColor)] {
        let lv = p.skills.level(d.id)
        var rows: [(String, NSColor)] = [(d.summary, NSColor(white: 0.85, alpha: 1))]
        rows.append(("需要等级 \(d.requiredLevel)", p.level >= d.requiredLevel ? .white : ItemVisuals.bad))
        for pre in d.prerequisites {
            let name = Skills.def(pre)?.name ?? pre
            rows.append(("前置: \(name)", p.skills.level(pre) > 0 ? .white : ItemVisuals.bad))
        }
        if d.requiresShield { rows.append(("需要盾牌", p.hasShield ? .white : ItemVisuals.bad)) }
        if lv > 0 {
            rows.append(("当前等级 \(lv)", ItemVisuals.gold))
            rows += p.skills.numbers(d.id).lines.map { ($0, ItemVisuals.color(.magic)) }
        }
        if lv < Skills.maxSkillLevel {
            var next = p.skills
            next.levels[d.id] = lv + 1
            rows.append(("下一级", ItemVisuals.gold))
            rows += next.numbers(d.id).lines.map { ($0, NSColor(white: 0.75, alpha: 1)) }
        }
        if !d.synergies.isEmpty {
            rows.append(("协同加成:", ItemVisuals.gold))
            for (sid, pct) in d.synergies {
                rows.append(("  \(Skills.def(sid)?.name ?? sid): 每级 +\(Int(pct))%", NSColor(white: 0.75, alpha: 1)))
            }
        }
        if d.isActive && lv > 0 { rows.append(("悬停时按 Q/W/E/R 或右键 绑定快捷键", NSColor(white: 0.55, alpha: 1))) }
        return rows
    }
}

/// Three skill trees side by side. Left click learns; Q/W/E/R or right click binds.
final class SkillPanel: SKNode {
    static let size = CGSize(width: 600, height: 470)
    private let content = SKNode()
    private var buttons: [(String, CGRect)] = []
    private var signature = ""
    private let pointsLabel = SKLabelNode(fontNamed: "PingFangSC-Semibold")

    override init() {
        super.init()
        zPosition = 25_000
        let bg = SKShapeNode(rectOf: Self.size, cornerRadius: 6)
        bg.fillColor = NSColor(calibratedRed: 0.06, green: 0.05, blue: 0.04, alpha: 0.96)
        bg.strokeColor = NSColor(calibratedRed: 0.45, green: 0.38, blue: 0.25, alpha: 1)
        bg.lineWidth = 2
        addChild(bg)
        let title = SKLabelNode(fontNamed: "PingFangSC-Semibold")
        title.text = "技能 · 烬卫"
        title.fontSize = 15
        title.fontColor = ItemVisuals.text
        title.position = CGPoint(x: 0, y: Self.size.height / 2 - 26)
        addChild(title)
        pointsLabel.fontSize = 13
        pointsLabel.fontColor = ItemVisuals.gold
        pointsLabel.position = CGPoint(x: 0, y: -Self.size.height / 2 + 14)
        addChild(pointsLabel)
        addChild(content)
    }

    required init?(coder: NSCoder) { fatalError() }

    func contains(camPoint p: CGPoint) -> Bool {
        abs(p.x - position.x) <= Self.size.width / 2 && abs(p.y - position.y) <= Self.size.height / 2
    }

    func skill(at p: CGPoint) -> String? {
        let local = CGPoint(x: p.x - position.x, y: p.y - position.y)
        return buttons.first { $0.1.contains(local) }?.0
    }

    func refresh(_ p: Player) {
        pointsLabel.text = p.skillPoints > 0 ? "剩余技能点: \(p.skillPoints)  · 左键学习" : "没有可用的技能点"
        let sig = "\(p.skills.levels.sorted { $0.key < $1.key })|\(p.skillPoints)|\(p.level)|\(p.hotbar.sorted { $0.key < $1.key })"
        guard sig != signature else { return }
        signature = sig
        content.removeAllChildren()
        buttons.removeAll()
        let colW = Self.size.width / 3
        let btn: CGFloat = 46
        for (ti, tree) in Skills.trees.enumerated() {
            let cx = -Self.size.width / 2 + colW * (CGFloat(ti) + 0.5)
            let header = SKLabelNode(fontNamed: "PingFangSC-Semibold")
            header.text = tree.name
            header.fontSize = 14
            header.fontColor = SkillVisuals.color(tree.id)
            header.position = CGPoint(x: cx, y: Self.size.height / 2 - 56)
            content.addChild(header)
            if ti > 0 {
                let sep = SKShapeNode(rectOf: CGSize(width: 1, height: Self.size.height - 90))
                sep.fillColor = NSColor(white: 0.25, alpha: 1); sep.strokeColor = .clear
                sep.position = CGPoint(x: cx - colW / 2, y: -10)
                content.addChild(sep)
            }
            func pos(_ d: SkillDef) -> CGPoint {
                CGPoint(x: cx + CGFloat(d.column - 1) * 60, y: Self.size.height / 2 - 100 - CGFloat(d.tier) * 66)
            }
            // Prerequisite lines first.
            for d in Skills.inTree(tree.id) {
                for pre in d.prerequisites {
                    guard let pd = Skills.def(pre) else { continue }
                    let path = CGMutablePath()
                    path.move(to: pos(pd)); path.addLine(to: pos(d))
                    let line = SKShapeNode(path: path)
                    line.strokeColor = p.skills.level(pre) > 0 ? SkillVisuals.color(tree.id).withAlphaComponent(0.7) : NSColor(white: 0.25, alpha: 1)
                    line.lineWidth = 2
                    line.zPosition = -1
                    content.addChild(line)
                }
            }
            for d in Skills.inTree(tree.id) {
                let lv = p.skills.level(d.id)
                let learnable = p.skills.learnError(d.id, characterLevel: p.level, points: p.skillPoints) == nil
                let c = pos(d)
                let box = SKShapeNode(rectOf: CGSize(width: btn, height: btn), cornerRadius: d.kind == .passive ? btn / 2 : 6)
                box.position = c
                let base = SkillVisuals.color(tree.id)
                box.fillColor = lv > 0 ? base.blended(withFraction: 0.55, of: .black)! : NSColor(white: 0.08, alpha: 1)
                box.strokeColor = learnable ? ItemVisuals.gold : (lv > 0 ? base : NSColor(white: 0.3, alpha: 1))
                box.lineWidth = learnable ? 2.5 : 1.5
                content.addChild(box)
                let name = SKLabelNode(fontNamed: "PingFangSC-Semibold")
                name.text = SkillVisuals.badge(d)
                name.fontSize = 14
                name.fontColor = lv > 0 ? .white : NSColor(white: p.level >= d.requiredLevel ? 0.6 : 0.35, alpha: 1)
                name.verticalAlignmentMode = .center
                name.position = c
                content.addChild(name)
                let lvl = SKLabelNode(fontNamed: "Menlo-Bold")
                lvl.text = "\(lv)"
                lvl.fontSize = 11
                lvl.fontColor = lv > 0 ? ItemVisuals.gold : NSColor(white: 0.4, alpha: 1)
                lvl.position = CGPoint(x: c.x + btn / 2 - 6, y: c.y - btn / 2 + 3)
                content.addChild(lvl)
                if let key = p.hotbar.first(where: { $0.value == d.id })?.key {
                    let k = SKLabelNode(fontNamed: "Menlo-Bold")
                    k.text = key == "rmb" ? "右" : key.uppercased()
                    k.fontSize = 10
                    k.fontColor = NSColor(calibratedRed: 0.6, green: 0.8, blue: 1, alpha: 1)
                    k.position = CGPoint(x: c.x - btn / 2 + 7, y: c.y + btn / 2 - 12)
                    content.addChild(k)
                }
                buttons.append((d.id, CGRect(x: c.x - btn / 2, y: c.y - btn / 2, width: btn, height: btn)))
            }
        }
    }
}

/// Bottom-center skill bar: RMB, Q, W, E, R.
final class Hotbar: SKNode {
    private var slots: [String: (SKShapeNode, SKLabelNode, SKSpriteNode)] = [:]
    static let slotSize: CGFloat = 44

    override init() {
        super.init()
        zPosition = 20_000
        for (i, key) in Player.hotbarKeys.enumerated() {
            let x = (CGFloat(i) - 2) * (Self.slotSize + 6)
            let box = SKShapeNode(rectOf: CGSize(width: Self.slotSize, height: Self.slotSize), cornerRadius: 5)
            box.position = CGPoint(x: x, y: 0)
            box.fillColor = NSColor(white: 0.05, alpha: 0.85)
            box.strokeColor = NSColor(calibratedRed: 0.45, green: 0.38, blue: 0.25, alpha: 1)
            addChild(box)
            let name = SKLabelNode(fontNamed: "PingFangSC-Semibold")
            name.fontSize = 13
            name.verticalAlignmentMode = .center
            box.addChild(name)
            let k = SKLabelNode(fontNamed: "Menlo-Bold")
            k.text = key == "rmb" ? "右键" : key.uppercased()
            k.fontSize = 9
            k.fontColor = NSColor(white: 0.7, alpha: 1)
            k.position = CGPoint(x: -Self.slotSize / 2 + 12, y: Self.slotSize / 2 - 11)
            box.addChild(k)
            let cd = SKSpriteNode(color: NSColor(white: 0, alpha: 0.65), size: CGSize(width: Self.slotSize, height: Self.slotSize))
            cd.anchorPoint = CGPoint(x: 0.5, y: 0)
            cd.position = CGPoint(x: 0, y: -Self.slotSize / 2)
            cd.yScale = 0
            box.addChild(cd)
            slots[key] = (box, name, cd)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(_ p: Player, time: Double) {
        for key in Player.hotbarKeys {
            guard let (box, name, cd) = slots[key] else { continue }
            if let id = p.hotbar[key], let d = Skills.def(id) {
                name.text = SkillVisuals.badge(d)
                let n = p.skills.numbers(id)
                let affordable = p.stats.mana >= n.manaCost
                name.fontColor = affordable ? .white : ItemVisuals.bad
                box.fillColor = SkillVisuals.color(d.tree).blended(withFraction: 0.65, of: .black)!
                let until = p.cooldowns[id] ?? 0
                cd.yScale = n.cooldown > 0 && until > time ? CGFloat((until - time) / n.cooldown) : 0
                let active = p.buffs.contains { $0.skillID == id }
                box.strokeColor = active ? ItemVisuals.gold : NSColor(calibratedRed: 0.45, green: 0.38, blue: 0.25, alpha: 1)
            } else {
                name.text = ""
                box.fillColor = NSColor(white: 0.05, alpha: 0.85)
                cd.yScale = 0
            }
        }
    }
}
