import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

@main
struct CompanionWidgetBundle: WidgetBundle {
    var body: some Widget {
        CompanionLiveActivity()
    }
}

struct CompanionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CompanionActivityAttributes.self) { context in
            HStack(spacing: 12) {
                CompanionIcon(data: context.state.iconPNGData, size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(context.state.activity)
                        .font(.headline)
                        .lineLimit(1)
                    Text(context.state.thought)
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
                    CompanionIcon(data: context.state.iconPNGData, size: 42)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.activity)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.thought)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                CompanionCompactBadge(data: context.state.iconPNGData)
            } compactTrailing: {
                Text(String(context.state.activity.prefix(5)))
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            } minimal: {
                CompanionCompactBadge(data: context.state.iconPNGData)
            }
            .widgetURL(telegramURL)
            .keylineTint(.mint)
        }
    }

    private var telegramURL: URL? {
        URL(string: "tg://resolve?domain=KCMond_bot")
    }

}

/// 用户 PNG 过透明或无法解码时，紧凑态仍会显示高对比的“因”。
private struct CompanionCompactBadge: View {
    let data: Data?

    var body: some View {
        ZStack {
            Circle().fill(Color.mint)
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(Circle())
            } else {
                Text("因")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(.black)
            }
        }
        .frame(width: 22, height: 22)
    }
}

private struct CompanionIcon: View {
    let data: Data?
    let size: CGFloat

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .fill(Color.mint)
                    Text("因")
                        .font(.system(size: size * 0.42, weight: .black))
                        .foregroundStyle(.black)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
}
