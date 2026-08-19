import Foundation

struct CompanionLocalHistoryEntry: Codable, Hashable {
    let mood: String
    let activity: String
    let innerThought: String
    let iconID: String
    let themeID: String
    let priority: Int
    let updatedAt: Date
}

final class CompanionAppearanceStore {
    static let shared = CompanionAppearanceStore()
    private init() {}

    private let themeOverrideKey = "companion.themeOverride"
    private let decorationsKey = "companion.decorationsEnabled"
    private let doNotDisturbKey = "companion.doNotDisturb"
    private let historyKey = "companion.localHistory"

    /// nil means the Bot can choose one of the safe built-in themes.
    var themeOverride: String? {
        get {
            let value = UserDefaults.standard.string(forKey: themeOverrideKey) ?? ""
            return CompanionThemes.all.contains(where: { $0.id == value }) ? value : nil
        }
        set { UserDefaults.standard.set(newValue ?? "", forKey: themeOverrideKey) }
    }

    var decorationsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: decorationsKey) }
        set { UserDefaults.standard.set(newValue, forKey: decorationsKey) }
    }

    var doNotDisturb: Bool {
        get { UserDefaults.standard.bool(forKey: doNotDisturbKey) }
        set { UserDefaults.standard.set(newValue, forKey: doNotDisturbKey) }
    }

    func resolvedTheme(modelTheme: String) -> String {
        themeOverride ?? CompanionThemes.resolve(modelTheme).id
    }

    func addHistory(_ entry: CompanionLocalHistoryEntry) {
        var values = history()
        if let first = values.first,
           first.mood == entry.mood, first.activity == entry.activity,
           first.innerThought == entry.innerThought, first.iconID == entry.iconID,
           first.themeID == entry.themeID { return }
        values.insert(entry, at: 0)
        if values.count > 60 { values.removeLast(values.count - 60) }
        if let data = try? JSONEncoder().encode(values) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    func history() -> [CompanionLocalHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let values = try? JSONDecoder().decode([CompanionLocalHistoryEntry].self, from: data)
        else { return [] }
        return values
    }

    func reset() {
        themeOverride = nil
        decorationsEnabled = false
        doNotDisturb = false
    }
}
