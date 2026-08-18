import ActivityKit
import UIKit

struct CompanionPublicState {
    let activity: String
    let thought: String
    let image: UIImage?
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
            activity: String(state.activity.prefix(18)),
            thought: String(state.thought.prefix(80)),
            updatedAt: Date())

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
