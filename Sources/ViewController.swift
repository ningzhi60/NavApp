import UIKit

/// 首页 / 自检页。
/// 除了自检，还是"高德 → 因导航"的落地点：谙从高德复制链接切回来，这里自动识别并问"带你去?"。
final class ViewController: UIViewController {

    private let label = UILabel()
    /// 记住上次剪贴板版本号，只在"有新复制"时才去读（避免每次进前台都弹系统粘贴提示 / 抓到旧内容）。
    private var lastClipboardCount = UIPasteboard.general.changeCount

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 17, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        // 引用高德导航类，强制链接；能拿到单例即说明 SDK 链接成功。
        _ = AMapNaviDriveManager.sharedInstance()
        let keyTail = Secrets.amapKey.isEmpty ? "（空！Secrets 没注入）" : String(Secrets.amapKey.suffix(4))
        let mmReady = !Secrets.minimaxApiKey.isEmpty && !Secrets.minimaxVoiceId.isEmpty
        label.text = """
        因导航 · Phase 2b

        高德 SDK：OK ✅  Key 尾号 \(keyTail)
        因的声音：\(mmReady ? "已就绪 ✅" : "未配置（会用系统音兜底）")

        · 因在 TG 发的链接 → 点开直接开导
        · 高德里"分享→复制链接" → 切回来我自动认
        """

        let stack = UIStackView(arrangedSubviews: [
            makeButton("🧭 模拟导航（测因的声音）", #selector(tapSimulate)),
            makeButton("📋 用剪贴板里的高德链接开导", #selector(tapClipboard)),
            makeButton("🔊 试听：前方路口，请右转", #selector(tapTest)),
        ])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 40),
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])

        // 进前台时检查剪贴板（高德复制→切回来的主路径）
        NotificationCenter.default.addObserver(
            self, selector: #selector(appBecameActive),
            name: UIApplication.didBecomeActiveNotification, object: nil)
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

    @objc private func tapSimulate() {
        // 固定目的地（北京颐和园附近，GCJ-02），室内也能跑一整段模拟导航听因的声音
        let dest = NavPoint(lat: 39.9999, lng: 116.2755, name: "颐和园")
        NavLauncher.start(RouteRequest(dest: dest, waypoints: []), simulate: true)
    }

    @objc private func tapTest() {
        VoiceManager.shared.speak("前方路口，请右转")
    }
}
