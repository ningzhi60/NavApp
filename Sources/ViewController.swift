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

        label.text = """
        因导航 · Phase 1 自检

        高德 SDK 链接：OK ✅
        Key 尾号：\(keyTail)

        看到这行字 =
        编译 / 侧载 / 启动 全部打通
        下一步做真导航 + 因的声音
        """
    }
}
