import Foundation

protocol HarnessRemoteClient: Sendable {
    var displayName: String { get }
    var isDemo: Bool { get }

    func describe() async throws -> RemoteHostDescription
    func sessions() async throws -> [RemoteSessionSummary]
    func conversation(sessionID: String) async throws -> [RemoteConversationItem]
    func send(_ text: String, to sessionID: String, steer: Bool) async throws
    func cancel(sessionID: String) async throws
    func respond(to interaction: RemoteInteraction, decision: RemoteInteractionDecision) async throws
    func liveEvents() -> AsyncStream<RemoteLiveEvent>
}

enum HarnessRemoteClientError: LocalizedError {
    case invalidResponse
    case mismatchedResponse
    case server(Int)
    case api(code: String, message: String)
    case unsupportedDecision

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "电脑没有返回有效的 Harness 数据。"
        case .mismatchedResponse:
            "电脑返回了无法匹配的响应。"
        case .server(let statusCode):
            statusCode == 401
                ? "局域网配对凭据已失效，请重新扫描 Desktop 二维码。"
                : "电脑返回了 HTTP \(statusCode)。"
        case .api(_, let message):
            message
        case .unsupportedDecision:
            "当前请求不支持这个操作。"
        }
    }
}

struct LiveHarnessRemoteClient: HarnessRemoteClient {
    let baseURL: URL
    let displayName: String
    let accessToken: String?

    init(baseURL: URL, displayName: String, accessToken: String? = nil) {
        self.baseURL = baseURL
        self.displayName = displayName
        self.accessToken = accessToken
    }

    var isDemo: Bool { false }

    func describe() async throws -> RemoteHostDescription {
        let response: HostDescriptionWire = try await call("host.describe", payload: EmptyPayload())
        guard !response.version.isEmpty else { throw HarnessRemoteClientError.invalidResponse }
        return RemoteHostDescription(version: response.version, attachedSessions: response.attachedSessions)
    }

    func sessions() async throws -> [RemoteSessionSummary] {
        let response: SessionListWire = try await call("session.list", payload: EmptyPayload())
        return response.items
            .filter { !$0.blank && $0.origin != "subagent" }
            .map { item in
                let title = item.projections?.values["title"]?.stringValue?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let projectName = item.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
                return RemoteSessionSummary(
                    id: item.sessionId,
                    title: title.flatMap { $0.isEmpty ? nil : $0 } ?? projectName ?? "未命名任务",
                    updatedAt: Date(timeIntervalSince1970: item.updatedAt / 1_000),
                    running: item.running,
                    projectName: projectName
                )
            }
    }

    func conversation(sessionID: String) async throws -> [RemoteConversationItem] {
        let response: SessionHistoryWire = try await call(
            "session.history",
            payload: SessionHistoryPayload(sessionId: sessionID, maxMessages: 80)
        )
        return ConversationFolder.fold(response.events)
    }

