import Foundation

enum RemoteEndpointError: LocalizedError, Equatable {
    case empty
    case invalidURL
    case insecureURL
    case unsupportedHost
    case embeddedCredentials
    case missingPairingCredential

    var errorDescription: String? {
        switch self {
        case .empty:
            return "请输入电脑上显示的 Remote 地址。"
        case .invalidURL:
            return "这不是有效的 Remote 地址。"
        case .insecureURL:
            return "公网地址必须使用 HTTPS；HTTP 只可用于本地局域网。"
        case .unsupportedHost:
            return "这个地址不是可识别的局域网地址，请改用 HTTPS。"
        case .embeddedCredentials:
            return "Remote 地址不能包含用户名或密码。"
        case .missingPairingCredential:
            return "同一 Wi-Fi 连接必须扫描 Desktop 的局域网配对二维码。"
        }
    }
}

struct RemoteConnectionDescriptor: Equatable {
    let baseURL: URL
    let accessToken: String?

    var importedURL: URL {
        RemoteEndpointValidator.connectionURL(for: baseURL, accessToken: accessToken) ?? baseURL
    }
}

enum RemoteEndpointValidator {
    static func normalizedURL(from input: String) throws -> URL {
        try connection(from: input).baseURL
    }

    static func connection(from input: String) throws -> RemoteConnectionDescriptor {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RemoteEndpointError.empty }

        if let connectionURL = URL(string: trimmed),
           ["harnessremote", "dshremote"].contains(connectionURL.scheme?.lowercased() ?? "") {
            return try normalizedConnection(connectionURL)
        }

        let endpoint = try endpointURL(from: trimmed, allowLocalHTTP: false)
        return RemoteConnectionDescriptor(baseURL: endpoint, accessToken: nil)
    }

    private static func endpointURL(from value: String, allowLocalHTTP: Bool) throws -> URL {
        let candidate = value.contains("://") ? value : "https://\(value)"
        guard var components = URLComponents(string: candidate),
              let host = components.host?.lowercased(),
              !host.isEmpty else {
            throw RemoteEndpointError.invalidURL
        }

        guard components.user == nil, components.password == nil else {
            throw RemoteEndpointError.embeddedCredentials
        }

        let scheme = components.scheme?.lowercased()
        guard scheme == "https" else {
            if scheme == "http", isLocalNetworkHost(host) {
                guard allowLocalHTTP else { throw RemoteEndpointError.missingPairingCredential }
                components.host = host
                components.path = "/"
                components.query = nil
                components.fragment = nil
                guard let url = components.url else { throw RemoteEndpointError.invalidURL }
                return url
            }
            if scheme == "http" { throw RemoteEndpointError.unsupportedHost }
            throw RemoteEndpointError.insecureURL
        }

        components.host = host
        components.path = "/"
        components.query = nil
        components.fragment = nil

        guard let url = components.url else { throw RemoteEndpointError.invalidURL }
        return url
    }

    static func connectionURL(for remoteURL: URL, accessToken: String? = nil) -> URL? {
        var components = URLComponents()
        components.scheme = "harnessremote"
        components.host = "connect"
        components.queryItems = [URLQueryItem(name: "url", value: remoteURL.absoluteString)]
        if let accessToken {
            components.queryItems?.append(URLQueryItem(name: "token", value: accessToken))
            components.queryItems?.append(URLQueryItem(name: "transport", value: "lan"))
        }
        return components.url
    }

    private static func normalizedConnection(_ url: URL) throws -> RemoteConnectionDescriptor {
        guard url.host == "connect",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let value = components.queryItems?.first(where: { $0.name == "url" })?.value else {
            throw RemoteEndpointError.invalidURL
        }
        let token = components.queryItems?.first(where: { $0.name == "token" })?.value
        if let token, !token.matchesRemoteAccessToken {
            throw RemoteEndpointError.invalidURL
        }
        let endpoint = try endpointURL(from: value, allowLocalHTTP: token != nil)
        if endpoint.scheme == "http", token == nil {
            throw RemoteEndpointError.invalidURL
        }
        return RemoteConnectionDescriptor(baseURL: endpoint, accessToken: token)
    }

    private static func isLocalNetworkHost(_ host: String) -> Bool {
        if host == "localhost" || host == "::1" || host.hasSuffix(".local") || !host.contains(".") {
            return true
        }
        let octets = host.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ 0...255 ~= $0 }) else { return false }
        return octets[0] == 10
            || octets[0] == 127
            || (octets[0] == 172 && 16...31 ~= octets[1])
            || (octets[0] == 192 && octets[1] == 168)
            || (octets[0] == 169 && octets[1] == 254)
    }
}

private extension String {
    var matchesRemoteAccessToken: Bool {
        utf8.count == 64 && utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }
}
