/// A* over the tile grid (8-directional, no corner cutting) + line-of-sight smoothing.
public enum Pathfinder {
    public static func findPath(on map: TileMap, from start: GridPoint, to goal: GridPoint,
                                maxExpanded: Int = 6000) -> [GridPoint]? {
        guard map.isWalkable(start), map.isWalkable(goal) else { return nil }
        if start == goal { return [start] }

        var open = BinaryHeap<Node>()
        var cameFrom: [GridPoint: GridPoint] = [:]
        var g: [GridPoint: Double] = [start: 0]
        open.push(Node(p: start, f: heuristic(start, goal)))
        var expanded = 0

        while let cur = open.pop() {
            if cur.p == goal { return reconstruct(cameFrom, goal) }
            expanded += 1
            if expanded > maxExpanded { return nil }
            let gc = g[cur.p]!
            if cur.f - heuristic(cur.p, goal) > gc + 1e-9 { continue }  // stale entry

            for d in GridPoint.neighbors8 {
                let n = cur.p + d
                guard map.isWalkable(n) else { continue }
                let diagonal = d.x != 0 && d.y != 0
                if diagonal && (!map.isWalkable(GridPoint(cur.p.x + d.x, cur.p.y)) ||
                                !map.isWalkable(GridPoint(cur.p.x, cur.p.y + d.y))) { continue }
                let cost = gc + (diagonal ? 1.41421356 : 1)
                if cost < g[n] ?? .infinity {
                    g[n] = cost
                    cameFrom[n] = cur.p
                    open.push(Node(p: n, f: cost + heuristic(n, goal)))
                }
            }
        }
        return nil
    }

    /// Octile distance.
    static func heuristic(_ a: GridPoint, _ b: GridPoint) -> Double {
        let dx = Double(abs(a.x - b.x)), dy = Double(abs(a.y - b.y))
        return max(dx, dy) + (1.41421356 - 1) * min(dx, dy)
    }

    private static func reconstruct(_ cameFrom: [GridPoint: GridPoint], _ goal: GridPoint) -> [GridPoint] {
        var path = [goal]
        var cur = goal
        while let prev = cameFrom[cur] { path.append(prev); cur = prev }
        return path.reversed()
    }

    /// True if a body of `radius` can travel in a straight line from a to b.
    public static func clearLine(on map: TileMap, from a: Vec2, to b: Vec2, radius: Double = 0.25) -> Bool {
        let dist = a.distance(to: b)
        let steps = max(1, Int(dist / 0.2))
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let p = a + (b - a) * t
            for o in [Vec2(-radius, -radius), Vec2(radius, -radius), Vec2(-radius, radius), Vec2(radius, radius)] {
                if !map.isWalkable((p + o).grid) { return false }
            }
        }
        return true
    }

    /// Turn a tile path into a few world waypoints by skipping nodes with direct line of sight.
    public static func smooth(_ path: [GridPoint], from start: Vec2, on map: TileMap, radius: Double = 0.25) -> [Vec2] {
        let pts = path.map { Vec2(center: $0) }
        guard !pts.isEmpty else { return [] }
        var result: [Vec2] = []
        var anchor = start
        var i = 0
        while i < pts.count {
            var j = pts.count - 1
            while j > i && !clearLine(on: map, from: anchor, to: pts[j], radius: radius) { j -= 1 }
            result.append(pts[j])
            anchor = pts[j]
            i = j + 1
        }
        return result
    }

    /// Nearest walkable tile to `p` (spiral search), used when the player clicks a wall.
    public static func nearestWalkable(on map: TileMap, to p: GridPoint, maxRadius: Int = 6) -> GridPoint? {
        if map.isWalkable(p) { return p }
        for r in 1...maxRadius {
            var best: GridPoint?
            var bestD = Int.max
            for dy in -r...r { for dx in -r...r where max(abs(dx), abs(dy)) == r {
                let q = GridPoint(p.x + dx, p.y + dy)
                let d = dx * dx + dy * dy
                if map.isWalkable(q) && d < bestD { best = q; bestD = d }
            } }
            if let best { return best }
        }
        return nil
    }

    struct Node: Comparable {
        let p: GridPoint
        let f: Double
        static func < (a: Node, b: Node) -> Bool { a.f < b.f }
    }
}

/// Minimal binary min-heap.
public struct BinaryHeap<T: Comparable> {
    private var items: [T] = []
    public init() {}
    public var isEmpty: Bool { items.isEmpty }
    public var count: Int { items.count }

    public mutating func push(_ x: T) {
        items.append(x)
        var i = items.count - 1
        while i > 0 {
            let parent = (i - 1) / 2
            if items[i] < items[parent] { items.swapAt(i, parent); i = parent } else { break }
        }
    }

    public mutating func pop() -> T? {
        guard !items.isEmpty else { return nil }
        items.swapAt(0, items.count - 1)
        let top = items.removeLast()
        var i = 0
        while true {
            let l = 2 * i + 1, r = l + 1
            var m = i
            if l < items.count && items[l] < items[m] { m = l }
            if r < items.count && items[r] < items[m] { m = r }
            if m == i { break }
            items.swapAt(i, m); i = m
        }
        return top
    }
}
