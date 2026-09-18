import Foundation

public struct Configuration: Codable, Sendable, Equatable {
    public var runnerID = "amp-mac-" + UUID().uuidString.prefix(8).lowercased()
    public var ampPath = ""
    public var directories: [String] = []
    public var startAtLogin = false
    public init() {}

    public mutating func renameRunner(_ name: String) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let labels = name.split(separator: ".", omittingEmptySubsequences: false)
        guard !name.isEmpty, name.utf8.count <= 253,
              labels.allSatisfy({ label in
                  !label.isEmpty && label.utf8.count <= 63 &&
                  label.range(of: "^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$", options: .regularExpression) != nil
              }) else {
            throw RunnerError.message("Use letters, numbers, hyphens, or dots—for example, studio-mac.")
        }
        runnerID = name
    }

    public mutating func add(_ urls: [URL]) throws {
        // Validate the whole selection before changing the saved configuration.
        let paths = try urls.map { url -> String in
            let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
            guard Self.isDirectory(resolved.path) else {
                throw RunnerError.message("Folder unavailable: \(url.path)")
            }
            return resolved.path
        }
        for path in paths where !directories.contains(path) { directories.append(path) }
    }

    public static func isDirectory(_ path: String) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue
    }
}

public struct ServiceStatus: Codable, Sendable {
    public var updatedAt = Date.distantPast
    public var ready = false
    public var registered: [String] = []
    public var managed: [String] = []
    public var errors: [String: String] = [:]
    public var message = ""
    public init() {}
    public var isFresh: Bool { Date().timeIntervalSince(updatedAt) < 15 }
}

public struct Storage: Sendable {
    public let root: URL
    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/AmpRunner", isDirectory: true)) {
        self.root = root
    }
    public var configurationURL: URL { root.appendingPathComponent("configuration.json") }
    public var statusURL: URL { root.appendingPathComponent("status.json") }
    // Amp always serves its startup directory. Keep it empty, separate from private app state.
    public var workspace: URL { root.appendingPathComponent("Workspace", isDirectory: true) }
    public var log: URL { root.appendingPathComponent("runner.log") }
    public var localAgent: URL { root.appendingPathComponent("\(LaunchAgent.label).plist") }

    public func prepare() throws {
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
    }
    public func loadConfiguration() throws -> Configuration {
        guard FileManager.default.fileExists(atPath: configurationURL.path) else { return Configuration() }
        return try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: configurationURL))
    }
    public func save(_ configuration: Configuration) throws {
        try prepare()
        try JSONEncoder().encode(configuration).write(to: configurationURL, options: .atomic)
    }
    public func loadStatus() -> ServiceStatus {
        (try? JSONDecoder().decode(ServiceStatus.self, from: Data(contentsOf: statusURL))) ?? ServiceStatus()
    }
    public func saveStatus(_ status: ServiceStatus) throws {
        try JSONEncoder().encode(status).write(to: statusURL, options: .atomic)
    }
}

public enum RunnerError: LocalizedError {
    case message(String)
    public var errorDescription: String? {
        switch self { case .message(let message): message }
    }
}

public enum Reconciliation {
    public static func removals(desired: [String], registered: [String]) -> [String] {
        registered.filter { !desired.contains($0) }
    }
    public static func additions(desired: [String], registered: [String]) -> [String] {
        desired.filter { !registered.contains($0) && Configuration.isDirectory($0) }
    }
}
