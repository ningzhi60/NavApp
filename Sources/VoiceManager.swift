import Foundation
import AVFoundation
import CryptoKit

/// 因的声音播报核心。
/// 一句话职责：给我一段文字，我用因的 MiniMax 克隆音念出来；
/// 合成失败 / 超时 / 没配 key，立刻退回系统中文语音——导航是保命功能，绝不哑巴。
final class VoiceManager: NSObject {

    static let shared = VoiceManager()

    private var player: AVAudioPlayer?
    /// 途中「碎碎念」专用播放器：独立于导航播报，不计入 isSpeaking，
    /// 所以导航转向播报永远能抢在它前面（保命优先）。
    private var chatterPlayer: AVAudioPlayer?
    private let synth = AVSpeechSynthesizer()
    private let cacheDir: URL
    /// 每次 speak 自增；回调里比对，晚到的旧请求直接丢弃（打断逻辑）。
    private var currentPlayId = 0
    /// MiniMax 合成超时（秒）。HD 合成一句常要 1~2s，给足余量；导航高频短语走缓存是秒开。
    /// 超时即退回系统音——车里最多等这么久，不会长时间哑巴。
    private let synthTimeout: TimeInterval = 6.0
    /// 「正在忙」标志：从收到 speak 请求（含网络合成那段空档）起为 true，直到真正播完/兜底播完。
    /// 高德的 driveManagerIsNaviSoundPlaying 靠它判断——忙就别急着发下一句，避免抢播。
    private var busy = false

    /// 因此刻是否在出声（含合成中的空档）。高德用它决定要不要发下一句播报。
    var isSpeaking: Bool {
        return busy || (player?.isPlaying ?? false) || synth.isSpeaking
    }

    private override init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDir = caches.appendingPathComponent("yin_tts", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        super.init()
        synth.delegate = self
    }

    // MARK: - 对外入口

    /// 念一句话。会打断上一句正在播/在合成的内容。
    func speak(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        currentPlayId += 1
        let playId = currentPlayId
        busy = true   // 从这一刻起就算"在忙"，覆盖住网络合成的空档

        // 打断上一句（含正在放的碎碎念——导航播报永远优先，保命）
        player?.stop()
        player = nil
        chatterPlayer?.stop()
        chatterPlayer = nil
        synth.stopSpeaking(at: .immediate)

        // 命中缓存直接放（最快，导航高频短语基本都在这）
        if let data = cachedAudio(for: text) {
            play(data: data, playId: playId, fallbackText: text)
            return
        }

        // 未命中：请 MiniMax 合成，超时/失败即兜底
        synthesize(text: text) { [weak self] data in
            guard let self = self else { return }
            guard playId == self.currentPlayId else { return } // 已被新的一句取代
            if let data = data, !data.isEmpty {
                self.cache(data: data, for: text)
                self.play(data: data, playId: playId, fallbackText: text)
            } else {
                self.fallback(text)
            }
        }
    }

    /// 立刻停声（导航结束/退出页面时调）。
    func stop() {
        currentPlayId += 1
        player?.stop()
        player = nil
        chatterPlayer?.stop()
        chatterPlayer = nil
        synth.stopSpeaking(at: .immediate)
        busy = false
        deactivateSession()
    }

    /// 途中「碎碎念」：因主动说的闲聊 / 路过点评。跟保命播报是两码事——
    /// 1) 正在念导航（或在合成空档）就直接放弃，绝不打断转向播报；
    /// 2) 合成失败就静默跳过，**不退系统音**（闲聊不值得让机器音蹦出来）；
    /// 3) 用独立 chatterPlayer，不计入 isSpeaking——所以任何时候导航播报都能抢在它前面。
    func speakChatter(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard !isSpeaking else { return }            // 有导航播报就让路
        if chatterPlayer?.isPlaying == true { return } // 上一句碎碎念还没完就不叠

        if let data = cachedAudio(for: text) {
            playChatter(data)
        } else {
            synthesize(text: text) { [weak self] data in
                guard let self = self, let data = data, !data.isEmpty else { return } // 失败静默
                self.cache(data: data, for: text)
                DispatchQueue.main.async {
                    guard !self.isSpeaking else { return } // 合成回来时导航已开口就放弃这句
                    self.playChatter(data)
                }
            }
        }
    }

    private func playChatter(_ data: Data) {
        activateSession()
        do {
            chatterPlayer = try AVAudioPlayer(data: data)
            chatterPlayer?.delegate = self
            chatterPlayer?.play()
        } catch {
            // 放不了就算了——闲聊不兜底
        }
    }

    /// 预合成一批高频短语进缓存（Phase 2b 导航开始前调，避免第一次现合成的空档）。
    func prewarm(_ phrases: [String]) {
        for p in phrases {
            let t = p.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, cachedAudio(for: t) == nil else { continue }
            synthesize(text: t) { [weak self] data in
                if let data = data, !data.isEmpty { self?.cache(data: data, for: t) }
            }
        }
    }

