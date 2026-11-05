# MacGlass

[English](README.en.md) | 简体中文

把任意可见的 macOS 标准窗口调成半透明的菜单栏应用。

它不使用截屏覆盖、滤镜或“假透明”。应用通过
[yabai](https://github.com/koekeishiya/yabai) 的 Dock scripting addition 调用
WindowServer 私有接口，直接修改目标窗口自身的 alpha。窗口切换 Space、拖动、
缩放后，透明度仍然生效。

## 前提条件

- macOS 13 或更高版本
- 当前 Release 为 Intel（x86_64）构建；Apple Silicon 请从源码构建
- 允许 yabai 注入 Dock：SIP 的**文件系统保护**与**调试限制**必须关闭
- MacGlass 获得辅助功能权限

内置的 yabai 为 `7.1.25` universal 二进制，已按 MIT License 附带；如果你已经
通过 Homebrew 安装 yabai，MacGlass 会优先使用系统版本。

## 1. 关闭 yabai 所需的 SIP 限制

先完整关机，再按以下步骤操作。Mac 需要先解锁 FileVault（如果有）。

1. Intel Mac 按住 `Command + R` 开机；Apple Silicon Mac 长按电源键进入启动选项，
   再进入“选项”。
2. 顶部菜单选择“实用工具 → 终端”。
3. 执行：

```bash
csrutil enable --without fs --without debug
```

4. 正常重启，在普通终端验证：

```bash
csrutil status
```

应看到：

```text
Filesystem Protections: disabled
Debugging Restrictions: disabled
```

不要执行 `csrutil disable`，也不需要关闭 Apple Internal、NVRAM 等其他保护。
修改 SIP 会降低系统安全性，是否接受由你自行决定。

“系统设置 → 隐私与安全性 → 开发者工具”中的开关**不能替代**这一步。它只允许
未满足系统策略的本地开发工具运行，不会改变 `task_for_pid` 所需的 SIP 配置位。

Apple Silicon 如果加载 SA 时提示缺少 `-arm64e_preview_abi`，按 yabai 的要求追加
启动参数后重启。先检查现有参数，避免覆盖：

```bash
nvram boot-args
# 仅当上面输出为空时执行：
sudo nvram boot-args="-arm64e_preview_abi"
```

## 2. 构建应用

```bash
git clone <你的仓库地址> MacGlass
cd MacGlass
chmod +x scripts/*.sh
./scripts/build-app.sh
```

产物：

```text
dist/MacGlass.app
```

启动：

```bash
open "dist/MacGlass.app"
```

## 3. 安装未签名 Release

从 GitHub Releases 下载 `MacGlass-<版本>-unsigned.zip` 后：

```bash
ditto -x -k MacGlass-<版本>-unsigned.zip /tmp/macglass
ditto /tmp/macglass/MacGlass.app /Applications/MacGlass.app
open /Applications/MacGlass.app
```

未签名构建会被 Gatekeeper 拦截。确认来源可信后，在
“系统设置 → 隐私与安全性”中选择“仍要打开”；或在终端执行：

```bash
xattr -d com.apple.quarantine /Applications/MacGlass.app
```

## 4. 从源码安装

一键安装到“应用程序”目录：

```bash
chmod +x scripts/install-app.sh
./scripts/install-app.sh
open "/Applications/MacGlass.app"
```

也可以生成可拖拽安装的 DMG：

```bash
hdiutil create -volname "MacGlass" \
  -srcfolder dist \
  -ov -format UDZO \
  "dist/MacGlass-1.0.0.dmg"
```

## 5. 首次启用

应用首次打开时会自动显示主窗口；之后点击菜单栏图标只会显示或隐藏这同一个窗口。

1. 如果“辅助功能”显示“需要允许”，点击右侧“打开设置”，进入：

```text
系统设置 → 隐私与安全性 → 辅助功能
```

允许 `MacGlass`。回到 MacGlass 后状态会自动更新，无需重启应用。
2. 点击“启用透明引擎”。此时系统会请求管理员密码，用于执行
   `yabai --load-sa`。密码只交给 macOS 管理员授权对话框，应用不会保存。

成功后状态列表全部显示绿色：

```text
yabai / 文件系统保护 / 调试限制 / 辅助功能 / 透明度注入 / yabai 后台
```

## 使用

1. 点击菜单栏图标。
2. 在窗口列表选择目标窗口。
3. 拖动 5%–100% 滑杆。
4. 点击“恢复原透明度”，或在右上角菜单中选择“恢复全部窗口”。
5. 退出 MacGlass 时，所有被修改窗口会自动恢复原始透明度。

也可以不打开窗口列表，直接对当前最前面的窗口使用全局快捷键：

```text
Control + Option + ←    降低透明度百分比（更透明）
Control + Option + →    提高透明度百分比（更不透明）
```

按一下调整 5%；按住超过 120ms 后持续加速调整，松开立即停止。范围限制在
5%–100%。快捷键需要辅助功能权限；窗口列表始终显示每个窗口当前的透明度。

应用会在 `~/Library/Application Support/MacGlass/opacity-journal.json`
记录原始透明度。进程异常退出后，下次启动会尝试恢复，避免窗口长期停留在
半透明状态。

## 工程结构

```text
MacGlass/
├── Package.swift
├── Resources/Info.plist
├── Resources/AppIcon.icns
├── Sources/
│   ├── MacGlass/
│   │   ├── AppDelegate.swift       # 菜单栏、右击菜单、退出恢复
│   │   ├── AppModel.swift          # 窗口选择、滑杆、状态与恢复逻辑
│   │   ├── ContentView.swift       # SwiftUI 控制面板
│   │   ├── GlobalHotKey.swift       # Carbon 全局热键
│   │   ├── KeyHoldMonitor.swift     # 物理按键长按监听
│   │   ├── OpacityJournal.swift    # 崩溃恢复日志
│   │   ├── ProcessRunner.swift     # 无 shell 的参数化进程调用
│   │   ├── YabaiClient.swift       # yabai 查询与透明度命令
│   │   ├── YabaiEngine.swift       # SIP/AX/SA/daemon 生命周期
│   │   └── YabaiLocator.swift
│   └── MacGlassCore/
│       ├── OpacityPolicy.swift     # 透明度边界与命令参数
│       ├── SIPStatus.swift         # csrutil status 解析
│       └── YabaiWindow.swift       # 查询模型与窗口过滤
├── Tests/MacGlassCoreTests/
├── Vendor/yabai
└── scripts/build-app.sh
```

## 诊断

```bash
"dist/MacGlass.app/Contents/MacOS/MacGlass" --diagnose
```

退出码说明：

- `0`：yabai、daemon、SA 均已就绪
- `2`：环境尚未就绪，标准输出会列出每一项状态

手动加载 scripting addition：

```bash
sudo env SUDO_UID="$(id -u)" SUDO_USER="$(id -un)" \
  "./Vendor/yabai" --load-sa
```

手动启动引擎（仅调试）：

```bash
"./Vendor/yabai" \
  --config "$HOME/Library/Application Support/MacGlass/yabairc"
```

## 常见问题

**列表里没有某个窗口**

MacGlass 只列出 yabai 已取得 AX 引用的 `AXStandardWindow`。先把窗口切到
当前可见 Space；原生全屏、系统面板、弹窗和部分跨 Space 窗口不会列出。

**提示 “failed to connect to socket”**

yabai 后台未运行。点击“重新检测”，或查看：

```bash
tail -n 100 "$HOME/Library/Application Support/MacGlass/yabai.log"
```

**提示 scripting addition 不可用**

确认 `csrutil status` 中两项均为 `disabled`，然后重新点击“启用透明引擎”。
`yabai --load-sa` 需要管理员权限；如果 osascript 被自动化权限阻断，直接执行
上文“手动加载 scripting addition”命令。

**Dock 重启后失效**

macOS 重启 Dock 会清除注入载荷。重新点击“启用透明引擎”，或在终端再次
执行 `sudo ... yabai --load-sa`。

**辅助功能已经允许，应用仍显示“需要允许”**

默认构建使用 ad-hoc 签名，重新编译会改变二进制 CDHash，macOS 会因此撤销旧授权。
在“辅助功能”中关闭再重新打开 `MacGlass`，应用会自动刷新为“已允许”。

如果经常重新编译，使用稳定的 Apple Development 或 Developer ID 证书签名：

```bash
MACGLASS_CODESIGN_IDENTITY="Apple Development: 你的名字 (TEAMID)" \
  ./scripts/build-app.sh
```

稳定证书签名后，后续重建不会改变 TCC 使用的代码要求。

**无法退出应用**

这表示还有窗口恢复失败。应用会刻意阻止退出，以免留下透明窗口。先解决 yabai
错误再退出；最后手段是“活动监视器 → 强制退出”。重新登录可以恢复窗口 alpha。

## 卸载

1. 在 MacGlass 中点击“恢复全部窗口”，再正常退出。
2. 删除应用。
3. 如果系统没有其他 yabai 配置，移除 SA：

```bash
sudo "/Applications/MacGlass.app/Contents/Resources/yabai" --uninstall-sa
```

4. 删除日志和配置：

```bash
find "$HOME/Library/Application Support/MacGlass" -depth -delete
```

5. 如需恢复 SIP：重启进入恢复模式并执行 `csrutil enable`。

## 安全边界

- MacGlass 不保存管理员密码。
- 所有命令都通过 `Process.executableURL + arguments` 调用，不拼接 shell。
- 透明度下限为 5%，避免误操作产生不可见窗口。
- 退出时会先恢复窗口，再停止由本应用启动的 yabai daemon。
- 若检测到系统已有 yabai daemon，应用只复用，不会强制结束或改写其配置。

## License

MacGlass 本身使用 MIT License，见根目录 `LICENSE`。

内置 yabai 使用 MIT License，版权归 Åsmund Vikane，完整文本见
`Vendor/yabai-LICENSE.txt`。
