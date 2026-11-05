import Foundation

struct OpacityJournalEntry: Codable, Equatable {
    let windowID: UInt32
    let pid: Int32
    let app: String
    let title: String
    let originalOpacity: Double
    let updatedAt: Date
}

/// 用磁盘日志兜底应用崩溃或被强制退出时的透明度恢复。
final class OpacityJournal {
    private let fileURL: URL

    init() {
        fileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacGlass", isDirectory: true)
            .appendingPathComponent("opacity-journal.json")
    }

    func load() -> [OpacityJournalEntry] {
        guard
            let data = try? Data(contentsOf: fileURL),
            let entries = try? JSONDecoder().decode([OpacityJournalEntry].self, from: data)
        else {
            return []
        }
        return entries
    }

    func save(_ entries: [OpacityJournalEntry]) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if entries.isEmpty {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                }
                return
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("MacGlass: 无法写入透明度恢复日志：%@", error.localizedDescription)
        }
    }
}
