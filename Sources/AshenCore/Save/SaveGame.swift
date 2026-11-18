import Foundation

/// Everything that persists between sessions. World layout is regenerated from `seed`.
public struct SaveGame: Codable, Sendable, Equatable {
    public static let currentVersion = 1
    public var version = SaveGame.currentVersion
    public var seed: UInt64
    public var heroClass: String
    public var level: Int
    public var xp: Int
    public var attributes: Attributes
    public var statPoints: Int
    public var skillPoints: Int
    public var skills: SkillBook
    public var hotbar: [String: String]
    public var equipment: [String: Item]
    public var inventory: Inventory
    public var stash: Inventory
    public var gold: Int
    public var healthPotions: Int
    public var manaPotions: Int
    public var portalScrolls: Int
    public var waypoints: [String]
    public var quests: [String: QuestState]
    public var savedAt: Date

    public var summary: String { "等级 \(level) · \(gold) 金币" }
}

extension Inventory: Equatable {
    public static func == (a: Inventory, b: Inventory) -> Bool {
        a.width == b.width && a.height == b.height && a.entries == b.entries
    }
}

extension GameWorld {
    public func makeSave() -> SaveGame {
        let p = player
        return SaveGame(seed: seed, heroClass: p.heroClass.id, level: p.level, xp: p.xp, attributes: p.attributes,
                        statPoints: p.statPoints, skillPoints: p.skillPoints, skills: p.skills, hotbar: p.hotbar,
                        equipment: Dictionary(uniqueKeysWithValues: p.equipment.map { ($0.key.rawValue, $0.value) }),
                        inventory: p.inventory, stash: p.stash, gold: p.gold,
                        healthPotions: p.healthPotions, manaPotions: p.manaPotions, portalScrolls: p.portalScrolls,
                        waypoints: p.waypoints.sorted(), quests: p.quests, savedAt: Date())
    }

    /// Restore a saved hero into a fresh world (always starting in camp).
    public convenience init(save s: SaveGame) {
        self.init(seed: s.seed, startArea: "reedford")
        var p = player
        p.stats.level = s.level
        p.xp = s.xp
        p.attributes = s.attributes
        p.statPoints = s.statPoints
        p.skillPoints = s.skillPoints
        p.skills = s.skills
        p.hotbar = s.hotbar
        p.equipment = Dictionary(uniqueKeysWithValues: s.equipment.compactMap { k, v in EquipSlot(rawValue: k).map { ($0, v) } })
        p.inventory = s.inventory
        p.stash = s.stash
        p.gold = s.gold
        p.healthPotions = s.healthPotions
        p.manaPotions = s.manaPotions
        p.portalScrolls = s.portalScrolls
        p.waypoints = Set(s.waypoints)
        p.quests = s.quests
        p.recalculate()
        p.stats.life = p.stats.maxLife
        p.stats.mana = p.stats.maxMana
        player = p
        // Make sure new ids never collide with saved items.
        let maxID = (s.inventory.items + s.stash.items + Array(s.equipment.values)).map(\.id).max() ?? 0
        reserveIDs(above: maxID)
        restockVendors()
    }
}

/// Reads and writes the save file as JSON.
public struct SaveStore {
    public let url: URL

    public init(url: URL) { self.url = url }

    /// ~/Library/Application Support/AshenSigil/save.json
    public static var `default`: SaveStore {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AshenSigil", isDirectory: true)
        return SaveStore(url: dir.appendingPathComponent("save.json"))
    }

    public func save(_ s: SaveGame) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        // Write atomically so a crash mid-save can't corrupt the file.
        try enc.encode(s).write(to: url, options: .atomic)
    }

    public func load() throws -> SaveGame? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try dec.decode(SaveGame.self, from: Data(contentsOf: url))
    }

    public func delete() throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
