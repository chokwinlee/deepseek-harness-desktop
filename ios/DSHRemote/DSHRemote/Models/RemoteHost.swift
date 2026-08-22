import Foundation

enum RemoteHostTransport {
    case loopback
    case sameWiFi
    case unpairedLocalNetwork
    case tailscale
    case https
    case custom

    var label: String {
        switch self {
        case .loopback:
            "本机调试"
        case .sameWiFi:
            "同一 Wi-Fi"
        case .unpairedLocalNetwork:
            "局域网（未配对）"
        case .tailscale:
            "Tailscale"
        case .https:
            "HTTPS"
        case .custom:
            "自定义连接"
        }
    }
}

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

    var transport: RemoteHostTransport {
        let host = baseURL.host?.lowercased() ?? ""
        let scheme = baseURL.scheme?.lowercased()

        if host == "127.0.0.1" || host == "localhost" || host == "::1" {
            return .loopback
        }
        if scheme == "http", Self.isPrivateNetworkHost(host) {
            return accessToken == nil ? .unpairedLocalNetwork : .sameWiFi
        }
        if scheme == "https", host.hasSuffix(".ts.net") {
            return .tailscale
        }
        if scheme == "https" {
            return .https
        }
        return .custom
    }

    var transportLabel: String {
        transport.label
    }

    private static func isPrivateNetworkHost(_ host: String) -> Bool {
        if host.hasSuffix(".local") || !host.contains(".") {
            return true
        }
        let octets = host.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ 0...255 ~= $0 }) else { return false }
        return octets[0] == 10
            || (octets[0] == 172 && 16...31 ~= octets[1])
            || (octets[0] == 192 && octets[1] == 168)
            || (octets[0] == 169 && octets[1] == 254)
    }
}
