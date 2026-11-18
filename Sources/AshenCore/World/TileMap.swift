public enum Tile: UInt8, Sendable {
    case void, floor, wall, door, tree, rock, water, path

    public var walkable: Bool { self == .floor || self == .door || self == .path }
    /// Tall obstacles that are drawn as blocks and can hide the player.
    public var isTall: Bool { self == .wall || self == .tree }
}

public struct TileMap: Sendable {
    public let width: Int
    public let height: Int
    private var tiles: [Tile]

    public init(width: Int, height: Int, fill: Tile = .void) {
        self.width = width
        self.height = height
        tiles = Array(repeating: fill, count: width * height)
    }

    public func contains(_ p: GridPoint) -> Bool { p.x >= 0 && p.y >= 0 && p.x < width && p.y < height }

    public subscript(_ p: GridPoint) -> Tile {
        get { contains(p) ? tiles[p.y * width + p.x] : .void }
        set { if contains(p) { tiles[p.y * width + p.x] = newValue } }
    }

    public subscript(x: Int, y: Int) -> Tile {
        get { self[GridPoint(x, y)] }
        set { self[GridPoint(x, y)] = newValue }
    }

    public func isWalkable(_ p: GridPoint) -> Bool { self[p].walkable }

    public var allPoints: [GridPoint] {
        (0..<height).flatMap { y in (0..<width).map { x in GridPoint(x, y) } }
    }

    /// All walkable tiles reachable from `start` (4-connected).
    public func reachable(from start: GridPoint) -> Set<GridPoint> {
        guard isWalkable(start) else { return [] }
        var seen: Set<GridPoint> = [start]
        var stack = [start]
        while let p = stack.popLast() {
            for d in GridPoint.cardinals {
                let n = p + d
                if isWalkable(n), seen.insert(n).inserted { stack.append(n) }
            }
        }
        return seen
    }
}

extension TileMap {
    /// BFS step distance from `start` over walkable tiles (4-connected). Unreachable = nil.
    public func distances(from start: GridPoint) -> [GridPoint: Int] {
        guard isWalkable(start) else { return [:] }
        var dist: [GridPoint: Int] = [start: 0]
        var queue = [start]
        var head = 0
        while head < queue.count {
            let p = queue[head]; head += 1
            for d in GridPoint.cardinals {
                let n = p + d
                if isWalkable(n) && dist[n] == nil { dist[n] = dist[p]! + 1; queue.append(n) }
            }
        }
        return dist
    }
}
