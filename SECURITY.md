# 安全策略

MacGlass 需要关闭 SIP 的部分保护，才能让 yabai 的 Dock scripting addition
注入 WindowServer。这属于降低系统安全性的操作，请只在明确了解风险后使用。

## 报告漏洞

请不要在公开 Issue 中披露可被利用的细节。请通过 GitHub Security Advisory
的私有报告入口提交，或直接联系维护者。收到报告后我们会尽快确认影响范围，
并在修复发布后公开致谢（如果你愿意）。

## 安全边界

- 应用不保存管理员密码，授权只通过 macOS 原生管理员对话框完成。
- 所有外部命令都使用 `Process.executableURL + arguments` 调用，不拼接 shell。
- 应用不会自动修改 SIP、NVRAM 或其他系统安全配置；SIP 步骤必须由用户手动完成。
- 应用退出时会恢复自己修改过的窗口透明度，并停止由它启动的 yabai daemon。
- 如果检测到系统已有 yabai daemon，应用只复用，不会强制结束或改写其配置。

## 分发说明

本项目默认发布源码和未签名构建。未签名构建可能被 Gatekeeper 拦截，需要在
“系统设置 → 隐私与安全性”中手动允许。正式签名和公证只改变分发体验，
不改变上述权限边界。
