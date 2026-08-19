import CryptoKit
import Foundation
import UIKit

struct CompanionGeneratedState {
    let mood: String
    let activity: String
    let innerThought: String
    let iconID: String
    let themeID: String
    let priority: Int
    let updatedAt: Date
    let backend: String
    let model: String
    let effort: String
    let cached: Bool
}

final class CompanionStateService {
    static let shared = CompanionStateService()
    private init() {}

    private let endpoint = "https://calendar.45.32.43.224.sslip.io/nav/api/companion-state"

    func fetch(force: Bool, completion: @escaping (Result<CompanionGeneratedState, Error>) -> Void) {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let batteryLevel = UIDevice.current.batteryLevel
        let batteryState: String
        switch UIDevice.current.batteryState {
        case .charging: batteryState = "charging"
        case .full: batteryState = "full"
        case .unplugged: batteryState = "unplugged"
        default: batteryState = "unknown"
        }
        var context: [String: Any] = [
            "event": "companion_app_foreground",
            "batteryPercent": batteryLevel >= 0 ? Int(batteryLevel * 100) : -1,
            "batteryState": batteryState,
            "lowPowerMode": ProcessInfo.processInfo.isLowPowerModeEnabled,
            "thermalState": ProcessInfo.processInfo.thermalState.rawValue,
            "locale": Locale.current.identifier,
            "timeZone": TimeZone.current.identifier,
            "imageCatalog": CompanionImageStore.shared.modelCatalog(),
            "companionDoNotDisturb": CompanionAppearanceStore.shared.doNotDisturb,
        ]
        LifeSignalCollector.shared.collect { [weak self] lifeSignals in
            guard let self else { return }
            context.merge(lifeSignals) { _, new in new }
            self.send(context: context, force: force, completion: completion)
        }
    }

    private func send(context: [String: Any], force: Bool,
                      completion: @escaping (Result<CompanionGeneratedState, Error>) -> Void) {
        let ts = String(Int(Date().timeIntervalSince1970))
        let key = SymmetricKey(data: Data(Secrets.minimaxApiKey.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(ts.utf8), using: key)
        let sig = mac.map { String(format: "%02x", $0) }.joined()
        guard let url = URL(string: endpoint),
              let body = try? JSONSerialization.data(withJSONObject: [
                "ts": ts, "sig": sig, "force": force, "context": context,
              ]) else {
            completion(.failure(ServiceError.invalidRequest))
            return
        }
        var request = URLRequest(url: url, timeoutInterval: 35)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let activity = json["activity"] as? String,
                  let innerThought = (json["innerThought"] ?? json["thought"]) as? String else {
                DispatchQueue.main.async { completion(.failure(ServiceError.badResponse)) }
                return
            }
            let state = CompanionGeneratedState(
                mood: json["mood"] as? String ?? "安静",
                activity: activity,
                innerThought: innerThought,
                iconID: json["iconID"] as? String ?? "",
                themeID: json["themeID"] as? String ?? "moonlight",
                priority: json["priority"] as? Int ?? 20,
                updatedAt: Date(timeIntervalSince1970:
                    (json["updatedAt"] as? Double) ?? (json["ts"] as? Double) ?? Date().timeIntervalSince1970),
                backend: json["backend"] as? String ?? "?",
                model: json["model"] as? String ?? "?",
                effort: json["effort"] as? String ?? "",
                cached: json["cached"] as? Bool ?? false)
            DispatchQueue.main.async { completion(.success(state)) }
        }.resume()
    }

    private enum ServiceError: LocalizedError {
        case invalidRequest, badResponse
        var errorDescription: String? {
            switch self {
            case .invalidRequest: return "无法组织灵动岛请求"
            case .badResponse: return "Bot 暂时没有返回有效状态"
            }
        }
    }
}
