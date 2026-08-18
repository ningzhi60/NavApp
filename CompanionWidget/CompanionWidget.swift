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
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.thought)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                CompanionIcon(data: context.state.iconPNGData, size: 22)
            } compactTrailing: {
                Text(shortActivity(context.state.activity))
                    .font(.caption2)
                    .lineLimit(1)
            } minimal: {
                CompanionIcon(data: context.state.iconPNGData, size: 22)
            }
            .widgetURL(telegramURL)
            .keylineTint(.mint)
        }
    }

    private var telegramURL: URL? {
        URL(string: "tg://resolve?domain=KCMond_bot")
    }

    private func shortActivity(_ value: String) -> String {
        String(value.prefix(4))
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
                Image(systemName: "house.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.mint)
                    .padding(3)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
}
