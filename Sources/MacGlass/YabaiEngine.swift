import AppKit
import Darwin
import Foundation
import MacGlassCore

struct EngineReport: Equatable {
    let executableURL: URL?
    let version: String?
    let sipStatus: SIPStatus?
    var accessibilityTrusted: Bool
    let daemonRunning: Bool
    let scriptingAdditionLoaded: Bool

    var isReady: Bool {
        executableURL != nil && daemonRunning && scriptingAdditionLoaded
    }

    var manualLoadCommand: String {
        guard let executableURL else {
            return "未找到 yabai"
        }
        return [
            "sudo",
            "env",
            "SUDO_UID=\(getuid())",
            "SUDO_USER=\(shellSingleQuoted(NSUserName()))",
            shellSingleQuoted(executableURL.path),
            "--load-sa"
        ].joined(separator: " ")
    }

    var diagnosticText: String {
        var lines: [String] = []
        lines.append("MacGlass diagnostics")
        lines.append("yabai: \(executableURL?.path ?? "未找到")")
        lines.append("yabai version: \(version ?? "未知")")
        lines.append("daemon: \(daemonRunning ? "running" : "not running")")
        lines.append("scripting addition: \(scriptingAdditionLoaded ? "loaded" : "not loaded")")
        lines.append("accessibility: \(accessibilityTrusted ? "trusted" : "not trusted")")
        if let sipStatus {
            lines.append("SIP filesystem disabled: \(sipStatus.filesystemProtectionsDisabled)")
            lines.append("SIP debugging disabled: \(sipStatus.debuggingRestrictionsDisabled)")
            lines.append("SIP raw: \(sipStatus.raw.replacingOccurrences(of: "\n", with: " | "))")
        } else {
            lines.append("SIP: 无法读取")
        }
        lines.append("ready: \(isReady)")
        return lines.joined(separator: "\n")
    }

    private func shellSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

enum YabaiEngineError: LocalizedError {
    case executableMissing
    case sipRestrictions(SIPStatus)
    case accessibilityPermissionRequired
    case scriptingAdditionLoadFailed(String)
    case authorizationCancelled
    case daemonStartFailed(String)
    case engineNotReady

    var errorDescription: String? {
        switch self {
        case .executableMissing:
            return "未找到 yabai。请重新构建应用，或设置 MACGLASS_YABAI_PATH。"
        case .sipRestrictions:
            return "SIP 尚未开放真实窗口透明所需的权限。请在恢复模式执行指定命令并重启。"
        case .accessibilityPermissionRequired:
            return "需要辅助功能权限。请在系统设置中授权 MacGlass，然后重新启动应用。"
        case .scriptingAdditionLoadFailed(let detail):
            return "加载 yabai scripting addition 失败。\n\(detail)"
        case .authorizationCancelled:
            return "管理员授权已取消或失败。"
        case .daemonStartFailed(let detail):
            return "yabai 后台服务启动失败。\n\(detail)"
        case .engineNotReady:
            return "透明引擎尚未就绪，请重新检测环境。"
        }
    }
}

@MainActor
final class YabaiEngine {
    private var client: YabaiClient?
    private var clientPath: URL?
    private var daemonProcess: Process?
    private var daemonLogHandle: FileHandle?
    private var ownsDaemon = false

    private var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacGlass", isDirectory: true)
    }

    var scriptingAdditionSocketPath: String {
        "/tmp/yabai-sa_\(NSUserName()).socket"
    }

    func inspect() async -> EngineReport {
        let executableURL = YabaiLocator.locate()
        let sipStatus = await readSIPStatus()
        var version: String?
        var daemonRunning = false
        var scriptingAdditionLoaded = false

        if let executableURL {
            let currentClient = client(for: executableURL)
            version = try? await currentClient.version()
            daemonRunning = await currentClient.isDaemonAvailable()
            scriptingAdditionLoaded = isScriptingAdditionReachable()
        }

        return EngineReport(
            executableURL: executableURL,
            version: version,
            sipStatus: sipStatus,
            accessibilityTrusted: AccessibilityPermission.isTrusted,
            daemonRunning: daemonRunning,
            scriptingAdditionLoaded: scriptingAdditionLoaded
        )
    }

