import Foundation

protocol HarnessRemoteClient: Sendable {
    var displayName: String { get }
    var isDemo: Bool { get }

    func describe() async throws -> RemoteHostDescription
    func sessions() async throws -> [RemoteSessionSummary]
    func conversation(sessionID: String, maxMessages: Int) async throws -> RemoteConversationSnapshot
    func send(_ text: String, to sessionID: String, steer: Bool) async throws
    func updateQueue(sessionID: String, itemID: String, action: RemoteQueueAction) async throws
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

    func conversation(sessionID: String, maxMessages: Int) async throws -> RemoteConversationSnapshot {
        let response: SessionHistoryWire = try await call(
            "session.history",
            payload: SessionHistoryPayload(sessionId: sessionID, maxMessages: maxMessages)
        )
        return ConversationFolder.fold(response)
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

    func updateQueue(sessionID: String, itemID: String, action: RemoteQueueAction) async throws {
        let wireAction: QueueActionWire
        switch action {
        case .edit(let text):
            wireAction = QueueActionWire(
                kind: "edit",
                content: [PromptTextPart(type: "text", text: text)]
            )
        case .remove:
            wireAction = QueueActionWire(kind: "remove", content: nil)
        case .steer:
            wireAction = QueueActionWire(kind: "steer", content: nil)
        }
        let _: AcceptedWire = try await call(
            "session.updateQueue",
            payload: SessionUpdateQueuePayload(sessionId: sessionID, itemId: itemID, action: wireAction)
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
    nonisolated let displayName = "体验模式"
    nonisolated let isDemo = true

    private let sessionID = "review-demo-session"
    private var running = false
    private static let demoInstructionText = """
    <system-reminder>
    The following workspace instructions may be relevant to your work. Use them as guidance when applicable.

    Instructions from:

    [AGENTS.md](AGENTS.md)

    # Project rules

    - Read `docs/architecture.md` before changing packages.
    - Run focused tests before release.
    - Keep credentials and model calls on the user's computer.
    </system-reminder>
    """
    private var items: [RemoteConversationItem] = [
        RemoteConversationItem(
            id: "demo-context",
            kind: .context,
            title: "项目指令",
            text: "AGENTS.md · 已载入",
            time: Date().addingTimeInterval(-185),
            details: [
                RemoteDetailSection(
                    id: "instruction-sources",
                    title: "指令来源",
                    content: "AGENTS.md\t已载入",
                    kind: .list
                ),
                RemoteDetailSection(
                    id: "context-raw",
                    title: "模型接收的内容",
                    content: DemoHarnessRemoteClient.demoInstructionText,
                    kind: .text
                ),
            ]
        ),
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
            time: Date().addingTimeInterval(-160),
            state: .succeeded,
            toolCard: .read,
            toolCategory: "read",
            details: [
                RemoteDetailSection(
                    id: "demo-tool-files",
                    title: "FILES",
                    content: "Sources/Auth/SessionStore.swift\nSources/Auth/LoginView.swift\nTests/AuthTests.swift\nREADME.md",
                    kind: .list
                ),
            ],
            metadata: ["4 files", "320 ms"]
        ),
        RemoteConversationItem(
            id: "demo-assistant",
            kind: .assistant,
            title: nil,
            text: "我发现两个需要先处理的问题：登录态过期后的恢复路径，以及错误提示没有告诉用户下一步怎么做。我已经整理了一份修复计划，请你确认。",
            time: Date().addingTimeInterval(-150),
            reasoning: "先核对登录状态的生命周期，再沿着错误处理分支检查用户是否能恢复操作。最后用现有测试确认风险是否已经被覆盖。",
            metadata: ["deepseek-chat", "1.7K tokens", "4.2 s"]
        ),
    ]

    private var demoTrajectory: [RemoteTrajectoryRecord] = [
        RemoteTrajectoryRecord(
            id: "demo-trajectory-context", sequence: 0, turn: nil, step: nil, kind: .context,
            title: "项目指令", summary: "AGENTS.md · 已载入", time: Date().addingTimeInterval(-185),
            duration: nil, state: .succeeded,
            details: [
                RemoteDetailSection(
                    id: "instruction-sources", title: "指令来源",
                    content: "AGENTS.md\t已载入", kind: .list
                ),
                RemoteDetailSection(
                    id: "context-raw", title: "模型接收的内容",
                    content: DemoHarnessRemoteClient.demoInstructionText, kind: .text
                ),
            ]
        ),
        RemoteTrajectoryRecord(
            id: "demo-trajectory-input", sequence: 1, turn: 0, step: nil, kind: .input,
            title: "User", summary: "检查登录流程并给出风险清单", time: Date().addingTimeInterval(-180),
            duration: nil, state: .succeeded
        ),
        RemoteTrajectoryRecord(
            id: "demo-trajectory-request", sequence: 2, turn: 0, step: 0, kind: .request,
            title: "Model request", summary: "整理上下文并请求分析", time: Date().addingTimeInterval(-174),
            duration: 0.12, state: .succeeded,
            details: [
                RemoteDetailSection(
                    id: "demo-request-payload", title: "PAYLOAD",
                    content: "model: deepseek-chat\nmode: normal\nproject: Sample Project", kind: .code(language: "yaml")
                ),
            ]
        ),
        RemoteTrajectoryRecord(
            id: "demo-trajectory-thinking", sequence: 3, turn: 0, step: 0, kind: .assistant,
            title: "Think", summary: "检查登录状态生命周期和错误恢复路径", time: Date().addingTimeInterval(-170),
            duration: 1.8, state: .succeeded
        ),
        RemoteTrajectoryRecord(
            id: "demo-trajectory-tool", sequence: 4, turn: 0, step: 1, kind: .tool,
            title: "Read", summary: "读取 4 个项目文件", time: Date().addingTimeInterval(-160),
            duration: 0.32, state: .succeeded,
            details: [
                RemoteDetailSection(
                    id: "demo-trajectory-files", title: "RESULT",
                    content: "Sources/Auth/SessionStore.swift\nSources/Auth/LoginView.swift\nTests/AuthTests.swift\nREADME.md", kind: .list
                ),
            ]
        ),
        RemoteTrajectoryRecord(
            id: "demo-trajectory-answer", sequence: 5, turn: 0, step: 2, kind: .assistant,
            title: "Assistant", summary: "整理两个上线前风险和修复计划", time: Date().addingTimeInterval(-150),
            duration: 2.4, state: .succeeded
        ),
        RemoteTrajectoryRecord(
            id: "demo-trajectory-end", sequence: 6, turn: 0, step: 2, kind: .lifecycle,
            title: "Turn complete", summary: "等待用户确认", time: Date().addingTimeInterval(-149),
            duration: 4.62, state: .succeeded
        ),
    ]

    func describe() async throws -> RemoteHostDescription {
        RemoteHostDescription(version: "Offline Demo", attachedSessions: 1)
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

    func conversation(sessionID: String, maxMessages: Int) async throws -> RemoteConversationSnapshot {
        RemoteConversationSnapshot(
            items: items,
            hasMore: false,
            stats: RemoteConversationStats(
                turns: 1,
                steps: 2,
                llmDuration: 4.2,
                toolDuration: 0.32,
                inputTokens: 1_284,
                outputTokens: 436
            ),
            trajectory: demoTrajectory
        )
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
            finishDemoReply()
        }
    }

    func updateQueue(sessionID: String, itemID: String, action: RemoteQueueAction) async throws {}

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
private struct SessionUpdateQueuePayload: Codable {
    let sessionId: String
    let itemId: String
    let action: QueueActionWire
}
private struct QueueActionWire: Codable {
    let kind: String
    let content: [PromptTextPart]?
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
    let hasMore: Bool
    let projections: SessionProjectionsWire?
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
        case "session/event", "session/projection":
            return .sessionChanged(sessionID)
        case "session/queue":
            let items = payload["items"]?.arrayValue?.compactMap(parseQueueItem) ?? []
            return .queueChanged(sessionID: sessionID, items: items)
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

    private static func parseQueueItem(_ value: JSONValue) -> RemoteQueuedMessage? {
        guard let object = value.objectValue,
              let id = object["id"]?.stringValue,
              let placementValue = object["placement"]?.stringValue,
              let placement = RemoteQueuedMessage.Placement(rawValue: placementValue) else {
            return nil
        }
        let message = object["message"]?.objectValue
        let text = textContent(message?["content"])
        let preview = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return RemoteQueuedMessage(
            id: id,
            placement: placement,
            preview: preview.flatMap { $0.isEmpty ? nil : $0 } ?? "等待中的消息",
            text: text
        )
    }

    private static func textContent(_ value: JSONValue?) -> String? {
        let parts = value?.arrayValue?.compactMap { item -> String? in
            guard let block = item.objectValue,
                  block["type"]?.stringValue == "text" else { return nil }
            return block["text"]?.stringValue
        } ?? []
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}

private enum ConversationFolder {
    private struct StreamBlock {
        var type: String
        var text: String
    }

    private struct PartialAssistant {
        var turn: Int
        var step: Int
        var firstSequence: Int
        var time: Date
        var blocks: [Int: StreamBlock] = [:]
    }

    private struct InstructionChange {
        let path: String
        let action: String
        let scope: String
    }

    private struct ContextPresentation {
        let preview: String
        let details: [RemoteDetailSection]
    }

    static func fold(_ history: SessionHistoryWire) -> RemoteConversationSnapshot {
        let entries = history.events
        let toolResults = Dictionary(uniqueKeysWithValues: entries.compactMap { entry -> (String, HistoryEntryWire)? in
            guard entry.event.type == "tool/result", let callID = toolResultCallID(entry) else { return nil }
            return (callID, entry)
        })
        let stepStarts = Dictionary(uniqueKeysWithValues: entries.compactMap { entry -> (String, Double)? in
            guard entry.event.type == "step/start",
                  let data = entry.event.data.objectValue,
                  let turn = int(data["turn"]),
                  let step = int(data["step"]) else { return nil }
            return ("\(turn):\(step)", entry.event.time)
        })
        let turnStarts = Dictionary(uniqueKeysWithValues: entries.compactMap { entry -> (Int, Double)? in
            guard entry.event.type == "turn/start",
                  let turn = int(entry.event.data.objectValue?["turn"]) else { return nil }
            return (turn, entry.event.time)
        })
        var output: [RemoteConversationItem] = []
        var partial: PartialAssistant?

        for entry in entries {
            let event = entry.event
            let date = Date(timeIntervalSince1970: event.time / 1_000)
            switch event.type {
            case "user/message":
                guard let data = event.data.objectValue,
                      let text = textContent(data["content"]) else { continue }
                let source = data["source"]?.objectValue
                let sourceKind = source?["kind"]?.stringValue ?? "context"
                if sourceKind == "user" {
                    output.append(RemoteConversationItem(
                        id: "user:\(event.seq)", sequence: event.seq, kind: .user,
                        title: nil, text: text, time: date
                    ))
                } else {
                    output.append(contextItem(
                        sequence: event.seq,
                        sourceKind: sourceKind,
                        source: source,
                        text: text,
                        time: date
                    ))
                }
            case "assistant/message":
                guard let data = event.data.objectValue,
                      let message = data["message"]?.objectValue else { continue }
                let turn = int(data["turn"])
                let step = int(data["step"])
                if partial?.turn == turn && partial?.step == step { partial = nil }
                let text = textContent(message["content"]) ?? ""
                let reasoning = reasoningContent(message["content"])
                guard !text.isEmpty || reasoning != nil else { continue }
                var item = RemoteConversationItem(
                    id: "assistant:\(event.seq)", sequence: event.seq, kind: .assistant,
                    title: nil, text: text, time: date, state: .succeeded,
                    reasoning: reasoning
                )
                if let source = message["source"]?.objectValue {
                    let provider = source["provider"]?.stringValue
                    let model = source["model"]?.stringValue
                    item.metadata.append([provider, model].compactMap { $0 }.joined(separator: " · "))
                }
                if let usage = data["usage"]?.objectValue,
                   let outputTokens = int(usage["outputTokens"]) {
                    item.metadata.append("\(outputTokens) tokens")
                }
                if let turn, let step, let started = stepStarts["\(turn):\(step)"] {
                    item.metadata.append(durationLabel(milliseconds: event.time - started))
                }
                item.metadata.removeAll(where: \.isEmpty)
                output.append(item)
            case "assistant/chunk":
                guard let data = event.data.objectValue,
                      let turn = int(data["turn"]),
                      let step = int(data["step"]),
                      let chunk = data["chunk"]?.objectValue,
                      let type = chunk["type"]?.stringValue else { continue }
                if partial?.turn != turn || partial?.step != step {
                    partial = PartialAssistant(
                        turn: turn, step: step, firstSequence: event.seq, time: date
                    )
                }
                updatePartial(&partial, chunk: chunk, type: type)
            case "tool/call":
                guard let data = event.data.objectValue,
                      let callID = data["callId"]?.stringValue else { continue }
                output.append(toolItem(call: entry, result: toolResults[callID]))
            case "turn/end":
                guard let data = event.data.objectValue,
                      let reason = data["reason"]?.objectValue,
                      let reasonKind = reason["kind"]?.stringValue,
                      reasonKind != "completed" else { continue }
                output.append(turnStatusItem(event: event, reason: reason, time: date))
            case "llm/retry":
                if let data = event.data.objectValue,
                   partial?.turn == int(data["turn"]),
                   partial?.step == int(data["step"]) {
                    partial = nil
                }
                let data = event.data.objectValue
                let delay = data?["delayMs"]?.numberValue.map(durationLabel(milliseconds:))
                output.append(RemoteConversationItem(
                    id: "retry:\(event.seq)", sequence: event.seq, kind: .status,
                    title: "模型请求正在重试",
                    text: delay.map { "将在 \($0) 后重试" } ?? "连接或模型请求暂时失败，Harness 会自动重试。",
                    time: date, state: .running
                ))
            case "compaction/summary":
                guard let data = event.data.objectValue,
                      let summary = data["summary"]?.stringValue else { continue }
                output.append(RemoteConversationItem(
                    id: "compaction:\(event.seq)", sequence: event.seq, kind: .status,
                    title: "上下文已整理", text: "较早内容已压缩为摘要。", time: date,
                    state: .info,
                    details: [RemoteDetailSection(
                        id: "summary", title: "压缩摘要", content: summary, kind: .text
                    )]
                ))
            default:
                continue
            }
        }

        if let partial {
            let text = partial.blocks.sorted(by: { $0.key < $1.key })
                .filter { $0.value.type == "text" }
                .map(\.value.text)
                .joined(separator: "\n")
            let reasoning = partial.blocks.sorted(by: { $0.key < $1.key })
                .filter { $0.value.type == "reasoning" }
                .map(\.value.text)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty || !reasoning.isEmpty {
                output.append(RemoteConversationItem(
                    id: "assistant-stream:\(partial.turn):\(partial.step)",
                    sequence: partial.firstSequence,
                    kind: .assistant,
                    title: nil,
                    text: text,
                    time: partial.time,
                    state: .running,
                    reasoning: reasoning.isEmpty ? nil : reasoning,
                    isStreaming: true
                ))
            }
        }

        output.sort { lhs, rhs in
            lhs.sequence == rhs.sequence ? lhs.id < rhs.id : lhs.sequence < rhs.sequence
        }
        return RemoteConversationSnapshot(
            items: output,
            hasMore: history.hasMore,
            stats: stats(from: history.projections),
            trajectory: buildTrajectory(
                entries,
                toolResults: toolResults,
                stepStarts: stepStarts,
                turnStarts: turnStarts
            )
        )
    }

    private static func buildTrajectory(
        _ entries: [HistoryEntryWire],
        toolResults: [String: HistoryEntryWire],
        stepStarts: [String: Double],
        turnStarts: [Int: Double]
    ) -> [RemoteTrajectoryRecord] {
        let orderedTurnStarts = entries.compactMap { entry -> (sequence: Int, turn: Int)? in
            guard entry.event.type == "turn/start",
                  let turn = int(entry.event.data.objectValue?["turn"]) else { return nil }
            return (entry.event.seq, turn)
        }
        var records: [RemoteTrajectoryRecord] = []
        var activeTurn: Int?
        var activeStep: Int?

        for entry in entries {
            let event = entry.event
            let data = event.data.objectValue ?? [:]
            let time = Date(timeIntervalSince1970: event.time / 1_000)
            if event.type == "turn/start" { activeTurn = int(data["turn"]) }
            if event.type == "step/start" { activeStep = int(data["step"]) }

            switch event.type {
            case "user/message":
                guard let text = textContent(data["content"]) else { break }
                let source = data["source"]?.objectValue
                let sourceKind = source?["kind"]?.stringValue ?? "context"
                let turn = activeTurn ?? orderedTurnStarts.first(where: { $0.sequence > event.seq })?.turn
                let isUser = sourceKind == "user"
                let presentation = contextPresentation(
                    sourceKind: sourceKind,
                    source: source,
                    text: text
                )
                records.append(RemoteTrajectoryRecord(
                    id: "trajectory-message:\(event.seq)",
                    sequence: event.seq,
                    turn: turn,
                    step: activeStep,
                    kind: isUser ? .input : .context,
                    title: isUser ? "用户消息" : contextSourceLabel(sourceKind),
                    summary: isUser
                        ? firstMeaningfulLine(text, fallback: "消息内容")
                        : presentation.preview,
                    time: time,
                    duration: nil,
                    state: .succeeded,
                    details: isUser
                        ? [RemoteDetailSection(
                            id: "message", title: "完整内容", content: limited(text), kind: .text
                        )]
                        : presentation.details
                ))
            case "request/header":
                let header = data["header"]?.objectValue
                let config = header?["config"]?.objectValue
                let provider = config?["provider"]?.stringValue
                let model = config?["model"]?.stringValue
                let effort = config?["reasoningEffort"]?.stringValue
                let label = [provider, model].compactMap { $0 }.joined(separator: " · ")
                var details: [RemoteDetailSection] = []
                if let system = header?["system"]?.stringValue {
                    details.append(.init(id: "system", title: "系统提示", content: limited(system), kind: .text))
                }
                records.append(RemoteTrajectoryRecord(
                    id: "trajectory-request:\(event.seq)", sequence: event.seq,
                    turn: activeTurn, step: activeStep, kind: .request,
                    title: "模型请求",
                    summary: [label, effort].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
                    time: time, duration: nil, state: .succeeded, details: details
                ))
            case "assistant/message":
                guard let message = data["message"]?.objectValue else { break }
                let text = textContent(message["content"]) ?? ""
                let reasoning = reasoningContent(message["content"]) ?? ""
                let turn = int(data["turn"]) ?? activeTurn
                let step = int(data["step"]) ?? activeStep
                let summarySource = text.isEmpty ? reasoning : text
                var details: [RemoteDetailSection] = []
                if !reasoning.isEmpty {
                    details.append(.init(id: "reasoning", title: "思考过程", content: reasoning, kind: .text))
                }
                if !text.isEmpty {
                    details.append(.init(id: "answer", title: "回答", content: text, kind: .text))
                }
                let duration = turn.flatMap { turn in
                    step.flatMap { stepStarts["\(turn):\($0)"] }.map { max(event.time - $0, 0) / 1_000 }
                }
                records.append(RemoteTrajectoryRecord(
                    id: "trajectory-assistant:\(event.seq)", sequence: event.seq,
                    turn: turn, step: step, kind: .assistant,
                    title: text.isEmpty ? "模型思考" : "模型回答",
                    summary: firstMeaningfulLine(summarySource, fallback: "模型输出"),
                    time: time, duration: duration, state: .succeeded, details: details
                ))
            case "tool/call":
                guard let callID = data["callId"]?.stringValue else { break }
                let item = toolItem(call: entry, result: toolResults[callID])
                let turn = int(data["turn"]) ?? activeTurn
                let step = int(data["step"]) ?? activeStep
                let duration = toolResults[callID].map { max($0.event.time - event.time, 0) / 1_000 }
                records.append(RemoteTrajectoryRecord(
                    id: "trajectory-tool:\(callID)", sequence: event.seq,
                    turn: turn, step: step, kind: .tool,
                    title: item.title ?? "工具调用", summary: item.text,
                    time: item.time, duration: duration, state: item.state, details: item.details
                ))
            case "llm/retry":
                let turn = int(data["turn"]) ?? activeTurn
                let step = int(data["step"]) ?? activeStep
                records.append(RemoteTrajectoryRecord(
                    id: "trajectory-retry:\(event.seq)", sequence: event.seq,
                    turn: turn, step: step, kind: .lifecycle,
                    title: "模型请求重试", summary: data["error"]?.objectValue?["message"]?.stringValue ?? "等待下一次请求",
                    time: time, duration: nil, state: .running
                ))
            case "compaction/start":
                records.append(RemoteTrajectoryRecord(
                    id: "trajectory-compaction:\(event.seq)", sequence: event.seq,
                    turn: activeTurn, step: activeStep, kind: .lifecycle,
                    title: "整理上下文", summary: "正在压缩较早的会话内容",
                    time: time, duration: nil, state: .running
                ))
            case "turn/end":
                guard let turn = int(data["turn"]),
                      let reason = data["reason"]?.objectValue else { break }
                let reasonKind = reason["kind"]?.stringValue ?? "interrupted"
                let status = turnStatusItem(event: event, reason: reason, time: time)
                let duration = turnStarts[turn].map { max(event.time - $0, 0) / 1_000 }
                records.append(RemoteTrajectoryRecord(
                    id: "trajectory-turn:\(event.seq)", sequence: event.seq,
                    turn: turn, step: nil, kind: .lifecycle,
                    title: reasonKind == "completed" ? "本轮完成" : (status.title ?? "本轮结束"),
                    summary: reasonKind == "completed" ? "Harness 已完成本轮任务" : status.text,
                    time: time, duration: duration,
                    state: reasonKind == "completed" ? .succeeded : status.state,
                    details: status.details
                ))
            default:
                break
            }

            if event.type == "step/end" { activeStep = nil }
            if event.type == "turn/end" {
                activeStep = nil
                activeTurn = nil
            }
        }
        return records.sorted { lhs, rhs in lhs.sequence < rhs.sequence }
    }

    private static func textContent(_ value: JSONValue?) -> String? {
        let parts = contentTexts(value, acceptedTypes: ["text"])
        let text = parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func reasoningContent(_ value: JSONValue?) -> String? {
        let text = contentTexts(value, acceptedTypes: ["reasoning"])
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func contentTexts(_ value: JSONValue?, acceptedTypes: Set<String>) -> [String] {
        value?.arrayValue?.flatMap { item -> [String] in
            guard let block = item.objectValue,
                  let type = block["type"]?.stringValue else { return [] }
            if acceptedTypes.contains(type), let text = block["text"]?.stringValue {
                return [text]
            }
            if type == "tool-result" {
                return contentTexts(block["content"], acceptedTypes: acceptedTypes)
            }
            return []
        } ?? []
    }

    private static func updatePartial(
        _ partial: inout PartialAssistant?,
        chunk: [String: JSONValue],
        type: String
    ) {
        guard var value = partial else { return }
        let index = int(chunk["index"]) ?? 0
        switch type {
        case "block-start":
            value.blocks[index] = StreamBlock(
                type: chunk["blockType"]?.stringValue ?? "other",
                text: ""
            )
        case "text-delta", "reasoning-delta":
            let blockType = type == "text-delta" ? "text" : "reasoning"
            var block = value.blocks[index] ?? StreamBlock(type: blockType, text: "")
            block.type = blockType
            block.text += chunk["text"]?.stringValue ?? ""
            value.blocks[index] = block
        case "block-end":
            if let block = chunk["block"]?.objectValue,
               let blockType = block["type"]?.stringValue {
                value.blocks[index] = StreamBlock(
                    type: blockType,
                    text: block["text"]?.stringValue ?? ""
                )
            }
        default:
            break
        }
        partial = value
    }

    private static func contextItem(
        sequence: Int,
        sourceKind: String,
        source: [String: JSONValue]?,
        text: String,
        time: Date
    ) -> RemoteConversationItem {
        let title = contextSourceLabel(sourceKind)
        let presentation = contextPresentation(
            sourceKind: sourceKind,
            source: source,
            text: text
        )
        return RemoteConversationItem(
            id: "context:\(sequence)", sequence: sequence, kind: .context,
            title: title, text: presentation.preview, time: time, state: .info,
            details: presentation.details
        )
    }

    private static func contextPresentation(
        sourceKind: String,
        source: [String: JSONValue]?,
        text: String
    ) -> ContextPresentation {
        var details: [RemoteDetailSection] = []
        var preview = firstContextLine(text)

        if sourceKind == "agent-instructions",
           let changes = instructionChanges(source) {
            let baseline = source?["baseline"]?.boolValue == true
            let rows = changes.map { change in
                "\(change.path)\t\(instructionAction(change.action, baseline: baseline))"
            }
            details.append(RemoteDetailSection(
                id: "instruction-sources",
                title: "指令来源",
                content: rows.joined(separator: "\n"),
                kind: .list
            ))
            if changes.count == 1, let change = changes.first {
                preview = "\(change.path) · \(instructionAction(change.action, baseline: baseline))"
            } else {
                preview = "已同步 \(changes.count) 个指令文件"
            }
        }

        details.append(RemoteDetailSection(
            id: "context-raw",
            title: "模型接收的内容",
            content: text,
            kind: .text
        ))
        return ContextPresentation(preview: preview, details: details)
    }

    private static func instructionChanges(
        _ source: [String: JSONValue]?
    ) -> [InstructionChange]? {
        guard source?["form"]?.stringValue == "instructions",
              let entries = source?["changes"]?.arrayValue,
              !entries.isEmpty else { return nil }
        var changes: [InstructionChange] = []
        var seen = Set<String>()
        for entry in entries {
            guard let object = entry.objectValue,
                  let path = object["path"]?.stringValue,
                  !path.isEmpty,
                  let scope = object["scope"]?.stringValue,
                  let action = object["action"]?.stringValue,
                  ["set", "replace", "remove"].contains(action) else { return nil }
            if let digest = object["digest"], digest.stringValue == nil { return nil }
            guard seen.insert("\(scope)\u{0}\(path)").inserted else { return nil }
            changes.append(InstructionChange(path: path, action: action, scope: scope))
        }
        return changes.isEmpty ? nil : changes
    }

    private static func instructionAction(_ action: String, baseline: Bool) -> String {
        if action == "remove" { return "已移除" }
        if baseline { return "已载入" }
        return action == "set" ? "已添加" : "已更新"
    }

    private static func firstContextLine(_ value: String) -> String {
        let line = value.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && $0 != "<system-reminder>" && $0 != "</system-reminder>" }
        return line ?? "Harness 已载入一段上下文"
    }

    private static func contextSourceLabel(_ sourceKind: String) -> String {
        let labels: [String: String] = [
            "agent-instructions": "项目指令",
            "plugin": "插件上下文",
            "skill-catalog": "可用能力",
            "skill-invocation": "技能上下文",
            "session-reference": "引用会话",
        ]
        return labels[sourceKind] ?? "系统上下文"
    }

    private static func toolItem(
        call: HistoryEntryWire,
        result: HistoryEntryWire?
    ) -> RemoteConversationItem {
        let event = call.event
        let data = event.data.objectValue ?? [:]
        let callID = data["callId"]?.stringValue ?? "seq-\(event.seq)"
        let toolName = data["name"]?.stringValue ?? "工具"
        let callView = call.view?.objectValue?["view"]?.objectValue
        let resultView = result?.view?.objectValue?["view"]?.objectValue
        let resultBlock = toolResultBlock(result)
        let isError = resultBlock?["isError"]?.boolValue == true
        let errorCode = resultBlock?["error"]?.objectValue?["code"]?.stringValue
        let state: RemoteConversationItem.State = result == nil
            ? .running
            : (errorCode == "interrupted" ? .stopped : (isError ? .failed : .succeeded))
        let title = resultView?["title"]?.stringValue
            ?? callView?["title"]?.stringValue
            ?? readableToolName(toolName)
        let cardName = resultView?["card"]?.stringValue ?? callView?["card"]?.stringValue
        let card = toolCard(cardName)
        let rawResult = textContent(resultBlock?["content"])
        let presentation = toolPresentation(
            card: card,
            callView: callView,
            resultView: resultView,
            rawResult: rawResult,
            state: state
        )
        var metadata: [String] = []
        if let result {
            metadata.append(durationLabel(milliseconds: result.event.time - event.time))
        }
        if let exitCode = int(resultView?["exitCode"]) {
            metadata.append("exit \(exitCode)")
        } else if let signal = resultView?["signal"]?.stringValue {
            metadata.append(signal)
        }
        return RemoteConversationItem(
            id: "tool:\(callID)",
            sequence: event.seq,
            kind: .tool,
            title: title,
            text: presentation.summary,
            time: Date(timeIntervalSince1970: event.time / 1_000),
            state: state,
            toolCard: card,
            toolCategory: callView?["kind"]?.stringValue,
            details: presentation.details,
            metadata: metadata
        )
    }

    private static func toolPresentation(
        card: RemoteConversationItem.ToolCard,
        callView: [String: JSONValue]?,
        resultView: [String: JSONValue]?,
        rawResult: String?,
        state: RemoteConversationItem.State
    ) -> (summary: String, details: [RemoteDetailSection]) {
        var sections: [RemoteDetailSection] = []
        if let description = callView?["description"]?.stringValue {
            sections.append(.init(id: "description", title: nil, content: description, kind: .text))
        }
        if let content = textContent(callView?["content"]) {
            sections.append(.init(id: "call-content", title: "操作说明", content: content, kind: .text))
        }
        if let rawInput = readableJSON(callView?["rawInput"]) {
            sections.append(.init(id: "input", title: "输入", content: rawInput, kind: .code(language: nil)))
        }

        var summary: String?
        switch card {
        case .terminal:
            if let output = resultView?["output"]?.stringValue {
                sections.append(.init(id: "terminal", title: "终端输出", content: limited(output), kind: .code(language: "console")))
                summary = firstMeaningfulLine(output, fallback: "命令已完成")
            }
        case .diff:
            let diffs = resultView?["diffs"]?.arrayValue ?? callView?["diffs"]?.arrayValue ?? []
            for (index, diff) in diffs.enumerated() {
                guard let object = diff.objectValue else { continue }
                let path = object["path"]?.stringValue ?? "文件 \(index + 1)"
                let oldText = object["oldText"]?.stringValue
                let newText = object["newText"]?.stringValue ?? ""
                sections.append(.init(
                    id: "diff-\(index)", title: path,
                    content: unifiedDiff(path: path, oldText: oldText, newText: newText),
                    kind: .diff
                ))
            }
            summary = sections.isEmpty ? nil : "修改了 \(sections.count) 个文件"
        case .search:
            if resultView?["shape"]?.stringValue == "paths" {
                let paths = resultView?["paths"]?.arrayValue?.compactMap(\.stringValue) ?? []
                sections.append(.init(id: "paths", title: "匹配路径", content: paths.joined(separator: "\n"), kind: .list))
            } else {
                let files = resultView?["files"]?.arrayValue ?? []
                for (index, file) in files.enumerated() {
                    guard let object = file.objectValue else { continue }
                    let path = object["path"]?.stringValue ?? "结果 \(index + 1)"
                    let lines = object["matches"]?.arrayValue?.compactMap { match -> String? in
                        guard let value = match.objectValue else { return nil }
                        let number = int(value["lineNumber"]).map(String.init) ?? "?"
                        return "\(number)  \(value["line"]?.stringValue ?? "")"
                    } ?? []
                    sections.append(.init(id: "match-\(index)", title: path, content: lines.joined(separator: "\n"), kind: .code(language: nil)))
                }
            }
            let total = int(resultView?["total"]) ?? sections.count
            summary = "找到 \(total) 条结果"
        case .read:
            let path = resultView?["path"]?.stringValue ?? "文件内容"
            let lines = resultView?["lines"]?.arrayValue?.compactMap { line -> String? in
                guard let value = line.objectValue else { return nil }
                let number = int(value["number"]).map(String.init) ?? ""
                return "\(number)  \(value["text"]?.stringValue ?? "")"
            } ?? []
            sections.append(.init(
                id: "read", title: path, content: limited(lines.joined(separator: "\n")),
                kind: .code(language: resultView?["lang"]?.stringValue)
            ))
            summary = "读取 \(path) · \(lines.count) 行"
        case .web:
            if resultView?["kind"]?.stringValue == "fetch" {
                let status = int(resultView?["statusCode"]).map(String.init) ?? ""
                let url = resultView?["url"]?.stringValue ?? "网页"
                summary = "抓取完成 \(status)"
                sections.append(.init(id: "url", title: "来源", content: url, kind: .text))
            } else {
                let sources = resultView?["sources"]?.arrayValue ?? []
                let list = sources.compactMap { source -> String? in
                    guard let value = source.objectValue,
                          let url = value["url"]?.stringValue else { return nil }
                    let title = value["title"]?.stringValue ?? url
                    let snippet = value["snippet"]?.stringValue
                    return [title, url, snippet].compactMap { $0 }.joined(separator: "\n")
                }.joined(separator: "\n\n")
                sections.append(.init(id: "sources", title: "来源", content: limited(list), kind: .list))
                if let answer = resultView?["answer"]?.stringValue {
                    sections.insert(.init(id: "answer", title: "摘要", content: answer, kind: .text), at: 0)
                }
                summary = "检索了 \(sources.count) 个来源"
            }
        case .generic:
            if let content = textContent(resultView?["content"]) {
                sections.append(.init(id: "result", title: "结果", content: limited(content), kind: inferredSectionKind(content)))
                summary = firstMeaningfulLine(content, fallback: "操作已完成")
            }
        }

        if resultView == nil, let rawResult, !rawResult.isEmpty {
            sections.append(.init(id: "raw-result", title: "结果", content: limited(rawResult), kind: inferredSectionKind(rawResult)))
            summary = summary ?? firstMeaningfulLine(rawResult, fallback: "操作已完成")
        }
        if summary == nil {
            switch state {
            case .running: summary = "正在电脑上执行"
            case .failed: summary = "执行失败"
            case .stopped: summary = "已停止"
            case .succeeded: summary = "已完成"
            case .info: summary = "Harness 操作"
            }
        }
        return (summary ?? "Harness 操作", sections)
    }

    private static func toolResultBlock(_ entry: HistoryEntryWire?) -> [String: JSONValue]? {
        entry?.event.data.objectValue?["message"]?.objectValue?["content"]?.arrayValue?
            .first(where: { $0.objectValue?["type"]?.stringValue == "tool-result" })?
            .objectValue
    }

    private static func toolResultCallID(_ entry: HistoryEntryWire) -> String? {
        entry.event.data.objectValue?["message"]?.objectValue?["source"]?.objectValue?["callId"]?.stringValue
            ?? toolResultBlock(entry)?["toolCallId"]?.stringValue
    }

    private static func turnStatusItem(
        event: SessionEventWire,
        reason: [String: JSONValue],
        time: Date
    ) -> RemoteConversationItem {
        let kind = reason["kind"]?.stringValue ?? "interrupted"
        let title: String
        let text: String
        let state: RemoteConversationItem.State
        switch kind {
        case "error":
            title = "本轮执行失败"
            text = reason["error"]?.objectValue?["message"]?.stringValue ?? "模型请求返回了错误。"
            state = .failed
        case "max-tokens":
            title = "已达到输出上限"
            text = "模型在完成回答前达到了本次输出 token 上限。"
            state = .failed
        case "aborted":
            title = "本轮已停止"
            text = "执行已被取消，已经产生的内容仍保留在轨迹中。"
            state = .stopped
        case "blocked":
            title = "本轮已阻塞"
            text = "Harness 无法继续当前步骤。"
            state = .failed
        default:
            title = "本轮已中断"
            text = "会话在完成前中断，已有内容已保留。"
            state = .stopped
        }
        return RemoteConversationItem(
            id: "turn-end:\(event.seq)", sequence: event.seq, kind: .status,
            title: title, text: text, time: time, state: state
        )
    }

    private static func stats(from projections: SessionProjectionsWire?) -> RemoteConversationStats? {
        guard let values = projections?.values,
              let session = values["sessionStats"]?.objectValue else { return nil }
        let usage = values["tokenUsage"]?.objectValue
        return RemoteConversationStats(
            turns: int(session["turns"]) ?? 0,
            steps: int(session["steps"]) ?? 0,
            llmDuration: (session["llmMs"]?.numberValue ?? 0) / 1_000,
            toolDuration: (session["toolMs"]?.numberValue ?? 0) / 1_000,
            inputTokens: (int(usage?["uncachedInputTokens"]) ?? 0) + (int(usage?["cacheReadTokens"]) ?? 0),
            outputTokens: int(usage?["outputTokens"]) ?? 0
        )
    }

    private static func toolCard(_ value: String?) -> RemoteConversationItem.ToolCard {
        switch value {
        case "terminal": .terminal
        case "diff": .diff
        case "search": .search
        case "read": .read
        case "web": .web
        default: .generic
        }
    }

    private static func inferredSectionKind(_ content: String) -> RemoteDetailSection.Kind {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            let firstLine = trimmed.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
            let language = String(firstLine.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            return .code(language: language.isEmpty ? nil : language)
        }
        return .text
    }

    private static func unifiedDiff(path: String, oldText: String?, newText: String) -> String {
        var lines = ["--- \(path)", "+++ \(path)"]
        if let oldText {
            lines.append(contentsOf: oldText.split(separator: "\n", omittingEmptySubsequences: false).map { "-\($0)" })
        }
        lines.append(contentsOf: newText.split(separator: "\n", omittingEmptySubsequences: false).map { "+\($0)" })
        return limited(lines.joined(separator: "\n"))
    }

    private static func readableJSON(_ value: JSONValue?) -> String? {
        guard let value else { return nil }
        if let string = value.stringValue { return string }
        guard let data = try? JSONEncoder().encode(value),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }
        return String(data: pretty, encoding: .utf8)
    }

    private static func firstMeaningfulLine(_ value: String, fallback: String) -> String {
        let line = value.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty && !$0.hasPrefix("```") })
        guard let line else { return fallback }
        return line.count > 120 ? String(line.prefix(117)) + "…" : line
    }

    private static func limited(_ value: String, limit: Int = 30_000) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(limit)) + "\n\n…内容过长，已在手机端截断。"
    }

    private static func durationLabel(milliseconds: Double) -> String {
        let seconds = max(milliseconds, 0) / 1_000
        return seconds < 1 ? "\(Int(seconds * 1_000)) ms" : String(format: "%.1f 秒", seconds)
    }

    private static func int(_ value: JSONValue?) -> Int? {
        value?.numberValue.map(Int.init)
    }

    private static func readableToolName(_ name: String) -> String {
        name.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
