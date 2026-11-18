/// Builds the map for an area according to its style.
public enum LevelGenerator {
    public static func generate(_ area: AreaDef, seed: UInt64) -> GeneratedLevel {
        var level: GeneratedLevel
        switch area.style {
        case .dungeon:
            level = DungeonGenerator(width: area.size, height: area.size, maxRooms: area.size / 4).generate(seed: seed)
        case .cave:
            level = cave(size: area.size, seed: seed)
        case .outdoor:
            level = outdoor(size: area.size, seed: seed)
        case .town:
            level = town(size: area.size, seed: seed)
        case .arena:
            level = arena(size: area.size)
        }
        if area.hasWaypoint && level.waypoint == nil { level.waypoint = waypointSpot(level) }
        return level
    }

    // MARK: - Helpers

    /// Exit = farthest reachable tile from the spawn.
    static func farthest(from spawn: GridPoint, on map: TileMap) -> GridPoint {
        map.distances(from: spawn).max { $0.value < $1.value }?.key ?? spawn
    }

    /// Sample spread-out pseudo-rooms over open floor so monster packs have places to spawn.
    static func pseudoRooms(on map: TileMap, avoid: GridPoint, count: Int, rng: inout SeededRNG) -> [Room] {
        let floors = map.allPoints.filter { map.isWalkable($0) }
        guard !floors.isEmpty else { return [] }
        var centers: [GridPoint] = [avoid]
        for _ in 0..<(count * 30) where centers.count <= count {
            let p = floors[rng.int(0...(floors.count - 1))]
            if centers.allSatisfy({ abs($0.x - p.x) + abs($0.y - p.y) > 10 }) { centers.append(p) }
        }
        return centers.map { Room(x: $0.x - 2, y: $0.y - 2, w: 5, h: 5) }
    }

    /// Keep only the region connected to `start`; everything else becomes `fill`.
    static func prune(_ map: inout TileMap, from start: GridPoint, fill: Tile) {
        let keep = map.reachable(from: start)
        for p in map.allPoints where map[p].walkable && !keep.contains(p) { map[p] = fill }
    }

    static func waypointSpot(_ level: GeneratedLevel) -> GridPoint? {
        let d = level.map.distances(from: level.spawn)
        // A few tiles from the entrance, with open space around.
        return d.filter { e in e.value >= 4 && e.value <= 8 && GridPoint.neighbors8.allSatisfy { level.map.isWalkable(e.key + $0) } }
            .min { ($0.value, $0.key.x, $0.key.y) < ($1.value, $1.key.x, $1.key.y) }?.key
    }

    static func carveDisc(_ map: inout TileMap, _ c: GridPoint, r: Int, tile: Tile = .floor) {
        for dy in -r...r { for dx in -r...r where dx * dx + dy * dy <= r * r {
            let p = GridPoint(c.x + dx, c.y + dy)
            if p.x > 0 && p.y > 0 && p.x < map.width - 1 && p.y < map.height - 1 { map[p] = tile }
        } }
    }

    // MARK: - Cave (cellular automata)

    static func cave(size: Int, seed: UInt64) -> GeneratedLevel {
        var rng = SeededRNG(seed: seed)
        var map = TileMap(width: size, height: size, fill: .wall)
        for p in map.allPoints where p.x > 1 && p.y > 1 && p.x < size - 2 && p.y < size - 2 {
            map[p] = rng.chance(0.43) ? .wall : .floor
        }
        for _ in 0..<5 {
            var next = map
            for p in map.allPoints where p.x > 0 && p.y > 0 && p.x < size - 1 && p.y < size - 1 {
                let walls = GridPoint.neighbors8.filter { !map[p + $0].walkable }.count
                next[p] = walls >= 5 ? .wall : (walls <= 3 ? .floor : map[p])
            }
            map = next
        }
        // Largest region becomes the cave.
        var best: Set<GridPoint> = []
        var seen: Set<GridPoint> = []
        for p in map.allPoints where map.isWalkable(p) && !seen.contains(p) {
            let region = map.reachable(from: p)
            seen.formUnion(region)
            if region.count > best.count { best = region }
        }
        for p in map.allPoints where map.isWalkable(p) && !best.contains(p) { map[p] = .wall }
        let spawn = best.min { ($0.x + $0.y, $0.x) < ($1.x + $1.y, $1.x) } ?? GridPoint(size / 2, size / 2)
        let exit = farthest(from: spawn, on: map)
        let rooms = pseudoRooms(on: map, avoid: spawn, count: size * size / 260, rng: &rng)
        return GeneratedLevel(map: map, rooms: rooms, spawn: spawn, exit: exit)
    }

    // MARK: - Outdoor (open field with tree / rock / pond clusters)

