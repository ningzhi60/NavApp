import Foundation
import AVFoundation
import Speech

extension Notification.Name {
    static let voiceWakeManagerDidUpdate = Notification.Name("VoiceWakeManagerDidUpdate")
}

/// 语音唤醒状态机的 Phase A 骨架。
///
/// Phase A 提供权限、实时转写、唤醒词匹配和自检日志；
/// Phase B 接入导航监听与回声抑制，但仍不发起对话、不播放应答音。
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
    private var recognitionGeneration = UUID()
    private var wakeDetectedInCurrentSegment = false
    private var listeningContext: ListeningContext?
    private var outputSuppressed = false
    private var outputObserver: NSObjectProtocol?

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

    /// 播放开始就取消并清空当前识别段；播放结束 300ms 后从全新识别段恢复。
    private func handleOutputStateChange() {
        guard isRunning else { return }
        if VoiceManager.shared.isAudioOutputActive {
            guard !outputSuppressed else { return }
            outputSuppressed = true
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