    func allWindows() async throws -> [YabaiWindow] {
        guard let executableURL = YabaiLocator.locate() else {
            throw YabaiEngineError.executableMissing
        }
        return try await client(for: executableURL).queryWindows()
    }

    func setOpacity(windowID: UInt32, value: Double) async throws {
        guard let executableURL = YabaiLocator.locate() else {
            throw YabaiEngineError.executableMissing
        }
        try await client(for: executableURL).setOpacity(windowID: windowID, value: value)
    }

    /// 依次检查 SIP、权限、SA 和 daemon，任何一步失败都给出可操作错误。
    func activate() async throws -> EngineReport {
        var report = await inspect()
        guard let executableURL = report.executableURL else {
            throw YabaiEngineError.executableMissing
        }

        if !report.scriptingAdditionLoaded {
            guard let sipStatus = report.sipStatus, sipStatus.allowsScriptingAddition else {
                if let sipStatus = report.sipStatus {
                    throw YabaiEngineError.sipRestrictions(sipStatus)
                }
                throw YabaiEngineError.scriptingAdditionLoadFailed("无法读取 csrutil status。")
            }
        }

        if !AccessibilityPermission.isTrusted {
            AccessibilityPermission.requestPrompt()
            AccessibilityPermission.openSystemSettings()
            throw YabaiEngineError.accessibilityPermissionRequired
        }

        if !report.scriptingAdditionLoaded {
            try await loadScriptingAddition(executableURL: executableURL)
        }

        report = await inspect()
        if !report.daemonRunning {
            try await startDaemon(executableURL: executableURL)
        }

        report = await inspect()
        guard report.isReady else {
            throw YabaiEngineError.engineNotReady
        }
        return report
    }

    func stopOwnedDaemon() async {
        guard ownsDaemon, let process = daemonProcess else { return }

        if process.isRunning {
            process.terminate()
            for _ in 0..<20 {
                if !process.isRunning { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }

        daemonLogHandle?.closeFile()
        daemonLogHandle = nil
        daemonProcess = nil
        ownsDaemon = false
    }

    /// 已加载 SA 且权限齐全时，自动启动 daemon，无需用户再点一次启用。
    func ensureDaemonRunning() async throws {
        let report = await inspect()
        guard report.scriptingAdditionLoaded, report.executableURL != nil else {
            throw YabaiEngineError.engineNotReady
        }
        if !report.daemonRunning, let executableURL = report.executableURL {
            try await startDaemon(executableURL: executableURL)
        }
    }

    private func client(for executableURL: URL) -> YabaiClient {
        let normalized = executableURL.standardizedFileURL
        if let client, clientPath == normalized {
            return client
        }
        let newClient = YabaiClient(executableURL: normalized)
        client = newClient
        clientPath = normalized
        return newClient
    }

    private func readSIPStatus() async -> SIPStatus? {
        guard let result = try? await ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/csrutil"),
            arguments: ["status"],
            timeout: 5
        ) else {
            return nil
        }
        let raw = (result.stdout + "\n" + result.stderr)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : SIPStatus(raw: raw)
    }

    private func loadScriptingAddition(executableURL: URL) async throws {
        // 已配置 sudoers 时无需密码；失败后再走系统管理员授权对话框。
        if let result = try? await ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/sudo"),
            arguments: ["-n", executableURL.path, "--load-sa"],
            timeout: 25
        ), result.exitCode == 0, await waitForScriptingAddition() {
            return
        }

        let script = administratorLoadScript(binaryPath: executableURL.path)
        let result: CommandResult
        do {
            result = try await ProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
                arguments: ["-e", script],
                timeout: 60
            )
        } catch {
            throw YabaiEngineError.scriptingAdditionLoadFailed(error.localizedDescription)
        }

