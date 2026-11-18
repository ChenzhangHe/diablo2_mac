public struct NPCDef: Sendable, Identifiable {
    public enum Service: Sendable { case trade, heal, story, stash }
    public let id: String
    public let name: String
    public let title: String
    public let marker: String
    public let services: [Service]
    public let greeting: String
}

public enum NPCs {
    public static let all: [NPCDef] = [
        NPCDef(id: "smith", name: "铁匠 柯尔", title: "铁匠", marker: "smith", services: [.trade],
               greeting: "沼泽里的东西会啃坏你的刀刃。需要新装备就来找我。"),
        NPCDef(id: "healer", name: "药师 艾琳", title: "药师", marker: "healer", services: [.heal, .trade],
               greeting: "坐下吧，让火光替你止血。我这儿还有药剂。"),
        NPCDef(id: "elder", name: "渡口长老 维斯", title: "长老", marker: "elder", services: [.story],
               greeting: "守烬人……你终于来了。第一枚圣印就在沉没修道院之下。"),
        NPCDef(id: "stash", name: "储物箱", title: "", marker: "stash", services: [.stash],
               greeting: ""),
    ]

    public static let byMarker: [String: NPCDef] = Dictionary(uniqueKeysWithValues: all.map { ($0.marker, $0) })
    public static func def(_ id: String) -> NPCDef? { all.first { $0.id == id } }
}
