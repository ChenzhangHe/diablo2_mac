import AppKit
import SpriteKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var scene: GameScene?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let size = NSSize(width: 1280, height: 800)
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Ashen Sigil"
        window.center()
        window.collectionBehavior = [.fullScreenPrimary]

        let view = SKView(frame: NSRect(origin: .zero, size: size))
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = 120
        #if DEBUG
        view.showsFPS = true
        view.showsNodeCount = true
        #endif
        window.contentView = view

        let env = ProcessInfo.processInfo.environment
        let debugRun = env["ASHEN_TITLE"] == nil && env.keys.contains { $0.hasPrefix("ASHEN_") }
        if debugRun {
            let scene = GameScene(size: size)
            scene.scaleMode = .resizeFill
            view.presentScene(scene)
            self.scene = scene
        } else {
            let title = TitleScene(size: size)
            title.scaleMode = .resizeFill
            view.presentScene(title)
        }

        window.makeKeyAndOrderFront(nil)
        Snapshot.scheduleIfRequested(view: view, window: window)
        window.makeFirstResponder(view)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        scene?.saveNow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
