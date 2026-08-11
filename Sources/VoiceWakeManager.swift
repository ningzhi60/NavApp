import Foundation
import AVFoundation
import CryptoKit
import Speech

extension Notification.Name {
    static let voiceWakeManagerDidUpdate = Notification.Name("VoiceWakeManagerDidUpdate")
}

/// 语音唤醒状态机的 Phase A 骨架。
///
/// Phase A 提供权限、实时转写、唤醒词匹配和自检日志；
/// Phase B 接入导航监听与回声抑制；Phase C 打通听写、服务端对话、克隆音回答与追问窗口。
final class VoiceWakeManager {

    private enum ListeningContext {
        case selfCheck
        case navigation
    }

    enum State: String {
        case stopped
        case idle
        case listening
        case replying
    }

    static let shared = VoiceWakeManager()

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var restartWorkItem: DispatchWorkItem?
    private var silenceWorkItem: DispatchWorkItem?
    private var listeningTimeoutWorkItem: DispatchWorkItem?
    private var recognitionGeneration = UUID()
    private var wakeDetectedInCurrentSegment = false
    private var listeningContext: ListeningContext?
    private var outputSuppressed = false
    private var outputObserver: NSObjectProtocol?
    private var capturedCommand = ""
    private var lastListeningTranscript = ""
    private var chatSessionId = ""
    private var isFollowUpWindow = false
    private let chatEndpoint = "https://calendar.45.32.43.224.sslip.io/nav/api/chat"

    private let wakeWords = [
        "嘤嘤", "宝宝", "老公", "茵茵", "因因",
        // Apple 中文识别常见同音结果，继续作为兜底。
        "音音", "阴阴", "銀銀",
    ]

    private(set) var state: State = .stopped
    private(set) var latestTranscript = ""
    private(set) var lastEvent = "尚未开始自检"
    private(set) var isRunning = false

    private init() {
        outputObserver = NotificationCenter.default.addObserver(
            forName: .voiceManagerOutputStateDidChange,
            object: VoiceManager.shared,
            queue: .main
        ) { [weak self] _ in
            self?.handleOutputStateChange()
        }
    }

    var authorizationSummary: String {
        let speech: String
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: speech = "已授权"
        case .denied: speech = "已拒绝"
        case .restricted: speech = "受系统限制"
        case .notDetermined: speech = "未询问"
        @unknown default: speech = "未知"
        }

