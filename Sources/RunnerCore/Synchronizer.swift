import Foundation

public struct Synchronizer: Sendable {
    public var status: ServiceStatus
    private var verified: [String] = []

    public init(status: ServiceStatus) { self.status = status }

    public mutating func reconcile(
        desired: [String],
        isolation: isolated (any Actor)? = #isolation,
        persist: (ServiceStatus) throws -> Void,
        execute: (String, String) async throws -> Void
    ) async throws {
        status.errors = [:]
        for path in Reconciliation.removals(desired: desired, registered: status.managed) {
            do {
                try await execute("remove", path)
                status.managed.removeAll { $0 == path }
                status.registered.removeAll { $0 == path }
                verified.removeAll { $0 == path }
            } catch { status.errors[path] = error.localizedDescription }
            try persist(status)
        }
        for path in Reconciliation.additions(desired: desired, registered: verified) {
            // Write intent before calling Amp: a crash or timeout must never leave an
            // exposed directory untracked and impossible to remove from the manager.
            if !status.managed.contains(path) { status.managed.append(path) }
            try persist(status)
            do {
                try await execute("add", path)
                if !status.registered.contains(path) { status.registered.append(path) }
                verified.append(path)
            } catch { status.errors[path] = error.localizedDescription }
            try persist(status)
        }
    }
}
