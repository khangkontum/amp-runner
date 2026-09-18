import AppKit
import Observation
import RunnerCore

@MainActor @Observable
final class AppModel {
    var configuration = Configuration()
    var status = ServiceStatus()
    var loaded = false
    var busy = false
    var error: String?
    var configurationReadable = true
    let storage: Storage
    let preview: Bool
    var zoom = ZoomLevel() {
        didSet {
            if !preview { UserDefaults.standard.set(zoom.percent, forKey: "interfaceZoom") }
        }
    }

    var agent: LaunchAgent {
        LaunchAgent(storage: storage, serviceExecutable: Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/AmpRunnerService").path)
    }
    var running: Bool { loaded && (preview || status.isFresh) && status.ready }
    var stalled: Bool { loaded && !preview && status.updatedAt != .distantPast && !status.isFresh }
    var title: String { running ? "Running" : stalled ? "Not responding" : loaded ? "Connecting" : "Stopped" }
    var serviceMessage: String {
        if stalled { return "Runner stopped responding. Restart it to reconnect." }
        if !status.message.isEmpty { return "Can’t connect to Amp. Retrying…" }
        return ""
    }
    var paths: [String] {
        configuration.directories + status.managed.filter { !configuration.directories.contains($0) }
    }

    init(preview: Bool = false) {
        self.preview = preview
        storage = Storage()
        if !preview {
            zoom = ZoomLevel(percent: UserDefaults.standard.object(forKey: "interfaceZoom") as? Int ?? 100)
        }
        if preview {
            configuration.runnerID = "example-runner"
            configuration.ampPath = "/Example/amp"
            if CommandLine.arguments.contains("--preview-populated") {
                configuration.directories = ["/Example Projects/website", "/Example Projects/amp-tools", "/Volumes/Example/archive"]
                status.registered = Array(configuration.directories.prefix(2))
                status.ready = true
                status.updatedAt = Date()
                loaded = true
            }
            return
        }
        do {
            configuration = try storage.loadConfiguration()
            if configuration.ampPath.isEmpty { configuration.ampPath = Command.findAmp() ?? "" }
            try storage.save(configuration)
        } catch {
            configurationReadable = false
            self.error = "Couldn’t load your settings. Nothing was changed."
        }
        Task { await monitor() }
    }

    func monitor() async {
        guard !preview else { return }
        while !Task.isCancelled {
            loaded = await agent.isLoaded()
            status = storage.loadStatus()
            try? await Task.sleep(for: .seconds(2))
        }
    }

    func save(_ change: (inout Configuration) throws -> Void) {
        guard !preview, configurationReadable else { return }
        do {
            var updated = configuration
            try change(&updated)
            try storage.save(updated)
            configuration = updated
        } catch {
            self.error = (error as? RunnerError)?.localizedDescription ?? "Couldn’t save your changes. Try again."
        }
    }

    func addFolders(_ urls: [URL]) { save { try $0.add(urls) } }

    func renameRunner(_ name: String) async {
        guard !preview, !busy, configurationReadable else { return }
        busy = true
        defer { busy = false }
        // Check launchd directly, not the periodically refreshed UI status.
        loaded = await agent.isLoaded()
        guard !loaded else {
            error = "Stop the runner before changing its ID."
            return
        }
        save { try $0.renameRunner(name) }
    }

    func chooseFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add Folders"
        panel.message = "These folders will be available to Amp threads on this Mac."
        if panel.runModal() == .OK { addFolders(panel.urls) }
    }

    func remove(_ path: String) {
        save { $0.directories.removeAll { $0 == path } }
    }

    func locate(_ path: String) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Use Folder"
        if panel.runModal() == .OK, let url = panel.url {
            save {
                try $0.add([url])
                if url.standardizedFileURL.resolvingSymlinksInPath().path != path {
                    $0.directories.removeAll { $0 == path }
                }
            }
        }
    }

    func chooseAmp() {
        let panel = NSOpenPanel()
        panel.showsHiddenFiles = true
        panel.message = "Select the Amp CLI executable (usually ~/.local/bin/amp). Stop the runner before changing it."
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin")
        if panel.runModal() == .OK, let url = panel.url {
            guard FileManager.default.isExecutableFile(atPath: url.path) else {
                error = "Select an executable file."
                return
            }
            save { $0.ampPath = url.path }
        }
    }

    func start() async {
        guard !preview, !busy, configurationReadable else { return }
        busy = true
        defer { busy = false }
        do {
            guard FileManager.default.isExecutableFile(atPath: configuration.ampPath) else {
                throw RunnerError.message("Install the Amp CLI, or choose its executable in Runner Settings.")
            }
            // Amp owns credentials. Do not read, copy, or store its API key.
            try await Command.run(configuration.ampPath, ["usage"], timeout: 30).checked()
            try await agent.start(startAtLogin: configuration.startAtLogin)
            loaded = true
        } catch {
            self.error = "Couldn’t start the runner. Check your Amp sign-in and Runner Settings, then try again."
        }
    }

    func stop() async {
        guard !preview, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await agent.stop()
            loaded = false
            // Explicit Stop also disables launch at login; Start can re-enable it later.
            save { $0.startAtLogin = false }
        } catch { self.error = "Couldn’t stop the runner. Try again." }
    }

    func setLogin(_ enabled: Bool) {
        guard !preview, !busy, configurationReadable else { return }
        do {
            var updated = configuration
            updated.startAtLogin = enabled
            _ = try agent.install(startAtLogin: enabled)
            do { try storage.save(updated) }
            catch {
                _ = try? agent.install(startAtLogin: configuration.startAtLogin)
                throw error
            }
            configuration = updated
        } catch { self.error = "Couldn’t update Start at login. Try again." }
    }

    func folderState(_ path: String) -> (String, String) {
        if !configuration.directories.contains(path) { return ("Pending removal", "clock") }
        if status.errors[path] != nil { return ("Needs attention", "exclamationmark.circle") }
        if preview && path.contains("/Volumes/") { return ("Unavailable", "exclamationmark.triangle") }
        if !preview && !Configuration.isDirectory(path) { return ("Unavailable", "exclamationmark.triangle") }
        if running && status.registered.contains(path) { return ("Registered", "checkmark.circle.fill") }
        if stalled { return ("Waiting for runner", "exclamationmark.circle") }
        return (loaded ? "Registering" : "Saved", "clock")
    }

    func openLogs() { NSWorkspace.shared.open(storage.log) }
}
