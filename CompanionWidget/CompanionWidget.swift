import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

@main
struct CompanionWidgetBundle: WidgetBundle {
    var body: some Widget {
        CompanionRegistrationWidget()
        CompanionLiveActivity()
    }
}

/// 注册诊断用普通主屏小组件：用于确认 iOS 是否真正加载了 CompanionWidget.appex。
struct CompanionRegistrationWidget: Widget {
    private let kind = "CompanionRegistrationWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CompanionTimelineProvider()) { entry in
            CompanionRegistrationView(entry: entry)
        }
        .configurationDisplayName("因的小屋测试")
        .description("用于确认灵动岛扩展是否已被系统正确注册。")
        .supportedFamilies([.systemSmall])
    }
}

struct CompanionTimelineEntry: TimelineEntry {
    let date: Date
}

struct CompanionTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> CompanionTimelineEntry {
        CompanionTimelineEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (CompanionTimelineEntry) -> Void) {
        completion(CompanionTimelineEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CompanionTimelineEntry>) -> Void) {
        completion(Timeline(entries: [CompanionTimelineEntry(date: Date())], policy: .never))
    }
}

struct CompanionRegistrationView: View {
    let entry: CompanionTimelineEntry

    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 8) {
                Text("因")
                    .font(.system(size: 42, weight: .black))
                    .foregroundStyle(.mint)
                Text("扩展已注册")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Static Widget")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .widgetBackgroundCompat()
    }
}

private extension View {
    @ViewBuilder
    func widgetBackgroundCompat() -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(.black, for: .widget)
        } else {
            background(Color.black)
        }
    }
}

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
