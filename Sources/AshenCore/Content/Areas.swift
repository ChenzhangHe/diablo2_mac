public enum MapStyle: String, Sendable {
    case town, outdoor, cave, dungeon, arena
}

/// Visual palette for tiles.
public enum TileTheme: String, Sendable {
    case village, swamp, forest, cave, abbey, crypt
}

/// A zone of the world, like an act's sub-area.
public struct AreaDef: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let act: Int
    public let level: Int                 // area level → monster level and item level
    public let style: MapStyle
    public let theme: TileTheme
    public let size: Int
    public let monsters: [MonsterKind]
    public let hasWaypoint: Bool
    public var isTown: Bool { style == .town }
}

public enum Areas {
    /// Act I — 灰雾沼泽: from the riverside camp down into the drowned abbey.
    public static let actOne: [AreaDef] = [
        AreaDef(id: "reedford", name: "芦苇渡口", act: 1, level: 0, style: .town, theme: .village, size: 36,
                monsters: [], hasWaypoint: true),
        AreaDef(id: "ashmire_fen", name: "灰雾沼泽", act: 1, level: 1, style: .outdoor, theme: .swamp, size: 72,
                monsters: [Bestiary.murkling, Bestiary.gloomBat, Bestiary.murkling], hasWaypoint: false),
        AreaDef(id: "rotroot_hollow", name: "腐根林地", act: 1, level: 3, style: .outdoor, theme: .forest, size: 80,
                monsters: [Bestiary.murkling, Bestiary.husk, Bestiary.hollowArcher, Bestiary.mireHexer, Bestiary.fenLurker],
                hasWaypoint: true),
        AreaDef(id: "seeping_caves", name: "渗水洞穴", act: 1, level: 4, style: .cave, theme: .cave, size: 70,
                monsters: [Bestiary.gloomBat, Bestiary.fenLurker, Bestiary.husk, Bestiary.mireHexer], hasWaypoint: false),
        AreaDef(id: "abbey_grounds", name: "沉没修道院·外院", act: 1, level: 5, style: .outdoor, theme: .abbey, size: 76,
                monsters: [Bestiary.husk, Bestiary.hollowArcher, Bestiary.drownedSister], hasWaypoint: true),
        AreaDef(id: "abbey_crypt", name: "修道院地窖", act: 1, level: 7, style: .dungeon, theme: .crypt, size: 70,
                monsters: [Bestiary.drownedSister, Bestiary.boneWarden, Bestiary.husk, Bestiary.hollowArcher], hasWaypoint: true),
        AreaDef(id: "abbess_sanctum", name: "院长圣所", act: 1, level: 8, style: .arena, theme: .crypt, size: 34,
                monsters: [], hasWaypoint: false),
    ]

    public static func def(_ id: String) -> AreaDef? { actOne.first { $0.id == id } }
    public static func index(of id: String) -> Int? { actOne.firstIndex { $0.id == id } }
}
