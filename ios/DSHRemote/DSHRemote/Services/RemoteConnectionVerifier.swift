import Foundation

enum RemoteConnectionError: LocalizedError {
    case invalidResponse
    case rejected
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "电脑没有返回有效的 Harness 页面。"
        case .rejected:
            return "电脑拒绝了 Remote 地址。请在 Desktop 中重新开启 Remote。"
        case .server(let statusCode):
            return "电脑返回了 HTTP \(statusCode)。"
        }
    }
}

enum RemoteConnectionVerifier {
    static func verify(_ baseURL: URL) async throws {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 10
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RemoteConnectionError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<400:
            return
        case 401, 403:
            throw RemoteConnectionError.rejected
        default:
            throw RemoteConnectionError.server(httpResponse.statusCode)
        }
    }
}
