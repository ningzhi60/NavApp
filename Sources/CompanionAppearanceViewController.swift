import UIKit

final class CompanionAppearanceViewController: UITableViewController {
    private let themes: [(String?, String)] = [(nil, "由因自动选择")] +
        CompanionThemes.all.map { ($0.id as String?, $0.name) }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "灵动岛外观"
        tableView = UITableView(frame: .zero, style: .insetGrouped)
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 3 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? themes.count : section == 1 ? 2 : 3
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["主题（固定安全配色）", "可选装饰", "工具"][section]
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let store = CompanionAppearanceStore.shared
        if indexPath.section == 0 {
            let value = themes[indexPath.row]
            cell.textLabel?.text = value.1
            cell.accessoryType = store.themeOverride == value.0 ? .checkmark : .none
            if let id = value.0 {
                let theme = CompanionThemes.resolve(id)
                cell.imageView?.image = swatch(theme)
                cell.detailTextLabel?.text = "字体：\(theme.fontStyle) · 动画：\(theme.animation)"
            } else {
                cell.detailTextLabel?.text = "Bot 按状态选择，但不能自造颜色"
            }
        } else if indexPath.section == 1 {
            cell.textLabel?.text = indexPath.row == 0 ? "猫耳与尾巴" : "陪伴勿扰"
            cell.detailTextLabel?.text = indexPath.row == 0
                ? "默认关闭；只在灵动岛内容区域内显示"
                : "继续更新灵动岛，但不会由岛触发 Telegram 消息"
            let toggle = UISwitch()
            toggle.tag = indexPath.row
            toggle.isOn = indexPath.row == 0 ? store.decorationsEnabled : store.doNotDisturb
            toggle.addTarget(self, action: #selector(toggleOption(_:)), for: .valueChanged)
            cell.accessoryView = toggle
        } else {
            let values = [("预览四种形态", "最小、紧凑、展开、锁屏"),
                          ("最近状态变化", "查看本机保存的最近 60 条"),
                          ("恢复默认外观", "自动主题、关闭猫耳尾巴")]
            cell.textLabel?.text = values[indexPath.row].0
            cell.detailTextLabel?.text = values[indexPath.row].1
            cell.accessoryType = indexPath.row < 2 ? .disclosureIndicator : .none
            if indexPath.row == 2 { cell.textLabel?.textColor = .systemRed }
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            CompanionAppearanceStore.shared.themeOverride = themes[indexPath.row].0
            tableView.reloadSections(IndexSet(integer: 0), with: .automatic)
        } else if indexPath.section == 2, indexPath.row == 0 {
            navigationController?.pushViewController(CompanionPreviewViewController(), animated: true)
        } else if indexPath.section == 2, indexPath.row == 1 {
            navigationController?.pushViewController(CompanionHistoryViewController(), animated: true)
        } else if indexPath.section == 2, indexPath.row == 2 {
            CompanionAppearanceStore.shared.reset()
            tableView.reloadData()
        }
    }

    @objc private func toggleOption(_ sender: UISwitch) {
        if sender.tag == 0 { CompanionAppearanceStore.shared.decorationsEnabled = sender.isOn }
        else { CompanionAppearanceStore.shared.doNotDisturb = sender.isOn }
    }

    private func swatch(_ theme: CompanionThemeDefinition) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 36, height: 36))
        return renderer.image { context in
            UIColor(companionHex: theme.backgroundHex).setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 36, height: 36))
            UIColor(companionHex: theme.outlineHex).setStroke()
            let path = UIBezierPath(ovalIn: CGRect(x: 8, y: 8, width: 20, height: 20))
            path.lineWidth = 3
            path.stroke()
        }
    }
}

