import Foundation

enum RemoteConnectionError: LocalizedError {
    case invalidResponse
    case rejected
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return remoteLocalized("电脑没有返回有效的 Harness 页面。")
        case .rejected:
            return remoteLocalized("电脑拒绝了 Remote 地址。请在 Desktop 中重新开启 Remote。")
        case .server(let statusCode):
            return remoteLocalizedFormat("电脑返回了 HTTP %lld。", statusCode)
        }
    }
}

enum RemoteConnectionVerifier {
    static func verify(_ connection: RemoteConnectionDescriptor) async throws {
        let client = LiveHarnessRemoteClient(
            baseURL: connection.baseURL,
            displayName: connection.baseURL.host ?? "Harness",
            accessToken: connection.accessToken
        )
        _ = try await client.describe()
    }
}
