import Foundation

/// 解析 `csrutil status`，只关心 yabai 注入 scripting addition 所需的两项权限。
public struct SIPStatus: Equatable, Sendable {
    public let raw: String
    public let filesystemProtectionsDisabled: Bool
    public let debuggingRestrictionsDisabled: Bool

    public static let recoveryCommand = "csrutil enable --without fs --without debug"

    public init(raw: String) {
        self.raw = raw

        let normalized = raw
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "  ", with: " ")

        let fullyDisabled = normalized.range(
            of: "System Integrity Protection status: disabled",
            options: [.caseInsensitive]
        ) != nil

        filesystemProtectionsDisabled = fullyDisabled
            || normalized.range(
                of: "Filesystem Protections: disabled",
                options: [.caseInsensitive, .diacriticInsensitive]
            ) != nil

        debuggingRestrictionsDisabled = fullyDisabled
            || normalized.range(
                of: "Debugging Restrictions: disabled",
                options: [.caseInsensitive, .diacriticInsensitive]
            ) != nil
    }

    public var allowsScriptingAddition: Bool {
        filesystemProtectionsDisabled && debuggingRestrictionsDisabled
    }
}
