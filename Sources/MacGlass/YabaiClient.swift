import Foundation
import MacGlassCore

enum YabaiClientError: LocalizedError {
    case daemonUnavailable(String)
    case scriptingAdditionUnavailable(String)
    case accessibilityUnavailable(String)
    case windowUnavailable(UInt32, String)
    case invalidResponse(String)
    case commandFailed(Int32, String)

    var errorDescription: String? {
        switch self {
        case .daemonUnavailable(let detail):
            return "yabai 后台服务未运行。\n\(detail)"
        case .scriptingAdditionUnavailable(let detail):
            return "真实透明引擎未加载，yabai scripting addition 不可用。\n\(detail)"
        case .accessibilityUnavailable(let detail):
            return "MacGlass 没有辅助功能权限。\n\(detail)"
        case .windowUnavailable(let id, let detail):
            return "窗口 \(id) 已关闭或当前不可操作。\n\(detail)"
        case .invalidResponse(let detail):
            return "yabai 返回了无法解析的数据。\n\(detail)"
        case .commandFailed(let code, let detail):
            return "yabai 命令失败（退出码 \(code)）。\n\(detail)"
        }
    }
}

actor YabaiClient {
    let executableURL: URL

    init(executableURL: URL) {
        self.executableURL = executableURL
    }

    func queryWindows() async throws -> [YabaiWindow] {
        let result = try await run(YabaiCommand.queryWindows, timeout: 5)
        guard result.exitCode == 0 else {
            throw classify(result)
        }

        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let start = output.firstIndex(of: "["),
            let end = output.lastIndex(of: "]"),
            start <= end
        else {
            throw YabaiClientError.invalidResponse(
                result.outputForError.isEmpty ? output : result.outputForError
            )
        }

        let json = String(output[start...end])
        guard let data = json.data(using: .utf8) else {
            throw YabaiClientError.invalidResponse("返回内容不是 UTF-8。")
        }

        do {
            return try JSONDecoder().decode([YabaiWindow].self, from: data)
        } catch {
            throw YabaiClientError.invalidResponse(error.localizedDescription)
        }
    }

    func setOpacity(windowID: UInt32, value: Double) async throws {
        let result = try await run(
            YabaiCommand.setOpacity(windowID: windowID, value: value),
            timeout: 5
        )
        guard result.exitCode == 0 else {
            throw classify(result)
        }
    }

    func version() async throws -> String {
        let result = try await run(["--version"], timeout: 5)
        guard result.exitCode == 0 else {
            throw classify(result)
        }
        return (result.stdout + result.stderr)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func isDaemonAvailable() async -> Bool {
        (try? await queryWindows()) != nil
    }

    private func run(_ arguments: [String], timeout: TimeInterval) async throws -> CommandResult {
        try await ProcessRunner.run(
            executableURL: executableURL,
            arguments: arguments,
            timeout: timeout
        )
    }

    private func classify(_ result: CommandResult) -> YabaiClientError {
        let message = result.outputForError.isEmpty
            ? "没有错误输出。"
            : result.outputForError
        let lowercased = message.lowercased()

        if lowercased.contains("failed to connect to socket")
            || lowercased.contains("connection refused")
            || lowercased.contains("no such file or directory") && lowercased.contains("socket") {
            return .daemonUnavailable(message)
        }
        if lowercased.contains("scripting-addition")
            || lowercased.contains("scripting addition")
            || lowercased.contains("system integrity protection") {
            return .scriptingAdditionUnavailable(message)
        }
        if lowercased.contains("accessibility") {
            return .accessibilityUnavailable(message)
        }
        if lowercased.contains("could not find window")
            || lowercased.contains("window not found")
            || lowercased.contains("could not locate the window") {
            return .windowUnavailable(0, message)
        }
        return .commandFailed(result.exitCode, message)
    }
}
