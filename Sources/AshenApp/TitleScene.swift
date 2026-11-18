import AppKit
import SpriteKit
import AshenCore

/// Main menu: continue / new game / quit, over drifting embers.
final class TitleScene: SKScene {
    private var buttons: [(String, SKShapeNode)] = []
    private let save = try? SaveStore.default.load()
    private var confirmingNew = false

    override func didMove(to view: SKView) {
        backgroundColor = NSColor(calibratedWhite: 0.02, alpha: 1)
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        view.window?.acceptsMouseMovedEvents = true
        build()
        let embers = SKEmitterNode()
        embers.particleTexture = Textures.image(width: 6, height: 6) { ctx in
            ctx.setFillColor(CGColor(red: 1, green: 0.6, blue: 0.2, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: 0, y: 0, width: 6, height: 6))
        }
        embers.particleBirthRate = 18
        embers.particleLifetime = 7
        embers.particlePositionRange = CGVector(dx: 1400, dy: 0)
        embers.position = CGPoint(x: 0, y: -460)
        embers.particleSpeed = 70
        embers.particleSpeedRange = 40
        embers.emissionAngle = .pi / 2
        embers.emissionAngleRange = 0.5
        embers.particleAlphaSpeed = -0.14
        embers.particleScale = 0.6
        embers.particleScaleRange = 0.5
        embers.particleColor = NSColor(calibratedRed: 1, green: 0.5, blue: 0.15, alpha: 1)
        embers.particleColorBlendFactor = 1
        embers.particleBlendMode = .add
        embers.zPosition = -1
        embers.advanceSimulationTime(6)
        addChild(embers)
    }

    private func build() {
        children.filter { !($0 is SKEmitterNode) }.forEach { $0.removeFromParent() }
        buttons.removeAll()
        let title = SKLabelNode(fontNamed: "PingFangSC-Semibold")
        title.text = "灰 烬 圣 印"
        title.fontSize = 72
        title.fontColor = NSColor(calibratedRed: 0.85, green: 0.35, blue: 0.12, alpha: 1)
        title.position = CGPoint(x: 0, y: 150)
        addChild(title)
        let sub = SKLabelNode(fontNamed: "Georgia-Italic")
        sub.text = "A S H E N   S I G I L"
        sub.fontSize = 18
        sub.fontColor = NSColor(calibratedRed: 0.75, green: 0.68, blue: 0.5, alpha: 1)
        sub.position = CGPoint(x: 0, y: 115)
        addChild(sub)

        var items: [(String, String)] = []
        if let s = save, !confirmingNew { items.append(("continue", "继续游戏  ·  \(s.summary)")) }
        if confirmingNew {
            items.append(("confirm", "确定开始新游戏？（覆盖现有存档）"))
            items.append(("cancel", "取消"))
        } else {
            items.append(("new", "新游戏"))
            items.append(("quit", "退出"))
        }
        for (i, (id, text)) in items.enumerated() {
            let box = SKShapeNode(rectOf: CGSize(width: 380, height: 44), cornerRadius: 4)
            box.position = CGPoint(x: 0, y: 10 - CGFloat(i) * 60)
            box.fillColor = NSColor(calibratedRed: 0.1, green: 0.07, blue: 0.05, alpha: 0.9)
            box.strokeColor = NSColor(calibratedRed: 0.5, green: 0.4, blue: 0.25, alpha: 1)
            box.lineWidth = 1.5
            let l = SKLabelNode(fontNamed: "PingFangSC-Regular")
            l.text = text
            l.fontSize = 17
            l.fontColor = NSColor(calibratedRed: 0.9, green: 0.85, blue: 0.7, alpha: 1)
            l.verticalAlignmentMode = .center
            box.addChild(l)
            addChild(box)
            buttons.append((id, box))
        }
        let hint = SKLabelNode(fontNamed: "PingFangSC-Regular")
        hint.text = "左键移动/攻击 · 右键/QWER 技能 · I 物品 · C 角色 · T 技能 · L 任务 · Tab 地图 · P 回城"
        hint.fontSize = 12
        hint.fontColor = NSColor(white: 0.5, alpha: 1)
        hint.position = CGPoint(x: 0, y: -260)
        addChild(hint)
    }

    private func button(at e: NSEvent) -> String? {
        let p = e.location(in: self)
        return buttons.first { $0.1.contains(p) }?.0
    }

    override func mouseMoved(with event: NSEvent) {
        let hit = button(at: event)
        for (id, box) in buttons { box.strokeColor = id == hit ? NSColor(calibratedRed: 1, green: 0.75, blue: 0.4, alpha: 1)
                                                              : NSColor(calibratedRed: 0.5, green: 0.4, blue: 0.25, alpha: 1) }
    }

    override func mouseDown(with event: NSEvent) {
        switch button(at: event) {
        case "continue": start(newGame: false)
        case "new":
            if save != nil { confirmingNew = true; build() } else { start(newGame: true) }
        case "confirm": start(newGame: true)
        case "cancel": confirmingNew = false; build()
        case "quit": NSApp.terminate(nil)
        default: break
        }
    }

    private func start(newGame: Bool) {
        guard let view else { return }
        let scene = GameScene(size: view.bounds.size)
        scene.scaleMode = .resizeFill
        scene.startNewGame = newGame
        (NSApp.delegate as? AppDelegate)?.scene = scene
        view.presentScene(scene, transition: .fade(withDuration: 0.6))
    }
}
