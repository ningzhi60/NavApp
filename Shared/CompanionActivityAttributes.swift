import ActivityKit
import Foundation

/// 灵动岛只展示因愿意公开给用户看的状态与想法，不承载模型隐藏推理过程。
@available(iOS 16.1, *)
struct CompanionActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// 缩小后的 PNG。连同其余状态必须低于 ActivityKit 的 4KB 上限。
        var iconPNGData: Data?
        var activity: String
        var thought: String
        var updatedAt: Date
    }

    var roomName: String
}
