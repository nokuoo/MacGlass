import Testing
@testable import MacGlassCore

@Suite("SIP 状态")
struct SIPStatusTests {
    @Test("识别调试限制仍开启的配置")
    func parsesCustomConfiguration() {
        let status = SIPStatus(
            raw: """
            System Integrity Protection status: unknown (Custom Configuration).

            Configuration:
                Apple Internal: disabled
                Kext Signing: disabled
                Filesystem Protections: disabled
                Debugging Restrictions: enabled
                DTrace Restrictions: enabled
            """
        )

        #expect(status.filesystemProtectionsDisabled)
        #expect(!status.debuggingRestrictionsDisabled)
        #expect(!status.allowsScriptingAddition)
    }

    @Test("识别 yabai 所需配置")
    func parsesRequiredYabaiConfiguration() {
        let status = SIPStatus(
            raw: """
            System Integrity Protection status: unknown (Custom Configuration).

            Configuration:
                Filesystem Protections: disabled
                Debugging Restrictions: disabled
            """
        )

        #expect(status.allowsScriptingAddition)
    }

    @Test("完全关闭 SIP")
    func fullyDisabledCountsAsBothPermissions() {
        let status = SIPStatus(raw: "System Integrity Protection status: disabled.")
        #expect(status.filesystemProtectionsDisabled)
        #expect(status.debuggingRestrictionsDisabled)
        #expect(status.allowsScriptingAddition)
    }

    @Test("完全开启 SIP 时阻止注入")
    func fullyEnabledIsBlocked() {
        let status = SIPStatus(
            raw: """
            System Integrity Protection status: enabled.
            Filesystem Protections: enabled
            Debugging Restrictions: enabled
            """
        )
        #expect(!status.allowsScriptingAddition)
    }
}
