import Foundation

/// yabai 查询结果中的窗口坐标。
public struct WindowFrame: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    private enum CodingKeys: String, CodingKey {
        case x
        case y
        case width = "w"
        case height = "h"
    }
}

/// `yabai -m query --windows` 返回的单个窗口。
public struct YabaiWindow: Codable, Identifiable, Equatable, Sendable {
    public let id: UInt32
    public let pid: Int32
    public let app: String
    public let title: String
    public let frame: WindowFrame
    public let role: String
    public let subrole: String
    public let layer: String
    public let opacity: Double
    public let hasAXReference: Bool
    public let isVisible: Bool
    public let isMinimized: Bool
    public let isHidden: Bool
    public let hasFocus: Bool
    public let isNativeFullscreen: Bool

    public init(
        id: UInt32,
        pid: Int32,
        app: String,
        title: String,
        frame: WindowFrame,
        role: String,
        subrole: String,
        layer: String,
        opacity: Double,
        hasAXReference: Bool,
        isVisible: Bool,
        isMinimized: Bool,
        isHidden: Bool,
        hasFocus: Bool,
        isNativeFullscreen: Bool
    ) {
        self.id = id
        self.pid = pid
        self.app = app
        self.title = title
        self.frame = frame
        self.role = role
        self.subrole = subrole
        self.layer = layer
        self.opacity = opacity
        self.hasAXReference = hasAXReference
        self.isVisible = isVisible
        self.isMinimized = isMinimized
        self.isHidden = isHidden
        self.hasFocus = hasFocus
        self.isNativeFullscreen = isNativeFullscreen
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case pid
        case app
        case title
        case frame
        case role
        case subrole
        case layer
        case opacity
        case hasAXReference = "has-ax-reference"
        case isVisible = "is-visible"
        case isMinimized = "is-minimized"
        case isHidden = "is-hidden"
        case hasFocus = "has-focus"
        case isNativeFullscreen = "is-native-fullscreen"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UInt32.self, forKey: .id)
        pid = try container.decode(Int32.self, forKey: .pid)
        app = try container.decodeIfPresent(String.self, forKey: .app) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        frame = try container.decode(WindowFrame.self, forKey: .frame)
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? ""
        subrole = try container.decodeIfPresent(String.self, forKey: .subrole) ?? ""
        layer = try container.decodeIfPresent(String.self, forKey: .layer) ?? ""
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1.0
        hasAXReference = try container.decodeIfPresent(Bool.self, forKey: .hasAXReference) ?? false
        isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? false
        isMinimized = try container.decodeIfPresent(Bool.self, forKey: .isMinimized) ?? false
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        hasFocus = try container.decodeIfPresent(Bool.self, forKey: .hasFocus) ?? false
        isNativeFullscreen = try container.decodeIfPresent(Bool.self, forKey: .isNativeFullscreen) ?? false
    }

    /// 只暴露 yabai 拥有 AX 引用、可安全操作的普通窗口。
    public var isEligibleForOpacity: Bool {
        role == "AXWindow"
            && subrole == "AXStandardWindow"
            && layer == "normal"
            && hasAXReference
            && isVisible
            && !isMinimized
            && !isHidden
            && !isNativeFullscreen
            && frame.width >= 40
            && frame.height >= 40
    }

    public var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var displayName: String {
        let appName = app.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTitle = trimmedTitle
        if appName.isEmpty {
            return cleanTitle.isEmpty ? "未命名窗口" : cleanTitle
        }
        if cleanTitle.isEmpty || cleanTitle == appName {
            return appName
        }
        return "\(appName) · \(cleanTitle)"
    }

    /// 将服务端返回值合并到本地状态，不重新查询窗口。
    public func replacingOpacity(with value: Double) -> YabaiWindow {
        YabaiWindow(
            id: id,
            pid: pid,
            app: app,
            title: title,
            frame: frame,
            role: role,
            subrole: subrole,
            layer: layer,
            opacity: value,
            hasAXReference: hasAXReference,
            isVisible: isVisible,
            isMinimized: isMinimized,
            isHidden: isHidden,
            hasFocus: hasFocus,
            isNativeFullscreen: isNativeFullscreen
        )
    }

    public func replacingFocus(_ focused: Bool) -> YabaiWindow {
        YabaiWindow(
            id: id,
            pid: pid,
            app: app,
            title: title,
            frame: frame,
            role: role,
            subrole: subrole,
            layer: layer,
            opacity: opacity,
            hasAXReference: hasAXReference,
            isVisible: isVisible,
            isMinimized: isMinimized,
            isHidden: isHidden,
            hasFocus: focused,
            isNativeFullscreen: isNativeFullscreen
        )
    }
}

public enum WindowCatalog {
    /// 过滤并排序可见窗口。焦点窗口置顶，其余按应用和标题稳定排序。
    public static func visibleWindows(
        from windows: [YabaiWindow],
        excludingPID excludedPID: Int32
    ) -> [YabaiWindow] {
        windows
            .filter { $0.pid != excludedPID && $0.isEligibleForOpacity }
            .sorted { lhs, rhs in
                if lhs.hasFocus != rhs.hasFocus {
                    return lhs.hasFocus
                }
                let appOrder = lhs.app.localizedStandardCompare(rhs.app)
                if appOrder != .orderedSame {
                    return appOrder == .orderedAscending
                }
                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
    }

    /// 返回当前焦点窗口；没有焦点时使用 yabai 前后顺序中最靠前的一个。
    public static func frontmostWindow(
        from windows: [YabaiWindow],
        excludingPID excludedPID: Int32
    ) -> YabaiWindow? {
        let eligible = windows.filter { $0.pid != excludedPID && $0.isEligibleForOpacity }
        return eligible.first(where: \.hasFocus) ?? eligible.first
    }

    public static func matches(_ window: YabaiWindow, query: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return true }
        return window.app.localizedCaseInsensitiveContains(normalized)
            || window.title.localizedCaseInsensitiveContains(normalized)
    }
}
