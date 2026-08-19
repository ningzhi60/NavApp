import UIKit

struct CompanionImageGroup: Codable, Hashable {
    let id: String
    var name: String
    let builtIn: Bool
}

struct CompanionImageMetadata: Codable, Hashable {
    let id: String
    let groupID: String
    var name: String
    var meaning: String
    let fileName: String
    let builtIn: Bool
}

struct CompanionImageItem: Hashable {
    let metadata: CompanionImageMetadata
    let url: URL
    var id: String { metadata.id }
    var name: String { metadata.name }
    var meaning: String { metadata.meaning }
    var image: UIImage? { UIImage(contentsOfFile: url.path) }
}

final class CompanionImageStore {
    static let shared = CompanionImageStore()
    static let builtInGroupID = "pretend-serious"

    private let selectedKey = "companion.selectedImage.v2"
    private let activeGroupKey = "companion.activeImageGroup.v2"
    private let customGroupsKey = "companion.customImageGroups.v2"
    private let customItemsKey = "companion.customImages.v2"
    private let hiddenBuiltInsKey = "companion.hiddenBuiltInImages.v2"
    private let disabledIDsKey = "companion.disabledImageIDs.v2"
    private let fileManager = FileManager.default

    private let builtInGroup = CompanionImageGroup(
        id: CompanionImageStore.builtInGroupID, name: "假装正经猫猫", builtIn: true)
    private let builtInMetadata: [CompanionImageMetadata] = [
        .init(id: "serious", groupID: CompanionImageStore.builtInGroupID,
              name: "假装正经", meaning: "平静、认真、专注、默认状态",
              fileName: "serious.png", builtIn: true),
        .init(id: "secretly_happy", groupID: CompanionImageStore.builtInGroupID,
              name: "暗自开心", meaning: "开心、害羞、被哄好、嘴硬但高兴",
              fileName: "secretly_happy.png", builtIn: true),
        .init(id: "sulking", groupID: CompanionImageStore.builtInGroupID,
              name: "嘴硬吃醋", meaning: "吃醋、生闷气、别扭、不服气",
              fileName: "sulking.png", builtIn: true),
        .init(id: "worried", groupID: CompanionImageStore.builtInGroupID,
              name: "有点担心", meaning: "担心、关心、不安、认真听你说",
              fileName: "worried.png", builtIn: true),
    ]

    private init() {}

    private var directory: URL {
        let base = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("CompanionImages", isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func decode<T: Decodable>(_ type: T.Type, key: String, fallback: T) -> T {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode(type, from: data) else { return fallback }
        return value
    }

    private func encode<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private var customGroups: [CompanionImageGroup] {
        get { decode([CompanionImageGroup].self, key: customGroupsKey, fallback: []) }
        set { encode(newValue, key: customGroupsKey) }
    }

    private var customMetadata: [CompanionImageMetadata] {
        get { decode([CompanionImageMetadata].self, key: customItemsKey, fallback: []) }
        set { encode(newValue, key: customItemsKey) }
    }

    private var hiddenBuiltIns: Set<String> {
        get { Set(decode([String].self, key: hiddenBuiltInsKey, fallback: [])) }
        set { encode(Array(newValue).sorted(), key: hiddenBuiltInsKey) }
    }

    private var disabledIDs: Set<String> {
        get { Set(decode([String].self, key: disabledIDsKey, fallback: [])) }
        set { encode(Array(newValue).sorted(), key: disabledIDsKey) }
    }

    func isEnabledForAI(_ id: String) -> Bool { !disabledIDs.contains(id) }

    func setEnabledForAI(_ enabled: Bool, id: String) {
        var values = disabledIDs
        if enabled { values.remove(id) } else { values.insert(id) }
        disabledIDs = values
    }

    func groups() -> [CompanionImageGroup] { [builtInGroup] + customGroups }

    var activeGroupID: String {
        get {
            let saved = UserDefaults.standard.string(forKey: activeGroupKey)
            return groups().contains(where: { $0.id == saved }) ? saved! : Self.builtInGroupID
        }
        set {
            guard groups().contains(where: { $0.id == newValue }) else { return }
            UserDefaults.standard.set(newValue, forKey: activeGroupKey)
            if !items().contains(where: { $0.id == selectedID }) {
                selectedID = items().first?.id
            }
        }
    }

    var activeGroup: CompanionImageGroup {
        groups().first(where: { $0.id == activeGroupID }) ?? builtInGroup
    }

    private func builtInURL(_ metadata: CompanionImageMetadata) -> URL? {
        let stem = (metadata.fileName as NSString).deletingPathExtension
        return Bundle.main.url(forResource: stem, withExtension: "png",
                               subdirectory: "CompanionAssets/pretend-serious")
            ?? Bundle.main.url(forResource: stem, withExtension: "png")
    }

    func items(groupID: String? = nil) -> [CompanionImageItem] {
        let groupID = groupID ?? activeGroupID
        var result: [CompanionImageItem] = []
        if groupID == Self.builtInGroupID {
            let hidden = hiddenBuiltIns
            result += builtInMetadata.compactMap { metadata in
                guard !hidden.contains(metadata.id), let url = builtInURL(metadata) else { return nil }
                return CompanionImageItem(metadata: metadata, url: url)
            }
        }
        result += customMetadata.compactMap { metadata in
            guard metadata.groupID == groupID else { return nil }
            let url = directory.appendingPathComponent(metadata.fileName)
            guard fileManager.fileExists(atPath: url.path) else { return nil }
            return CompanionImageItem(metadata: metadata, url: url)
        }
        return result
    }

    var selectedID: String? {
        get { UserDefaults.standard.string(forKey: selectedKey) }
        set { UserDefaults.standard.set(newValue, forKey: selectedKey) }
    }

    func item(id: String?) -> CompanionImageItem? {
        guard let id else { return items().first }
        return items().first(where: { $0.id == id }) ?? items().first
    }

    var selectedImage: UIImage? { item(id: selectedID)?.image }
    func select(id: String?) { selectedID = item(id: id)?.id }

    /// Only names/meanings go to the model. Image bytes and filenames stay on-device.
    func modelCatalog() -> [String: Any] {
        ["groupID": activeGroup.id, "groupName": activeGroup.name,
         "images": items().filter { isEnabledForAI($0.id) }.prefix(30).map {
            ["id": $0.id, "name": $0.name, "meaning": $0.meaning]
         }]
    }

    @discardableResult
    func createGroup(name: String) -> CompanionImageGroup {
        let group = CompanionImageGroup(
            id: "custom_" + UUID().uuidString.lowercased(),
            name: String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24)),
            builtIn: false)
        var values = customGroups
        values.append(group)
        customGroups = values
        activeGroupID = group.id
        return group
    }

