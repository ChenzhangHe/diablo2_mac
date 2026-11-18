public enum Tile: UInt8, Sendable {
    case void, floor, wall, door

    public var walkable: Bool { self == .floor || self == .door }
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
