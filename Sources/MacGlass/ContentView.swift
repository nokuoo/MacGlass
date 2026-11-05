import AppKit
import SwiftUI
import MacGlassCore

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            if model.isChecking && model.report == nil {
                loadingView
            } else if !model.engineReady {
                setupView
            } else {
                mainPanel
            }
        }
        .frame(width: 380, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert(
            item: Binding(
                get: { model.alert },
                set: { model.alert = $0 }
            )
        ) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("知道了"))
            )
        }
    }

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.large)
            Text("正在检查环境…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var setupView: some View {
        VStack(spacing: 0) {
            setupHeader
            Divider()

            Form {
                Section {
                    SetupStatusRow(
                        title: "yabai",
                        detail: model.report?.version ?? "未找到",
                        ok: model.report?.executableURL != nil
                    )
                    SetupStatusRow(
                        title: "文件系统保护",
                        detail: model.report?.sipStatus?.filesystemProtectionsDisabled == true
                            ? "已关闭"
                            : "需要关闭",
                        ok: model.report?.sipStatus?.filesystemProtectionsDisabled == true
                    )
                    SetupStatusRow(
                        title: "调试限制",
                        detail: model.report?.sipStatus?.debuggingRestrictionsDisabled == true
                            ? "已关闭"
                            : "需要关闭",
                        ok: model.report?.sipStatus?.debuggingRestrictionsDisabled == true
                    )
                    SetupStatusRow(
                        title: "辅助功能",
                        detail: model.accessibilityTrusted ? "已允许" : "需要允许",
                        ok: model.accessibilityTrusted
                    )
                    SetupStatusRow(
                        title: "透明引擎",
                        detail: model.report?.scriptingAdditionLoaded == true
                            ? "已加载"
                            : "未加载",
                        ok: model.report?.scriptingAdditionLoaded == true
                    )
                    SetupStatusRow(
                        title: "后台服务",
                        detail: model.report?.daemonRunning == true ? "运行中" : "未运行",
                        ok: model.report?.daemonRunning == true
                    )
                } header: {
                    Text("状态")
                }

                if let sip = model.report?.sipStatus, !sip.allowsScriptingAddition {
                    Section {
                        CopyableCommand(
                            command: SIPStatus.recoveryCommand,
                            copyAction: model.copyRecoveryCommand
                        )
                        Text("在恢复模式终端执行，完成后重启 Mac。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("SIP")
                    }
                }

                if !model.accessibilityTrusted {
                    Section {
                        HStack {
                            Text("允许 MacGlass 使用辅助功能")
                                .font(.callout)
                            Spacer()
                            Button("打开设置") {
                                model.openAccessibilitySettings()
                            }
                            .controlSize(.small)
                        }
                    } header: {
                        Text("辅助功能")
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            setupFooter
        }
    }

    private var setupHeader: some View {
        HStack(spacing: 11) {
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.10))
                )
            VStack(alignment: .leading, spacing: 1) {
                Text("MacGlass")
                    .font(.headline)
                Text("真实窗口透明")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isChecking || model.isEnabling {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
    }

    private var setupFooter: some View {
        HStack(spacing: 10) {
            Menu {
                Button("重新检测") {
                    Task {
                        await model.checkEnvironment()
                    }
                }
                .disabled(model.isEnabling)

                Button("复制加载命令") {
                    model.copyManualLoadCommand()
                }
                .disabled(model.report?.executableURL == nil)

                Divider()

                Button("在 Finder 中显示") {
                    model.revealApplicationInFinder()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("更多操作")

            if let message = model.inlineMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                model.enableEngine()
            } label: {
                HStack(spacing: 6) {
                    if model.isEnabling {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(model.isEnabling ? "正在启用…" : "启用透明引擎")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(model.isEnabling || model.report?.executableURL == nil)
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
    }

    private var mainPanel: some View {
        VStack(spacing: 0) {
            mainHeader
            Divider()
            searchBar
            Divider()
            windowList
            Divider()
            HotKeyHint(error: model.hotKeyError)
            Divider()
            opacityControls
        }
    }

    private var mainHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.on.rectangle")
                .foregroundStyle(.tint)
            Text("MacGlass")
                .font(.headline)
            if model.trackedCount > 0 {
                Text("\(model.trackedCount)")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(Color.accentColor.opacity(0.12))
                    )
                    .foregroundStyle(.tint)
            }
            Spacer()
            if model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                model.refreshNow()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("刷新窗口列表")

            Menu {
                Button("恢复全部窗口") {
                    model.restoreAllWindows()
                }
                .disabled(model.trackedCount == 0)

                Divider()

                Button("退出 MacGlass") {
                    NSApp.terminate(nil)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
    }

    private var searchBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索应用或窗口", text: $model.searchText)
                .textFieldStyle(.plain)
            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .frame(height: 42)
    }

    private var windowList: some View {
        ScrollView {
            LazyVStack(spacing: 3) {
                if model.filteredWindows.isEmpty {
                    VStack(spacing: 9) {
                        Image(systemName: "macwindow.badge.plus")
                            .font(.system(size: 22))
                            .foregroundStyle(.tertiary)
                        Text(model.windows.isEmpty ? "没有可调整的窗口" : "没有匹配的窗口")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 54)
                } else {
                    ForEach(model.filteredWindows) { window in
                        WindowRow(
                            window: window,
                            isSelected: window.id == model.selectedWindowID,
                            isTracked: model.trackedEntries[window.id] != nil
                        ) {
                            model.selectWindow(window)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
        }
        .frame(minHeight: 190, maxHeight: .infinity)
    }

    private var opacityControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let window = model.selectedWindow {
                HStack(alignment: .center, spacing: 9) {
                    AppIcon(pid: window.pid)
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(window.app)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                        Text(window.trimmedTitle.isEmpty ? "未命名窗口" : window.trimmedTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("恢复原透明度") {
                        model.restoreSelectedWindow()
                    }
                    .controlSize(.small)
                    .disabled(!model.selectedWindowIsTracked)
                }

                HStack(spacing: 10) {
                    Slider(
                        value: Binding(
                            get: { model.opacity },
                            set: { model.previewOpacity($0) }
                        ),
                        in: OpacityPolicy.minimum...OpacityPolicy.maximum,
                        step: 0.01
                    )
                    Text("\(Int((model.opacity * 100).rounded()))%")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .trailing)
                }

                HStack {
                    Text("透明度")
                    Spacer()
                    Text("5%")
                    Text("100%")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            } else {
                HStack(spacing: 9) {
                    Image(systemName: "cursorarrow.click.2")
                        .foregroundStyle(.tertiary)
                    Text("选择一个窗口以调整透明度")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 20)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 136)
    }
}

private struct SetupStatusRow: View {
    let title: String
    let detail: String
    let ok: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? Color.green : Color.orange)
                .imageScale(.small)
            Text(title)
                .font(.callout)
            Spacer()
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct CopyableCommand: View {
    let command: String
    let copyAction: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(command)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            Spacer(minLength: 0)
            Button(action: copyAction) {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.plain)
            .help("复制命令")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.7))
        )
    }
}

private struct WindowRow: View {
    let window: YabaiWindow
    let isSelected: Bool
    let isTracked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                AppIcon(pid: window.pid)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(window.app)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(window.trimmedTitle.isEmpty ? "未命名窗口" : window.trimmedTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if isTracked {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
                Text(window.opacity.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(window.opacity < 0.995 ? .secondary : .tertiary)
                    .frame(width: 34, alignment: .trailing)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 46)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct HotKeyHint: View {
    let error: String?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "keyboard")
                .foregroundStyle(.secondary)
            Text("⌃⌥← 更透明  ⌃⌥→ 更不透明")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if let error {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .help(error)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
    }
}

private struct AppIcon: View {
    let pid: Int32

    var body: some View {
        if let icon = NSRunningApplication(processIdentifier: pid)?.icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            Image(systemName: "macwindow")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
        }
    }
}
