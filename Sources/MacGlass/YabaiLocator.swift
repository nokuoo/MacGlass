import Foundation

enum YabaiLocator {
    /// 优先使用用户已有 yabai，独立分发时回退到内置引擎。
    static func locate() -> URL? {
        let fileManager = FileManager.default
        var candidates: [URL] = []

        if let configured = ProcessInfo.processInfo.environment["MACGLASS_YABAI_PATH"] {
            candidates.append(URL(fileURLWithPath: configured))
        }

        candidates.append(URL(fileURLWithPath: "/usr/local/bin/yabai"))
        candidates.append(URL(fileURLWithPath: "/opt/homebrew/bin/yabai"))
        candidates.append(
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("homebrew/bin/yabai")
        )

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("yabai"))
        }

        candidates.append(
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/MacGlass/bin/yabai")
        )
        candidates.append(
            URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appendingPathComponent("Vendor/yabai")
        )

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates.append(
                contentsOf: path.split(separator: ":").map {
                    URL(fileURLWithPath: String($0)).appendingPathComponent("yabai")
                }
            )
        }

        var seen = Set<String>()
        for candidate in candidates {
            let standardized = candidate.standardizedFileURL
            guard seen.insert(standardized.path).inserted else { continue }
            if fileManager.isExecutableFile(atPath: standardized.path) {
                return standardized
            }
        }
        return nil
    }
}
