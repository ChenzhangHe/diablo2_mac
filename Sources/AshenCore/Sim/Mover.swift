/// Moves a body along waypoints with wall collision. Shared by the player and (later) monsters.
public struct Mover: Sendable {
    public var position: Vec2
    public var speed: Double          // tiles / second
    public var radius: Double = 0.28
    public private(set) var waypoints: [Vec2] = []
    public private(set) var facing = Vec2(1, 1).normalized

    public init(position: Vec2, speed: Double) {
        self.position = position
        self.speed = speed
    }

    public var isMoving: Bool { !waypoints.isEmpty }

    public mutating func stop() { waypoints.removeAll() }

    /// Path to `target`; returns false if unreachable.
    @discardableResult
    public mutating func moveTo(_ target: Vec2, on map: TileMap) -> Bool {
        guard let goal = Pathfinder.nearestWalkable(on: map, to: target.grid) else { return false }
        let dest = map.isWalkable(target.grid) ? target : Vec2(center: goal)
        if Pathfinder.clearLine(on: map, from: position, to: dest, radius: radius) {
            waypoints = [dest]
            return true
        }
        guard let path = Pathfinder.findPath(on: map, from: position.grid, to: goal) else { return false }
        var pts = Pathfinder.smooth(path, from: position, on: map, radius: radius)
        if !pts.isEmpty, map.isWalkable(target.grid) { pts[pts.count - 1] = dest }
        waypoints = pts
        return true
    }

    public mutating func update(dt: Double, map: TileMap) {
        var budget = speed * dt
        while budget > 0, let next = waypoints.first {
            let delta = next - position
            let dist = delta.length
            if dist > 1e-6 { facing = delta.normalized }
            if dist <= budget {
                position = next
                budget -= dist
                waypoints.removeFirst()
            } else {
                let step = delta.normalized * budget
                let before = position
                slide(step, map: map)
                if position.distance(to: before) < budget * 0.1 { waypoints.removeAll() } // stuck
                budget = 0
            }
        }
    }

    /// Direct movement (keyboard) with axis-separated wall sliding.
    public mutating func slide(_ step: Vec2, map: TileMap) {
        if step.length > 1e-6 { facing = step.normalized }
        tryMove(Vec2(step.x, 0), map)
        tryMove(Vec2(0, step.y), map)
    }

    private mutating func tryMove(_ d: Vec2, _ map: TileMap) {
        let n = position + d
        let r = radius
        let ok = [Vec2(n.x - r, n.y - r), Vec2(n.x + r, n.y - r), Vec2(n.x - r, n.y + r), Vec2(n.x + r, n.y + r)]
            .allSatisfy { map.isWalkable($0.grid) }
        if ok { position = n }
    }
}
