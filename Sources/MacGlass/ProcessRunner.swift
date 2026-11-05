import Darwin
import Foundation

struct CommandResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var outputForError: String {
        let preferred = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !preferred.isEmpty {
            return preferred
        }
        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ProcessRunnerError: LocalizedError {
    case launchFailed(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .launchFailed(let detail):
            return "无法启动命令：\(detail)"
        case .timedOut:
            return "命令执行超时。"
        }
    }
}

enum ProcessRunner {
    private final class LockedState: @unchecked Sendable {
        private let lock = NSLock()
        private var timedOutStorage = false

        var timedOut: Bool {
            lock.lock()
            defer { lock.unlock() }
            return timedOutStorage
        }

        func markTimedOut() {
            lock.lock()
            timedOutStorage = true
            lock.unlock()
        }
    }

    /// 直接启动可执行文件，不经过 shell，避免路径和窗口标题带来的注入问题。
    static func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        timeout: TimeInterval = 5
    ) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                let timeoutState = LockedState()

                process.executableURL = executableURL
                process.arguments = arguments
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                var mergedEnvironment = environment ?? ProcessInfo.processInfo.environment
                mergedEnvironment["USER"] = NSUserName()
                mergedEnvironment["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
                process.environment = mergedEnvironment

                do {
                    try process.run()
                } catch {
                    continuation.resume(
                        throwing: ProcessRunnerError.launchFailed(error.localizedDescription)
                    )
                    return
                }

                let outputLock = NSLock()
                var stdoutData = Data()
                var stderrData = Data()
                let readGroup = DispatchGroup()

                readGroup.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    outputLock.lock()
                    stdoutData = data
                    outputLock.unlock()
                    readGroup.leave()
                }

                readGroup.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    outputLock.lock()
                    stderrData = data
                    outputLock.unlock()
                    readGroup.leave()
                }

                let timeoutItem = DispatchWorkItem {
                    timeoutState.markTimedOut()
                    if process.isRunning {
                        process.terminate()
                    }
                    DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                        if process.isRunning {
                            kill(process.processIdentifier, SIGKILL)
                        }
                    }
                }
                DispatchQueue.global(qos: .userInitiated).asyncAfter(
                    deadline: .now() + timeout,
                    execute: timeoutItem
                )

                process.waitUntilExit()
                readGroup.wait()
                timeoutItem.cancel()

                if timeoutState.timedOut {
                    continuation.resume(throwing: ProcessRunnerError.timedOut)
                    return
                }

                outputLock.lock()
                let stdout = String(decoding: stdoutData, as: UTF8.self)
                let stderr = String(decoding: stderrData, as: UTF8.self)
                outputLock.unlock()

                continuation.resume(
                    returning: CommandResult(
                        exitCode: process.terminationStatus,
                        stdout: stdout,
                        stderr: stderr
                    )
                )
            }
        }
    }
}
