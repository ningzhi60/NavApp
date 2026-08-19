import ActivityKit
import UIKit

struct CompanionPublicState {
    let mood: String
    let activity: String
    let innerThought: String
    let image: UIImage?
    let themeID: String
    let priority: Int
    let decorationsEnabled: Bool
}

final class CompanionActivityManager {
    static let shared = CompanionActivityManager()
    private init() {}

    var isSupported: Bool {
        guard #available(iOS 16.1, *) else { return false }
        return ActivityAuthorizationInfo().areActivitiesEnabled
    }

    var isRunning: Bool {
        guard #available(iOS 16.1, *) else { return false }
        return !Activity<CompanionActivityAttributes>.activities.isEmpty
    }

    func publish(_ state: CompanionPublicState, completion: @escaping (String?) -> Void) {
        guard #available(iOS 16.1, *) else {
            completion("需要 iOS 16.1 或更高版本")
            return
        }
        let content = CompanionActivityAttributes.ContentState(
            iconPNGData: CompanionImageStore.shared.activityIconData(for: state.image),
            mood: String(state.mood.prefix(18)),
            activity: String(state.activity.prefix(18)),
            innerThought: String(state.innerThought.prefix(100)),
            updatedAt: Date(),
            themeID: state.themeID,
            priority: state.priority,
            decorationsEnabled: state.decorationsEnabled)

        if let activity = Activity<CompanionActivityAttributes>.activities.first {
            Task {
                await activity.update(using: content)
                await MainActor.run { completion(nil) }
            }
            return
        }

        do {
            _ = try Activity.request(
                attributes: CompanionActivityAttributes(roomName: "因的小屋"),
                contentState: content,
                pushType: nil)
            completion(nil)
        } catch {
            completion(error.localizedDescription)
        }
    }

    func end(completion: @escaping () -> Void) {
        guard #available(iOS 16.1, *) else { completion(); return }
        Task {
            for activity in Activity<CompanionActivityAttributes>.activities {
                await activity.end(dismissalPolicy: .immediate)
            }
            await MainActor.run { completion() }
        }
    }
}
