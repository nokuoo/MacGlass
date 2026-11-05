import Testing
@testable import MacGlassCore

@Suite("透明度策略")
struct OpacityPolicyTests {
    @Test("限制安全透明度范围")
    func clampsToSafeRange() {
        #expect(OpacityPolicy.clamped(-5) == 0.05)
        #expect(OpacityPolicy.clamped(0) == 0.05)
        #expect(OpacityPolicy.clamped(0.73) == 0.73)
        #expect(OpacityPolicy.clamped(2) == 1.0)
        #expect(OpacityPolicy.clamped(.nan) == 1.0)
    }

    @Test("命令值使用百分之一精度")
    func commandValueUsesHundredthSteps() {
        #expect(OpacityPolicy.commandValue(for: 0.726) == 0.73)
        #expect(OpacityPolicy.commandValue(for: 0.04) == 0.05)
        #expect(OpacityPolicy.commandValue(for: 1.0) == 1.0)
    }

    @Test("不透明窗口使用 yabai 的 0.0 重置语义")
    func restoreValueUsesResetSentinel() {
        #expect(OpacityPolicy.restoreValue(for: 1.0) == 0.0)
        #expect(OpacityPolicy.restoreValue(for: 0.65) == 0.65)
        #expect(OpacityPolicy.restoreValue(for: 0.02) == 0.02)
    }

    @Test("生成 yabai 窗口选择器命令")
    func setOpacityCommandMatchesYabaiGrammar() {
        #expect(
            YabaiCommand.setOpacity(windowID: 1234, value: 0.8)
                == ["-m", "window", "1234", "--opacity", "0.80"]
        )
        #expect(YabaiCommand.queryWindows == ["-m", "query", "--windows"])
    }

    @Test("快捷键按 5% 步进并限制安全范围")
    func shortcutStepsWithinSafeRange() {
        #expect(OpacityPolicy.stepped(from: 1.0, direction: .moreTransparent) == 0.95)
        #expect(OpacityPolicy.stepped(from: 0.73, direction: .moreTransparent) == 0.68)
        #expect(OpacityPolicy.stepped(from: 0.12, direction: .moreTransparent) == 0.07)
        #expect(OpacityPolicy.stepped(from: 0.07, direction: .moreTransparent) == 0.05)
        #expect(OpacityPolicy.stepped(from: 0.05, direction: .lessTransparent) == 0.10)
        #expect(OpacityPolicy.stepped(from: 0.98, direction: .lessTransparent) == 1.0)
        #expect(OpacityPolicy.stepped(from: 1.0, direction: .lessTransparent) == 1.0)
    }

    @Test("长按使用 1% 细步进并停在边界")
    func holdStepsUseOnePercent() {
        #expect(OpacityPolicy.stepped(from: 0.42, direction: .moreTransparent, amount: 0.01) == 0.41)
        #expect(OpacityPolicy.stepped(from: 0.06, direction: .moreTransparent, amount: 0.01) == 0.05)
        #expect(OpacityPolicy.stepped(from: 0.05, direction: .moreTransparent, amount: 0.01) == 0.05)
        #expect(OpacityPolicy.stepped(from: 0.99, direction: .lessTransparent, amount: 0.01) == 1.0)
    }

    @Test("长按加速步进仍受安全边界限制")
    func acceleratedHoldStepsRespectBounds() {
        #expect(OpacityPolicy.stepped(from: 0.50, direction: .moreTransparent, amount: 0.02) == 0.48)
        #expect(OpacityPolicy.stepped(from: 0.06, direction: .moreTransparent, amount: 0.02) == 0.05)
        #expect(OpacityPolicy.stepped(from: 0.99, direction: .lessTransparent, amount: 0.02) == 1.0)
        #expect(OpacityPolicy.stepped(from: 0.50, direction: .lessTransparent, amount: 0.10) == 0.60)
    }
}
