import Foundation
import RunnerCore

@main
struct RunnerService {
    static func main() async {
        guard CommandLine.arguments.count == 2 else { return }
        let storage = Storage(root: URL(fileURLWithPath: CommandLine.arguments[1]))
        var status = storage.loadStatus()
        let previousRegistrations = status.registered
        status.ready = false
        status.errors = [:]
        do {
            try storage.prepare()
            let configuration = try storage.loadConfiguration()
            guard !configuration.ampPath.isEmpty else { throw RunnerError.message("Choose an Amp executable in the app.") }
            let runnerPID = try spawnRunner(configuration, workspace: storage.workspace)
            var exitStatus: Int32 = 0
            var synchronizer = Synchronizer(status: status)
            while waitpid(runnerPID, &exitStatus, WNOHANG) == 0 {
                do {
                    let desired = try storage.loadConfiguration()
                    let ready = try await Command.run(configuration.ampPath,
                        Command.directoryArguments("list", runnerID: configuration.runnerID), cwd: storage.workspace, timeout: 5)
                    status.ready = ready.code == 0
                    status.message = status.ready ? "" : ready.output
                    if status.ready {
                        synchronizer.status = status
                        try await synchronizer.reconcile(desired: desired.directories, persist: storage.saveStatus) { action, path in
                            try await Command.run(configuration.ampPath,
                                Command.directoryArguments(action, path: path, runnerID: configuration.runnerID), cwd: storage.workspace).checked()
                        }
                        status = synchronizer.status
                    }
                    status.updatedAt = Date()
                    try storage.saveStatus(status)
                } catch {
                    status = synchronizer.status
                    status.ready = false
                    status.message = error.localizedDescription
                    status.updatedAt = Date()
                    try? storage.saveStatus(status)
                }
                try? await Task.sleep(for: .seconds(2))
            }
            status.ready = false
            status.message = "Amp exited (wait status \(exitStatus)). Retrying shortly; check runner.log for details."
        } catch {
            status.registered = previousRegistrations
            status.ready = false
            status.message = error.localizedDescription
        }
        status.updatedAt = Date()
        try? storage.saveStatus(status)
    }

    private static func spawnRunner(_ configuration: Configuration, workspace: URL) throws -> pid_t {
        // Foundation.Process creates a separate process group. Spawn into this helper's
        // launchd-owned group instead, so even SIGKILL/restarts cannot orphan the runner.
        var attributes: posix_spawnattr_t?
        var actions: posix_spawn_file_actions_t?
        posix_spawnattr_init(&attributes)
        posix_spawn_file_actions_init(&actions)
        defer {
            posix_spawnattr_destroy(&attributes)
            posix_spawn_file_actions_destroy(&actions)
        }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attributes, getpgrp())
        posix_spawn_file_actions_addchdir_np(&actions, workspace.path)
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        let argumentStrings: [String] = [configuration.ampPath, "--no-tui", "--runner-id", configuration.runnerID]
        var arguments = argumentStrings.map { $0.withCString { strdup($0) } } + [nil]
        var environment = Command.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            arguments.forEach { free($0) }
            environment.forEach { free($0) }
        }
        var pid: pid_t = 0
        let result = posix_spawn(&pid, configuration.ampPath, &actions, &attributes, &arguments, &environment)
        guard result == 0 else { throw RunnerError.message("Could not launch Amp: \(String(cString: strerror(result)))") }
        return pid
    }
}
