import PhotosUI
import UIKit
import UniformTypeIdentifiers

final class CompanionHomeViewController: UIViewController {
    private let statusLabel = UILabel()
    private let preview = UIImageView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "因的灵动岛小屋"
        view.backgroundColor = .systemBackground

        let explanation = UILabel()
        explanation.numberOfLines = 0
        explanation.textAlignment = .center
        explanation.textColor = .secondaryLabel
        explanation.text = "灵动岛展示因公开表达的状态和想法。点灵动岛可去 Telegram 找她聊天；不点也不会打断她。"

        preview.contentMode = .scaleAspectFit
        preview.backgroundColor = .secondarySystemBackground
        preview.layer.cornerRadius = 18
        preview.clipsToBounds = true
        preview.heightAnchor.constraint(equalToConstant: 112).isActive = true

        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.font = .systemFont(ofSize: 14, weight: .medium)

        let stack = UIStackView(arrangedSubviews: [
            explanation,
            preview,
            statusLabel,
            makeButton("🏠 开启 / 更新灵动岛", #selector(startOrUpdate)),
            makeButton("✨ 让因换一个状态", #selector(nextPreview)),
            makeButton("🖼 添加或删除 PNG", #selector(manageImages)),
            makeButton("⏹ 关闭灵动岛", #selector(endActivity), color: .systemRed),
        ])
        stack.axis = .vertical
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
        ])
        refresh()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refresh()
        if CompanionActivityManager.shared.isRunning {
            requestState(force: false)
        }
    }

    private func makeButton(_ title: String, _ action: Selector, color: UIColor = .systemBlue) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(color, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func refresh(message: String? = nil) {
        preview.image = CompanionImageStore.shared.selectedImage
        let count = CompanionImageStore.shared.items().count
        let support = CompanionActivityManager.shared.isSupported ? "可用" : "不可用或被系统关闭"
        let running = CompanionActivityManager.shared.isRunning ? "运行中" : "未开启"
        statusLabel.text = message ?? "Live Activity：\(support) · \(running)\nPNG：\(count) 张（当前图会自动压缩后送进灵动岛）"
    }

    @objc private func startOrUpdate() {
        requestState(force: false)
    }

    @objc private func nextPreview() {
        requestState(force: true)
    }

    private func requestState(force: Bool) {
        refresh(message: "因正在想此刻想公开的状态…")
        CompanionStateService.shared.fetch(force: force) { [weak self] result in
            switch result {
            case .failure(let error):
                self?.refresh(message: "更新失败：\(error.localizedDescription)\n已有的灵动岛内容不变。")
            case .success(let generated):
                let state = CompanionPublicState(
                    mood: generated.mood,
                    activity: generated.activity,
                    innerThought: generated.innerThought,
                    image: CompanionImageStore.shared.selectedImage)
                CompanionActivityManager.shared.publish(state) { [weak self] error in
                    if let error = error {
                        self?.refresh(message: "开启失败：\(error)")
                        return
                    }
                    let effort = generated.effort.isEmpty ? "" : " · \(generated.effort)"
                    let source = generated.cached ? "复用近期状态" : "新生成"
                    self?.refresh(message:
                        "状态：\(generated.mood)\n正在做：\(generated.activity)\n心里话：\(generated.innerThought)\n\(generated.backend) · \(generated.model)\(effort) · \(source) ✅")
                }
            }
        }
    }

    @objc private func manageImages() {
        navigationController?.pushViewController(CompanionImageManagerViewController(), animated: true)
    }

    @objc private func endActivity() {
        CompanionActivityManager.shared.end { [weak self] in self?.refresh(message: "灵动岛已关闭") }
    }
}

final class CompanionImageManagerViewController: UITableViewController,
    PHPickerViewControllerDelegate, UIDocumentPickerDelegate {

    private var items: [CompanionImageItem] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "小屋 PNG"
        tableView.rowHeight = 68
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add, target: self, action: #selector(showImporter))
        reload()
    }

    private func reload() {
        items = CompanionImageStore.shared.items()
        tableView.reloadData()
    }

    @objc private func showImporter() {
        let sheet = UIAlertController(title: "添加一张图片", message: "导入后会统一保存为 PNG", preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "从照片选择", style: .default) { [weak self] _ in
            var config = PHPickerConfiguration(photoLibrary: .shared())
            config.filter = .images
            config.selectionLimit = 1
            let picker = PHPickerViewController(configuration: config)
            picker.delegate = self
            self?.present(picker, animated: true)
        })
        sheet.addAction(UIAlertAction(title: "从文件选择 PNG", style: .default) { [weak self] _ in
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.png, .image], asCopy: true)
            picker.delegate = self
            self?.present(picker, animated: true)
        })
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        sheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(sheet, animated: true)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let id = "png"
        let cell = tableView.dequeueReusableCell(withIdentifier: id) ?? UITableViewCell(style: .subtitle, reuseIdentifier: id)
        let item = items[indexPath.row]
        cell.imageView?.image = item.image
        cell.imageView?.contentMode = .scaleAspectFit
        cell.textLabel?.text = "小屋图片 \(indexPath.row + 1)"
        cell.detailTextLabel?.text = item.id
        cell.accessoryType = CompanionImageStore.shared.selectedID == item.id ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        CompanionImageStore.shared.selectedID = items[indexPath.row].id
        reload()
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        try? CompanionImageStore.shared.delete(items[indexPath.row])
        reload()
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            guard let image = object as? UIImage else { return }
            try? CompanionImageStore.shared.importImage(image)
            DispatchQueue.main.async { self?.reload() }
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first, let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return }
        try? CompanionImageStore.shared.importImage(image)
        reload()
    }
}
