# 参与贡献

## 开发环境

- macOS 13 或更高版本
- Xcode Command Line Tools（提供 `swift`、`codesign`、`iconutil`）

## 本地验证

提交前至少运行：

```bash
swift test
swift build -c release --product MacGlass
./scripts/build-app.sh
```

`build-app.sh` 会运行测试、生成 App 并做签名校验。发布前请再确认：

```bash
codesign --verify --deep --strict dist/MacGlass.app
```

## 代码约定

- 使用 Swift 6 并发模型，UI 与状态更新保持在 MainActor。
- 外部命令必须使用参数化进程调用，不拼接 shell 字符串。
- 修改透明度范围、快捷键或窗口筛选逻辑时，必须同步更新
  `Tests/MacGlassCoreTests/` 中的测试。
- Bundle ID 与签名标识统一使用 `com.macglass.app`，不要单独修改其中一个。

## 提交与 PR

- 一个 PR 只解决一个主题，避免混入无关格式化。
- PR 描述中写清复现步骤、修改点和验证方式。
- 涉及 SIP、辅助功能、管理员授权或进程调用的改动，请额外说明安全影响。