final class CompanionPreviewViewController: UIViewController {
    private let canvas = UIView()
    private let content = UIStackView()
    private let imageView = UIImageView()
    private let mood = UILabel()
    private let activity = UILabel()
    private let thought = UILabel()
    private let updated = UILabel()
    private let segment = UISegmentedControl(items: ["最小", "紧凑", "展开", "锁屏"])

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "四态预览"
        view.backgroundColor = .systemBackground
        segment.selectedSegmentIndex = 2
        segment.addTarget(self, action: #selector(render), for: .valueChanged)
        segment.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(segment)

        canvas.layer.cornerRadius = 26
        canvas.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(canvas)
        content.axis = .vertical
        content.alignment = .center
        content.spacing = 8
        content.translatesAutoresizingMaskIntoConstraints = false
        canvas.addSubview(content)
        imageView.contentMode = .scaleAspectFit
        imageView.image = CompanionImageStore.shared.selectedImage
        imageView.heightAnchor.constraint(equalToConstant: 54).isActive = true
        imageView.widthAnchor.constraint(equalToConstant: 60).isActive = true
        mood.text = "假装正经"
        mood.font = .systemFont(ofSize: 17, weight: .bold)
        activity.text = "正在小屋里整理尾巴"
        thought.text = "只是顺便等你看见，不是特意。"
        thought.numberOfLines = 2
        thought.textAlignment = .center
        updated.font = .systemFont(ofSize: 11)
        updated.text = "刚刚更新"
        content.addArrangedSubview(imageView)
        content.addArrangedSubview(mood)
        content.addArrangedSubview(activity)
        content.addArrangedSubview(thought)
        content.addArrangedSubview(updated)
        NSLayoutConstraint.activate([
            segment.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 28),
            segment.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            segment.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            canvas.topAnchor.constraint(equalTo: segment.bottomAnchor, constant: 52),
            canvas.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            canvas.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.82),
            canvas.heightAnchor.constraint(equalToConstant: 210),
            content.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
            content.centerYAnchor.constraint(equalTo: canvas.centerYAnchor),
            content.leadingAnchor.constraint(greaterThanOrEqualTo: canvas.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(lessThanOrEqualTo: canvas.trailingAnchor, constant: -16),
        ])
        render()
    }

    @objc private func render() {
        let override = CompanionAppearanceStore.shared.themeOverride
        let theme = CompanionThemes.resolve(override ?? "moonlight")
        canvas.backgroundColor = UIColor(companionHex: theme.backgroundHex)
        [mood, activity].forEach { $0.textColor = UIColor(companionHex: theme.primaryHex) }
        thought.textColor = UIColor(companionHex: theme.secondaryHex)
        updated.textColor = UIColor(companionHex: theme.secondaryHex).withAlphaComponent(0.75)
        imageView.isHidden = false
        mood.isHidden = true
        activity.isHidden = true
        thought.isHidden = true
        updated.isHidden = true
        switch segment.selectedSegmentIndex {
        case 0:
            canvas.layer.cornerRadius = 44
            canvas.frame.size = CGSize(width: 88, height: 88)
        case 1:
            activity.isHidden = false
            canvas.layer.cornerRadius = 28
        case 2:
            mood.isHidden = false; activity.isHidden = false
            thought.isHidden = false; updated.isHidden = false
            canvas.layer.cornerRadius = 28
        default:
            mood.isHidden = false; activity.isHidden = false
            thought.isHidden = false; updated.isHidden = false
            canvas.layer.cornerRadius = 22
        }
        UIView.animate(withDuration: 0.45, delay: 0, options: [.curveEaseOut]) {
            self.canvas.transform = CGAffineTransform(scaleX: 1.025, y: 1.025)
        } completion: { _ in
            UIView.animate(withDuration: 0.25) { self.canvas.transform = .identity }
        }
    }
}

final class CompanionHistoryViewController: UITableViewController {
    private var values: [CompanionLocalHistoryEntry] = []
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "状态变化历史"
        values = CompanionAppearanceStore.shared.history()
        tableView.rowHeight = 92
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { values.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let value = values[indexPath.row]
        cell.textLabel?.text = "\(value.mood) · \(value.activity)"
        cell.detailTextLabel?.numberOfLines = 3
        cell.detailTextLabel?.text = "\(value.innerThought)\n\(CompanionThemes.resolve(value.themeID).name) · P\(value.priority) · \(value.updatedAt.formatted(date: .abbreviated, time: .shortened))"
        cell.imageView?.image = CompanionImageStore.shared.item(id: value.iconID)?.image
        return cell
    }
}

private extension UIColor {
    convenience init(companionHex hex: UInt, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255,
                  green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
    }
}