    func renameActiveGroup(_ name: String) {
        guard activeGroupID != Self.builtInGroupID else { return }
        var values = customGroups
        guard let index = values.firstIndex(where: { $0.id == activeGroupID }) else { return }
        values[index].name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        customGroups = values
    }

    func deleteActiveGroup() throws {
        let target = activeGroupID
        guard target != Self.builtInGroupID else { return }
        for item in items(groupID: target) { try? fileManager.removeItem(at: item.url) }
        var images = customMetadata
        images.removeAll(where: { $0.groupID == target })
        customMetadata = images
        var groups = customGroups
        groups.removeAll(where: { $0.id == target })
        customGroups = groups
        activeGroupID = Self.builtInGroupID
        selectedID = items().first?.id
    }

    @discardableResult
    func importImage(_ source: UIImage, name: String, meaning: String) throws -> CompanionImageItem {
        guard let normalized = source.normalized(maxPixel: 768),
              let data = normalized.pngData() else { throw CocoaError(.fileWriteUnknown) }
        let uuid = UUID().uuidString.lowercased()
        let fileName = uuid + ".png"
        let url = directory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        let metadata = CompanionImageMetadata(
            id: "custom_" + uuid, groupID: activeGroupID,
            name: String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24)),
            meaning: String(meaning.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)),
            fileName: fileName, builtIn: false)
        var values = customMetadata
        values.append(metadata)
        customMetadata = values
        selectedID = metadata.id
        return CompanionImageItem(metadata: metadata, url: url)
    }

    func update(_ item: CompanionImageItem, name: String, meaning: String) {
        guard !item.metadata.builtIn else { return }
        var values = customMetadata
        guard let index = values.firstIndex(where: { $0.id == item.id }) else { return }
        values[index].name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        values[index].meaning = String(meaning.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        customMetadata = values
    }

    func delete(_ item: CompanionImageItem) throws {
        if item.metadata.builtIn {
            var hidden = hiddenBuiltIns
            hidden.insert(item.id)
            hiddenBuiltIns = hidden
        } else {
            try fileManager.removeItem(at: item.url)
            var values = customMetadata
            values.removeAll(where: { $0.id == item.id })
            customMetadata = values
        }
        if selectedID == item.id { selectedID = items().first?.id }
    }

    func restoreBuiltIns() {
        hiddenBuiltIns = []
        if activeGroupID == Self.builtInGroupID { selectedID = items().first?.id }
    }

    func activityIconData(for image: UIImage?) -> Data? {
        guard let image else { return nil }
        for pixels in [32, 28, 24, 20, 18, 16] {
            if let resized = image.normalized(maxPixel: CGFloat(pixels)),
               let data = resized.pngData(), data.count <= 2_200 { return data }
        }
        return nil
    }
}

private extension UIImage {
    func normalized(maxPixel: CGFloat) -> UIImage? {
        let longest = max(size.width, size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maxPixel / longest)
        let target = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
