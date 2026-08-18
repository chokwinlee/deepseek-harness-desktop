import Foundation

enum RemoteEndpointError: LocalizedError, Equatable {
    case empty
    case invalidURL
    case insecureURL
    case unsupportedHost
    case embeddedCredentials

    var errorDescription: String? {
        switch self {
        case .empty:
            return "请输入电脑上显示的 Remote 地址。"
        case .invalidURL:
            return "这不是有效的 Remote 地址。"
        case .insecureURL:
            return "Remote 只接受 Tailscale Serve 提供的 HTTPS 地址。"
        case .unsupportedHost:
            return "地址必须是 Tailscale 的 .ts.net 设备域名。"
        case .embeddedCredentials:
            return "Remote 地址不能包含用户名或密码。"
        }
    }
}

enum RemoteEndpointValidator {
    static func normalizedURL(from input: String) throws -> URL {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RemoteEndpointError.empty }

        if let connectionURL = URL(string: trimmed), connectionURL.scheme == "dshremote" {
            return try normalizedConnectionURL(connectionURL)
        }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var components = URLComponents(string: candidate),
              let host = components.host?.lowercased(),
              !host.isEmpty else {
            throw RemoteEndpointError.invalidURL
        }

        guard components.scheme?.lowercased() == "https" else {
#if DEBUG
            if components.scheme?.lowercased() == "http", isLoopback(host) {
                components.path = "/"
                components.query = nil
                components.fragment = nil
                guard let url = components.url else { throw RemoteEndpointError.invalidURL }
                return url
            }
#endif
            throw RemoteEndpointError.insecureURL
        }

        guard components.user == nil, components.password == nil else {
            throw RemoteEndpointError.embeddedCredentials
        }

        guard host.hasSuffix(".ts.net") else {
            throw RemoteEndpointError.unsupportedHost
        }

        components.host = host
        components.path = "/"
        components.query = nil
        components.fragment = nil

        guard let url = components.url else { throw RemoteEndpointError.invalidURL }
        return url
    }

    static func connectionURL(for remoteURL: URL) -> URL? {
        var components = URLComponents()
        components.scheme = "dshremote"
        components.host = "connect"
        components.queryItems = [URLQueryItem(name: "url", value: remoteURL.absoluteString)]
        return components.url
    }

    private static func normalizedConnectionURL(_ url: URL) throws -> URL {
        guard url.host == "connect",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let value = components.queryItems?.first(where: { $0.name == "url" })?.value else {
            throw RemoteEndpointError.invalidURL
        }
        return try normalizedURL(from: value)
    }

#if DEBUG
    private static func isLoopback(_ host: String) -> Bool {
        host == "127.0.0.1" || host == "localhost" || host == "::1"
    }
#endif
}
