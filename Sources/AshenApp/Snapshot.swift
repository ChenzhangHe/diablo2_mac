import AppKit
import SpriteKit

/// Debug helper: `ASHEN_SNAPSHOT=/path/out.png` renders the window to a PNG after a delay, then quits.
enum Snapshot {
    static func scheduleIfRequested(view: SKView, window: NSWindow) {
        guard let path = ProcessInfo.processInfo.environment["ASHEN_SNAPSHOT"] else { return }
        let delay = Double(ProcessInfo.processInfo.environment["ASHEN_SNAPSHOT_DELAY"] ?? "") ?? 1.5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
            view.cacheDisplay(in: view.bounds, to: rep)
            var data = rep.representation(using: .png, properties: [:])
            if data == nil || isBlank(rep), let scene = view.scene, let tex = view.texture(from: scene) {
                data = NSBitmapImageRep(cgImage: tex.cgImage()).representation(using: .png, properties: [:])
            }
            try? data?.write(to: URL(fileURLWithPath: path))
            NSApp.terminate(nil)
        }
    }

    private static func isBlank(_ rep: NSBitmapImageRep) -> Bool {
        rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)?.alphaComponent == 0
    }
}
