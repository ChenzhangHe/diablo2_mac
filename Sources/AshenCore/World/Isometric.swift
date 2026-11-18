/// 2:1 isometric projection. World tile (x, y) → screen point, y-up (SpriteKit convention).
public enum Iso {
    public static let tileWidth = 64.0
    public static let tileHeight = 32.0

    public static func toScreen(_ p: Vec2) -> (x: Double, y: Double) {
        let sx = (p.x - p.y) * tileWidth / 2
        let sy = -(p.x + p.y) * tileHeight / 2
        return (sx, sy)
    }

    public static func toWorld(screenX sx: Double, screenY sy: Double) -> Vec2 {
        let a = sx / (tileWidth / 2)      // x - y
        let b = -sy / (tileHeight / 2)    // x + y
        return Vec2((a + b) / 2, (b - a) / 2)
    }

    /// Depth key: larger = closer to the viewer = drawn on top.
    public static func depth(_ p: Vec2) -> Double { p.x + p.y }
}
