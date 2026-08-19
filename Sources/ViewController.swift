import UIKit

/// 首页 / 自检页。
/// 除了自检，还是"高德 → 因导航"的落地点：谙从高德复制链接切回来，这里自动识别并问"带你去?"。
final class ViewController: UIViewController {

    private let label = UILabel()
    private let voiceStatusLabel = UILabel()
    private let voiceTranscriptLabel = UILabel()
    private let voiceConversationLabel = UILabel()
    private let voiceConversationSwitch = UISwitch()
    private var voiceSelfCheckButton: UIButton!
    /// 记住上次剪贴板版本号，只在"有新复制"时才去读（避免每次进前台都弹系统粘贴提示 / 抓到旧内容）。
    private var lastClipboardCount = UIPasteboard.general.changeCount

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        // 首页内容会随功能增加而变长。使用滚动容器，避免小屏手机把末尾入口裁掉。
        let scrollView = UIScrollView()
        let contentView = UIView()
        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 17, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)

        // 引用高德导航类，强制链接；能拿到单例即说明 SDK 链接成功。
        _ = AMapNaviDriveManager.sharedInstance()
        let keyLen = Secrets.amapKey.count
        let keyTail = Secrets.amapKey.isEmpty ? "（空！Secrets 没注入）" : String(Secrets.amapKey.suffix(4))
        // 高德鉴权真正比对的是「运行时包名」——免费侧载可能被 Sideloadly 改掉，这里如实打出来
        let bundleId = Bundle.main.bundleIdentifier ?? "（读不到）"
        let bundleOK = bundleId == "com.an.yinnav"
        let mmReady = !Secrets.minimaxApiKey.isEmpty && !Secrets.minimaxVoiceId.isEmpty
        label.text = """
        因导航 · Phase 2b

        高德 SDK：OK ✅  Key 尾号 \(keyTail)（\(keyLen)位）
        运行包名：\(bundleId) \(bundleOK ? "✅" : "⚠️ 跟 key 绑定不符！")
        因的声音：\(mmReady ? "已就绪 ✅" : "未配置（会用系统音兜底）")

        · 因在 TG 发的链接 → 点开直接开导
        · 高德里"分享→复制链接" → 切回来我自动认
        """

        voiceStatusLabel.numberOfLines = 0
        voiceStatusLabel.textAlignment = .center
        voiceStatusLabel.font = .systemFont(ofSize: 13)
        voiceStatusLabel.textColor = .secondaryLabel

        voiceTranscriptLabel.numberOfLines = 3
        voiceTranscriptLabel.textAlignment = .center
        voiceTranscriptLabel.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        voiceTranscriptLabel.textColor = .systemBlue

        voiceConversationLabel.text = "导航语音对话"
        voiceConversationLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        voiceConversationSwitch.isOn = VoiceWakeManager.shared.isVoiceConversationEnabled
        voiceConversationSwitch.addTarget(
            self, action: #selector(toggleVoiceConversation), for: .valueChanged)
        let voiceConversationRow = UIStackView(arrangedSubviews: [
            voiceConversationLabel, voiceConversationSwitch,
        ])
        voiceConversationRow.axis = .horizontal
        voiceConversationRow.alignment = .center
        voiceConversationRow.spacing = 18

        voiceSelfCheckButton = makeButton("🎙️ 开始语音唤醒自检", #selector(toggleVoiceSelfCheck))
        let stack = UIStackView(arrangedSubviews: [
            voiceStatusLabel,
            voiceTranscriptLabel,
            voiceConversationRow,
            voiceSelfCheckButton,
            makeButton("🏠 因的灵动岛小屋", #selector(openCompanionHome)),
            makeButton("🧭 模拟导航（测因的声音）", #selector(tapSimulate)),
            makeButton("📋 用剪贴板里的高德链接开导", #selector(tapClipboard)),
            makeButton("🔊 试听：前方路口，请右转", #selector(tapTest)),
        ])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 24),
            stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -28),
        ])

        // 进前台时检查剪贴板（高德复制→切回来的主路径）
        NotificationCenter.default.addObserver(
            self, selector: #selector(appBecameActive),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(voiceWakeDidUpdate),
            name: .voiceWakeManagerDidUpdate, object: VoiceWakeManager.shared)
        refreshVoiceSelfCheck()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // 自检录音绝不带进导航页，避免碰到现有导航播报的音频会话。
        VoiceWakeManager.shared.stop()
    }

    private func makeButton(_ title: String, _ action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }

    // MARK: - 剪贴板（高德 → 因导航）

    @objc private func appBecameActive() {
        let count = UIPasteboard.general.changeCount
        guard count != lastClipboardCount else { return }   // 没新复制就不打扰
        lastClipboardCount = count
        checkClipboard(auto: true)
    }

    @objc private func tapClipboard() {
        checkClipboard(auto: false)
    }

    /// auto=true 是自动触发（识别不出就闭嘴）；auto=false 是谙手动点的（识别不出要给个反馈）。
    private func checkClipboard(auto: Bool) {
        guard UIPasteboard.general.hasStrings, let text = UIPasteboard.general.string, !text.isEmpty else {
            if !auto { NavLauncher.toast("剪贴板里没有文字~") }
            return
        }
        RouteParser.resolve(fromClipboard: text) { [weak self] req in
            guard let self = self else { return }
            guard let req = req else {
                if !auto { NavLauncher.toast("没在剪贴板里认出高德地点~\n在高德里点『分享 → 复制链接』再回来试试") }
                return
            }
            self.confirmAndGo(req)
        }
    }

    private func confirmAndGo(_ req: RouteRequest) {
        let a = UIAlertController(title: "发现一个地方~",
                                  message: "带你去「\(req.title)」吗？我用我的声音一路念给你听。",
                                  preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "好，出发", style: .default) { _ in
            NavLauncher.start(req)
        })
        a.addAction(UIAlertAction(title: "先不用", style: .cancel))
        (NavLauncher.topViewController() ?? self).present(a, animated: true)
    }

    // MARK: - 测试按钮

    @objc private func toggleVoiceSelfCheck() {
        if VoiceWakeManager.shared.isRunning {
            VoiceWakeManager.shared.stop()
        } else {
            VoiceWakeManager.shared.startSelfCheck { [weak self] _ in
                self?.refreshVoiceSelfCheck()
            }
        }
        refreshVoiceSelfCheck()
    }

    @objc private func toggleVoiceConversation() {
        VoiceWakeManager.shared.setVoiceConversationEnabled(voiceConversationSwitch.isOn)
        refreshVoiceSelfCheck()
    }

    @objc private func voiceWakeDidUpdate() {
        refreshVoiceSelfCheck()
    }

    private func refreshVoiceSelfCheck() {
        let manager = VoiceWakeManager.shared
        voiceConversationSwitch.isOn = manager.isVoiceConversationEnabled
        voiceStatusLabel.text = "语音自检：\(manager.authorizationSummary)\n\(manager.lastEvent)"
        voiceTranscriptLabel.text = manager.latestTranscript.isEmpty
            ? "最近识别：—"
            : "最近识别：\(manager.latestTranscript)"
        voiceSelfCheckButton?.setTitle(
            manager.isRunning ? "⏹ 停止语音唤醒自检" : "🎙️ 开始语音唤醒自检",
            for: .normal)
        voiceSelfCheckButton?.isEnabled = manager.isVoiceConversationEnabled
        voiceSelfCheckButton?.alpha = manager.isVoiceConversationEnabled ? 1 : 0.45
    }

    @objc private func tapSimulate() {
        // 固定目的地（北京颐和园附近，GCJ-02），室内也能跑一整段模拟导航听因的声音
        let dest = NavPoint(lat: 39.9999, lng: 116.2755, name: "颐和园")
        NavLauncher.start(RouteRequest(start: nil, dest: dest, waypoints: []), simulate: true)
    }

    @objc private func tapTest() {
        VoiceManager.shared.speak("前方路口，请右转")
    }

    @objc private func openCompanionHome() {
        let controller = CompanionHomeViewController()
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .pageSheet
        present(navigation, animated: true)
    }
}
