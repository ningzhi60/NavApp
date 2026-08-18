import CryptoKit
import Foundation

struct CompanionGeneratedState {
    let activity: String
    let thought: String
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
        let ts = String(Int(Date().timeIntervalSince1970))
        let key = SymmetricKey(data: Data(Secrets.minimaxApiKey.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(ts.utf8), using: key)
        let sig = mac.map { String(format: "%02x", $0) }.joined()
        guard let url = URL(string: endpoint),
              let body = try? JSONSerialization.data(withJSONObject: [
                "ts": ts, "sig": sig, "force": force,
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
                  let thought = json["thought"] as? String else {
                DispatchQueue.main.async { completion(.failure(ServiceError.badResponse)) }
                return
            }
            let state = CompanionGeneratedState(
                activity: activity,
                thought: thought,
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
