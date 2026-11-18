public struct GridPoint: Hashable, Sendable, CustomStringConvertible {
    public var x: Int
    public var y: Int
    public init(_ x: Int, _ y: Int) { self.x = x; self.y = y }

    public static func + (a: GridPoint, b: GridPoint) -> GridPoint { GridPoint(a.x + b.x, a.y + b.y) }
    public static func - (a: GridPoint, b: GridPoint) -> GridPoint { GridPoint(a.x - b.x, a.y - b.y) }

    public static let cardinals = [GridPoint(1, 0), GridPoint(-1, 0), GridPoint(0, 1), GridPoint(0, -1)]
    public static let neighbors8 = cardinals + [GridPoint(1, 1), GridPoint(1, -1), GridPoint(-1, 1), GridPoint(-1, -1)]

    public var description: String { "(\(x), \(y))" }
}

/// Continuous world position in tile units (1.0 = one tile).
public struct Vec2: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    public static let zero = Vec2(0, 0)

    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    public static func * (a: Vec2, s: Double) -> Vec2 { Vec2(a.x * s, a.y * s) }
    public var length: Double { (x * x + y * y).squareRoot() }
    public var normalized: Vec2 { let l = length; return l > 0 ? Vec2(x / l, y / l) : .zero }
    public func distance(to o: Vec2) -> Double { (self - o).length }

    /// Center of a grid tile.
    public init(center p: GridPoint) { self.init(Double(p.x) + 0.5, Double(p.y) + 0.5) }
    public var grid: GridPoint { GridPoint(Int(x.rounded(.down)), Int(y.rounded(.down))) }
}