    func send(_ text: String, to sessionID: String, steer: Bool) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let _: AcceptedWire = try await call(
            "session.prompt",
            payload: SessionPromptPayload(
                sessionId: sessionID,
                mode: steer ? "steer" : "queue",
                content: [PromptTextPart(type: "text", text: trimmed)],
                clientTimeZone: TimeZone.current.identifier
            )
        )
    }

    func cancel(sessionID: String) async throws {
        let _: AcceptedWire = try await call(
            "session.cancel",
            payload: SessionIDPayload(sessionId: sessionID)
        )
    }

    func respond(to interaction: RemoteInteraction, decision: RemoteInteractionDecision) async throws {
        let result: JSONValue
        switch (interaction.kind, decision) {
        case (.approval, .allowOnce), (.approval, .reject):
            guard let approvalID = interaction.approvalID else {
                throw HarnessRemoteClientError.unsupportedDecision
            }
            let outcome = decision == .allowOnce ? "allowed-once" : "rejected"
            result = .object([
                "ok": .bool(true),
                "value": .object([
                    "sessionId": .string(interaction.sessionID),
                    "approvalId": .string(approvalID),
                    "outcome": .string(outcome),
                ]),
            ])
        case (.questions, .answer(let answers)):
            let encodedAnswers = answers.map { answer -> JSONValue in
                var value: [String: JSONValue] = [
                    "id": .string(answer.questionID),
                    "selected": .array(answer.selected.map(JSONValue.string)),
                ]
                if let custom = answer.custom, !custom.isEmpty {
                    value["custom"] = .string(custom)
                }
                return .object(value)
            }
            result = .object([
                "ok": .bool(true),
                "value": .object([
                    "sessionId": .string(interaction.sessionID),
                    "answer": .object(["answers": .array(encodedAnswers)]),
                ]),
            ])
        case (.questions, .cancelQuestions):
            result = .object([
                "ok": .bool(false),
                "error": .object([
                    "code": .string("cancelled"),
                    "message": .string("the user closed this question request"),
                    "details": .object([:]),
                ]),
            ])
        default:
            throw HarnessRemoteClientError.unsupportedDecision
        }

        let envelope = InteractionResponseEnvelope(
            type: "client-response",
            rpcId: interaction.rpcID,
            result: result
        )
        var request = URLRequest(url: endpoint("api/respond"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorize(&request)
        request.httpBody = try JSONEncoder().encode(envelope)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HarnessRemoteClientError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw HarnessRemoteClientError.server(httpResponse.statusCode)
        }
        let receipt = try JSONDecoder().decode(InteractionReceipt.self, from: data)
        guard receipt.accepted else {
            throw HarnessRemoteClientError.api(
                code: "interaction-rejected",
                message: receipt.reason ?? "电脑已拒绝这次操作。"
            )
        }
    }

    func liveEvents() -> AsyncStream<RemoteLiveEvent> {
        let streamURL = webSocketEndpoint("api/events.mux")
        return AsyncStream { continuation in
            let receiver = Task {
                while !Task.isCancelled {
                    var request = URLRequest(url: streamURL)
                    request.timeoutInterval = 20
                    authorize(&request)
                    let socket = URLSession.shared.webSocketTask(with: request)
                    socket.resume()
                    do {
                        while !Task.isCancelled {
                            let message = try await socket.receive()
                            let data: Data
                            switch message {
                            case .string(let value): data = Data(value.utf8)
                            case .data(let value): data = value
                            @unknown default: continue
                            }
                            guard let envelope = try? JSONDecoder().decode(LiveEventEnvelope.self, from: data),
                                  let event = LiveEventParser.parse(envelope) else {
                                continue
                            }
                            continuation.yield(event)
                        }
                    } catch {
                        socket.cancel(with: .goingAway, reason: nil)
                        if !Task.isCancelled {
                            try? await Task.sleep(for: .seconds(1.5))
                        }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in receiver.cancel() }
        }
    }

    private func call<Payload: Encodable, Value: Decodable>(
        _ method: String,
        payload: Payload
    ) async throws -> Value {
        let rpcID = UUID().uuidString.lowercased()
        let envelope = RPCRequestEnvelope(
            type: "client-request",
            rpcId: rpcID,
            method: method,
            payload: payload
        )
        var request = URLRequest(url: endpoint("api/\(method)"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorize(&request)
        request.httpBody = try JSONEncoder().encode(envelope)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HarnessRemoteClientError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw HarnessRemoteClientError.server(httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(RPCResponseEnvelope<Value>.self, from: data)
        guard decoded.rpcId == rpcID else { throw HarnessRemoteClientError.mismatchedResponse }
        if decoded.result.ok, let value = decoded.result.value {
            return value
        }
        if let error = decoded.result.error {
            throw HarnessRemoteClientError.api(code: error.code, message: error.message)
        }
        throw HarnessRemoteClientError.invalidResponse
    }

    private func endpoint(_ path: String) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/\(path)"
        components.query = nil
        components.fragment = nil
        return components.url!
    }

    private func webSocketEndpoint(_ path: String) -> URL {
        var components = URLComponents(url: endpoint(path), resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        return components.url!
    }

    private func authorize(_ request: inout URLRequest) {
        guard let accessToken else { return }
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    }
}

actor DemoHarnessRemoteClient: HarnessRemoteClient {
    nonisolated let displayName = "审核演示"
    nonisolated let isDemo = true

    private let sessionID = "review-demo-session"
    private var running = false
    private var items: [RemoteConversationItem] = [
        RemoteConversationItem(
            id: "demo-user",
            kind: .user,
            title: nil,
            text: "请检查登录流程，并给出上线前的风险清单。",
            time: Date().addingTimeInterval(-180)
        ),
        RemoteConversationItem(
            id: "demo-tool",
            kind: .tool,
            title: "读取 4 个项目文件",
            text: "已在你的电脑上安全完成",
            time: Date().addingTimeInterval(-160)
        ),
        RemoteConversationItem(
            id: "demo-assistant",
            kind: .assistant,
            title: nil,
            text: "我发现两个需要先处理的问题：登录态过期后的恢复路径，以及错误提示没有告诉用户下一步怎么做。我已经整理了一份修复计划，请你确认。",
            time: Date().addingTimeInterval(-150)
        ),
    ]

    func describe() async throws -> RemoteHostDescription {
        RemoteHostDescription(version: "Review Demo", attachedSessions: 1)
    }

    func sessions() async throws -> [RemoteSessionSummary] {
        [
            RemoteSessionSummary(
                id: sessionID,
                title: "登录流程上线检查",
                updatedAt: items.last?.time ?? Date(),
                running: running,
                projectName: "Sample Project"
            ),
        ]
    }

    func conversation(sessionID: String) async throws -> [RemoteConversationItem] {
        items
    }

    func send(_ text: String, to sessionID: String, steer: Bool) async throws {
        let now = Date()
        items.append(RemoteConversationItem(
            id: UUID().uuidString,
            kind: .user,
            title: steer ? "中途补充" : nil,
            text: text,
            time: now
        ))
        running = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            await finishDemoReply()
        }
    }

    func cancel(sessionID: String) async throws {
        running = false
        items.append(RemoteConversationItem(
            id: UUID().uuidString,
            kind: .status,
            title: nil,
            text: "任务已由你停止",
            time: Date()
        ))
    }

    func respond(to interaction: RemoteInteraction, decision: RemoteInteractionDecision) async throws {
        let message: String
        switch decision {
        case .answer(let answers):
            message = "已确认：\(answers.flatMap(\.selected).joined(separator: "、"))"
        case .allowOnce:
            message = "已允许本次操作"
        case .reject:
            message = "已拒绝本次操作"
        case .cancelQuestions:
            message = "已暂不处理确认问题"
        }
        items.append(RemoteConversationItem(
            id: UUID().uuidString,
            kind: .status,
            title: nil,
            text: message,
            time: Date()
        ))
    }

    nonisolated func liveEvents() -> AsyncStream<RemoteLiveEvent> {
        AsyncStream { continuation in
            let task = Task {
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { return }
                let question = RemoteQuestion(
                    id: "release-choice",
                    header: "需要确认",
                    question: "是否按这份计划修复后再上线？",
                    detail: "1. 补齐登录态恢复\n2. 改写错误提示\n3. 增加回归测试",
                    options: [
                        .init(label: "批准计划", description: "继续在电脑上执行修复"),
                        .init(label: "先不执行", description: "保留当前结果，不修改项目"),
                    ],
                    allowsMultipleSelection: false
                )
                continuation.yield(.interaction(RemoteInteraction(
                    id: "question:review-demo",
                    rpcID: "review-demo",
                    sessionID: "review-demo-session",
                    approvalID: nil,
                    kind: .questions([question])
                )))
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func finishDemoReply() {
        guard running else { return }
        running = false
        items.append(RemoteConversationItem(
            id: UUID().uuidString,
            kind: .assistant,
            title: nil,
            text: "收到。我会把这条补充加入当前任务；所有执行仍发生在你的电脑上。",
            time: Date()
        ))
    }
}

private struct EmptyPayload: Codable {}
private struct SessionIDPayload: Codable { let sessionId: String }
private struct SessionHistoryPayload: Codable { let sessionId: String; let maxMessages: Int }
private struct PromptTextPart: Codable { let type: String; let text: String }
private struct SessionPromptPayload: Codable {
    let sessionId: String
    let mode: String
    let content: [PromptTextPart]
    let clientTimeZone: String
}

private struct RPCRequestEnvelope<Payload: Encodable>: Encodable {
    let type: String
    let rpcId: String
    let method: String
    let payload: Payload
}

private struct RPCResponseEnvelope<Value: Decodable>: Decodable {
    let rpcId: String
    let result: RPCResultWire<Value>
}

private struct RPCResultWire<Value: Decodable>: Decodable {
    let ok: Bool
    let value: Value?
    let error: APIErrorWire?
}

private struct APIErrorWire: Decodable {
    let code: String
    let message: String
}

private struct HostDescriptionWire: Decodable {
    let version: String
    let attachedSessions: Int
}

private struct SessionListWire: Decodable { let items: [SessionSummaryWire] }
private struct SessionSummaryWire: Decodable {
    let sessionId: String
    let updatedAt: Double
    let running: Bool
    let blank: Bool
    let origin: String?
    let cwd: String?
    let projections: SessionProjectionsWire?
}
private struct SessionProjectionsWire: Decodable {
    let values: [String: JSONValue]
}

private struct SessionHistoryWire: Decodable {
    let events: [HistoryEntryWire]
}
private struct HistoryEntryWire: Decodable {
    let event: SessionEventWire
    let view: JSONValue?
}
private struct SessionEventWire: Decodable {
    let type: String
    let seq: Int
    let time: Double
    let data: JSONValue
}

private struct AcceptedWire: Decodable { let accepted: Bool }

private struct InteractionResponseEnvelope: Encodable {
    let type: String
    let rpcId: String
    let result: JSONValue
}
private struct InteractionReceipt: Decodable {
    let accepted: Bool
    let reason: String?
}
private struct LiveEventEnvelope: Decodable {
    let rpcId: String
    let payload: JSONValue
}

private enum LiveEventParser {
    static func parse(_ envelope: LiveEventEnvelope) -> RemoteLiveEvent? {
        guard let payload = envelope.payload.objectValue,
              let type = payload["type"]?.stringValue,
              let sessionID = payload["sessionId"]?.stringValue else {
            return nil
        }

        switch type {
        case "session/event", "session/queue", "session/projection":
            return .sessionChanged(sessionID)
        case "approval/requested":
            guard let approvalID = payload["approvalId"]?.stringValue,
                  let toolName = payload["toolName"]?.stringValue else { return nil }
            return .interaction(RemoteInteraction(
                id: "approval:\(approvalID)",
                rpcID: envelope.rpcId,
                sessionID: sessionID,
                approvalID: approvalID,
                kind: .approval(toolName: toolName, reason: payload["reason"]?.stringValue)
            ))
        case "approval/resolved":
            guard let approvalID = payload["approvalId"]?.stringValue else { return nil }
            return .interactionResolved("approval:\(approvalID)")
        case "question/requested":
            guard let rawQuestions = payload["questions"]?.arrayValue else { return nil }
            let questions = rawQuestions.compactMap(parseQuestion)
            guard !questions.isEmpty else { return nil }
            return .interaction(RemoteInteraction(
                id: "question:\(envelope.rpcId)",
                rpcID: envelope.rpcId,
                sessionID: sessionID,
                approvalID: nil,
                kind: .questions(questions)
            ))
        case "question/resolved":
            guard let rpcID = payload["questionRpcId"]?.stringValue else { return nil }
            return .interactionResolved("question:\(rpcID)")
        default:
            return nil
        }
    }

    private static func parseQuestion(_ value: JSONValue) -> RemoteQuestion? {
        guard let object = value.objectValue,
              let id = object["id"]?.stringValue,
              let question = object["question"]?.stringValue else { return nil }
        let options = object["options"]?.arrayValue?.compactMap { option -> RemoteQuestion.Option? in
            guard let value = option.objectValue,
                  let label = value["label"]?.stringValue else { return nil }
            return .init(label: label, description: value["description"]?.stringValue)
        } ?? []
        return RemoteQuestion(
            id: id,
            header: object["header"]?.stringValue,
            question: question,
            detail: object["detail"]?.stringValue,
            options: options,
            allowsMultipleSelection: object["multiSelect"]?.boolValue ?? false
        )
    }
}

private enum ConversationFolder {
    static func fold(_ entries: [HistoryEntryWire]) -> [RemoteConversationItem] {
        let completedToolCalls = Set(entries.compactMap { entry -> String? in
            guard entry.event.type == "tool/result",
                  let data = entry.event.data.objectValue,
                  let message = data["message"]?.objectValue,
                  let source = message["source"]?.objectValue else { return nil }
            return source["callId"]?.stringValue
        })
        var output: [RemoteConversationItem] = []
        var partial: (id: String, text: String, time: Date)?

        for entry in entries {
            let event = entry.event
            let date = Date(timeIntervalSince1970: event.time / 1_000)
            switch event.type {
            case "user/message":
                guard let data = event.data.objectValue,
                      data["source"]?.objectValue?["kind"]?.stringValue == "user",
                      let text = textContent(data["content"]) else { continue }
                output.append(RemoteConversationItem(
                    id: "user:\(event.seq)", kind: .user, title: nil, text: text, time: date
                ))
            case "assistant/message":
                partial = nil
                guard let data = event.data.objectValue,
                      let message = data["message"]?.objectValue,
                      let text = textContent(message["content"]) else { continue }
                output.append(RemoteConversationItem(
                    id: "assistant:\(event.seq)", kind: .assistant, title: nil, text: text, time: date
                ))
            case "assistant/chunk":
                guard let data = event.data.objectValue,
                      let chunk = data["chunk"]?.objectValue,
                      chunk["type"]?.stringValue == "block-end",
                      let block = chunk["block"]?.objectValue,
                      block["type"]?.stringValue == "text",
                      let text = block["text"]?.stringValue,
                      !text.isEmpty else { continue }
                partial = ("stream:\(event.seq)", text, date)
            case "tool/call":
                guard let data = event.data.objectValue else { continue }
                let callID = data["callId"]?.stringValue
                let toolName = data["name"]?.stringValue ?? "工具"
                let view = entry.view?.objectValue?["view"]?.objectValue
                let title = safeToolTitle(view: view, fallbackName: toolName)
                let status = safeToolDetail(
                    view: view,
                    completed: callID.map(completedToolCalls.contains) == true
                )
                output.append(RemoteConversationItem(
                    id: "tool:\(event.seq)", kind: .tool, title: title, text: status, time: date
                ))
            default:
                continue
            }
        }

        if let partial {
            output.append(RemoteConversationItem(
                id: partial.id,
                kind: .assistant,
                title: nil,
                text: partial.text,
                time: partial.time,
                isStreaming: true
            ))
        }
        return output
    }

    private static func textContent(_ value: JSONValue?) -> String? {
        let parts = value?.arrayValue?.compactMap { item -> String? in
            guard let block = item.objectValue,
                  block["type"]?.stringValue == "text" else { return nil }
            return block["text"]?.stringValue
        } ?? []
        let text = parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func readableToolName(_ name: String) -> String {
        name.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private static func safeToolTitle(view: [String: JSONValue]?, fallbackName: String) -> String {
        switch view?["kind"]?.stringValue {
        case "execute": return "在电脑上执行操作"
        case "read": return "读取电脑上的任务结果"
        case "edit": return "修改项目文件"
        default: return view?["title"]?.stringValue ?? readableToolName(fallbackName)
        }
    }

    private static func safeToolDetail(view: [String: JSONValue]?, completed: Bool) -> String {
        if let summary = view?["content"]?.arrayValue?.compactMap({ block -> String? in
            guard let value = block.objectValue,
                  value["type"]?.stringValue == "text" else { return nil }
            return value["text"]?.stringValue
        }).first, !summary.isEmpty {
            return summary
        }
        return completed ? "已在电脑上完成" : "正在电脑上执行"
    }
}
