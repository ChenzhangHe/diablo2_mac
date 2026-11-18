public struct Room: Sendable, Equatable {
    public var x, y, w, h: Int
    public var center: GridPoint { GridPoint(x + w / 2, y + h / 2) }
    func intersects(_ o: Room, margin: Int = 1) -> Bool {
        x - margin < o.x + o.w && x + w + margin > o.x && y - margin < o.y + o.h && y + h + margin > o.y
    }
}

public struct GeneratedLevel: Sendable {
    public var map: TileMap
    public var rooms: [Room]
    public var spawn: GridPoint
    public var exit: GridPoint
    public var waypoint: GridPoint? = nil
    /// Named spots (NPCs in town, boss position in arenas...).
    public var markers: [String: GridPoint] = [:]

    public init(map: TileMap, rooms: [Room], spawn: GridPoint, exit: GridPoint,
                waypoint: GridPoint? = nil, markers: [String: GridPoint] = [:]) {
        self.map = map; self.rooms = rooms; self.spawn = spawn; self.exit = exit
        self.waypoint = waypoint; self.markers = markers
    }
}

/// Classic rooms-and-corridors dungeon generator.
public struct DungeonGenerator {
    public var width = 64
    public var height = 64
    public var maxRooms = 14
    public var roomSize = 5...11

    public init(width: Int = 64, height: Int = 64, maxRooms: Int = 14) {
        self.width = width
        self.height = height
        self.maxRooms = maxRooms
    }

    public func generate(seed: UInt64) -> GeneratedLevel {
        var rng = SeededRNG(seed: seed)
        var map = TileMap(width: width, height: height)
        var rooms: [Room] = []

        for _ in 0..<(maxRooms * 8) where rooms.count < maxRooms {
            let w = rng.int(roomSize), h = rng.int(roomSize)
            let room = Room(x: rng.int(1...(width - w - 2)), y: rng.int(1...(height - h - 2)), w: w, h: h)
            if rooms.contains(where: { $0.intersects(room) }) { continue }
            carve(room, into: &map)
            if let prev = rooms.last { corridor(from: prev.center, to: room.center, map: &map, rng: &rng) }
            rooms.append(room)
        }

        // A few extra loops so the layout isn't a pure chain.
        for _ in 0..<(rooms.count / 4) where rooms.count > 2 {
            let a = rooms[rng.int(0...(rooms.count - 1))], b = rooms[rng.int(0...(rooms.count - 1))]
            corridor(from: a.center, to: b.center, map: &map, rng: &rng)
        }

        addWalls(&map)

        let spawn = rooms.first!.center
        // Exit in the room farthest (by BFS order proxy: Manhattan) from spawn.
        let exit = rooms.max { manhattan($0.center, spawn) < manhattan($1.center, spawn) }!.center
        return GeneratedLevel(map: map, rooms: rooms, spawn: spawn, exit: exit)
    }

    private func manhattan(_ a: GridPoint, _ b: GridPoint) -> Int { abs(a.x - b.x) + abs(a.y - b.y) }

    private func carve(_ r: Room, into map: inout TileMap) {
        for y in r.y..<(r.y + r.h) { for x in r.x..<(r.x + r.w) { map[x, y] = .floor } }
    }

    private func corridor(from a: GridPoint, to b: GridPoint, map: inout TileMap, rng: inout SeededRNG) {
        let horizontalFirst = rng.chance(0.5)
        let corner = horizontalFirst ? GridPoint(b.x, a.y) : GridPoint(a.x, b.y)
        line(a, corner, &map)
        line(corner, b, &map)
    }

    private func line(_ a: GridPoint, _ b: GridPoint, _ map: inout TileMap) {
        var p = a
        let dx = (b.x - a.x).signum(), dy = (b.y - a.y).signum()
        while true {
            map[p] = .floor
            if p == b { break }
            p = GridPoint(p.x + dx, p.y + dy)
        }
    }

    private func addWalls(_ map: inout TileMap) {
        for p in map.allPoints where map[p] == .void {
            if GridPoint.neighbors8.contains(where: { map[p + $0] == .floor }) { map[p] = .wall }
        }
    }
}
