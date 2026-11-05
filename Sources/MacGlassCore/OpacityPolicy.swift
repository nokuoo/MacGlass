import Foundation

public enum OpacityPolicy {
    /// 最低 5%，避免用户把窗口变成无法找回的“隐形窗口”。
    public static let minimum = 0.05
    public static let maximum = 1.0

    public static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return maximum }
        return min(maximum, max(minimum, value))
    }

    /// 滑杆使用 1% 步进，同时四舍五入到两位小数，避免浮点尾差。
    public static func commandValue(for value: Double) -> Double {
        let normalized = clamped(value)
        return (normalized * 100).rounded() / 100
    }

    /// yabai 约定传 0.0 表示恢复自动管理并回到完全不透明。
    public static func restoreValue(for originalOpacity: Double) -> Double {
        guard originalOpacity.isFinite else { return 0.0 }
        if originalOpacity >= 0.999 {
            return 0.0
        }
        return min(1.0, max(0.01, originalOpacity))
    }

    public static func displayValue(forActualOpacity value: Double) -> Double {
        guard value.isFinite else { return maximum }
        if value <= 0.0 || value >= 1.0 {
            return maximum
        }
        return clamped(value)
    }

    public static func isEffectivelyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < 0.005
    }

    /// 快捷键每次固定调整 5%，并按 1% 精度对齐，避免连续按键累积浮点误差。
    public static func stepped(
        from current: Double,
        direction: OpacityStepDirection,
        amount: Double = 0.05
    ) -> Double {
        let normalized = commandValue(for: current)
        let step = max(0.01, amount)
        switch direction {
        case .moreTransparent:
            return commandValue(for: normalized - step)
        case .lessTransparent:
            return commandValue(for: normalized + step)
        }
    }
}

public enum OpacityStepDirection: Sendable, Hashable {
    case moreTransparent
    case lessTransparent
}

public enum YabaiCommand {
    public static let queryWindows = ["-m", "query", "--windows"]
    public static let loadScriptingAddition = ["--load-sa"]

    public static func setOpacity(windowID: UInt32, value: Double) -> [String] {
        [
            "-m",
            "window",
            String(windowID),
            "--opacity",
            formatted(value)
        ]
    }

    public static func start(configurationPath: String) -> [String] {
        ["--config", configurationPath]
    }

    private static func formatted(_ value: Double) -> String {
        let normalized = min(1.0, max(0.0, value))
        return String(
            format: "%.2f",
            locale: Locale(identifier: "en_US_POSIX"),
            normalized
        )
    }
}
