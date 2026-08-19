import Foundation

struct RemoteHost: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var baseURL: URL
    var accessToken: String?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        baseURL: URL,
        accessToken: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.accessToken = accessToken
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

    var transportLabel: String {
        accessToken == nil ? "Tailscale / HTTPS" : "同一 Wi-Fi"
    }
}
