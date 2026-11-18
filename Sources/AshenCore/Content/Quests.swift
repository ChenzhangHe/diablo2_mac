public enum QuestReward: Sendable, Equatable {
    case skillPoint
    case statPoints(Int)
    case rareItem(level: Int)
    case experience(Int)
}

public enum QuestState: String, Codable, Sendable {
    case notStarted, active, complete, rewarded
}

public struct QuestDef: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let giver: String              // NPC id
    public let area: String               // where the target lives
    public let targetName: String
    public let targetKind: MonsterKind
    public let targetAffixes: [EliteAffix]
    public let intro: String
    public let completion: String
    public let reward: QuestReward
    public let isMain: Bool

    public var rewardText: String {
        switch reward {
        case .skillPoint: "奖励：1 技能点"
        case .statPoints(let n): "奖励：\(n) 属性点"
        case .rareItem: "奖励：一件稀有装备"
        case .experience(let n): "奖励：\(n) 经验"
        }
    }
}

public enum Quests {
    public static let all: [QuestDef] = [
        QuestDef(id: "q_matron", name: "泥沼之母", giver: "elder", area: "ashmire_fen",
                 targetName: "泥沼之母", targetKind: Bestiary.murkling, targetAffixes: [.hulking, .berserk],
                 intro: "沼泽深处有个肥硕的怪物在孵化那些小鬼。杀了她，渡口才能喘口气。",
                 completion: "那东西死了？好！你的武艺配得上守烬人之名。", reward: .skillPoint, isMain: false),
        QuestDef(id: "q_priest", name: "腐喉祭司", giver: "healer", area: "seeping_caves",
                 targetName: "腐喉祭司", targetKind: Bestiary.mireHexer, targetAffixes: [.fireTouched, .swift],
                 intro: "洞穴里的巫医首领在用尸体做邪恶的仪式。阻止他，我会教你调息之法。",
                 completion: "你身上还带着焦糊的气味……谢谢你。闭上眼，感受力量流过你。", reward: .statPoints(5), isMain: false),
        QuestDef(id: "q_bell", name: "骨钟守卫长", giver: "smith", area: "abbey_crypt",
                 targetName: "骨钟守卫长", targetKind: Bestiary.boneWarden, targetAffixes: [.stoneskin, .hulking],
                 intro: "修道院地窖里有个守卫长，每敲一次骨钟，死者就站起来。把他砸碎。",
                 completion: "钟声停了。拿着，这是我这些年打得最好的东西。", reward: .rareItem(level: 10), isMain: false),
        QuestDef(id: "q_abbess", name: "溺亡院长", giver: "elder", area: "abbess_sanctum",
                 targetName: "溺亡院长 莫尔薇", targetKind: Bestiary.drownedSister, targetAffixes: [],
                 intro: "朝圣者击碎第一枚圣印时，修道院沉入了沼泽。院长莫尔薇守着碎片——她已不再是人。",
                 completion: "第一枚碎印……它在你手中发烫。前方还有更深的黑暗，守烬人。", reward: .experience(3000), isMain: true),
    ]

    public static func def(_ id: String) -> QuestDef? { all.first { $0.id == id } }
    public static func given(by npc: String) -> [QuestDef] { all.filter { $0.giver == npc } }
}