        let microphone: String
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted: microphone = "已授权"
        case .denied: microphone = "已拒绝"
        case .undetermined: microphone = "未询问"
        @unknown default: microphone = "未知"
        }

        let recognitionMode = recognizer?.supportsOnDeviceRecognition == true ? "本机优先" : "Apple 在线识别"
        return "麦克风：\(microphone) · 语音识别：\(speech) · \(recognitionMode)"
    }

    /// 首次进入导航页或启动自检时调用。拒绝权限只关闭语音唤醒，不影响导航。
    func requestPermissions(completion: @escaping (Bool) -> Void) {
        let group = DispatchGroup()
        var speechGranted = false
        var microphoneGranted = false

        group.enter()
        SFSpeechRecognizer.requestAuthorization { status in
            speechGranted = status == .authorized
            group.leave()
        }

        group.enter()
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            microphoneGranted = granted
            group.leave()
        }

        group.notify(queue: .main) {
            self.publishUpdate()
            completion(speechGranted && microphoneGranted)
        }
    }

    /// 首页真机自检入口。使用临时 `.record` 会话，仅在自检期间生效。
    /// Phase B 才会把导航全程会话改为 `.playAndRecord` 并回归现有三条播放路径。
    func startSelfCheck(completion: @escaping (Bool) -> Void) {
        guard !isRunning else { completion(true); return }

        requestPermissions { [weak self] granted in
            guard let self = self else { return }
            guard granted else {
                self.lastEvent = "权限未开启，语音唤醒已静默关闭（导航不受影响）"
                self.publishUpdate()
                completion(false)
                return
            }
            guard self.recognizer?.isAvailable == true else {
                self.lastEvent = "中文语音识别当前不可用"
                self.publishUpdate()
                completion(false)
                return
            }

            do {
                try self.beginAudio(context: .selfCheck)
                self.lastEvent = "监听中：可喊「嘤嘤 / 宝宝 / 老公 / 茵茵 / 因因」"
                self.publishUpdate()
                completion(true)
            } catch {
                self.stop()
                self.lastEvent = "自检启动失败：\(error.localizedDescription)"
                self.publishUpdate()
                completion(false)
            }
        }
    }

    /// Phase B：导航已先固定为 `.playAndRecord`；这里只挂输入 tap，不再切 category。
    func startNavigationListening() {
        guard !isRunning else { return }
        chatSessionId = UUID().uuidString
        requestPermissions { [weak self] granted in
            guard let self = self, granted else { return }
            do {
                try self.beginAudio(context: .navigation)
                self.lastEvent = "导航唤醒监听中"
                self.publishUpdate()
            } catch {
                self.stop()
                self.lastEvent = "导航唤醒监听启动失败：\(error.localizedDescription)"
                self.publishUpdate()
            }
        }
    }

    func stop() {
        guard isRunning || audioEngine.isRunning else { return }
        let context = listeningContext
        isRunning = false
        state = .stopped
        listeningContext = nil
        outputSuppressed = false
        restartWorkItem?.cancel()
        restartWorkItem = nil
        silenceWorkItem?.cancel()
        silenceWorkItem = nil
        listeningTimeoutWorkItem?.cancel()
        listeningTimeoutWorkItem = nil
        capturedCommand = ""
        lastListeningTranscript = ""
        isFollowUpWindow = false
        chatSessionId = ""
        recognitionGeneration = UUID()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        if context == .selfCheck {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
        lastEvent = context == .navigation ? "导航唤醒监听已停止" : "自检已停止"
        publishUpdate()
    }

    private func beginAudio(context: ListeningContext) throws {
        let session = AVAudioSession.sharedInstance()
        if context == .selfCheck {
            // 首页自检仍使用临时录音会话；导航 category 只由 VoiceManager 生命周期持有。
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true)
        }

        isRunning = true
        listeningContext = context
        state = .idle
        latestTranscript = ""
        wakeDetectedInCurrentSegment = false
        startRecognitionCycle()

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()
    }

    private func startRecognitionCycle() {
        guard isRunning, !outputSuppressed, let recognizer = recognizer else { return }

        restartWorkItem?.cancel()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request
        wakeDetectedInCurrentSegment = false

        let generation = UUID()
        recognitionGeneration = generation
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self,
                      self.isRunning,
                      generation == self.recognitionGeneration else { return }

                if let result = result {
                    self.consume(result.bestTranscription.formattedString)
                }
                if error != nil || result?.isFinal == true {
                    self.scheduleRestart(after: 0.35, generation: generation)
                }
            }
        }

        // Apple 的长识别任务会被系统截断；主动按 50 秒滚动，避免持续增长。
        scheduleRestart(after: 50, generation: generation)
    }

    private func consume(_ transcript: String) {
        if VoiceManager.shared.isAudioOutputActive || outputSuppressed { return }
        let cleaned = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        latestTranscript = cleaned

        if state == .listening {
            consumeListening(cleaned)
            return
        }
        if state == .replying { return }

        let tail = String(cleaned.suffix(10))
        if !wakeDetectedInCurrentSegment,
           let matched = wakeWords.first(where: { tail.contains($0) }) {
            wakeDetectedInCurrentSegment = true
            if listeningContext == .navigation {
                beginListening(followUp: false, matchedWakeWord: matched)
            } else {
                lastEvent = "✅ 唤醒词命中：\(matched)"
            }
            NSLog("[VoiceWake] wake word detected: %@", matched)
            publishUpdate()
            scheduleRestart(after: 0.25, generation: recognitionGeneration)
            return
        }

        lastEvent = "正在实时转写"
        publishUpdate()
    }

    private func beginListening(followUp: Bool, matchedWakeWord: String? = nil) {
        silenceWorkItem?.cancel()
        listeningTimeoutWorkItem?.cancel()
        state = .listening
        isFollowUpWindow = followUp
        capturedCommand = ""
        lastListeningTranscript = ""
        latestTranscript = ""
        lastEvent = followUp
            ? "可继续说，5 秒内不用再喊唤醒词"
            : "✅ 唤醒词命中：\(matchedWakeWord ?? "")，正在听你说"
        publishUpdate()

        let timeout = followUp ? 5.0 : 8.0
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.state == .listening else { return }
            if self.capturedCommand.isEmpty {
                self.returnToIdle(event: followUp ? "追问窗口结束，恢复唤醒监听" : "没听到问题，恢复唤醒监听")
            } else {
                self.submitCapturedCommand()
            }
        }
        listeningTimeoutWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
    }

    private func consumeListening(_ transcript: String) {
        var command = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        // 识别任务切段前偶尔仍会把唤醒词带进下一段，避免把它发给服务端。
        if !isFollowUpWindow,
           let word = wakeWords.first(where: { command.hasPrefix($0) }) {
            command.removeFirst(word.count)
            command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !command.isEmpty, command != lastListeningTranscript else { return }
        capturedCommand = command
        lastListeningTranscript = command
        latestTranscript = command
        lastEvent = "正在听：\(command)"
        publishUpdate()

        silenceWorkItem?.cancel()
        let snapshot = command
        let work = DispatchWorkItem { [weak self] in
            guard let self = self,
                  self.state == .listening,
                  self.capturedCommand == snapshot else { return }
            self.submitCapturedCommand()
        }
        silenceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    private func submitCapturedCommand() {
        let text = capturedCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard state == .listening, !text.isEmpty else {
            returnToIdle(event: "没听清，恢复唤醒监听")
            return
        }
        state = .replying
        silenceWorkItem?.cancel()
        listeningTimeoutWorkItem?.cancel()
        pauseRecognition()
        lastEvent = "已听到，正在等因回答"
        publishUpdate()

        fetchReply(text: text) { [weak self] reply in
            DispatchQueue.main.async {
                guard let self = self, self.state == .replying else { return }
                guard let reply = reply, !reply.isEmpty else {
                    self.returnToIdle(event: "对话暂时没接通，恢复唤醒监听")
                    return
                }
                self.lastEvent = "因正在回答"
                self.publishUpdate()
                VoiceManager.shared.speakChatter(reply) { [weak self] played in
                    guard let self = self, self.state == .replying else { return }
                    if played {
                        self.beginListening(followUp: true)
                        if !self.outputSuppressed {
                            self.scheduleRestart(after: 0.3, generation: self.recognitionGeneration)
                        }
                    } else {
                        self.returnToIdle(event: "回答已让路给导航播报，恢复唤醒监听")
                    }
                }
            }
        }
    }

    private func fetchReply(text: String, completion: @escaping (String?) -> Void) {
        guard !chatSessionId.isEmpty else { completion(nil); return }
        let ts = String(Int(Date().timeIntervalSince1970))
        let key = SymmetricKey(data: Data(Secrets.minimaxApiKey.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(ts.utf8), using: key)
        let sig = mac.map { String(format: "%02x", $0) }.joined()
        guard let url = URL(string: chatEndpoint),
              let body = try? JSONSerialization.data(withJSONObject: [
                "text": text, "sid": chatSessionId, "ts": ts, "sig": sig,
              ]) else { completion(nil); return }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        URLSession.shared.dataTask(with: request) { data, _, error in
            guard error == nil, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let reply = json["reply"] as? String else { completion(nil); return }
            completion(reply.trimmingCharacters(in: .whitespacesAndNewlines))
        }.resume()
    }

    private func returnToIdle(event: String) {
        state = .idle
        isFollowUpWindow = false
        capturedCommand = ""
        lastListeningTranscript = ""
        silenceWorkItem?.cancel()
        listeningTimeoutWorkItem?.cancel()
        lastEvent = event
        publishUpdate()
        if !outputSuppressed {
            scheduleRestart(after: 0.3, generation: recognitionGeneration)
        }
    }

    private func pauseRecognition() {
        restartWorkItem?.cancel()
        recognitionGeneration = UUID()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
    }

    private func scheduleRestart(after delay: TimeInterval, generation: UUID) {
        restartWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self,
                  self.isRunning,
                  generation == self.recognitionGeneration else { return }
            self.startRecognitionCycle()
        }
        restartWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func publishUpdate() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .voiceWakeManagerDidUpdate, object: self)
        }
    }

    /// 播放开始就取消并清空当前识别段；播放结束 300ms 后从全新识别段恢复。
    private func handleOutputStateChange() {
        guard isRunning else { return }
        if VoiceManager.shared.isAudioOutputActive {
            guard !outputSuppressed else { return }
            outputSuppressed = true
            silenceWorkItem?.cancel()
            listeningTimeoutWorkItem?.cancel()
            if state == .listening {
                capturedCommand = ""
                lastListeningTranscript = ""
            }
            restartWorkItem?.cancel()
            recognitionGeneration = UUID()
            recognitionRequest?.endAudio()
            recognitionTask?.cancel()
            recognitionRequest = nil
            recognitionTask = nil
            lastEvent = "播报期间已暂停唤醒匹配"
            publishUpdate()
            return
        }

        guard outputSuppressed else { return }
        outputSuppressed = false
        lastEvent = "播报结束，300ms 后恢复监听"
        publishUpdate()
        if state == .replying { return }
        if state == .listening {
            beginListening(followUp: isFollowUpWindow)
        }
        let generation = recognitionGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self = self,
                  self.isRunning,
                  generation == self.recognitionGeneration else { return }
            self.startRecognitionCycle()
        }
        restartWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
}
