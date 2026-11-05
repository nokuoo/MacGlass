import AppKit
import Combine
import Foundation
import MacGlassCore

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var windows: [YabaiWindow] = []
    @Published var searchText = ""
    @Published private(set) var selectedWindowID: UInt32?
    @Published private(set) var opacity = 1.0
    @Published private(set) var trackedEntries: [UInt32: OpacityJournalEntry] = [:]
    @Published private(set) var report: EngineReport?
    @Published private(set) var engineReady = false
    @Published private(set) var isChecking = true
    @Published private(set) var isEnabling = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var inlineMessage: String?
    @Published var alert: AppAlert?
    @Published private(set) var hotKeyError: String?

    private let engine = YabaiEngine()
    private let journal = OpacityJournal()
    private var allWindowIDs = Set<UInt32>()
    private var refreshTask: Task<Void, Never>?
    private var opacityTask: Task<Void, Never>?
    private var opacityRevision = 0
    private var hasStarted = false
    private var hasRecoveredJournal = false
    private var isShuttingDown = false
    private var lockedWindowID: UInt32?
    private var pendingFrontmostDelta: (direction: OpacityStepDirection, amount: Double)?
    private var isApplyingFrontmostStep = false

    var filteredWindows: [YabaiWindow] {
        windows.filter { WindowCatalog.matches($0, query: searchText) }
    }

    var selectedWindow: YabaiWindow? {
        guard let selectedWindowID else { return nil }
        return windows.first { $0.id == selectedWindowID }
    }

    var trackedCount: Int {
        trackedEntries.count
    }

    var selectedWindowIsTracked: Bool {
        guard let selectedWindowID else { return false }
        return trackedEntries[selectedWindowID] != nil
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        Task {
            await checkEnvironment(recoverJournal: true)
        }
    }

    func checkEnvironment(recoverJournal: Bool = false) async {
        guard !isEnabling else { return }
        isChecking = true
        defer { isChecking = false }

        var latestReport = await engine.inspect()
        // SA 已就绪时自动拉起 daemon，避免热键因为后台服务未运行而失效。
        if !latestReport.daemonRunning && latestReport.scriptingAdditionLoaded {
            if (try? await engine.ensureDaemonRunning()) != nil {
                latestReport = await engine.inspect()
            }
        }
        report = latestReport
        engineReady = latestReport.isReady

        if engineReady {
            await reloadWindows(showAlert: false)
            if recoverJournal {
                await recoverJournalIfNeeded()
            }
        } else {
            windows = []
            selectedWindowID = nil
        }
    }

    func enableEngine() {
        guard !isEnabling else { return }
        Task {
            isEnabling = true
            inlineMessage = nil
            defer { isEnabling = false }

            do {
                let latestReport = try await engine.activate()
                report = latestReport
                engineReady = true
                await reloadWindows(showAlert: false)
                await recoverJournalIfNeeded()
            } catch {
                report = await engine.inspect()
                engineReady = false
                present(error)
            }
        }
    }

    func refreshNow() {
        guard engineReady else { return }
        Task {
            await reloadWindows(showAlert: true)
        }
    }

    func selectWindow(_ window: YabaiWindow) {
        opacityRevision += 1
        opacityTask?.cancel()
        selectedWindowID = window.id
        opacity = OpacityPolicy.displayValue(forActualOpacity: window.opacity)
        inlineMessage = nil
    }

    func previewOpacity(_ rawValue: Double) {
        guard engineReady, let windowID = selectedWindowID else { return }

        let value = OpacityPolicy.commandValue(for: rawValue)
        opacity = value
        opacityRevision += 1
        let revision = opacityRevision
        opacityTask?.cancel()

        opacityTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 70_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            await self.commitOpacity(
                windowID: windowID,
                value: value,
                revision: revision
            )
        }
    }

    /// 全局快捷键作用于当前焦点窗口，不受窗口列表是否打开或当前选择影响。
    func stepFrontmostOpacity(
        _ direction: OpacityStepDirection,
        amount: Double = 0.05
    ) {
        guard engineReady else {
            hotKeyError = "透明引擎未就绪，请先启用。"
            return
        }
        // 长按期间把多次小步合并成一次命令，避免 yabai 往返延迟拖慢整体速度。
        if let pending = pendingFrontmostDelta, pending.direction == direction {
            pendingFrontmostDelta = (direction, pending.amount + amount)
        } else {
            pendingFrontmostDelta = (direction, amount)
        }
        guard !isApplyingFrontmostStep else { return }
        isApplyingFrontmostStep = true

        Task {
            defer { isApplyingFrontmostStep = false }
            while let request = pendingFrontmostDelta {
                pendingFrontmostDelta = nil
                await applyFrontmostStep(
                    direction: request.direction,
                    amount: request.amount
                )
            }
        }
    }

    private func applyFrontmostStep(
        direction: OpacityStepDirection,
        amount: Double
    ) async {
        do {
            let window: YabaiWindow
            if let lockedWindowID, let cached = windows.first(where: { $0.id == lockedWindowID }) {
                window = cached
            } else {
                let allWindows = try await Task.detached(priority: .userInitiated) { [engine] in
                    try await engine.allWindows()
                }.value
                guard let frontmost = WindowCatalog.frontmostWindow(
                    from: allWindows,
                    excludingPID: Int32(ProcessInfo.processInfo.processIdentifier)
                ) else {
                    hotKeyError = "当前没有可调整的标准窗口。"
                    return
                }
                window = frontmost
                lockedWindowID = frontmost.id
            }

            let existingEntry = trackedEntries[window.id]
            let originalOpacity = existingEntry?.originalOpacity ?? window.opacity
            let target = OpacityPolicy.stepped(
                from: window.opacity,
                direction: direction,
                amount: amount
            )
            let returningToOriginal = OpacityPolicy.isEffectivelyEqual(target, originalOpacity)
            // 已到边界且没有可恢复的修改时不再重复发送命令。
            if OpacityPolicy.isEffectivelyEqual(target, window.opacity)
                && !(returningToOriginal && existingEntry != nil) {
                return
            }
            let commandValue = returningToOriginal
                ? OpacityPolicy.restoreValue(for: originalOpacity)
                : target

            // 先落盘再调用 yabai，快捷键修改也必须能在异常退出后恢复。
            if existingEntry == nil && !returningToOriginal {
                trackedEntries[window.id] = OpacityJournalEntry(
                    windowID: window.id,
                    pid: window.pid,
                    app: window.app,
                    title: window.title,
                    originalOpacity: originalOpacity,
                    updatedAt: Date()
                )
                journal.save(Array(trackedEntries.values))
            }

            do {
                try await Task.detached(priority: .userInitiated) { [engine] in
                    try await engine.setOpacity(windowID: window.id, value: commandValue)
                }.value
            } catch {
                if existingEntry == nil && !returningToOriginal {
                    trackedEntries.removeValue(forKey: window.id)
                    journal.save(Array(trackedEntries.values))
                }
                hotKeyError = error.localizedDescription
                await handleCommandFailure(error)
                return
            }

            if returningToOriginal {
                trackedEntries.removeValue(forKey: window.id)
                journal.save(Array(trackedEntries.values))
            }

            let visualOpacity = returningToOriginal
                ? (originalOpacity >= 0.999
                    ? 1.0
                    : OpacityPolicy.displayValue(forActualOpacity: originalOpacity))
                : target
            applyOpacity(
                windowID: window.id,
                value: visualOpacity,
                originalOpacity: originalOpacity,
                isTracked: !returningToOriginal
            )
            hotKeyError = nil
        } catch {
            hotKeyError = error.localizedDescription
            await handleCommandFailure(error)
        }
    }

    func restoreSelectedWindow() {
        guard let selectedWindowID else { return }
        Task {
            await restoreWindow(id: selectedWindowID, showAlert: true)
        }
    }

    func restoreAllWindows() {
        Task {
            _ = await restoreAll(showAlert: true)
        }
    }

    func copyManualLoadCommand() {
        guard let report else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report.manualLoadCommand, forType: .string)
        inlineMessage = "加载命令已复制。"
    }

    func reportHotKeyError(_ message: String) {
        hotKeyError = message
    }

    /// 松开快捷键后解除目标窗口锁定，下一次按键重新选择最前窗口。
    func releaseFrontmostWindowLock() {
        lockedWindowID = nil
    }

    /// 松开快捷键后丢弃尚未执行的步进，避免继续改变透明度。
    func cancelPendingFrontmostSteps() {
        pendingFrontmostDelta = nil
    }

    func copyRecoveryCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(SIPStatus.recoveryCommand, forType: .string)
        inlineMessage = "恢复模式命令已复制。"
    }

    func openAccessibilitySettings() {
        AccessibilityPermission.openSystemSettings()
    }

    func revealApplicationInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    func windowDidOpen() {
        refreshAccessibilityPermission()
        if engineReady {
            Task {
                await reloadWindows(showAlert: false)
            }
        }
        startRefreshLoop()
    }

    func windowDidClose() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// TCC 授权可能在应用运行期间发生变化，回到前台时立即同步系统状态。
    func refreshAccessibilityPermission() {
        let trusted = AccessibilityPermission.isTrusted
        guard var latestReport = report, latestReport.accessibilityTrusted != trusted else {
            return
        }
        latestReport.accessibilityTrusted = trusted
        report = latestReport
    }

    var accessibilityTrusted: Bool {
        AccessibilityPermission.isTrusted
    }

    /// 退出前必须完成恢复，失败时阻止退出，避免留下半透明窗口。
    func shutdown() async -> Bool {
        isShuttingDown = true
        opacityRevision += 1
        opacityTask?.cancel()
        refreshTask?.cancel()

        let restored = await restoreAll(showAlert: false)
        guard restored else {
            isShuttingDown = false
            alert = AppAlert(
                title: "无法恢复全部窗口",
                message: "仍有窗口透明设置未恢复。应用已取消退出，请恢复引擎后重试；也可使用活动监视器强制退出并重新登录恢复显示。"
            )
            return false
        }

        await engine.stopOwnedDaemon()
        return true
    }

    private func commitOpacity(
        windowID: UInt32,
        value: Double,
        revision: Int
    ) async {
        guard
            engineReady,
            !isShuttingDown,
            revision == opacityRevision,
            selectedWindowID == windowID,
            let window = windows.first(where: { $0.id == windowID })
        else {
            return
        }

        let existingEntry = trackedEntries[windowID]
        let originalOpacity = existingEntry?.originalOpacity ?? window.opacity
        let returningToOriginal = OpacityPolicy.isEffectivelyEqual(value, originalOpacity)

        // 从未修改过且目标就是当前值，不产生无意义的 yabai 进程调用。
        if existingEntry == nil && returningToOriginal {
            opacity = OpacityPolicy.displayValue(forActualOpacity: originalOpacity)
            return
        }

        let commandValue = returningToOriginal
            ? OpacityPolicy.restoreValue(for: originalOpacity)
            : value

        // 先落盘再修改窗口：即使命令执行后进程崩溃，也能在下次启动恢复。
        if existingEntry == nil && !returningToOriginal {
            trackedEntries[windowID] = OpacityJournalEntry(
                windowID: window.id,
                pid: window.pid,
                app: window.app,
                title: window.title,
                originalOpacity: originalOpacity,
                updatedAt: Date()
            )
            journal.save(Array(trackedEntries.values))
        }

        do {
            try await engine.setOpacity(windowID: windowID, value: commandValue)
            guard revision == opacityRevision else { return }

            if returningToOriginal {
                trackedEntries.removeValue(forKey: windowID)
                journal.save(Array(trackedEntries.values))
            }

            let visualOpacity = returningToOriginal
                ? (originalOpacity >= 0.999 ? 1.0 : OpacityPolicy.displayValue(forActualOpacity: originalOpacity))
                : value
            replaceWindowOpacity(id: windowID, with: visualOpacity)
            opacity = visualOpacity
            inlineMessage = nil
        } catch {
            guard revision == opacityRevision else { return }
            if existingEntry == nil && !returningToOriginal {
                trackedEntries.removeValue(forKey: windowID)
                journal.save(Array(trackedEntries.values))
            }
            opacity = OpacityPolicy.displayValue(forActualOpacity: window.opacity)
            await handleCommandFailure(error)
        }
    }

    private func reloadWindows(showAlert: Bool) async {
        guard engineReady else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let allWindows = try await engine.allWindows()
            allWindowIDs = Set(allWindows.map(\.id))
            windows = WindowCatalog.visibleWindows(
                from: allWindows,
                excludingPID: Int32(ProcessInfo.processInfo.processIdentifier)
            )

            if let selectedWindowID, !windows.contains(where: { $0.id == selectedWindowID }) {
                self.selectedWindowID = nil
                opacityRevision += 1
                opacityTask?.cancel()
                opacity = 1.0
            }

            let staleIDs = trackedEntries.keys.filter { !allWindowIDs.contains($0) }
            if !staleIDs.isEmpty {
                for id in staleIDs {
                    trackedEntries.removeValue(forKey: id)
                }
                journal.save(Array(trackedEntries.values))
            }
        } catch {
            await handleCommandFailure(error)
            if showAlert {
                present(error)
            }
        }
    }

    private func startRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 2_500_000_000)
                } catch {
                    return
                }
                guard let self, !Task.isCancelled else { return }
                self.refreshAccessibilityPermission()
                if self.engineReady {
                    await self.reloadWindows(showAlert: false)
                }
            }
        }
    }

    private func restoreWindow(id: UInt32, showAlert: Bool) async {
        guard let entry = trackedEntries[id] else { return }
        if selectedWindowID == id {
            opacityRevision += 1
            opacityTask?.cancel()
        }

        do {
            try await engine.setOpacity(
                windowID: id,
                value: OpacityPolicy.restoreValue(for: entry.originalOpacity)
            )
            trackedEntries.removeValue(forKey: id)
            journal.save(Array(trackedEntries.values))
            replaceWindowOpacity(
                id: id,
                with: entry.originalOpacity >= 0.999
                    ? 1.0
                    : OpacityPolicy.displayValue(forActualOpacity: entry.originalOpacity)
            )
            if selectedWindowID == id {
                opacity = entry.originalOpacity >= 0.999
                    ? 1.0
                    : OpacityPolicy.displayValue(forActualOpacity: entry.originalOpacity)
            }
        } catch {
            await handleCommandFailure(error)
            if showAlert {
                present(error)
            }
        }
    }

    @discardableResult
    private func restoreAll(showAlert: Bool) async -> Bool {
        opacityRevision += 1
        opacityTask?.cancel()

        let entries = Array(trackedEntries.values)
        guard !entries.isEmpty else {
            journal.save([])
            return true
        }

        var failures: [(OpacityJournalEntry, Error)] = []
        for entry in entries {
            do {
                try await engine.setOpacity(
                    windowID: entry.windowID,
                    value: OpacityPolicy.restoreValue(for: entry.originalOpacity)
                )
                trackedEntries.removeValue(forKey: entry.windowID)
                replaceWindowOpacity(
                    id: entry.windowID,
                    with: entry.originalOpacity >= 0.999
                        ? 1.0
                        : OpacityPolicy.displayValue(forActualOpacity: entry.originalOpacity)
                )
                if selectedWindowID == entry.windowID {
                    opacity = entry.originalOpacity >= 0.999
                        ? 1.0
                        : OpacityPolicy.displayValue(forActualOpacity: entry.originalOpacity)
                }
            } catch {
                failures.append((entry, error))
            }
        }

        journal.save(Array(trackedEntries.values))

        if !failures.isEmpty {
            if showAlert {
                let detail = failures
                    .prefix(3)
                    .map { "\($0.0.app)：\($0.1.localizedDescription)" }
                    .joined(separator: "\n")
                alert = AppAlert(
                    title: "部分窗口恢复失败",
                    message: "\(failures.count) 个窗口未能恢复。\n\(detail)"
                )
            }
            return false
        }
        return true
    }

    private func replaceWindowOpacity(id: UInt32, with value: Double) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        windows[index] = windows[index].replacingOpacity(with: value)
    }

    private func applyOpacity(
        windowID: UInt32,
        value: Double,
        originalOpacity: Double,
        isTracked: Bool
    ) {
        replaceWindowOpacity(id: windowID, with: value)
        if selectedWindowID == windowID {
            opacity = value
        }
        if isTracked {
            inlineMessage = "\(value.formatted(.percent.precision(.fractionLength(0))))"
        } else if OpacityPolicy.isEffectivelyEqual(value, originalOpacity) {
            inlineMessage = nil
        }
    }

    private func recoverJournalIfNeeded() async {
        guard !hasRecoveredJournal else { return }
        hasRecoveredJournal = true

        let entries = journal.load()
        guard !entries.isEmpty else { return }

        let allWindows: [YabaiWindow]
        do {
            allWindows = try await engine.allWindows()
        } catch {
            hasRecoveredJournal = false
            return
        }

        var remaining: [OpacityJournalEntry] = []
        var restoredCount = 0
        for entry in entries {
            guard let window = allWindows.first(where: {
                $0.id == entry.windowID && $0.pid == entry.pid && $0.app == entry.app
            }) else {
                // 窗口已关闭，原透明度不会跨进程保留，日志可以安全丢弃。
                continue
            }
            guard window.hasAXReference else {
                remaining.append(entry)
                continue
            }
            do {
                try await engine.setOpacity(
                    windowID: entry.windowID,
                    value: OpacityPolicy.restoreValue(for: entry.originalOpacity)
                )
                restoredCount += 1
            } catch {
                remaining.append(entry)
            }
        }
        journal.save(remaining)

        if restoredCount > 0 {
            inlineMessage = "已恢复上次异常退出前留下的 \(restoredCount) 个窗口透明度。"
            await reloadWindows(showAlert: false)
        }
    }

    private func handleCommandFailure(_ error: Error) async {
        if let clientError = error as? YabaiClientError {
            switch clientError {
            case .daemonUnavailable, .scriptingAdditionUnavailable, .accessibilityUnavailable:
                report = await engine.inspect()
                engineReady = report?.isReady == true
            case .windowUnavailable, .invalidResponse, .commandFailed:
                break
            }
        }
    }

    private func present(_ error: Error) {
        alert = AppAlert(
            title: "操作失败",
            message: error.localizedDescription
        )
    }
}
