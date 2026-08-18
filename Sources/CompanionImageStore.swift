import UIKit

struct CompanionImageItem: Hashable {
    let url: URL
    var id: String { url.lastPathComponent }
    var image: UIImage? { UIImage(contentsOfFile: url.path) }
}

final class CompanionImageStore {
    static let shared = CompanionImageStore()

    private let selectedKey = "companion.selectedImage"
    private let fileManager = FileManager.default

    private init() {}

    private var directory: URL {
        let base = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("CompanionImages", isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func items() -> [CompanionImageItem] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        let urls = (try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles])) ?? []
        return urls
            .filter { $0.pathExtension.lowercased() == "png" }
            .sorted {
                let left = try? $0.resourceValues(forKeys: keys).contentModificationDate
                let right = try? $1.resourceValues(forKeys: keys).contentModificationDate
                return (left ?? .distantPast) > (right ?? .distantPast)
            }
            .map(CompanionImageItem.init)
    }

    var selectedID: String? {
        get { UserDefaults.standard.string(forKey: selectedKey) }
        set { UserDefaults.standard.set(newValue, forKey: selectedKey) }
    }

    var selectedImage: UIImage? {
        guard let id = selectedID else { return items().first?.image }
        return items().first(where: { $0.id == id })?.image ?? items().first?.image
    }

    @discardableResult
    func importImage(_ source: UIImage) throws -> CompanionImageItem {
        guard let normalized = source.normalized(maxPixel: 768),
              let data = normalized.pngData() else {
            throw CocoaError(.fileWriteUnknown)
        }
        let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        try data.write(to: url, options: .atomic)
        let item = CompanionImageItem(url: url)
        selectedID = item.id
        return item
    }

    func delete(_ item: CompanionImageItem) throws {
        try fileManager.removeItem(at: item.url)
        if selectedID == item.id { selectedID = items().first?.id }
    }

    /// Dynamic Island 状态总计只有 4KB。保留原 PNG，同时为岛生成尽量大的轻量透明缩略图。
    func activityIconData(for image: UIImage?) -> Data? {
        guard let image else { return nil }
        for pixels in [72, 60, 52, 44, 36, 28, 22, 18] {
            if let resized = image.normalized(maxPixel: CGFloat(pixels)),
               let data = resized.pngData(), data.count <= 2_200 {
                return data
            }
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
