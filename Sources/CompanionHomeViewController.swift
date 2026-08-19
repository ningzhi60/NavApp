import PhotosUI
import ReplayKit
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

        let broadcastPicker = RPSystemBroadcastPickerView()
        broadcastPicker.preferredExtension = "com.an.yinnav.ScreenBroadcast"
        broadcastPicker.showsMicrophoneButton = false
        broadcastPicker.heightAnchor.constraint(equalToConstant: 48).isActive = true
        let broadcastHint = UILabel()
        broadcastHint.text = "共享屏幕给灵动岛（点下方广播按钮；系统停止后不会自动重连）"
        broadcastHint.numberOfLines = 0
        broadcastHint.textAlignment = .center
        broadcastHint.textColor = .secondaryLabel
        broadcastHint.font = .systemFont(ofSize: 13)

        let stack = UIStackView(arrangedSubviews: [
            explanation,
            preview,
            statusLabel,
            makeButton("🏠 开启 / 更新灵动岛", #selector(startOrUpdate)),
            makeButton("✨ 让因换一个状态", #selector(nextPreview)),
            makeButton("🖼 添加或删除 PNG", #selector(manageImages)),
            broadcastHint,
            broadcastPicker,
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
        statusLabel.text = message ?? "Live Activity：\(support) · \(running)\n图片组：\(CompanionImageStore.shared.activeGroup.name) · \(count) 张"
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
                CompanionImageStore.shared.select(id: generated.iconID)
                let chosen = CompanionImageStore.shared.item(id: generated.iconID)
                let state = CompanionPublicState(
                    mood: generated.mood,
                    activity: generated.activity,
                    innerThought: generated.innerThought,
                    image: chosen?.image)
                CompanionActivityManager.shared.publish(state) { [weak self] error in
                    if let error = error {
                        self?.refresh(message: "开启失败：\(error)")
                        return
                    }
                    let effort = generated.effort.isEmpty ? "" : " · \(generated.effort)"
                    let source = generated.cached ? "复用近期状态" : "新生成"
                    self?.refresh(message:
                        "状态：\(generated.mood) · 图片：\(chosen?.name ?? "无")\n正在做：\(generated.activity)\n心里话：\(generated.innerThought)\n\(generated.backend) · \(generated.model)\(effort) · \(source) ✅")
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
    private var pendingImage: UIImage?

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.rowHeight = 76
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "图片组", style: .plain, target: self, action: #selector(showGroups))
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add, target: self, action: #selector(showImporter))
        reload()
    }

    private func reload() {
        items = CompanionImageStore.shared.items()
        title = CompanionImageStore.shared.activeGroup.name
        tableView.reloadData()
    }

    @objc private func showGroups() {
        let store = CompanionImageStore.shared
        let sheet = UIAlertController(title: "切换图片组", message: "模型只会从当前组选择图片", preferredStyle: .actionSheet)
        for group in store.groups() {
            let mark = group.id == store.activeGroupID ? "✓ " : ""
            sheet.addAction(UIAlertAction(title: mark + group.name, style: .default) { [weak self] _ in
                store.activeGroupID = group.id
                self?.reload()
            })
        }
        sheet.addAction(UIAlertAction(title: "新建图片组", style: .default) { [weak self] _ in
            self?.promptForGroup()
        })
        if !store.activeGroup.builtIn {
            sheet.addAction(UIAlertAction(title: "重命名当前组", style: .default) { [weak self] _ in
                self?.promptForGroup(rename: true)
            })
            sheet.addAction(UIAlertAction(title: "删除当前组", style: .destructive) { [weak self] _ in
                try? store.deleteActiveGroup()
                self?.reload()
            })
        } else {
            sheet.addAction(UIAlertAction(title: "恢复内置猫头", style: .default) { [weak self] _ in
                store.restoreBuiltIns()
                self?.reload()
            })
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        sheet.popoverPresentationController?.barButtonItem = navigationItem.leftBarButtonItem
        present(sheet, animated: true)
    }

    private func promptForGroup(rename: Bool = false) {
        let alert = UIAlertController(title: rename ? "重命名图片组" : "新建图片组",
                                      message: "例如：像素猫头", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "图片组名称"
            if rename { field.text = CompanionImageStore.shared.activeGroup.name }
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
            let name = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { return }
            if rename { CompanionImageStore.shared.renameActiveGroup(name) }
            else { CompanionImageStore.shared.createGroup(name: name) }
            self?.reload()
        })
        present(alert, animated: true)
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
        cell.textLabel?.text = item.name
        cell.detailTextLabel?.text = item.meaning
        cell.detailTextLabel?.numberOfLines = 2
        cell.accessoryType = CompanionImageStore.shared.selectedID == item.id ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = items[indexPath.row]
        CompanionImageStore.shared.select(id: item.id)
        if item.metadata.builtIn { reload() }
        else { promptForMetadata(image: item.image, editing: item) }
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
            DispatchQueue.main.async { self?.promptForMetadata(image: image) }
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first, let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return }
        promptForMetadata(image: image)
    }

    private func promptForMetadata(image: UIImage?, editing item: CompanionImageItem? = nil) {
        guard let image else { return }
        pendingImage = image
        let alert = UIAlertController(
            title: item == nil ? "给猫头命名" : "编辑猫头含义",
            message: "名称和含义会交给模型，用来准确选择这张图。", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "名称，例如：刚睡醒"
            field.text = item?.name
        }
        alert.addTextField { field in
            field.placeholder = "含义，例如：困倦、迷糊、想赖床"
            field.text = item?.meaning
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let name = alert?.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let meaning = alert?.textFields?[1].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty, !meaning.isEmpty else { return }
            if let item { CompanionImageStore.shared.update(item, name: name, meaning: meaning) }
            else { try? CompanionImageStore.shared.importImage(image, name: name, meaning: meaning) }
            self.pendingImage = nil
            self.reload()
        })
        present(alert, animated: true)
    }
}