        guard result.exitCode == 0 else {
            let message = result.outputForError
            if message.contains("-128") || message.localizedCaseInsensitiveContains("canceled") {
                throw YabaiEngineError.authorizationCancelled
            }
            throw YabaiEngineError.scriptingAdditionLoadFailed(message)
        }

        guard await waitForScriptingAddition() else {
            throw YabaiEngineError.scriptingAdditionLoadFailed(
                "命令执行完成，但未检测到 \(scriptingAdditionSocketPath)。请重启 Dock 后重试。"
            )
        }
    }

    private func waitForScriptingAddition() async -> Bool {
        for _ in 0..<120 {
            if isScriptingAdditionReachable() {
                return true
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }

    /// 只检查 socket 文件会被上次崩溃留下的死文件误导，实际 connect 一次更可靠。
    private func isScriptingAdditionReachable() -> Bool {
        let path = scriptingAdditionSocketPath
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < pathCapacity else { return false }
        _ = path.withCString { source in
            withUnsafeMutablePointer(to: &address.sun_path) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: pathCapacity) { destination in
                    strncpy(destination, source, pathCapacity - 1)
                }
            }
        }

        let socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else { return false }
        defer { close(socketFD) }

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        return result == 0
    }

    private func administratorLoadScript(binaryPath: String) -> String {
        let user = appleScriptEscaped(NSUserName())
        let path = appleScriptEscaped(binaryPath)
        let uid = getuid()
        return """
        do shell script "/usr/bin/env SUDO_UID=\(uid) SUDO_USER=" & quoted form of "\(user)" & " " & quoted form of "\(path)" & " --load-sa" with administrator privileges
        """
    }

    private func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private func startDaemon(executableURL: URL) async throws {
        try FileManager.default.createDirectory(
            at: supportDirectory,
            withIntermediateDirectories: true
        )

        let configURL = supportDirectory.appendingPathComponent("yabairc")
        let config = """
        # 由 MacGlass 创建：保持 macOS 原始窗口布局，只启用透明度控制。
        "\(executableURL.path)" -m config layout float
        "\(executableURL.path)" -m config mouse_follows_focus off
        "\(executableURL.path)" -m config focus_follows_mouse off
        """
        try config.write(to: configURL, atomically: true, encoding: .utf8)

        let logURL = supportDirectory.appendingPathComponent("yabai.log")
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        let logHandle = try FileHandle(forWritingTo: logURL)
        try logHandle.seekToEnd()

        let process = Process()
        process.executableURL = executableURL
        process.arguments = YabaiCommand.start(configurationPath: configURL.path)
        process.currentDirectoryURL = supportDirectory
        process.standardOutput = logHandle
        process.standardError = logHandle

        var environment = ProcessInfo.processInfo.environment
        environment["USER"] = NSUserName()
        environment["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        process.environment = environment

        do {
            try process.run()
        } catch {
            logHandle.closeFile()
            throw YabaiEngineError.daemonStartFailed(error.localizedDescription)
        }

        daemonProcess = process
        daemonLogHandle = logHandle
        ownsDaemon = true

        let currentClient = client(for: executableURL)
        for _ in 0..<60 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if !process.isRunning {
                let detail = readLogTail()
                await stopOwnedDaemon()
                throw YabaiEngineError.daemonStartFailed(detail)
            }
            if await currentClient.isDaemonAvailable() {
                return
            }
        }

        let detail = readLogTail()
        await stopOwnedDaemon()
        throw YabaiEngineError.daemonStartFailed(
            detail.isEmpty ? "等待 yabai socket 超时。" : detail
        )
    }

    private func readLogTail() -> String {
        let logURL = supportDirectory.appendingPathComponent("yabai.log")
        guard
            let handle = try? FileHandle(forReadingFrom: logURL),
            let data = try? handle.readToEnd()
        else {
            return ""
        }
        handle.closeFile()
        let tail = data.suffix(8_000)
        return String(decoding: tail, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
