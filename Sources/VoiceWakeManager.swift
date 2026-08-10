import Foundation
import AVFoundation
import Speech

extension Notification.Name {
    static let voiceWakeManagerDidUpdate = Notification.Name("VoiceWakeManagerDidUpdate")
}

/// 语音唤醒状态机的 Phase A 骨架。
///
/// 本阶段只负责：权限、实时转写、唤醒词匹配和自检日志。
/// 不接入导航对话、不播放应答音，也不修改导航使用的 `.playback` 音频会话。
final class VoiceWakeManager {

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
    private var recognitionGeneration = UUID()
    private var wakeDetectedInCurrentSegment = false

    private let wakeWords = [
        "嘤嘤", "宝宝", "老公", "茵茵", "因因",
        // Apple 中文识别常见同音结果，继续作为兜底。
        "音音", "阴阴", "銀銀",
    ]

    private(set) var state: State = .stopped
    private(set) var latestTranscript = ""
    private(set) var lastEvent = "尚未开始自检"
    private(set) var isRunning = false

    private init() {}

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
                try self.beginSelfCheckAudio()
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

    func stop() {
        guard isRunning || audioEngine.isRunning else { return }
        isRunning = false
        state = .stopped
        restartWorkItem?.cancel()
        restartWorkItem = nil
        recognitionGeneration = UUID()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        lastEvent = "自检已停止"
        publishUpdate()
    }

    private func beginSelfCheckAudio() throws {
        // 只供首页自检。这里刻意不动 VoiceManager 的导航 `.playback` 配置。
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)

        isRunning = true
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
        guard isRunning, let recognizer = recognizer else { return }

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
        let cleaned = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        latestTranscript = cleaned

        let tail = String(cleaned.suffix(10))
        if !wakeDetectedInCurrentSegment,
           let matched = wakeWords.first(where: { tail.contains($0) }) {
            wakeDetectedInCurrentSegment = true
            lastEvent = "✅ 唤醒词命中：\(matched)"
            NSLog("[VoiceWake][Phase A] wake word detected: %@", matched)
            publishUpdate()
            scheduleRestart(after: 0.6, generation: recognitionGeneration)
            return
        }

        lastEvent = "正在实时转写"
        publishUpdate()
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
}
