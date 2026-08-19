import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

@main
struct CompanionWidgetBundle: WidgetBundle {
    var body: some Widget { CompanionLiveActivity() }
}

struct CompanionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CompanionActivityAttributes.self) { context in
            CompanionLockScreenView(context: context)
                .activityBackgroundTint(Color(companionHex:
                    CompanionThemes.resolve(context.state.themeID).backgroundHex, alpha: 0.96))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(telegramURL)
        } dynamicIsland: { context in
            let theme = CompanionThemes.resolve(context.state.themeID)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    CompanionIcon(data: context.state.iconPNGData, size: 42,
                                  color: Color(companionHex: theme.outlineHex),
                                  updatedAt: context.state.updatedAt)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.mood)
                        .font(companionFont(theme, size: 16, weight: .bold))
                        .foregroundStyle(Color(companionHex: theme.primaryHex))
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    CompanionExpandedBody(context: context, theme: theme)
                }
            } compactLeading: {
                CompanionCompactBadge(data: context.state.iconPNGData,
                                      color: Color(companionHex: theme.outlineHex),
                                      updatedAt: context.state.updatedAt)
            } compactTrailing: {
                Text(String(context.state.activity.prefix(7)))
                    .font(companionFont(theme, size: 11, weight: .semibold))
                    .foregroundStyle(Color(companionHex: theme.primaryHex))
                    .lineLimit(1)
                    .contentTransition(.opacity)
            } minimal: {
                CompanionCompactBadge(data: context.state.iconPNGData,
                                      color: Color(companionHex: theme.outlineHex),
                                      updatedAt: context.state.updatedAt)
            }
            .widgetURL(telegramURL)
            .keylineTint(Color(companionHex: theme.outlineHex))
        }
    }

    private var telegramURL: URL? { URL(string: "tg://resolve?domain=KCMond_bot") }
}

private struct CompanionLockScreenView: View {
    let context: ActivityViewContext<CompanionActivityAttributes>
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        let theme = CompanionThemes.resolve(context.state.themeID)
        HStack(spacing: 12) {
            CompanionIcon(data: context.state.iconPNGData, size: 48,
                          color: Color(companionHex: theme.outlineHex),
                          updatedAt: context.state.updatedAt)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(context.state.mood)
                        .font(companionFont(theme, size: 16, weight: .bold))
                    Spacer(minLength: 4)
                    Text(context.state.updatedAt, style: .relative)
                        .font(.caption2)
                        .opacity(0.66)
                }
                Text(context.state.activity)
                    .font(companionFont(theme, size: 14, weight: .semibold))
                    .lineLimit(1)
                if !isLuminanceReduced {
                    Text(context.state.innerThought)
                        .font(companionFont(theme, size: 13, weight: .regular))
                        .foregroundStyle(Color(companionHex: theme.secondaryHex))
                        .lineLimit(2)
                }
            }
            .foregroundStyle(Color(companionHex: theme.primaryHex))
        }
        .padding(.horizontal, 14)
        .overlay {
            if context.state.decorationsEnabled == true && !isLuminanceReduced {
                CatEarTailDecoration(color: Color(companionHex: theme.outlineHex),
                                     mood: context.state.mood)
            }
        }
        .animation(.easeOut(duration: 0.55), value: context.state.updatedAt)
    }
}

private struct CompanionExpandedBody: View {
    let context: ActivityViewContext<CompanionActivityAttributes>
    let theme: CompanionThemeDefinition
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(context.state.activity)
                .font(companionFont(theme, size: 14, weight: .semibold))
                .foregroundStyle(Color(companionHex: theme.primaryHex))
            if !isLuminanceReduced {
                Text(context.state.innerThought)
                    .font(companionFont(theme, size: 13, weight: .regular))
                    .foregroundStyle(Color(companionHex: theme.secondaryHex))
                    .lineLimit(2)
            }
            HStack {
                Text(context.state.updatedAt, style: .relative)
                Spacer()
                Text("点一下去 Telegram")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color(companionHex: theme.secondaryHex).opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            if context.state.decorationsEnabled == true && !isLuminanceReduced {
                CatEarTailDecoration(color: Color(companionHex: theme.outlineHex),
                                     mood: context.state.mood)
            }
        }
        .animation(.easeOut(duration: 0.55), value: context.state.updatedAt)
    }
}

private struct CatEarTailDecoration: View {
    let color: Color
    let mood: String

    private var earAngle: Double {
        mood.contains("困") ? 12 : mood.contains("担心") ? -8 : 0
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                HStack(spacing: 8) {
                    Triangle().stroke(color.opacity(0.8), lineWidth: 1.4)
                        .rotationEffect(.degrees(-earAngle))
                    Triangle().stroke(color.opacity(0.8), lineWidth: 1.4)
                        .rotationEffect(.degrees(earAngle))
                }
                .frame(width: 35, height: 13)
                .position(x: 25, y: 1)
                Path { path in
                    let w = geometry.size.width
                    let h = geometry.size.height
                    path.move(to: CGPoint(x: w - 6, y: h * 0.72))
                    path.addCurve(to: CGPoint(x: w - 22, y: h * 0.35),
                                  control1: CGPoint(x: w + 3, y: h * 0.54),
                                  control2: CGPoint(x: w - 4, y: h * 0.3))
                }
                .stroke(color.opacity(0.72), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct CompanionCompactBadge: View {
    let data: Data?
    let color: Color
    let updatedAt: Date

    var body: some View {
        ZStack {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
                    .shadow(color: color.opacity(0.55), radius: 1)
            } else {
                Circle().fill(color)
                Text("因").font(.system(size: 11, weight: .black)).foregroundStyle(.black)
            }
        }
        .frame(width: 22, height: 22)
        .id(updatedAt)
        .transition(.scale(scale: 0.82).combined(with: .opacity))
        .animation(.easeOut(duration: 0.48), value: updatedAt)
    }
}

private struct CompanionIcon: View {
    let data: Data?
    let size: CGFloat
    let color: Color
    let updatedAt: Date

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
                    .shadow(color: color.opacity(0.55), radius: 2)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).fill(color)
                    Text("因").font(.system(size: size * 0.42, weight: .black)).foregroundStyle(.black)
                }
            }
        }
        .frame(width: size, height: size)
        .id(updatedAt)
        .transition(.scale(scale: 0.88).combined(with: .opacity))
        .animation(.easeOut(duration: 0.55), value: updatedAt)
    }
}

private func companionFont(_ theme: CompanionThemeDefinition, size: CGFloat,
                           weight: Font.Weight) -> Font {
    switch theme.fontStyle {
    case "light": return .system(size: size, weight: .light, design: .rounded)
    case "bold": return .system(size: size, weight: .bold, design: .rounded)
    case "mono": return .system(size: size, weight: weight, design: .monospaced)
    default: return .system(size: size, weight: weight, design: .rounded)
    }
}
