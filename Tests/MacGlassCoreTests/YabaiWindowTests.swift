import Foundation
import Testing
@testable import MacGlassCore

@Suite("yabai 窗口模型")
struct YabaiWindowTests {
    @Test("解析 yabai 的连字符字段")
    func decodesHyphenatedKeys() throws {
        let data = Data(Self.fixture.utf8)
        let windows = try JSONDecoder().decode([YabaiWindow].self, from: data)

        #expect(windows.count == 3)
        #expect(windows[0].id == 311)
        #expect(windows[0].app == "ChatGPT")
        #expect(windows[0].frame.width == 1920)
        #expect(windows[0].hasAXReference)
        #expect(windows[0].hasFocus)
        #expect(abs(windows[1].opacity - 0.72) < 0.0001)
    }

    @Test("过滤不可操作窗口")
    func filtersIneligibleWindows() {
        let windows = try! JSONDecoder().decode(
            [YabaiWindow].self,
            from: Data(Self.fixture.utf8)
        )

        let visible = WindowCatalog.visibleWindows(
            from: windows,
            excludingPID: 999
        )

        #expect(visible.map(\.id) == [311, 637])
        #expect(visible[0].hasFocus)
    }

    @Test("排除当前应用窗口")
    func excludesCurrentApplication() {
        let windows = try! JSONDecoder().decode(
            [YabaiWindow].self,
            from: Data(Self.fixture.utf8)
        )

        let visible = WindowCatalog.visibleWindows(
            from: windows,
            excludingPID: 2321
        )

        #expect(visible.map(\.id) == [637])
    }

    @Test("搜索应用与标题")
    func searchMatchesApplicationAndTitle() throws {
        let windows = try JSONDecoder().decode(
            [YabaiWindow].self,
            from: Data(Self.fixture.utf8)
        )

        #expect(WindowCatalog.matches(windows[0], query: "chatgpt"))
        #expect(WindowCatalog.matches(windows[0], query: "透明"))
        #expect(!WindowCatalog.matches(windows[0], query: "不存在"))
        #expect(WindowCatalog.matches(windows[0], query: "   "))
    }

    @Test("快捷键目标为当前焦点窗口")
    func frontmostWindowPrefersFocus() throws {
        let windows = try JSONDecoder().decode(
            [YabaiWindow].self,
            from: Data(Self.fixture.utf8)
        )

        #expect(WindowCatalog.frontmostWindow(from: windows, excludingPID: 999)?.id == 311)

        let withoutFocus = windows.map { $0.replacingFocus(false) }
        #expect(WindowCatalog.frontmostWindow(from: withoutFocus, excludingPID: 999)?.id == 311)
        #expect(WindowCatalog.frontmostWindow(from: windows, excludingPID: 2321)?.id == 637)
    }

    private static let fixture = """
    [
      {
        "id": 311,
        "pid": 2321,
        "app": "ChatGPT",
        "title": "开发窗口透明工具",
        "frame": { "x": 1920, "y": 25, "w": 1920, "h": 1055 },
        "role": "AXWindow",
        "subrole": "AXStandardWindow",
        "layer": "normal",
        "opacity": 1.0,
        "has-ax-reference": true,
        "is-visible": true,
        "is-minimized": false,
        "is-hidden": false,
        "has-focus": true,
        "is-native-fullscreen": false
      },
      {
        "id": 637,
        "pid": 5880,
        "app": "微信",
        "title": "微信",
        "frame": { "x": 520, "y": 220, "w": 880, "h": 640 },
        "role": "AXWindow",
        "subrole": "AXStandardWindow",
        "layer": "normal",
        "opacity": 0.72,
        "has-ax-reference": true,
        "is-visible": true,
        "is-minimized": false,
        "is-hidden": false,
        "has-focus": false,
        "is-native-fullscreen": false
      },
      {
        "id": 900,
        "pid": 999,
        "app": "DialogHelper",
        "title": "系统对话框",
        "frame": { "x": 0, "y": 0, "w": 300, "h": 180 },
        "role": "AXWindow",
        "subrole": "AXDialog",
        "layer": "normal",
        "opacity": 1.0,
        "has-ax-reference": true,
        "is-visible": true,
        "is-minimized": false,
        "is-hidden": false,
        "has-focus": false,
        "is-native-fullscreen": false
      }
    ]
    """
}
