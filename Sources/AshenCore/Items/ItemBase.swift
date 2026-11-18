public enum ItemCategory: String, Codable, Sendable, CaseIterable {
    case weapon, shield, helm, armor, gloves, boots, belt, ring, amulet, potion

    public var displayName: String {
        switch self {
        case .weapon: "武器"
        case .shield: "盾牌"
        case .helm: "头盔"
        case .armor: "护甲"
        case .gloves: "手套"
        case .boots: "靴子"
        case .belt: "腰带"
        case .ring: "戒指"
        case .amulet: "护符"
        case .potion: "药剂"
        }
    }

    public var isArmorPiece: Bool { [.shield, .helm, .armor, .gloves, .boots, .belt].contains(self) }
    public var isJewelry: Bool { self == .ring || self == .amulet }
}

public enum EquipSlot: String, Codable, Sendable, CaseIterable {
    case weapon, offhand, head, body, hands, feet, waist, neck, leftRing, rightRing

    public var displayName: String {
        switch self {
        case .weapon: "主手"
        case .offhand: "副手"
        case .head: "头部"
        case .body: "身体"
        case .hands: "手部"
        case .feet: "脚部"
        case .waist: "腰部"
        case .neck: "颈部"
        case .leftRing: "左戒"
        case .rightRing: "右戒"
        }
    }

    public static func slots(for c: ItemCategory) -> [EquipSlot] {
        switch c {
        case .weapon: [.weapon]
        case .shield: [.offhand]
        case .helm: [.head]
        case .armor: [.body]
        case .gloves: [.hands]
        case .boots: [.feet]
        case .belt: [.waist]
        case .amulet: [.neck]
        case .ring: [.leftRing, .rightRing]
        case .potion: []
        }
    }
}

public struct ItemSize: Codable, Sendable, Equatable {
    public var w: Int, h: Int
    public init(_ w: Int, _ h: Int) { self.w = w; self.h = h }
}

/// A base item type ("白板"). Quality level (qlvl) gates which areas can drop it.
public struct ItemBase: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let category: ItemCategory
    public let size: ItemSize
    public let qlvl: Int
    public var damage: ClosedRange<Int>? = nil       // weapons
    public var attacksPerSecond: Double = 0          // weapons
    public var defense: ClosedRange<Int>? = nil      // armor pieces
    public var block: Int = 0                        // shields, percent
    public var reqStr = 0
    public var reqDex = 0
    public var maxSockets = 0
}

public enum ItemBases {
    static func weapon(_ id: String, _ name: String, qlvl: Int, dmg: ClosedRange<Int>, aps: Double,
                       str: Int = 0, dex: Int = 0, size: ItemSize = ItemSize(1, 3), sockets: Int = 2) -> ItemBase {
        ItemBase(id: id, name: name, category: .weapon, size: size, qlvl: qlvl, damage: dmg,
                 attacksPerSecond: aps, reqStr: str, reqDex: dex, maxSockets: sockets)
    }

    static func armor(_ id: String, _ name: String, _ cat: ItemCategory, qlvl: Int, def: ClosedRange<Int>,
                      str: Int = 0, size: ItemSize, block: Int = 0, sockets: Int = 0) -> ItemBase {
        ItemBase(id: id, name: name, category: cat, size: size, qlvl: qlvl, defense: def, block: block,
                 reqStr: str, maxSockets: sockets)
    }

