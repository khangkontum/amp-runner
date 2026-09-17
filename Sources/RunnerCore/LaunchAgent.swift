import Foundation

public struct LaunchAgent: Sendable {
    public static let label = "com.local.AmpRunner.service"
    public let storage: Storage
    public let serviceExecutable: String
    public var domain: String { "gui/\(getuid())" }
    public var target: String { "\(domain)/\(Self.label)" }
    public var loginURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(Self.label).plist")
    }

    public init(storage: Storage, serviceExecutable: String) {
        self.storage = storage
        self.serviceExecutable = serviceExecutable
    }

    public func plist() throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: [
            "Label": Self.label,
            "ProgramArguments": [serviceExecutable, storage.root.path],
            "WorkingDirectory": storage.workspace.path,
            "RunAtLoad": true,
            "KeepAlive": true,
            "ThrottleInterval": 10,
            "StandardOutPath": storage.log.path,
            "StandardErrorPath": storage.log.path,
            "EnvironmentVariables": ["PATH": Command.environment["PATH"]!]
        ], format: .xml, options: 0)
    }

    public func isLoaded() async -> Bool {
        (try? await Command.run("/bin/launchctl", ["print", target]).code) == 0
    }

    public func install(startAtLogin: Bool) throws -> URL {
        try storage.prepare()
        let destination = startAtLogin ? loginURL : storage.localAgent
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try plist().write(to: destination, options: .atomic)
        let obsolete = startAtLogin ? storage.localAgent : loginURL
        if FileManager.default.fileExists(atPath: obsolete.path) { try FileManager.default.removeItem(at: obsolete) }
        return destination
    }

    public func start(startAtLogin: Bool) async throws {
        guard FileManager.default.isExecutableFile(atPath: serviceExecutable) else {
            throw RunnerError.message("Background helper is missing. Build and open the complete Amp Runner.app bundle.")
        }
        let url = try install(startAtLogin: startAtLogin)
        if await !isLoaded() {
            try await Command.run("/bin/launchctl", ["bootstrap", domain, url.path]).checked()
        }
    }

    public func stop() async throws {
        // Remove the login entry first so an intentional stop also survives the next login.
        for url in [loginURL, storage.localAgent] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        if await isLoaded() {
            try await Command.run("/bin/launchctl", ["bootout", target]).checked()
        }
    }
}
