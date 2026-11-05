import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI
import MacGlassCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = AppModel()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var mainWindow: NSWindow?
    private var engineStateCancellable: AnyCancellable?
    private var terminationRequested = false
    private var hasPresentedInitialWindow = false
    private var hotKeys: [GlobalHotKey] = []
    private var holdTasks: [OpacityStepDirection: Task<Void, Never>] = [:]
    private var keyHoldMonitor: KeyHoldMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        observeEngineState()
        registerHotKeys()
        startKeyHoldMonitor()
        model.start()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model.refreshAccessibilityPermission()
    }

    private func startKeyHoldMonitor() {
        let monitor = KeyHoldMonitor(
            onPress: { [weak self] keyCode in
                self?.beginOpacityHold(keyCode == 123 ? .moreTransparent : .lessTransparent)
            },
            onRelease: { [weak self] keyCode in
                self?.endOpacityHold(keyCode == 123 ? .moreTransparent : .lessTransparent)
            }
        )
        if !monitor.start() {
            model.reportHotKeyError("按住连调需要辅助功能权限。")
        }
        keyHoldMonitor = monitor
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showMainWindow()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationRequested else { return .terminateNow }
        terminationRequested = true
        cancelAllHolds()

        Task { @MainActor in
            let canTerminate = await model.shutdown()
            sender.reply(toApplicationShouldTerminate: canTerminate)
            if !canTerminate {
                terminationRequested = false
                showMainWindow()
            }
        }
        return .terminateLater
    }

    func windowWillClose(_ notification: Notification) {
        model.windowDidClose()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        let image = NSImage(
            systemSymbolName: "rectangle.on.rectangle",
            accessibilityDescription: "MacGlass 窗口透明"
        )
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageOnly
        button.toolTip = "MacGlass · 真实窗口透明"
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func observeEngineState() {
        engineStateCancellable = model.$isChecking
            .receive(on: RunLoop.main)
            .sink { [weak self] isChecking in
                guard let self, !isChecking else { return }
                guard !self.hasPresentedInitialWindow else { return }
                self.hasPresentedInitialWindow = true
                self.showMainWindow()
            }
    }

    private func registerHotKeys() {
        // Control+Option+Left 降低透明度百分比（更透明），Right 提高（更不透明）。
        // 避开系统默认的 Control+Option+Up/Down（调度中心）。
        let moreTransparent = GlobalHotKey(
            keyCode: UInt32(kVK_LeftArrow),
            modifiers: UInt32(controlKey | optionKey),
            onPress: { [weak self] in
                self?.fallbackPress(.moreTransparent)
            },
            onRelease: { [weak self] in
                self?.fallbackRelease(.moreTransparent)
            }
        )
        let lessTransparent = GlobalHotKey(
            keyCode: UInt32(kVK_RightArrow),
            modifiers: UInt32(controlKey | optionKey),
            onPress: { [weak self] in
                self?.fallbackPress(.lessTransparent)
            },
            onRelease: { [weak self] in
                self?.fallbackRelease(.lessTransparent)
            }
        )
        hotKeys = [moreTransparent, lessTransparent].compactMap { $0 }
        if hotKeys.count != 2 {
            model.reportHotKeyError("快捷键注册失败，可能与其他应用冲突。")
        }
    }

    /// 物理按键监听已生效时，Carbon 回调不重复触发。
    private func fallbackPress(_ direction: OpacityStepDirection) {
        guard keyHoldMonitor?.isActive != true else { return }
        beginOpacityHold(direction)
    }

    private func fallbackRelease(_ direction: OpacityStepDirection) {
        guard keyHoldMonitor?.isActive != true else { return }
        endOpacityHold(direction)
    }

    /// 首次按下立即调整 5%，持续按住 120ms 后每 40ms 触发 2%，由模型合并执行。
    private func beginOpacityHold(_ direction: OpacityStepDirection) {
        guard holdTasks[direction] == nil else { return }
        model.stepFrontmostOpacity(direction)

        let task = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 120_000_000)
            } catch {
                return
            }

            while !Task.isCancelled {
                guard let self else { return }
                self.model.stepFrontmostOpacity(direction, amount: 0.02)
                do {
                    try await Task.sleep(nanoseconds: 40_000_000)
                } catch {
                    return
                }
            }
        }
        holdTasks[direction] = task
    }

    private func endOpacityHold(_ direction: OpacityStepDirection) {
        holdTasks.removeValue(forKey: direction)?.cancel()
        model.cancelPendingFrontmostSteps()
        model.releaseFrontmostWindowLock()
    }

    private func cancelAllHolds() {
        for task in holdTasks.values {
            task.cancel()
        }
        holdTasks.removeAll()
        model.cancelPendingFrontmostSteps()
        model.releaseFrontmostWindowLock()
    }

    private func showMainWindow() {
        if let mainWindow {
            if mainWindow.isMiniaturized {
                mainWindow.deminiaturize(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
            mainWindow.makeKeyAndOrderFront(nil)
            model.windowDidOpen()
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MacGlass"
        window.titlebarAppearsTransparent = false
        window.tabbingMode = .disallowed
        window.contentViewController = NSHostingController(rootView: ContentView(model: model))
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("MacGlassMainWindow")
        window.center()
        mainWindow = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        model.windowDidOpen()
    }

    @objc
    private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
            return
        }

        if let mainWindow, mainWindow.isVisible {
            mainWindow.orderOut(nil)
        } else {
            showMainWindow()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let showItem = NSMenuItem(
            title: "显示 MacGlass",
            action: #selector(showWindowFromMenu),
            keyEquivalent: ""
        )
        showItem.target = self
        menu.addItem(showItem)

        let refreshItem = NSMenuItem(
            title: "重新检测环境",
            action: #selector(refreshEnvironmentFromMenu),
            keyEquivalent: ""
        )
        refreshItem.target = self
        menu.addItem(refreshItem)

        let restoreItem = NSMenuItem(
            title: model.trackedCount > 0
                ? "恢复全部窗口（\(model.trackedCount)）"
                : "恢复全部窗口",
            action: #selector(restoreAllFromMenu),
            keyEquivalent: ""
        )
        restoreItem.target = self
        restoreItem.isEnabled = model.trackedCount > 0
        menu.addItem(restoreItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出 MacGlass",
            action: #selector(quitFromMenu),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc
    private func showWindowFromMenu() {
        showMainWindow()
    }

    @objc
    private func refreshEnvironmentFromMenu() {
        Task {
            await model.checkEnvironment()
        }
    }

    @objc
    private func restoreAllFromMenu() {
        model.restoreAllWindows()
    }

    @objc
    private func quitFromMenu() {
        NSApp.terminate(nil)
    }
}
