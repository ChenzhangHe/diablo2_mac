/// Grid inventory where items occupy w×h cells.
public struct Inventory: Codable, Sendable {
    public struct Entry: Codable, Sendable, Equatable {
        public var item: Item
        public var x: Int, y: Int
    }

    public let width: Int
    public let height: Int
    public private(set) var entries: [Entry] = []

    public init(width: Int = 10, height: Int = 4) {
        self.width = width
        self.height = height
    }

    public func entry(at x: Int, _ y: Int) -> Entry? {
        entries.first { x >= $0.x && x < $0.x + $0.item.base.size.w && y >= $0.y && y < $0.y + $0.item.base.size.h }
    }

    /// Items overlapping the rectangle.
    public func overlapping(x: Int, y: Int, size: ItemSize) -> [Entry] {
        entries.filter { e in
            let s = e.item.base.size
            return x < e.x + s.w && x + size.w > e.x && y < e.y + s.h && y + size.h > e.y
        }
    }

    public func fits(_ size: ItemSize, x: Int, y: Int) -> Bool {
        x >= 0 && y >= 0 && x + size.w <= width && y + size.h <= height && overlapping(x: x, y: y, size: size).isEmpty
    }

    public func firstFit(_ size: ItemSize) -> (Int, Int)? {
        for x in 0..<width { for y in 0..<height where fits(size, x: x, y: y) { return (x, y) } }
        return nil
    }

    @discardableResult
    public mutating func add(_ item: Item) -> Bool {
        guard let (x, y) = firstFit(item.base.size) else { return false }
        entries.append(Entry(item: item, x: x, y: y))
        return true
    }

    @discardableResult
    public mutating func place(_ item: Item, x: Int, y: Int) -> Bool {
        guard fits(item.base.size, x: x, y: y) else { return false }
        entries.append(Entry(item: item, x: x, y: y))
        return true
    }

    /// Place at (x,y), swapping out exactly one blocking item (classic cursor swap). Returns the displaced item.
    public mutating func placeSwapping(_ item: Item, x: Int, y: Int) -> (ok: Bool, displaced: Item?) {
        let s = item.base.size
        guard x >= 0, y >= 0, x + s.w <= width, y + s.h <= height else { return (false, nil) }
        let blockers = overlapping(x: x, y: y, size: s)
        if blockers.count > 1 { return (false, nil) }
        if let b = blockers.first { remove(id: b.item.id) }
        entries.append(Entry(item: item, x: x, y: y))
        return (true, blockers.first?.item)
    }

    @discardableResult
    public mutating func remove(id: Int) -> Item? {
        guard let i = entries.firstIndex(where: { $0.item.id == id }) else { return nil }
        return entries.remove(at: i).item
    }

    public var items: [Item] { entries.map(\.item) }
}
