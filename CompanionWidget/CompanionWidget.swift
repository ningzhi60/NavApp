import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

@main
struct CompanionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CompanionActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Text("因")
                    .font(.title.bold())
                    .foregroundStyle(.mint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("纯文字测试")
                        .font(.headline)
                        .lineLimit(1)
                    Text("如果你看见这句话，说明扩展已经成功渲染。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .activityBackgroundTint(Color.black.opacity(0.92))
            .activitySystemActionForegroundColor(.white)
            .widgetURL(telegramURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("因")
                        .font(.title.bold())
                        .foregroundStyle(.mint)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("纯文字测试")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("如果你看见这句话，说明灵动岛扩展已经成功渲染。")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Text("因")
                    .font(.caption.bold())
                    .foregroundStyle(.mint)
            } compactTrailing: {
                Text("在家")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            } minimal: {
                Text("因")
                    .font(.caption.bold())
                    .foregroundStyle(.mint)
            }
            .widgetURL(telegramURL)
            .keylineTint(.mint)
        }
    }

    private var telegramURL: URL? {
        URL(string: "tg://resolve?domain=KCMond_bot")
    }

}