    public static let all: [ItemBase] = [
        // Weapons — fast/weak to slow/heavy
        weapon("dirk", "匕刃", qlvl: 1, dmg: 1...5, aps: 2.0, dex: 15, size: ItemSize(1, 2), sockets: 1),
        weapon("short_blade", "短剑", qlvl: 1, dmg: 2...7, aps: 1.6),
        weapon("hatchet", "手斧", qlvl: 3, dmg: 3...7, aps: 1.5, str: 20, size: ItemSize(2, 3)),
        weapon("cudgel", "棍棒", qlvl: 4, dmg: 2...9, aps: 1.4, str: 15, size: ItemSize(1, 3)),
        weapon("broadsword", "阔剑", qlvl: 8, dmg: 4...12, aps: 1.5, str: 35, dex: 20),
        weapon("war_pick", "战镐", qlvl: 12, dmg: 6...14, aps: 1.3, str: 50, size: ItemSize(2, 3), sockets: 3),
        weapon("knight_blade", "骑士长剑", qlvl: 18, dmg: 8...19, aps: 1.5, str: 60, dex: 35, sockets: 3),
        weapon("maul", "重锤", qlvl: 22, dmg: 12...24, aps: 1.1, str: 80, size: ItemSize(2, 3), sockets: 3),

        // Body armor
        armor("tunic", "粗布衣", .armor, qlvl: 1, def: 3...6, size: ItemSize(2, 3), sockets: 1),
        armor("leather_jerkin", "皮甲", .armor, qlvl: 2, def: 8...11, str: 12, size: ItemSize(2, 3), sockets: 2),
        armor("studded_vest", "镶钉背心", .armor, qlvl: 7, def: 16...21, str: 27, size: ItemSize(2, 3), sockets: 2),
        armor("scale_hauberk", "鳞甲", .armor, qlvl: 13, def: 28...35, str: 45, size: ItemSize(2, 3), sockets: 3),
        armor("plate_cuirass", "板甲胸铠", .armor, qlvl: 20, def: 45...55, str: 70, size: ItemSize(2, 3), sockets: 3),

        // Helms
        armor("hood", "兜帽", .helm, qlvl: 1, def: 2...4, size: ItemSize(2, 2), sockets: 1),
        armor("iron_cap", "铁盔", .helm, qlvl: 5, def: 6...9, str: 20, size: ItemSize(2, 2), sockets: 2),
        armor("barbute", "护面盔", .helm, qlvl: 14, def: 14...19, str: 40, size: ItemSize(2, 2), sockets: 2),

        // Shields
        armor("buckler", "小圆盾", .shield, qlvl: 1, def: 3...6, size: ItemSize(2, 2), block: 15, sockets: 1),
        armor("kite_shield", "鸢形盾", .shield, qlvl: 8, def: 10...15, str: 35, size: ItemSize(2, 3), block: 22, sockets: 2),
        armor("bulwark", "壁垒巨盾", .shield, qlvl: 18, def: 22...30, str: 65, size: ItemSize(2, 3), block: 30, sockets: 3),

        // Gloves / boots / belts
        armor("wraps", "布裹手", .gloves, qlvl: 1, def: 1...3, size: ItemSize(2, 2)),
        armor("gauntlets", "铁护手", .gloves, qlvl: 10, def: 6...10, str: 35, size: ItemSize(2, 2)),
        armor("sandals", "草鞋", .boots, qlvl: 1, def: 1...3, size: ItemSize(2, 2)),
        armor("greaves", "铁胫靴", .boots, qlvl: 10, def: 6...10, str: 35, size: ItemSize(2, 2)),
        armor("sash", "腰绳", .belt, qlvl: 1, def: 1...2, size: ItemSize(2, 1)),
        armor("girdle", "宽腰带", .belt, qlvl: 9, def: 4...7, str: 25, size: ItemSize(2, 1)),

        // Jewelry
        ItemBase(id: "ring", name: "戒指", category: .ring, size: ItemSize(1, 1), qlvl: 1),
        ItemBase(id: "amulet", name: "护符", category: .amulet, size: ItemSize(1, 1), qlvl: 1),
    ]

    public static let healthPotion = ItemBase(id: "potion_health", name: "治疗药剂", category: .potion,
                                              size: ItemSize(1, 1), qlvl: 1)
    public static let manaPotion = ItemBase(id: "potion_mana", name: "法力药剂", category: .potion,
                                            size: ItemSize(1, 1), qlvl: 1)

    public static let portalScroll = ItemBase(id: "scroll_portal", name: "回城卷轴", category: .potion,
                                              size: ItemSize(1, 1), qlvl: 1)

    public static let consumables = [healthPotion, manaPotion, portalScroll]

    public static func base(_ id: String) -> ItemBase? {
        all.first { $0.id == id } ?? consumables.first { $0.id == id }
    }
}