    static func outdoor(size: Int, seed: UInt64) -> GeneratedLevel {
        var rng = SeededRNG(seed: seed)
        var map = TileMap(width: size, height: size, fill: .floor)
        for p in map.allPoints where p.x == 0 || p.y == 0 || p.x == size - 1 || p.y == size - 1 { map[p] = .tree }
        // Thick tree border with ragged edge.
        for p in map.allPoints {
            let edge = min(p.x, p.y, size - 1 - p.x, size - 1 - p.y)
            if edge < 2 || (edge < 4 && rng.chance(0.5)) { map[p] = .tree }
        }
        // Obstacle clusters.
        let clusters = size * size / 120
        for _ in 0..<clusters {
            let c = GridPoint(rng.int(4...(size - 5)), rng.int(4...(size - 5)))
            let kind: Tile = rng.chance(0.55) ? .tree : (rng.chance(0.5) ? .rock : .water)
            let r = kind == .water ? rng.int(2...4) : rng.int(1...3)
            for dy in -r...r { for dx in -r...r where dx * dx + dy * dy <= r * r && rng.chance(kind == .water ? 0.95 : 0.6) {
                let p = GridPoint(c.x + dx, c.y + dy)
                if map[p] == .floor { map[p] = kind }
            } }
        }
        // Spawn on one edge, exit on the opposite; carve a winding dirt path between.
        let horizontal = rng.chance(0.5)
        let spawn = horizontal ? GridPoint(5, rng.int(8...(size - 9))) : GridPoint(rng.int(8...(size - 9)), 5)
        let goal = horizontal ? GridPoint(size - 6, rng.int(8...(size - 9))) : GridPoint(rng.int(8...(size - 9)), size - 6)
        var p = spawn
        while p != goal {
            carveDisc(&map, p, r: 1, tile: .path)
            let dx = (goal.x - p.x).signum(), dy = (goal.y - p.y).signum()
            if rng.chance(0.3) {
                let side = horizontal ? GridPoint(0, rng.chance(0.5) ? 1 : -1) : GridPoint(rng.chance(0.5) ? 1 : -1, 0)
                let n = p + side
                if n.x > 4 && n.y > 4 && n.x < size - 5 && n.y < size - 5 { p = n; continue }
            }
            p = GridPoint(p.x + (horizontal ? dx : (rng.chance(0.25) ? dx : 0)),
                          p.y + (horizontal ? (rng.chance(0.25) ? dy : 0) : dy))
        }
        carveDisc(&map, spawn, r: 3)
        carveDisc(&map, goal, r: 2)
        prune(&map, from: spawn, fill: .tree)
        let rooms = pseudoRooms(on: map, avoid: spawn, count: size * size / 300, rng: &rng)
        return GeneratedLevel(map: map, rooms: rooms, spawn: spawn, exit: goal)
    }

    // MARK: - Town

    static func town(size: Int, seed: UInt64) -> GeneratedLevel {
        var rng = SeededRNG(seed: seed)
        var map = TileMap(width: size, height: size, fill: .floor)
        for p in map.allPoints {
            let edge = min(p.x, p.y, size - 1 - p.x, size - 1 - p.y)
            if edge == 0 { map[p] = .tree } else if edge == 1 { map[p] = .wall }   // palisade
        }
        let c = size / 2
        // Huts: small wall blocks.
        let huts = [GridPoint(c - 9, c - 9), GridPoint(c + 5, c - 9), GridPoint(c - 9, c + 5)]
        for h in huts { for y in 0..<4 { for x in 0..<4 { map[h.x + x, h.y + y] = .wall } } }
        // River on one side, crossed by a path.
        for y in 2..<(size - 2) { for x in (size - 6)..<(size - 3) { map[x, y] = .water } }
        for y in (c - 1)...(c + 1) { for x in (size - 6)..<(size - 1) { map[x, y] = .path } }
        map[size - 2, c] = .path; map[size - 1, c] = .path
        // Gate to the wilds.
        let gate = GridPoint(size - 2, c)
        for x in (c - 2)...(size - 2) { map[x, c] = .path }
        _ = rng.next()
        let markers: [String: GridPoint] = [
            "smith": GridPoint(c + 3, c - 4),
            "healer": GridPoint(c - 4, c + 3),
            "elder": GridPoint(c - 3, c - 3),
            "stash": GridPoint(c + 2, c + 3),
        ]
        return GeneratedLevel(map: map, rooms: [], spawn: GridPoint(c, c), exit: gate,
                              waypoint: GridPoint(c, c + 2), markers: markers)
    }

    // MARK: - Boss arena

    static func arena(size: Int) -> GeneratedLevel {
        var map = TileMap(width: size, height: size, fill: .void)
        let c = GridPoint(size / 2, size / 2)
        carveDisc(&map, c, r: size / 2 - 3)
        // Entry corridor from the south-west.
        for i in 0..<6 { carveDisc(&map, GridPoint(3 + i, size / 2), r: 1) }
        // Pillars.
        for (dx, dy) in [(-5, -5), (5, -5), (-5, 5), (5, 5)] { map[c.x + dx, c.y + dy] = .wall; map[c.x + dx + 1, c.y + dy] = .wall }
        for p in map.allPoints where map[p] == .void {
            if GridPoint.neighbors8.contains(where: { map[p + $0].walkable }) { map[p] = .wall }
        }
        let spawn = GridPoint(4, size / 2)
        return GeneratedLevel(map: map, rooms: [], spawn: spawn, exit: spawn, markers: ["boss": GridPoint(c.x + 4, c.y)])
    }
}
