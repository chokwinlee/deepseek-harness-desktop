import Combine
import Foundation

@MainActor
final class RemoteHostStore: ObservableObject {
    @Published private(set) var hosts: [RemoteHost] = []
    @Published var pendingImportedURL: URL?

    private let defaults: UserDefaults
    private let storageKey = "dsh-remote.hosts.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    @discardableResult
    func add(name: String?, baseURL: URL) -> RemoteHost {
        if let existing = hosts.first(where: { $0.baseURL == baseURL }) {
            return existing
        }

        let fallbackName = baseURL.host?
            .split(separator: ".")
            .first
            .map(String.init) ?? "My computer"
        let resolvedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = resolvedName.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName
        let host = RemoteHost(
            name: displayName,
            baseURL: baseURL
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

    func importConnectionURL(_ url: URL) {
        guard let normalized = try? RemoteEndpointValidator.normalizedURL(from: url.absoluteString) else {
            return
        }
        pendingImportedURL = normalized
    }

    func consumePendingImportedURL() -> URL? {
        defer { pendingImportedURL = nil }
        return pendingImportedURL
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