    // MARK: - MiniMax 合成

    private func synthesize(text: String, completion: @escaping (Data?) -> Void) {
        guard !Secrets.minimaxApiKey.isEmpty,
              !Secrets.minimaxGroupId.isEmpty,
              !Secrets.minimaxVoiceId.isEmpty else {
            completion(nil); return
        }
        // 与 bot 的 voice.py 完全一致：{host}/v1/t2a_v2?GroupId=...
        var host = Secrets.minimaxHost
        while host.hasSuffix("/") { host.removeLast() }
        var urlStr = "\(host)/v1/t2a_v2"
        if !Secrets.minimaxGroupId.isEmpty { urlStr += "?GroupId=\(Secrets.minimaxGroupId)" }
        guard let url = URL(string: urlStr) else { completion(nil); return }

        let speed = Double(Secrets.minimaxSpeed) ?? 1.0
        let model = Secrets.minimaxModel.isEmpty ? "speech-02-hd" : Secrets.minimaxModel

        var req = URLRequest(url: url, timeoutInterval: synthTimeout)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(Secrets.minimaxApiKey)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": model,
            "text": String(text.prefix(9000)),
            "stream": false,
            "voice_setting": ["voice_id": Secrets.minimaxVoiceId, "speed": speed, "vol": 1.0, "pitch": 0],
            // mp3，AVAudioPlayer 直接能放
            "audio_setting": ["format": "mp3", "sample_rate": 32000, "bitrate": 128000, "channel": 1]
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { data, _, err in
            guard err == nil, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(nil); return
            }
            // base_resp.status_code 非 0 = MiniMax 报错（鉴权/额度/参数），当失败处理
            if let base = json["base_resp"] as? [String: Any],
               let code = base["status_code"] as? Int, code != 0 {
                completion(nil); return
            }
            guard let d = json["data"] as? [String: Any],
                  let hex = d["audio"] as? String,          // MiniMax 默认 hex 编码，不是 base64
                  let audio = Data(hexString: hex), !audio.isEmpty else {
                completion(nil); return
            }
            completion(audio)
        }.resume()
    }

    // MARK: - 播放 / 兜底

    private func play(data: Data, playId: Int, fallbackText: String) {
        DispatchQueue.main.async {
            guard playId == self.currentPlayId else { return }
            self.activateSession()
            do {
                self.player = try AVAudioPlayer(data: data)
                self.player?.delegate = self
                self.player?.play()
                self.busy = false   // 已在放，player.isPlaying 接管"在忙"状态
            } catch {
                self.fallback(fallbackText)
            }
        }
    }

    /// 系统中文语音兜底——任何一步出错都走这，保证有声。
    private func fallback(_ text: String) {
        DispatchQueue.main.async {
            self.activateSession()
            let u = AVSpeechUtterance(string: text)
            u.voice = AVSpeechSynthesisVoice(language: "zh-CN")
            u.rate = AVSpeechUtteranceDefaultSpeechRate
            self.synth.speak(u)
            self.busy = false   // 已交给系统合成器，synth.isSpeaking 接管"在忙"状态
        }
    }

    /// 播放前激活音频会话：压低（不掐断）其他 App 的声音，导航播报优先。
    private func activateSession() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .voicePrompt,
                           options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? s.setActive(true)
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    // MARK: - 磁盘缓存（key = 文本的 MD5）

    private func cacheURL(for text: String) -> URL {
        let digest = Insecure.MD5.hash(data: Data(text.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return cacheDir.appendingPathComponent(name + ".mp3")
    }
    private func cachedAudio(for text: String) -> Data? {
        let u = cacheURL(for: text)
        guard FileManager.default.fileExists(atPath: u.path) else { return nil }
        return try? Data(contentsOf: u)
    }
    private func cache(data: Data, for text: String) {
        try? data.write(to: cacheURL(for: text))
    }
}

// MARK: - 播放结束后让出音频会话
extension VoiceManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) {
        if p === chatterPlayer {
            chatterPlayer = nil
            if !isSpeaking { deactivateSession() } // 导航没在说才让出会话
            return
        }
        busy = false
        deactivateSession()
    }
}
extension VoiceManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        busy = false
        deactivateSession()
    }
}

// MARK: - hex 字符串 → Data（MiniMax 的 data.audio 是 hex）
extension Data {
    init?(hexString: String) {
        let chars = Array(hexString)
        guard chars.count % 2 == 0 else { return nil }
        var data = Data(capacity: chars.count / 2)
        var i = 0
        while i < chars.count {
            guard let b = UInt8(String(chars[i]) + String(chars[i + 1]), radix: 16) else { return nil }
            data.append(b)
            i += 2
        }
        self = data
    }
}
