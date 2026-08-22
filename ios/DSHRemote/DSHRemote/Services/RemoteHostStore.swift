import Combine
import Foundation

@MainActor
final class RemoteHostStore: ObservableObject {
    @Published private(set) var hosts: [RemoteHost] = []
    @Published var pendingImportedConnection: RemoteConnectionDescriptor?

    private let defaults: UserDefaults
    private let storageKey = "dsh-remote.hosts.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    @discardableResult
    func add(name: String?, connection: RemoteConnectionDescriptor) -> RemoteHost {
        if let index = hosts.firstIndex(where: { $0.baseURL == connection.baseURL }) {
            hosts[index].accessToken = connection.accessToken
            save()
            return hosts[index]
        }

        let fallbackName = connection.baseURL.host?
            .split(separator: ".")
            .first
            .map(String.init) ?? "My computer"
        let resolvedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = resolvedName.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName
        let host = RemoteHost(
            name: displayName,
            baseURL: connection.baseURL,
            accessToken: connection.accessToken
        )
        hosts.insert(host, at: 0)
        save()
        return host
    }

    func remove(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            hosts.remove(at: index)
        }
        save()
    }

    func removeAll() {
        hosts.removeAll()
        save()
    }

    func importConnectionURL(_ url: URL) {
        guard let connection = try? RemoteEndpointValidator.connection(from: url.absoluteString) else {
            return
        }
        pendingImportedConnection = connection
    }

    func consumePendingImportedConnection() -> RemoteConnectionDescriptor? {
        defer { pendingImportedConnection = nil }
        return pendingImportedConnection
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([RemoteHost].self, from: data) else {
            return
        }
        hosts = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(hosts) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
