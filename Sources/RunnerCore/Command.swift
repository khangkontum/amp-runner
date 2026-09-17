import Foundation

public struct CommandResult: Sendable {
    public let code: Int32
    public let output: String
    public func checked() throws {
        guard code == 0 else { throw RunnerError.message(output.isEmpty ? "Command failed (\(code))." : output) }
    }
}

public enum Command {
    public static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        env["PATH"] = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (env["PATH"] ?? "")
        env["NO_COLOR"] = "1"
        return env
    }

    public static func findAmp() -> String? {
        environment["PATH"]!.split(separator: ":").map { "\($0)/amp" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public static func run(_ executable: String, _ arguments: [String], cwd: URL? = nil,
                           timeout: TimeInterval = 20) async throws -> CommandResult {
        try await Task.detached {
            // File-backed output avoids pipe-buffer deadlocks; every invocation has a deadline.
            let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            FileManager.default.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600])
            let handle = try FileHandle(forWritingTo: output)
            defer { try? handle.close(); try? FileManager.default.removeItem(at: output) }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.currentDirectoryURL = cwd
            process.environment = environment
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = handle
            process.standardError = handle
            try process.run()
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
            if process.isRunning {
                process.terminate()
                let grace = Date().addingTimeInterval(1)
                while process.isRunning && Date() < grace { try await Task.sleep(for: .milliseconds(50)) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                throw RunnerError.message("Command timed out: \(URL(fileURLWithPath: executable).lastPathComponent) \(arguments.prefix(3).joined(separator: " "))")
            }
            // isRunning is already false. waitUntilExit spins a thread-bound run loop
            // and can hang when an async task resumes on a different worker thread.
            let text = String(decoding: try Data(contentsOf: output), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return CommandResult(code: process.terminationStatus, output: text)
        }.value
    }

    public static func directoryArguments(_ action: String, path: String? = nil, runnerID: String) -> [String] {
        ["runner", "dirs", action] + (path.map { [$0] } ?? []) + ["--runner-id", runnerID]
    }
}
