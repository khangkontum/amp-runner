import Foundation
import Testing
@testable import RunnerCore

struct RunnerCoreTests {
    @Test func runnerNamesValidateAndPersistWithoutChangingFolders() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = Storage(root: root)
        var config = Configuration()
        config.directories = ["/alpha", "/beta gamma"]
        config.startAtLogin = true
        for name in ["  My-Mac.local  ", "a", String(repeating: "a", count: 63)] {
            try config.renameRunner(name)
            #expect(config.runnerID == name.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let before = config
        for name in ["", " ", "my mac", "-mac", "mac-", "mac_name", "mac..local", "mac.", "mác", String(repeating: "a", count: 64), Array(repeating: String(repeating: "a", count: 63), count: 4).joined(separator: ".")] {
            #expect(throws: (any Error).self) { try config.renameRunner(name) }
            #expect(config == before)
        }
        try config.renameRunner("Studio-Mac")
        try storage.save(config)
        #expect(try storage.loadConfiguration() == config)
        #expect(config.directories == ["/alpha", "/beta gamma"])
        #expect(config.startAtLogin)
    }

    func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func canonicalizesDuplicatesAndRejectsFilesAtomically() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Project 'one' & two")
        let link = root.appendingPathComponent("alias")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
        var config = Configuration()
        try config.add([folder, link, folder.appendingPathComponent(".")])
        #expect(config.directories == [folder.resolvingSymlinksInPath().path])
        let file = root.appendingPathComponent("file.txt")
        try Data("untouched".utf8).write(to: file)
        let before = config
        #expect(throws: (any Error).self) { try config.add([root, file]) }
        #expect(config == before)
    }

    @Test func persistsIdentityDirectoriesAndLoginWithoutServingAppState() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = Storage(root: root)
        var config = Configuration()
        config.ampPath = "/some path/amp"
        config.directories = ["/alpha", "/beta gamma"]
        config.startAtLogin = true
        try storage.save(config)
        #expect(try Storage(root: root).loadConfiguration() == config)
        #expect(storage.configurationURL.deletingLastPathComponent() != storage.workspace)
        try Data("broken".utf8).write(to: storage.configurationURL)
        #expect(throws: (any Error).self) { try storage.loadConfiguration() }
        #expect(try String(contentsOf: storage.configurationURL, encoding: .utf8) == "broken")
    }

    @Test func launchAgentUsesLiteralArgumentsAndStableWorkspace() throws {
        let storage = Storage(root: URL(fileURLWithPath: "/tmp/a & b"))
        let agent = LaunchAgent(storage: storage, serviceExecutable: "/Applications/Amp Runner.app/Contents/Helpers/AmpRunnerService")
        let plist = try #require(PropertyListSerialization.propertyList(from: agent.plist(), format: nil) as? [String: Any])
        #expect(plist["ProgramArguments"] as? [String] == ["/Applications/Amp Runner.app/Contents/Helpers/AmpRunnerService", "/tmp/a & b"])
        #expect(plist["WorkingDirectory"] as? String == "/tmp/a & b/Workspace")
        #expect(plist["KeepAlive"] as? Bool == true)
        #expect(Command.directoryArguments("remove", path: "/tmp/$(touch nope)", runnerID: "mine") ==
            ["runner", "dirs", "remove", "/tmp/$(touch nope)", "--runner-id", "mine"])
    }

    @Test func commandPreservesArgumentsAndReportsFailures() async throws {
        let result = try await Command.run("/usr/bin/printf", ["%s", "two words; $(not a command)"])
        #expect(result.code == 0)
        #expect(result.output == "two words; $(not a command)")
        let failure = try await Command.run("/bin/sh", ["-c", "printf denied >&2; exit 7"])
        #expect(failure.code == 7)
        #expect(failure.output == "denied")
        #expect(throws: (any Error).self) { try failure.checked() }
    }

    @Test func hungCommandsHaveDeadline() async throws {
        let start = Date()
        await #expect(throws: (any Error).self) {
            try await Command.run("/bin/sleep", ["30"], timeout: 0.1)
        }
        #expect(Date().timeIntervalSince(start) < 3)
    }

    @Test func concurrentCommandsCompleteAfterAsyncThreadHops() async throws {
        try await withThrowingTaskGroup(of: String.self) { group in
            for index in 0..<20 {
                group.addTask {
                    let result = try await Command.run("/usr/bin/printf", ["%s", "result-\(index)"])
                    try result.checked()
                    return result.output
                }
            }
            var results = Set<String>()
            for try await result in group { results.insert(result) }
            #expect(results == Set((0..<20).map { "result-\($0)" }))
        }
    }

    @Test func reconciliationRetriesFailedRemovalAndSkipsMissingFolders() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let added = root.path
        var status = ServiceStatus()
        status.managed = ["/removed"]
        status.registered = ["/removed"]
        var sync = Synchronizer(status: status)
        var calls: [String] = []
        var persisted = ServiceStatus()
        try await sync.reconcile(desired: [added, "/missing/does-not-exist"], persist: { persisted = $0 }) { action, path in
            calls.append("\(action):\(path)")
            if action == "remove" { throw RunnerError.message("busy") }
            #expect(persisted.managed.contains(added))
            #expect(!persisted.registered.contains(added))
        }
        #expect(calls == ["remove:/removed", "add:\(added)"])
        #expect(sync.status.registered == ["/removed", added])
        #expect(sync.status.errors["/removed"] == "busy")
        calls = []
        try await sync.reconcile(desired: [added], persist: { persisted = $0 }) { action, path in
            calls.append("\(action):\(path)")
        }
        #expect(calls == ["remove:/removed"])
        #expect(sync.status.registered == [added])
        #expect(sync.status.errors.isEmpty)
        #expect(FileManager.default.fileExists(atPath: added))
    }

    @Test func uncertainAddIsTrackedAndRemovedAfterRestart() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var persisted = ServiceStatus()
        var sync = Synchronizer(status: ServiceStatus())
        try await sync.reconcile(desired: [root.path], persist: { persisted = $0 }) { _, _ in
            throw RunnerError.message("timeout after Amp accepted the folder")
        }
        #expect(persisted.registered.isEmpty)
        #expect(persisted.managed == [root.path])
        var restarted = Synchronizer(status: persisted)
        var calls: [String] = []
        try await restarted.reconcile(desired: [], persist: { persisted = $0 }) { action, path in
            calls.append("\(action):\(path)")
        }
        #expect(calls == ["remove:\(root.path)"])
        #expect(persisted.managed.isEmpty)
    }

    @Test func restartReassertsSavedRegistration() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var status = ServiceStatus()
        status.registered = [root.path]
        status.managed = [root.path]
        var sync = Synchronizer(status: status)
        var calls: [String] = []
        try await sync.reconcile(desired: [root.path], persist: { _ in }) { action, path in calls.append("\(action):\(path)") }
        #expect(calls == ["add:\(root.path)"])
    }

    @Test func zoomChangesScaleAndStopsAtBothBounds() {
        var zoom = ZoomLevel()
        zoom.increase()
        #expect(zoom.percent == 125)
        #expect(zoom.scale == 1.25)
        for _ in 0..<10 { zoom.increase() }
        #expect(zoom.percent == 175)
        #expect(!zoom.canIncrease)
        #expect(zoom.canDecrease)
        for _ in 0..<10 { zoom.decrease() }
        #expect(zoom.percent == 75)
        #expect(zoom.scale == 0.75)
        #expect(!zoom.canDecrease)
        #expect(zoom.canIncrease)
        zoom.reset()
        #expect(zoom.percent == 100)
        #expect(ZoomLevel(percent: 200).percent == 175)
        #expect(ZoomLevel(percent: 0).percent == 75)
    }
}
