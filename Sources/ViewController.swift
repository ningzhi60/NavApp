import UIKit

/// Phase 1 自检页：能看到这行字，就说明 编译 → 侧载 → 启动 → 高德 SDK 链接 全通了。
final class ViewController: UIViewController {

    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 18, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])

        // 引用高德导航类，强制链接；能拿到单例即说明 SDK 链接成功。
        _ = AMapNaviDriveManager.sharedInstance()
        let keyTail = Secrets.amapKey.isEmpty ? "（空！Secrets 没注入）" : String(Secrets.amapKey.suffix(4))
        let mmReady = !Secrets.minimaxApiKey.isEmpty && !Secrets.minimaxVoiceId.isEmpty

        label.text = """
        因导航 · Phase 2a 自检

        高德 SDK 链接：OK ✅
        高德 Key 尾号：\(keyTail)
        因的声音配置：\(mmReady ? "已就绪 ✅" : "未配置（会用系统音兜底）")

        点下面按钮试听因的声音
        """

        // 试听按钮：跑一遍完整声音管线（MiniMax→缓存→播放，失败兜底系统音）
        let btn = UIButton(type: .system)
        btn.setTitle("🔊 试听：前方路口，请右转", for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(tapTest), for: .touchUpInside)
        view.addSubview(btn)
        NSLayoutConstraint.activate([
            btn.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 32),
            btn.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }

    @objc private func tapTest() {
        VoiceManager.shared.speak("前方路口，请右转")
    }
}
