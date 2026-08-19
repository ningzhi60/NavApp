import ActivityKit
import Foundation

/// 灵动岛只展示因愿意公开给用户看的状态与想法，不承载模型隐藏推理过程。
@available(iOS 16.1, *)
struct CompanionActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// 压缩后的单张 PNG；与文字合计保持在 ActivityKit 4KB 上限内。
        var iconPNGData: Data?
        var mood: String
        var activity: String
        var innerThought: String
        var updatedAt: Date
        /// Optional keeps an already-running activity decodable after an app upgrade.
        var themeID: String?
        var priority: Int?
        var decorationsEnabled: Bool?
    }

    var roomName: String
}
