import Foundation

struct RemoteHost: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var baseURL: URL
    let createdAt: Date

    init(id: UUID = UUID(), name: String, baseURL: URL, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.createdAt = createdAt
    }

    var address: String {
        guard let components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL.absoluteString
        }

        if let port = components.port {
            return "\(components.host ?? baseURL.host ?? "Unknown host"):\(port)"
        }
        return components.host ?? baseURL.host ?? "Unknown host"
    }
}
