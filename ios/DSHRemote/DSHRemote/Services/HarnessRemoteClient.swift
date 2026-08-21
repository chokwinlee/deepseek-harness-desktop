import Foundation

protocol HarnessRemoteClient: Sendable {
    var displayName: String { get }
    var isDemo: Bool { get }

    func describe() async throws -> RemoteHostDescription
    func workspaces() async throws -> RemoteWorkspaceSnapshot
    func sessions() async throws -> [RemoteSessionSummary]
    func conversation(sessionID: String, maxMessages: Int) async throws -> RemoteConversationSnapshot
    func attachment(sessionID: String, attachmentID: String) async throws -> RemoteImageAttachmentPayload
    func fileReferences(sessionID: String, query: String) async throws -> [RemoteFileReferenceCandidate]
    func sessionReferences(sessionID: String, query: String) async throws -> [RemoteSessionReferenceCandidate]
    func subagents(parentSessionID: String) async throws -> RemoteSubagentCatalog
    func subagentConversation(
        parentSessionID: String,
        child: RemoteSubagentEntry,
        maxMessages: Int
    ) async throws -> RemoteConversationSnapshot
    func promptSubagent(
        parentSessionID: String,
        child: RemoteSubagentEntry,
        text: String
    ) async throws
    func interruptSubagent(parentSessionID: String, child: RemoteSubagentEntry) async throws
    func models(sessionID: String) async throws -> RemoteModelDirectory
    func selectModel(sessionID: String, selection: RemoteModelSelection) async throws -> RemoteModelSelection
    func send(
        _ text: String,
        images: [RemotePromptImage],
        to sessionID: String,
        steer: Bool
    ) async throws
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
            switch statusCode {
            case 401:
                "局域网配对凭据已失效，请重新扫描 Desktop 二维码。"
            case 413:
                "图片或消息过大，超过电脑允许的远程传输上限。"
            default:
                "电脑返回了 HTTP \(statusCode)。"
            }
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

    func workspaces() async throws -> RemoteWorkspaceSnapshot {
        let response: WorkspaceListWire = try await call("workspace.list", payload: EmptyPayload())
        let items = try response.items.map { item in
            guard let createdAt = Self.parseISO8601Date(item.createdAt),
                  let updatedAt = Self.parseISO8601Date(item.updatedAt) else {
                throw HarnessRemoteClientError.invalidResponse
            }
            return RemoteWorkspaceSummary(
                id: item.workspaceId,
                title: item.title,
                path: item.path,
                sessionIDs: item.sessionIds,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
        return RemoteWorkspaceSnapshot(
            items: items,
            archivedSessionIDs: Set(response.archivedSessionIds)
        )
    }

    func sessions() async throws -> [RemoteSessionSummary] {
        let response: SessionListWire = try await call("session.list", payload: EmptyPayload())
        return response.items
            .filter {
                $0.origin != "subagent"
                    && (!$0.blank || Self.hasVisibleCollaborationState($0.projections))
            }
            .map { item in
                let title = item.projections?.values["title"]?.stringValue?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let goalTitle = item.projections?.values["goal"]?.objectValue?["goal"]?
                    .objectValue?["objective"]?.stringValue?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let projectPath = item.cwd.flatMap { path in
                    path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : path
                }
                let projectName = Self.projectName(from: projectPath)
                return RemoteSessionSummary(
                    id: item.sessionId,
                    title: title.flatMap { $0.isEmpty ? nil : $0 }
                        ?? goalTitle.flatMap { $0.isEmpty ? nil : $0 }
                        ?? projectName
                        ?? "未命名任务",
                    updatedAt: Date(timeIntervalSince1970: item.updatedAt / 1_000),
                    running: item.running,
                    projectName: projectName,
                    projectPath: projectPath
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

    func attachment(
        sessionID: String,
        attachmentID: String
    ) async throws -> RemoteImageAttachmentPayload {
        let response: SessionAttachmentWire = try await call(
            "session.attachment",
            payload: SessionAttachmentPayload(
                sessionId: sessionID,
                attachmentId: attachmentID
            )
        )
        let attachment = try response.attachment.remoteValue()
        guard attachment.attachmentID == attachmentID,
              let data = Data(base64Encoded: response.data),
              data.count == attachment.bytes else {
            throw HarnessRemoteClientError.invalidResponse
        }
        return RemoteImageAttachmentPayload(attachment: attachment, data: data)
    }

    func fileReferences(
        sessionID: String,
        query: String
    ) async throws -> [RemoteFileReferenceCandidate] {
        let response: [FileReferenceWire] = try await call(
            "fileReferences/list",
            payload: ScopedQueryPayload(args: .init(agentId: sessionID, query: query))
        )
        return try response.map { try $0.remoteValue() }
    }

    func sessionReferences(
        sessionID: String,
        query: String
    ) async throws -> [RemoteSessionReferenceCandidate] {
        let response: [SessionReferenceWire] = try await call(
            "sessionReferenceResolver/candidates",
            payload: ScopedQueryPayload(args: .init(agentId: sessionID, query: query))
        )
        return try response.map { try $0.remoteValue() }
    }

    func subagents(parentSessionID: String) async throws -> RemoteSubagentCatalog {
        let response: SubagentCatalogWire = try await call(
            "subagent.list",
            payload: ParentSessionPayload(parentSessionId: parentSessionID)
        )
        return RemoteSubagentCatalog(
            entries: try response.entries.map { try $0.remoteValue() },
            parentAvailable: response.parentAvailable
        )
    }

    func subagentConversation(
        parentSessionID: String,
        child: RemoteSubagentEntry,
        maxMessages: Int
    ) async throws -> RemoteConversationSnapshot {
        guard let mode = child.mode, !child.isDiagnostic else {
            throw HarnessRemoteClientError.invalidResponse
        }
        let response: SessionHistoryWire = try await call(
            "subagent.history",
            payload: SubagentHistoryPayload(
                parentSessionId: parentSessionID,
                childSessionId: child.id,
                mode: mode.rawValue,
                maxMessages: maxMessages
            )
        )
        return ConversationFolder.fold(response)
    }

    func promptSubagent(
        parentSessionID: String,
        child: RemoteSubagentEntry,
        text: String
    ) async throws {
        guard child.mode == .continuable else {
            throw HarnessRemoteClientError.api(
                code: "subagent-not-resumable",
                message: "这个子代理不支持继续对话。"
            )
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let _: SubagentPromptReceiptWire = try await call(
            "subagent.prompt",
            payload: SubagentPromptPayload(
                parentSessionId: parentSessionID,
                childSessionId: child.id,
                mode: RemoteSubagentEntry.Mode.continuable.rawValue,
                content: [PromptContentPart.text(trimmed)],
                clientTimeZone: TimeZone.current.identifier
            )
        )
    }

    func interruptSubagent(
        parentSessionID: String,
        child: RemoteSubagentEntry
    ) async throws {
        guard child.mode == .continuable else {
            throw HarnessRemoteClientError.api(
                code: "subagent-not-resumable",
                message: "这个子代理不能接收停止操作。"
            )
        }
        let _: AcceptedWire = try await call(
            "subagent.interrupt",
            payload: SubagentAddressPayload(
                parentSessionId: parentSessionID,
                childSessionId: child.id,
                mode: RemoteSubagentEntry.Mode.continuable.rawValue
            )
        )
    }

    func models(sessionID: String) async throws -> RemoteModelDirectory {
        let response: SessionModelsWire = try await call(
            "session.models",
            payload: SessionIDPayload(sessionId: sessionID)
        )
        return response.remoteValue
    }

    func selectModel(
        sessionID: String,
        selection: RemoteModelSelection
    ) async throws -> RemoteModelSelection {
        let response: SessionSelectModelWire = try await call(
            "session.selectModel",
            payload: SessionSelectModelPayload(
                sessionId: sessionID,
                provider: selection.provider,
                model: selection.model,
                reasoningEffort: selection.reasoningEffort
            )
        )
        return response.selected.remoteValue
    }

    func send(
        _ text: String,
        images: [RemotePromptImage],
        to sessionID: String,
        steer: Bool
    ) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !images.isEmpty else { return }
        var content: [PromptContentPart] = []
        if !trimmed.isEmpty { content.append(.text(trimmed)) }
        content.append(contentsOf: images.map { .image($0) })
        let _: AcceptedWire = try await call(
            "session.prompt",
            payload: SessionPromptPayload(
                sessionId: sessionID,
                mode: steer ? "steer" : "queue",
                content: content,
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
            let message = error.code == "attachment-error"
                && error.message.localizedCaseInsensitiveContains("does not support image input")
                ? "当前模型不支持图片输入，请先切换到支持视觉的模型。"
                : error.message
            throw HarnessRemoteClientError.api(code: error.code, message: message)
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

    private static func projectName(from path: String?) -> String? {
        guard let path,
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let components = path
            .split { $0 == "/" || $0 == "\\" }
        return components.last.map(String.init)
    }

    private static func hasVisibleCollaborationState(
        _ projections: SessionProjectionsWire?
    ) -> Bool {
        if projections?.values["goal"]?.objectValue != nil { return true }
        let plan = projections?.values["plan"]?.objectValue
        return plan?["active"]?.boolValue == true || plan?["pending"]?.boolValue == true
    }

    private static func parseISO8601Date(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }
}

actor DemoHarnessRemoteClient: HarnessRemoteClient {
    nonisolated let displayName = "体验模式"
    nonisolated let isDemo = true

    private let sessionID = "review-demo-session"
    private var running = false
    private var selectedModel = RemoteModelSelection(
        provider: "deepseek-official",
        model: "deepseek-v4-flash",
        reasoningEffort: "high"
    )
    private var uploadedAttachments: [String: RemoteImageAttachmentPayload] = [:]
    private var demoSubagentRunning = false
    private var demoSubagentItems: [RemoteConversationItem] = [
        RemoteConversationItem(
            id: "demo-subagent-user",
            kind: .user,
            title: nil,
            text: "检查登录态恢复的回归风险。",
            time: Date().addingTimeInterval(-90)
        ),
        RemoteConversationItem(
            id: "demo-subagent-answer",
            kind: .assistant,
            title: nil,
            text: "已检查状态恢复、错误提示和回归测试入口。",
            time: Date().addingTimeInterval(-75)
        ),
    ]
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
    private static let demoAttachment = RemoteImageAttachment(
        attachmentID: "demo-image",
        mediaType: "image/png",
        bytes: 1_365,
        width: 64,
        height: 40,
        name: "登录流程截图.png"
    )
    private static let demoAttachmentData = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAEAAAAAoCAYAAABOzvzpAAAAAXNSR0IArs4c6QAAADhlWElmTU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAAqACAAQAAAABAAAAQKADAAQAAAABAAAAKAAAAADM21wGAAAEy0lEQVRoBe1YW1NaVxT+EBTwBogXklSTqFXrXaOiNWrGGiczzTR96Exn+tif0af+hz70F/Spk2amM23STIyX1ssAjdp614hRC9F4QY2IGLB7HeAURZBzwEqUNQPs+97rW2t9a28kxV9+f4hLLAmXWHdO9TgAcQ+45AjEQ+CSOwDiHhCLHtBw+y4KisshkZy9fWSxBkBJWS2u5d7kPvkflmF8xADLsvnMjnn2EAs4ujZLh5LyWn5GapoK+pa7aO34DBptNt8ezULMAJCYJEf9x+2QJAQeiYC50/k56/8EySlp0dQf0szy+99GdUWRizUw5XxW3t93oOfpI7hcLmg0mTwo6eoM5BeWIjFRjs31VbjdLpG7/TctJgDILypDYUklfypD/zNsrK1g9fUylhbmoFAkg5QnIQ/RZuXgRkEJ3Awg28YaaxX/njt3AFRqLRqaO5Dgdf25qb8wPzvOKUtfBwdOWJbMWLEuIS1dzUIgleuTymTIuZqLD64XwGG3Y2fbxs8RUjhXAKRSGZrbP4VCmcydmaxpGOhiBg20qGNvF6/mp7G9tQG1JgtJcjk3J0mu4EDI1l1jfZugcUIkKgDoWzqRrtJgbdUiZG/UNLSCDk5Clu7v/gVOFv+hhCxtnp2A0+mAJiML5Akk5BkUFuQlBCStF45EDEBZVQO3cWb2FWRk5mDFssiR12mb594oRGllHT9s2NDLALTy9dCFQ44EF+YmucuSJsNDlFIJ8EWjFt98VYGv71dDk6aAccIC9wke5Vs/IgDybhahoqbRtxZS09KZOxZi/Y2VuaKdbz9eSElNR1PrPSRIpVzXq/kZTI+/OD7s1DplAX+iJOXvFEkgl0mgTJKitljHvCQDvX++DLpWYNINOvRoB1m7pr7laCOrkSu2djzgvCKgkzUQixPpyRITuW5y6VHTHycNDbvNvrsDI+OOipz9gDmdt64EtPk3iAJAmZyKRhb3Pgtuba6DUpfT6TmAlFmW4rtW38bY3WNl36blVXqomcuSUJ439nex33e+7oh+3YfugPlud2Cb/yDBABDpNLXdg1yh5NbZd+xhsO83/LM4j+4nP8G2SXnZI9fzi9HW+YC/vemu5rF8X+HrxtjIELZs63w90sKjnumAJU5q8x8kmAP0zH2J8EjIggO9j7HD0g8JMe+ieQZKZQpLVR4rU4ojriB2r6q7DZmXtS3LCxgbHuLmRevLNGmFTJqAPJ0KdscBfngyhu9+NIYkQYmQv8WJ8YtKq/nzmga72U1tlq/7FyglVd5qBoXDcdmzv0XX44c48IbM8f7/sx52CJAV/ZWfmRgJqjwpsPByCn3PfoZ99+0RfQ5ZTBoHnseE8nSwsAAgxq/2Y3wrc9/xUcMRxU6q2DbeMF54yK6xy3z31NgLliZf8/XzLpz6h4iP8X2uTIxvHHwe9rkpMwz0/IqPKurYI0aHKRH5PuzNRAwMCUAwxne9E562Jv82sVsbu6rFmIQMgfqmdqi8z1Bi/KHfn4IITKwchriSil0z0nnBAWDW2vN7WQ0b+rg3eqQbxtr84CHArDVq6se2bRPK5JSQjB9rSgk5T3AAvKuY5yaErPfejQ0eAu+dKuIOHAdAHG4XZ1bcAy6OLcVpEvcAcbhdnFmX3gP+BRGTk4HlIkDOAAAAAElFTkSuQmCC"
    )!
    private static let demoGoal = RemoteGoalState(
        id: "demo-goal",
        revision: 2,
        objective: "完成登录态恢复并通过上线前回归验证",
        phase: .active,
        blockedReasonCode: nil,
        blockedReasonMessage: nil,
        maxRounds: 12,
        roundsStarted: 3,
        createdAt: Date().addingTimeInterval(-240),
        updatedAt: Date().addingTimeInterval(-120)
    )
    private static let demoPlan = RemotePlanState(active: true, pending: false)
    private static let demoImageLimits = RemoteImageLimits(
        maxImageBytes: 3_670_016,
        maxImagesPerMessage: 20,
        maxMessageImageBytes: 104_857_600,
        maxImagePixels: 40_000_000,
        maxImageDimension: 2_000,
        mediaTypes: ["image/png", "image/jpeg", "image/webp", "image/gif"]
    )
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
            time: Date().addingTimeInterval(-180),
            attachments: [DemoHarnessRemoteClient.demoAttachment]
        ),
        RemoteConversationItem(
            id: "demo-goal-status",
            sequence: 2,
            kind: .status,
            title: "目标已创建",
            text: DemoHarnessRemoteClient.demoGoal.objective,
            time: Date().addingTimeInterval(-178),
            state: .running,
            details: [RemoteDetailSection(
                id: "goal-objective",
                title: "目标",
                content: DemoHarnessRemoteClient.demoGoal.objective,
                kind: .text
            )],
            metadata: ["3/12 轮", "修订 2"],
            symbolName: "target"
        ),
        RemoteConversationItem(
            id: "demo-plan-status",
            sequence: 3,
            kind: .status,
            title: "已进入计划模式",
            text: "Harness 会先整理方案，再请求你确认是否执行。",
            time: Date().addingTimeInterval(-176),
            state: .running,
            symbolName: "map"
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
            metadata: ["deepseek-chat", "1.7K tokens", "4.2 秒"]
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
            title: "用户消息", summary: "检查登录流程并给出风险清单 · 1 张图片", time: Date().addingTimeInterval(-180),
            duration: nil,
            state: .succeeded,
            attachments: [DemoHarnessRemoteClient.demoAttachment]
        ),
        RemoteTrajectoryRecord(
            id: "demo-trajectory-goal", sequence: 2, turn: nil, step: nil, kind: .goal,
            title: "目标已创建", summary: DemoHarnessRemoteClient.demoGoal.objective,
            time: Date().addingTimeInterval(-178), duration: nil, state: .running
        ),
        RemoteTrajectoryRecord(
            id: "demo-trajectory-plan", sequence: 3, turn: nil, step: nil, kind: .plan,
            title: "计划模式已开启", summary: "先整理方案，再请求确认",
            time: Date().addingTimeInterval(-176), duration: nil, state: .running
        ),
        RemoteTrajectoryRecord(
            id: "demo-trajectory-request", sequence: 4, turn: 0, step: 0, kind: .request,
            title: "模型请求", summary: "整理上下文并请求分析", time: Date().addingTimeInterval(-174),
            duration: 0.12, state: .succeeded,
            details: [
                RemoteDetailSection(
                    id: "demo-request-payload", title: "PAYLOAD",
                    content: "model: deepseek-chat\nmode: normal\nproject: Sample Project", kind: .code(language: "yaml")
                ),
            ]
        ),
        RemoteTrajectoryRecord(
            id: "demo-trajectory-thinking", sequence: 5, turn: 0, step: 0, kind: .assistant,
            title: "模型思考", summary: "检查登录状态生命周期和错误恢复路径", time: Date().addingTimeInterval(-170),
            duration: 1.8, state: .succeeded
        ),
        RemoteTrajectoryRecord(
            id: "demo-trajectory-tool", sequence: 6, turn: 0, step: 1, kind: .tool,
            title: "读取文件", summary: "读取 4 个项目文件", time: Date().addingTimeInterval(-160),
            duration: 0.32, state: .succeeded,
            details: [
                RemoteDetailSection(
                    id: "demo-trajectory-files", title: "RESULT",
                    content: "Sources/Auth/SessionStore.swift\nSources/Auth/LoginView.swift\nTests/AuthTests.swift\nREADME.md", kind: .list
                ),
            ]
        ),
        RemoteTrajectoryRecord(
            id: "demo-trajectory-answer", sequence: 7, turn: 0, step: 2, kind: .assistant,
            title: "模型回答", summary: "整理两个上线前风险和修复计划", time: Date().addingTimeInterval(-150),
            duration: 2.4, state: .succeeded
        ),
        RemoteTrajectoryRecord(
            id: "demo-trajectory-end", sequence: 8, turn: 0, step: 2, kind: .lifecycle,
            title: "本轮完成", summary: "等待用户确认", time: Date().addingTimeInterval(-149),
            duration: 4.62, state: .succeeded
        ),
    ]

    func describe() async throws -> RemoteHostDescription {
        RemoteHostDescription(version: "Offline Demo", attachedSessions: 1)
    }

    func workspaces() async throws -> RemoteWorkspaceSnapshot {
        let updatedAt = items.last?.time ?? Date()
        return RemoteWorkspaceSnapshot(
            items: [
                RemoteWorkspaceSummary(
                    id: "review-demo-workspace",
                    title: "Sample Project",
                    path: "/Users/demo/Sample Project",
                    sessionIDs: [sessionID],
                    createdAt: updatedAt.addingTimeInterval(-3_600),
                    updatedAt: updatedAt
                ),
            ],
            archivedSessionIDs: []
        )
    }

    func sessions() async throws -> [RemoteSessionSummary] {
        [
            RemoteSessionSummary(
                id: sessionID,
                title: "登录流程上线检查",
                updatedAt: items.last?.time ?? Date(),
                running: running,
                projectName: "Sample Project",
                projectPath: "/Users/demo/Sample Project"
            ),
        ]
    }

    func conversation(sessionID: String, maxMessages: Int) async throws -> RemoteConversationSnapshot {
        #if DEBUG
        if let scenario = ProcessInfo.processInfo.environment["DSH_REMOTE_SCENARIO"],
           ["rc8", "rc8-trajectory", "rc8-image-failure"].contains(scenario) {
            let snapshot = ConversationFolder.fold(DemoHarnessRemoteClient.rc8HistoryFixture())
            assert(snapshot.items.contains {
                $0.kind == .user && $0.text.isEmpty && $0.attachments.count == 1
            })
            assert(snapshot.goal?.id == DemoHarnessRemoteClient.demoGoal.id)
            assert(snapshot.plan?.effectiveActive == true)
            DemoHarnessRemoteClient.assertRC8ContractFixtures()
            return snapshot
        }
        #endif
        return RemoteConversationSnapshot(
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
            trajectory: demoTrajectory,
            goal: DemoHarnessRemoteClient.demoGoal,
            plan: DemoHarnessRemoteClient.demoPlan,
            imageLimits: DemoHarnessRemoteClient.demoImageLimits
        )
    }

    func attachment(
        sessionID: String,
        attachmentID: String
    ) async throws -> RemoteImageAttachmentPayload {
        #if DEBUG
        if ProcessInfo.processInfo.environment["DSH_REMOTE_SCENARIO"] == "rc8-image-failure" {
            throw HarnessRemoteClientError.api(
                code: "attachment-unavailable",
                message: "图片暂时不可用。"
            )
        }
        #endif
        guard sessionID == self.sessionID,
              attachmentID == DemoHarnessRemoteClient.demoAttachment.attachmentID
                || uploadedAttachments[attachmentID] != nil else {
            throw HarnessRemoteClientError.api(
                code: "attachment-not-found",
                message: "找不到这张图片。"
            )
        }
        if let uploaded = uploadedAttachments[attachmentID] { return uploaded }
        return RemoteImageAttachmentPayload(
            attachment: DemoHarnessRemoteClient.demoAttachment,
            data: DemoHarnessRemoteClient.demoAttachmentData
        )
    }

    func fileReferences(
        sessionID: String,
        query: String
    ) async throws -> [RemoteFileReferenceCandidate] {
        let candidates = [
            RemoteFileReferenceCandidate(path: "Sources/Auth/LoginView.swift", kind: .file),
            RemoteFileReferenceCandidate(path: "Sources/Auth/SessionStore.swift", kind: .file),
            RemoteFileReferenceCandidate(path: "Tests/Auth", kind: .directory),
        ]
        guard !query.isEmpty else { return candidates }
        return candidates.filter { $0.path.localizedCaseInsensitiveContains(query) }
    }

    func sessionReferences(
        sessionID: String,
        query: String
    ) async throws -> [RemoteSessionReferenceCandidate] {
        let candidate = RemoteSessionReferenceCandidate(
            mention: "@[登录错误恢复](dsh-session:ZGVtby1yZWZlcmVuY2U)",
            sessionID: "demo-reference",
            label: "登录错误恢复",
            cwd: "/Users/demo/Sample Project",
            createdAt: Date().addingTimeInterval(-7_200)
        )
        return query.isEmpty || candidate.label.localizedCaseInsensitiveContains(query)
            ? [candidate]
            : []
    }

    func subagents(parentSessionID: String) async throws -> RemoteSubagentCatalog {
        RemoteSubagentCatalog(
            entries: [RemoteSubagentEntry(
                id: "demo-subagent",
                mode: .continuable,
                activity: demoSubagentRunning ? .running : .inactive,
                hasChildren: false,
                label: "登录回归测试",
                diagnosticReason: nil
            )],
            parentAvailable: true
        )
    }

    func subagentConversation(
        parentSessionID: String,
        child: RemoteSubagentEntry,
        maxMessages: Int
    ) async throws -> RemoteConversationSnapshot {
        RemoteConversationSnapshot(
            items: demoSubagentItems,
            hasMore: false,
            stats: nil,
            trajectory: []
        )
    }

    func promptSubagent(
        parentSessionID: String,
        child: RemoteSubagentEntry,
        text: String
    ) async throws {
        demoSubagentRunning = true
        demoSubagentItems.append(RemoteConversationItem(
            id: UUID().uuidString,
            kind: .user,
            title: nil,
            text: text,
            time: Date()
        ))
        demoSubagentItems.append(RemoteConversationItem(
            id: UUID().uuidString,
            kind: .assistant,
            title: nil,
            text: "已收到补充，我会继续检查。",
            time: Date()
        ))
        demoSubagentRunning = false
    }

    func interruptSubagent(
        parentSessionID: String,
        child: RemoteSubagentEntry
    ) async throws {
        demoSubagentRunning = false
    }

    func models(sessionID: String) async throws -> RemoteModelDirectory {
        RemoteModelDirectory(
            current: selectedModel,
            routable: true,
            groups: [
                RemoteModelProviderGroup(
                    id: "deepseek-official",
                    name: "DeepSeek",
                    models: [
                        RemoteModelCatalogEntry(
                            id: "deepseek-v4-flash",
                            name: "DeepSeek-V4-Flash",
                            description: "快速完成日常编码与分析",
                            reasoning: RemoteModelReasoning(
                                efforts: [
                                    .init(id: "off", name: "Off", description: "关闭深度推理"),
                                    .init(id: "high", name: "High", description: "适合复杂编码任务"),
                                    .init(id: "max", name: "Max", description: "投入最多推理时间"),
                                ],
                                defaultEffort: "high"
                            )
                        ),
                        RemoteModelCatalogEntry(
                            id: "deepseek-v4-pro",
                            name: "DeepSeek-V4-Pro",
                            description: "面向更复杂的长程任务",
                            reasoning: RemoteModelReasoning(
                                efforts: [
                                    .init(id: "off", name: "Off", description: "关闭深度推理"),
                                    .init(id: "high", name: "High", description: "适合复杂编码任务"),
                                    .init(id: "max", name: "Max", description: "投入最多推理时间"),
                                ],
                                defaultEffort: "high"
                            )
                        ),
                    ]
                ),
            ],
            failures: []
        )
    }

    func selectModel(
        sessionID: String,
        selection: RemoteModelSelection
    ) async throws -> RemoteModelSelection {
        let directory = try await models(sessionID: sessionID)
        guard let model = directory.groups
            .first(where: { $0.id == selection.provider })?
            .models.first(where: { $0.id == selection.model }) else {
            throw HarnessRemoteClientError.api(code: "model-unavailable", message: "这个模型当前不可用。")
        }
        let acceptedEffort = selection.reasoningEffort ?? model.reasoning?.defaultEffort
        if let acceptedEffort,
           model.reasoning?.efforts.contains(where: { $0.id == acceptedEffort }) != true {
            throw HarnessRemoteClientError.api(code: "model-unavailable", message: "这个推理强度当前不可用。")
        }
        selectedModel = RemoteModelSelection(
            provider: selection.provider,
            model: selection.model,
            reasoningEffort: acceptedEffort
        )
        return selectedModel
    }

    func send(
        _ text: String,
        images: [RemotePromptImage],
        to sessionID: String,
        steer: Bool
    ) async throws {
        let now = Date()
        let attachments = images.map { image in
            let attachment = RemoteImageAttachment(
                attachmentID: "demo-upload-\(image.id.uuidString.lowercased())",
                mediaType: image.mediaType,
                bytes: image.data.count,
                width: image.width,
                height: image.height,
                name: image.name
            )
            uploadedAttachments[attachment.attachmentID] = RemoteImageAttachmentPayload(
                attachment: attachment,
                data: image.data
            )
            return attachment
        }
        items.append(RemoteConversationItem(
            id: UUID().uuidString,
            kind: .user,
            title: steer ? "中途补充" : nil,
            text: text,
            time: now,
            attachments: attachments
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
        #if DEBUG
        if let scenario = ProcessInfo.processInfo.environment["DSH_REMOTE_SCENARIO"],
           [
               "trajectory", "rc8", "rc8-trajectory", "rc8-image-failure",
               "references", "image-draft", "subagents",
           ].contains(scenario) {
            return AsyncStream { continuation in continuation.finish() }
        }
        #endif
        return AsyncStream { continuation in
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

    #if DEBUG
    private static func rc8HistoryFixture() -> SessionHistoryWire {
        let now = Date().timeIntervalSince1970 * 1_000
        let attachment: JSONValue = .object([
            "attachmentId": .string(demoAttachment.attachmentID),
            "mediaType": .string(demoAttachment.mediaType),
            "bytes": .number(Double(demoAttachment.bytes)),
            "width": .number(Double(demoAttachment.width)),
            "height": .number(Double(demoAttachment.height)),
            "name": .string(demoAttachment.name ?? "图片.png"),
        ])
        let goal: JSONValue = .object([
            "id": .string(demoGoal.id),
            "revision": .number(Double(demoGoal.revision)),
            "objective": .string(demoGoal.objective),
            "phase": .string(demoGoal.phase.rawValue),
            "maxGoalRounds": .number(Double(demoGoal.maxRounds)),
        ])
        let goalProjection: JSONValue = .object([
            "goal": goal,
            "roundsStarted": .number(Double(demoGoal.roundsStarted)),
            "createdAt": .number(demoGoal.createdAt.timeIntervalSince1970 * 1_000),
            "updatedAt": .number(demoGoal.updatedAt.timeIntervalSince1970 * 1_000),
        ])
        let events = [
            HistoryEntryWire(event: SessionEventWire(
                type: "user/message",
                seq: 1,
                time: now - 12_000,
                data: .object([
                    "source": .object(["kind": .string("user")]),
                    "content": .array([
                        .object(["type": .string("image"), "attachment": attachment]),
                    ]),
                ])
            ), view: nil),
            HistoryEntryWire(event: SessionEventWire(
                type: "goal/change",
                seq: 2,
                time: now - 11_000,
                data: .object([
                    "kind": .string("goal/change"),
                    "version": .number(1),
                    "operation": .string("create"),
                    "goal": goal,
                    "roundsStarted": .number(Double(demoGoal.roundsStarted)),
                    "createdAt": .number(demoGoal.createdAt.timeIntervalSince1970 * 1_000),
                    "updatedAt": .number(demoGoal.updatedAt.timeIntervalSince1970 * 1_000),
                ])
            ), view: nil),
            HistoryEntryWire(event: SessionEventWire(
                type: "plan/mode",
                seq: 3,
                time: now - 10_000,
                data: .object(["active": .bool(true)])
            ), view: nil),
            HistoryEntryWire(event: SessionEventWire(
                type: "turn/start",
                seq: 4,
                time: now - 9_000,
                data: .object(["turn": .number(0)])
            ), view: nil),
            HistoryEntryWire(event: SessionEventWire(
                type: "step/start",
                seq: 5,
                time: now - 8_000,
                data: .object(["turn": .number(0), "step": .number(0)])
            ), view: nil),
            HistoryEntryWire(event: SessionEventWire(
                type: "assistant/message",
                seq: 6,
                time: now - 4_000,
                data: .object([
                    "turn": .number(0),
                    "step": .number(0),
                    "message": .object([
                        "content": .array([.object([
                            "type": .string("text"),
                            "text": .string("我会先核对截图中的登录状态，再整理上线前修复计划。"),
                        ])]),
                    ]),
                    "usage": .object(["outputTokens": .number(128)]),
                ])
            ), view: nil),
            HistoryEntryWire(event: SessionEventWire(
                type: "turn/end",
                seq: 7,
                time: now - 3_000,
                data: .object([
                    "turn": .number(0),
                    "reason": .object(["kind": .string("completed")]),
                ])
            ), view: nil),
        ]
        return SessionHistoryWire(
            events: events,
            hasMore: false,
            projections: SessionProjectionsWire(values: [
                "goal": goalProjection,
                "plan": .object(["active": .bool(true), "pending": .bool(false)]),
                "imageLimits": .object([
                    "maxImageBytes": .number(Double(demoImageLimits.maxImageBytes)),
                    "maxImagesPerMessage": .number(Double(demoImageLimits.maxImagesPerMessage)),
                    "maxMessageImageBytes": .number(Double(demoImageLimits.maxMessageImageBytes)),
                    "maxImagePixels": .number(Double(demoImageLimits.maxImagePixels)),
                    "maxImageDimension": .number(Double(demoImageLimits.maxImageDimension ?? 2_000)),
                    "mediaTypes": .array(demoImageLimits.mediaTypes.map(JSONValue.string)),
                ]),
                "sessionStats": .object([
                    "turns": .number(1),
                    "steps": .number(1),
                    "llmMs": .number(4_000),
                    "toolMs": .number(0),
                ]),
                "tokenUsage": .object([
                    "uncachedInputTokens": .number(320),
                    "cacheReadTokens": .number(0),
                    "outputTokens": .number(128),
                ]),
            ])
        )
    }

    private static func assertRC8ContractFixtures() {
        let decodedReplacement = try! JSONDecoder().decode(
            SessionEventWire.self,
            from: Data(#"{"type":"user/message","seq":9,"time":9000,"data":{},"surfaceOp":{"op":"replace","start":1,"end":2}}"#.utf8)
        )
        assert(decodedReplacement.surfaceOp?.objectValue?["op"]?.stringValue == "replace")

        func resultEvent(
            seq: Int,
            turn: Int,
            step: Int,
            text: String,
            attachment: JSONValue? = nil
        ) -> HistoryEntryWire {
            var content: [JSONValue] = [.object([
                "type": .string("text"),
                "text": .string(text),
            ])]
            if let attachment {
                content.append(.object([
                    "type": .string("image"),
                    "attachment": attachment,
                ]))
            }
            return HistoryEntryWire(event: SessionEventWire(
                type: "tool/result",
                seq: seq,
                time: Double(seq * 1_000),
                data: .object([
                    "turn": .number(Double(turn)),
                    "step": .number(Double(step)),
                    "message": .object([
                        "source": .object(["callId": .string("call-0")]),
                        "content": .array([.object([
                            "type": .string("tool-result"),
                            "toolCallId": .string("call-0"),
                            "content": .array(content),
                            "isError": .bool(false),
                        ])]),
                    ]),
                ]),
                surfaceOp: .string("append")
            ), view: nil)
        }

        let attachment: JSONValue = .object([
            "attachmentId": .string(demoAttachment.attachmentID),
            "mediaType": .string(demoAttachment.mediaType),
            "bytes": .number(Double(demoAttachment.bytes)),
            "width": .number(Double(demoAttachment.width)),
            "height": .number(Double(demoAttachment.height)),
        ])
        let events: [HistoryEntryWire] = [
            HistoryEntryWire(event: SessionEventWire(
                type: "compaction/summary",
                seq: 1,
                time: 1_000,
                data: .object([
                    "compactionId": .string("compact-1"),
                    "summary": .array([.object([
                        "type": .string("text"),
                        "text": .string("保留的压缩摘要"),
                    ])]),
                ])
            ), view: nil),
            HistoryEntryWire(event: SessionEventWire(
                type: "user/message",
                seq: 2,
                time: 2_000,
                data: .object([
                    "source": .object(["kind": .string("plugin")]),
                    "content": .array([.object([
                        "type": .string("text"),
                        "text": .string("MODEL_ONLY_REPLACEMENT"),
                    ])]),
                ]),
                sourceEventSeqs: [1],
                surfaceOp: .object([
                    "op": .string("replace"),
                    "start": .number(1),
                    "end": .number(1),
                ])
            ), view: nil),
            HistoryEntryWire(event: SessionEventWire(
                type: "tool/call",
                seq: 3,
                time: 3_000,
                data: .object([
                    "turn": .number(0), "step": .number(0),
                    "callId": .string("call-0"), "name": .string("first"),
                    "arguments": .string("{}"),
                ])
            ), view: nil),
            resultEvent(seq: 4, turn: 0, step: 0, text: "FIRST_RESULT"),
            HistoryEntryWire(event: SessionEventWire(
                type: "tool/call",
                seq: 5,
                time: 5_000,
                data: .object([
                    "turn": .number(0), "step": .number(1),
                    "callId": .string("call-0"), "name": .string("second"),
                    "arguments": .string("{}"),
                ])
            ), view: nil),
            resultEvent(seq: 6, turn: 0, step: 1, text: "SECOND_RESULT"),
            resultEvent(
                seq: 7,
                turn: 1,
                step: 0,
                text: "ORPHAN_RESULT",
                attachment: attachment
            ),
            HistoryEntryWire(event: SessionEventWire(
                type: "compaction/end",
                seq: 8,
                time: 8_000,
                data: .object([
                    "compactionId": .string("compact-1"),
                    "turn": .null,
                ])
            ), view: nil),
        ]
        let snapshot = ConversationFolder.fold(SessionHistoryWire(
            events: events,
            hasMore: false,
            projections: nil
        ))
        assert(!snapshot.items.contains { $0.text.contains("MODEL_ONLY_REPLACEMENT") })
        assert(snapshot.items.contains {
            $0.details.contains { $0.content.contains("保留的压缩摘要") }
        })
        let tools = snapshot.items.filter { $0.kind == .tool }
        assert(tools.count == 3)
        assert(tools.contains { $0.text.contains("FIRST_RESULT") })
        assert(tools.contains { $0.text.contains("SECOND_RESULT") })
        assert(tools.contains {
            $0.text.contains("ORPHAN_RESULT") && $0.attachments.count == 1
        })
        let compactions = snapshot.trajectory.filter {
            $0.id == "trajectory-compaction:compact-1"
        }
        assert(compactions.count == 1 && compactions[0].state == .succeeded)
    }
    #endif
}

private struct EmptyPayload: Codable {}
private struct SessionIDPayload: Codable { let sessionId: String }
private struct SessionSelectModelPayload: Codable {
    let sessionId: String
    let provider: String
    let model: String
    let reasoningEffort: String?
}
private struct SessionHistoryPayload: Codable { let sessionId: String; let maxMessages: Int }
private struct SessionAttachmentPayload: Codable {
    let sessionId: String
    let attachmentId: String
}
private struct ScopedQueryPayload: Codable { let args: ScopedQueryArguments }
private struct ScopedQueryArguments: Codable { let agentId: String; let query: String }
private struct ParentSessionPayload: Codable { let parentSessionId: String }
private struct SubagentAddressPayload: Codable {
    let parentSessionId: String
    let childSessionId: String
    let mode: String
}
private struct SubagentHistoryPayload: Codable {
    let parentSessionId: String
    let childSessionId: String
    let mode: String
    let maxMessages: Int
}
private struct SubagentPromptPayload: Encodable {
    let parentSessionId: String
    let childSessionId: String
    let mode: String
    let content: [PromptContentPart]
    let clientTimeZone: String
}
private struct PromptTextPart: Codable { let type: String; let text: String }
private enum PromptContentPart: Encodable {
    case text(String)
    case image(RemotePromptImage)

    private enum CodingKeys: String, CodingKey {
        case type, text, mediaType, data, name
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let image):
            try container.encode("image", forKey: .type)
            try container.encode(image.mediaType, forKey: .mediaType)
            try container.encode(image.data.base64EncodedString(), forKey: .data)
            try container.encodeIfPresent(image.name, forKey: .name)
        }
    }
}
private struct SessionPromptPayload: Encodable {
    let sessionId: String
    let mode: String
    let content: [PromptContentPart]
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
private struct WorkspaceListWire: Decodable {
    let items: [WorkspaceSummaryWire]
    let archivedSessionIds: [String]
}
private struct WorkspaceSummaryWire: Decodable {
    let workspaceId: String
    let path: String
    let title: String
    let sessionIds: [String]
    let createdAt: String
    let updatedAt: String
}
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

private struct SessionAttachmentWire: Decodable {
    let attachment: ImageAttachmentWire
    let data: String
}

private struct ImageAttachmentWire: Decodable {
    let attachmentId: String
    let mediaType: String
    let bytes: Int
    let width: Int
    let height: Int
    let name: String?

    func remoteValue() throws -> RemoteImageAttachment {
        guard !attachmentId.isEmpty,
              ["image/png", "image/jpeg", "image/webp", "image/gif"].contains(mediaType),
              bytes > 0,
              width > 0,
              height > 0 else {
            throw HarnessRemoteClientError.invalidResponse
        }
        return RemoteImageAttachment(
            attachmentID: attachmentId,
            mediaType: mediaType,
            bytes: bytes,
            width: width,
            height: height,
            name: name
        )
    }
}

private struct FileReferenceWire: Decodable {
    let path: String
    let kind: String

    func remoteValue() throws -> RemoteFileReferenceCandidate {
        guard !path.isEmpty,
              let kind = RemoteFileReferenceCandidate.Kind(rawValue: kind) else {
            throw HarnessRemoteClientError.invalidResponse
        }
        return RemoteFileReferenceCandidate(path: path, kind: kind)
    }
}

private struct SessionReferenceWire: Decodable {
    let mention: String
    let sessionId: String
    let label: String
    let cwd: String?
    let createdAt: Double

    func remoteValue() throws -> RemoteSessionReferenceCandidate {
        guard !mention.isEmpty, !sessionId.isEmpty, !label.isEmpty else {
            throw HarnessRemoteClientError.invalidResponse
        }
        return RemoteSessionReferenceCandidate(
            mention: mention,
            sessionID: sessionId,
            label: label,
            cwd: cwd,
            createdAt: Date(timeIntervalSince1970: createdAt / 1_000)
        )
    }
}

private struct SubagentCatalogWire: Decodable {
    let entries: [SubagentEntryWire]
    let parentAvailable: Bool
}

private struct SubagentEntryWire: Decodable {
    let kind: String
    let id: String
    let mode: String?
    let activity: String?
    let hasChildren: Bool?
    let label: String?
    let reason: String?

    func remoteValue() throws -> RemoteSubagentEntry {
        guard !id.isEmpty else { throw HarnessRemoteClientError.invalidResponse }
        if kind == "diagnostic" {
            guard let reason,
                  let diagnostic = RemoteSubagentEntry.DiagnosticReason(rawValue: reason) else {
                throw HarnessRemoteClientError.invalidResponse
            }
            return RemoteSubagentEntry(
                id: id,
                mode: nil,
                activity: nil,
                hasChildren: false,
                label: nil,
                diagnosticReason: diagnostic
            )
        }
        guard kind == "child",
              let mode,
              let remoteMode = RemoteSubagentEntry.Mode(rawValue: mode),
              let activity,
              let remoteActivity = RemoteSubagentEntry.Activity(rawValue: activity),
              let hasChildren else {
            throw HarnessRemoteClientError.invalidResponse
        }
        if remoteMode == .continuable,
           label?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            throw HarnessRemoteClientError.invalidResponse
        }
        return RemoteSubagentEntry(
            id: id,
            mode: remoteMode,
            activity: remoteActivity,
            hasChildren: hasChildren,
            label: label,
            diagnosticReason: nil
        )
    }
}

private struct SubagentPromptReceiptWire: Decodable { let messageId: String }

private struct SessionModelsWire: Decodable {
    let current: ModelSelectionWire
    let routable: Bool
    let groups: [ModelProviderGroupWire]
    let failures: [ModelCatalogFailureWire]

    var remoteValue: RemoteModelDirectory {
        RemoteModelDirectory(
            current: current.remoteValue,
            routable: routable,
            groups: groups.map(\.remoteValue),
            failures: failures.map(\.remoteValue)
        )
    }
}

private struct SessionSelectModelWire: Decodable {
    let selected: ModelSelectionWire
}

private struct ModelSelectionWire: Decodable {
    let provider: String
    let model: String
    let reasoningEffort: String?

    var remoteValue: RemoteModelSelection {
        RemoteModelSelection(provider: provider, model: model, reasoningEffort: reasoningEffort)
    }
}

private struct ModelProviderGroupWire: Decodable {
    let id: String
    let name: String
    let models: [ModelCatalogEntryWire]

    var remoteValue: RemoteModelProviderGroup {
        RemoteModelProviderGroup(id: id, name: name, models: models.map(\.remoteValue))
    }
}

private struct ModelCatalogEntryWire: Decodable {
    let id: String
    let name: String
    let description: String?
    let reasoning: ModelReasoningWire?

    var remoteValue: RemoteModelCatalogEntry {
        RemoteModelCatalogEntry(
            id: id,
            name: name,
            description: description,
            reasoning: reasoning?.remoteValue
        )
    }
}

private struct ModelReasoningWire: Decodable {
    let efforts: [ModelReasoningEffortWire]
    let defaultEffort: String?

    var remoteValue: RemoteModelReasoning {
        RemoteModelReasoning(efforts: efforts.map(\.remoteValue), defaultEffort: defaultEffort)
    }
}

private struct ModelReasoningEffortWire: Decodable {
    let id: String
    let name: String
    let description: String?

    var remoteValue: RemoteModelReasoningEffort {
        RemoteModelReasoningEffort(id: id, name: name, description: description)
    }
}

private struct ModelCatalogFailureWire: Decodable {
    let id: String
    let name: String
    let message: String

    var remoteValue: RemoteModelCatalogFailure {
        RemoteModelCatalogFailure(id: id, name: name, message: message)
    }
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
    var sourceEventSeqs: [Int]? = nil
    var surfaceOp: JSONValue? = nil
    var ignorable: Bool? = nil
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
        let attachmentCount = imageCount(message?["content"])
        let visiblePreview: String
        if let preview, !preview.isEmpty {
            visiblePreview = attachmentCount > 0
                ? "\(preview) · \(attachmentCount) 张图片"
                : preview
        } else if attachmentCount > 0 {
            visiblePreview = "\(attachmentCount) 张图片"
        } else {
            visiblePreview = "等待中的消息"
        }
        return RemoteQueuedMessage(
            id: id,
            placement: placement,
            preview: visiblePreview,
            text: text,
            attachmentCount: attachmentCount
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

    private static func imageCount(_ value: JSONValue?) -> Int {
        value?.arrayValue?.reduce(into: 0) { count, item in
            guard let block = item.objectValue else { return }
            if block["type"]?.stringValue == "image" { count += 1 }
            if let nested = block["content"] { count += imageCount(nested) }
        } ?? 0
    }
}

private enum ConversationFolder {
    private struct StreamBlock {
        var type: String
        var text: String
        var attachment: RemoteImageAttachment?
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

    private struct ToolOccurrenceKey: Hashable {
        let turn: Int
        let step: Int
        let callID: String
    }

    static func fold(_ history: SessionHistoryWire) -> RemoteConversationSnapshot {
        let entries = history.events
        var toolResults: [ToolOccurrenceKey: HistoryEntryWire] = [:]
        var toolCallKeys = Set<ToolOccurrenceKey>()
        for entry in entries {
            guard !isReplacementSurfaceEvent(entry.event),
                  let key = toolOccurrenceKey(entry) else { continue }
            if entry.event.type == "tool/result" {
                toolResults[key] = entry
            } else if entry.event.type == "tool/call" {
                toolCallKeys.insert(key)
            }
        }
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
                guard !isReplacementSurfaceEvent(event) else { continue }
                guard let data = event.data.objectValue else { continue }
                let text = textContent(data["content"]) ?? ""
                let attachments = imageAttachments(data["content"])
                guard !text.isEmpty || !attachments.isEmpty else { continue }
                let source = data["source"]?.objectValue
                let sourceKind = source?["kind"]?.stringValue ?? "context"
                if sourceKind == "user" {
                    output.append(RemoteConversationItem(
                        id: "user:\(event.seq)", sequence: event.seq, kind: .user,
                        title: nil, text: text, time: date,
                        attachments: attachments
                    ))
                } else {
                    output.append(contextItem(
                        sequence: event.seq,
                        sourceKind: sourceKind,
                        source: source,
                        text: text,
                        time: date,
                        attachments: attachments
                    ))
                }
            case "assistant/message":
                guard !isReplacementSurfaceEvent(event) else { continue }
                guard let data = event.data.objectValue,
                      let message = data["message"]?.objectValue else { continue }
                let turn = int(data["turn"])
                let step = int(data["step"])
                if partial?.turn == turn && partial?.step == step { partial = nil }
                let text = textContent(message["content"]) ?? ""
                let reasoning = reasoningContent(message["content"])
                let attachments = imageAttachments(message["content"])
                guard !text.isEmpty || reasoning != nil || !attachments.isEmpty else { continue }
                let interrupted = data["interrupted"]?.boolValue == true
                var item = RemoteConversationItem(
                    id: "assistant:\(event.seq)", sequence: event.seq, kind: .assistant,
                    title: nil,
                    text: text,
                    time: date,
                    state: interrupted ? .stopped : .succeeded,
                    reasoning: reasoning,
                    attachments: attachments
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
                if interrupted { item.metadata.append("已停止") }
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
                guard let key = toolOccurrenceKey(entry) else { continue }
                output.append(toolItem(call: entry, result: toolResults[key]))
            case "tool/result":
                guard !isReplacementSurfaceEvent(event),
                      let key = toolOccurrenceKey(entry),
                      !toolCallKeys.contains(key) else { continue }
                output.append(toolItem(call: nil, result: entry))
            case "goal/change":
                output.append(goalChangeItem(event: event, time: date))
            case "plan/mode":
                output.append(planModeItem(event: event, time: date))
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
                      let summary = textContent(data["summary"]) else { continue }
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
            let attachments = partial.blocks.sorted(by: { $0.key < $1.key })
                .compactMap(\.value.attachment)
            if !text.isEmpty || !reasoning.isEmpty || !attachments.isEmpty {
                output.append(RemoteConversationItem(
                    id: "assistant-stream:\(partial.turn):\(partial.step)",
                    sequence: partial.firstSequence,
                    kind: .assistant,
                    title: nil,
                    text: text,
                    time: partial.time,
                    state: .running,
                    reasoning: reasoning.isEmpty ? nil : reasoning,
                    attachments: attachments,
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
            ),
            goal: goalState(from: history.projections),
            plan: planState(from: history.projections),
            imageLimits: imageLimits(from: history.projections)
        )
    }

    private static func compactionTrajectoryRecords(
        _ entries: [HistoryEntryWire]
    ) -> [RemoteTrajectoryRecord] {
        let relevant = entries.filter {
            ["compaction/start", "compaction/summary", "compaction/end"]
                .contains($0.event.type)
        }
        let grouped = Dictionary(grouping: relevant) { entry in
            entry.event.data.objectValue?["compactionId"]?.stringValue ?? ""
        }
        return grouped.compactMap { compactionID, group in
            guard !compactionID.isEmpty else { return nil }
            let ordered = group.sorted { $0.event.seq < $1.event.seq }
            let start = ordered.first { $0.event.type == "compaction/start" }
            let summaryEvent = ordered.first { $0.event.type == "compaction/summary" }
            let end = ordered.first { $0.event.type == "compaction/end" }
            guard let anchor = summaryEvent ?? end ?? start else { return nil }

            let summary = summaryEvent.flatMap {
                textContent($0.event.data.objectValue?["summary"])
            }
            let error = end?.event.data.objectValue?["error"]?.stringValue
            let completed = end != nil
            let state: RemoteConversationItem.State = error != nil
                ? .failed
                : (completed ? .succeeded : .running)
            let title = error != nil
                ? "上下文整理失败"
                : (completed ? "上下文已整理" : "整理上下文")
            let text = error
                ?? summary.map { firstMeaningfulLine($0, fallback: "较早内容已整理") }
                ?? "正在压缩较早的会话内容"
            let duration: TimeInterval? = if let start, let end {
                max(end.event.time - start.event.time, 0) / 1_000
            } else {
                nil
            }
            let details = summary.map { value in
                [RemoteDetailSection(
                    id: "summary",
                    title: "压缩摘要",
                    content: value,
                    kind: .text
                )]
            } ?? []
            return RemoteTrajectoryRecord(
                id: "trajectory-compaction:\(compactionID)",
                sequence: anchor.event.seq,
                turn: start.flatMap { int($0.event.data.objectValue?["turn"]) },
                step: nil,
                kind: .lifecycle,
                title: title,
                summary: text,
                time: Date(timeIntervalSince1970: anchor.event.time / 1_000),
                duration: duration,
                state: state,
                details: details
            )
        }
    }

    private static func buildTrajectory(
        _ entries: [HistoryEntryWire],
        toolResults: [ToolOccurrenceKey: HistoryEntryWire],
        stepStarts: [String: Double],
        turnStarts: [Int: Double]
    ) -> [RemoteTrajectoryRecord] {
        let orderedTurnStarts = entries.compactMap { entry -> (sequence: Int, turn: Int)? in
            guard entry.event.type == "turn/start",
                  let turn = int(entry.event.data.objectValue?["turn"]) else { return nil }
            return (entry.event.seq, turn)
        }
        var records = compactionTrajectoryRecords(entries)
        let toolCallKeys = Set(entries.compactMap { entry in
            entry.event.type == "tool/call" ? toolOccurrenceKey(entry) : nil
        })
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
                guard !isReplacementSurfaceEvent(event) else { break }
                let text = textContent(data["content"]) ?? ""
                let attachments = imageAttachments(data["content"])
                guard !text.isEmpty || !attachments.isEmpty else { break }
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
                        ? attachmentSummary(text, attachments)
                        : (attachments.isEmpty
                            ? presentation.preview
                            : attachmentSummary(presentation.preview, attachments)),
                    time: time,
                    duration: nil,
                    state: .succeeded,
                    details: (isUser
                        ? (text.isEmpty ? [] : [RemoteDetailSection(
                            id: "message", title: "完整内容", content: limited(text), kind: .text
                        )])
                        : presentation.details) + attachmentDetails(attachments),
                    attachments: attachments
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
                guard !isReplacementSurfaceEvent(event) else { break }
                guard let message = data["message"]?.objectValue else { break }
                let text = textContent(message["content"]) ?? ""
                let reasoning = reasoningContent(message["content"]) ?? ""
                let attachments = imageAttachments(message["content"])
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
                details.append(contentsOf: attachmentDetails(attachments))
                let duration = turn.flatMap { turn in
                    step.flatMap { stepStarts["\(turn):\($0)"] }.map { max(event.time - $0, 0) / 1_000 }
                }
                records.append(RemoteTrajectoryRecord(
                    id: "trajectory-assistant:\(event.seq)", sequence: event.seq,
                    turn: turn, step: step, kind: .assistant,
                    title: text.isEmpty ? "模型思考" : "模型回答",
                    summary: attachments.isEmpty
                        ? firstMeaningfulLine(summarySource, fallback: "模型输出")
                        : attachmentSummary(summarySource, attachments),
                    time: time,
                    duration: duration,
                    state: data["interrupted"]?.boolValue == true ? .stopped : .succeeded,
                    details: details,
                    attachments: attachments
                ))
            case "tool/call":
                guard let key = toolOccurrenceKey(entry) else { break }
                let item = toolItem(call: entry, result: toolResults[key])
                let turn = int(data["turn"]) ?? activeTurn
                let step = int(data["step"]) ?? activeStep
                let duration = toolResults[key].map { max($0.event.time - event.time, 0) / 1_000 }
                records.append(RemoteTrajectoryRecord(
                    id: "trajectory-tool:\(key.turn):\(key.step):\(key.callID)", sequence: event.seq,
                    turn: turn, step: step, kind: .tool,
                    title: item.title ?? "工具调用", summary: item.text,
                    time: item.time,
                    duration: duration,
                    state: item.state,
                    details: item.details + attachmentDetails(item.attachments),
                    attachments: item.attachments
                ))
            case "tool/result":
                guard !isReplacementSurfaceEvent(event),
                      let key = toolOccurrenceKey(entry),
                      !toolCallKeys.contains(key) else { break }
                let item = toolItem(call: nil, result: entry)
                records.append(RemoteTrajectoryRecord(
                    id: "trajectory-tool-result:\(key.turn):\(key.step):\(key.callID):\(event.seq)",
                    sequence: event.seq,
                    turn: key.turn,
                    step: key.step,
                    kind: .tool,
                    title: item.title ?? key.callID,
                    summary: item.text,
                    time: item.time,
                    duration: nil,
                    state: item.state,
                    details: item.details + attachmentDetails(item.attachments),
                    attachments: item.attachments
                ))
            case "goal/change":
                let item = goalChangeItem(event: event, time: time)
                records.append(RemoteTrajectoryRecord(
                    id: "trajectory-goal:\(event.seq)",
                    sequence: event.seq,
                    turn: activeTurn,
                    step: activeStep,
                    kind: .goal,
                    title: item.title ?? "目标变化",
                    summary: item.text,
                    time: time,
                    duration: nil,
                    state: item.state,
                    details: item.details
                ))
            case "plan/mode":
                let item = planModeItem(event: event, time: time)
                records.append(RemoteTrajectoryRecord(
                    id: "trajectory-plan:\(event.seq)",
                    sequence: event.seq,
                    turn: activeTurn,
                    step: activeStep,
                    kind: .plan,
                    title: item.title ?? "计划模式",
                    summary: item.text,
                    time: time,
                    duration: nil,
                    state: item.state,
                    details: item.details
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
            case "compaction/start", "compaction/summary", "compaction/end":
                break
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

    private static func imageAttachments(_ value: JSONValue?) -> [RemoteImageAttachment] {
        var attachments: [RemoteImageAttachment] = []

        func collect(_ value: JSONValue?) {
            guard let value else { return }
            if let values = value.arrayValue {
                values.forEach { collect($0) }
                return
            }
            guard let object = value.objectValue else { return }
            if object["type"]?.stringValue == "image",
               let attachment = remoteImageAttachment(object["attachment"]) {
                attachments.append(attachment)
            }
            if let nested = object["content"] {
                collect(nested)
            }
        }

        collect(value)
        return attachments
    }

    private static func remoteImageAttachment(_ value: JSONValue?) -> RemoteImageAttachment? {
        guard let object = value?.objectValue,
              let attachmentID = object["attachmentId"]?.stringValue,
              !attachmentID.isEmpty,
              let mediaType = object["mediaType"]?.stringValue,
              ["image/png", "image/jpeg", "image/webp", "image/gif"].contains(mediaType),
              let bytes = int(object["bytes"]), bytes > 0,
              let width = int(object["width"]), width > 0,
              let height = int(object["height"]), height > 0 else {
            return nil
        }
        return RemoteImageAttachment(
            attachmentID: attachmentID,
            mediaType: mediaType,
            bytes: bytes,
            width: width,
            height: height,
            name: object["name"]?.stringValue
        )
    }

    private static func attachmentSummary(
        _ text: String,
        _ attachments: [RemoteImageAttachment]
    ) -> String {
        if attachments.isEmpty {
            return firstMeaningfulLine(text, fallback: "消息内容")
        }
        let imageText = "\(attachments.count) 张图片"
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return imageText }
        return "\(firstMeaningfulLine(trimmed, fallback: imageText)) · \(imageText)"
    }

    private static func attachmentDetails(
        _ attachments: [RemoteImageAttachment]
    ) -> [RemoteDetailSection] {
        guard !attachments.isEmpty else { return [] }
        let rows = attachments.enumerated().map { index, attachment in
            let name = attachment.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = name.flatMap { $0.isEmpty ? nil : $0 } ?? "图片 \(index + 1)"
            let size = ByteCountFormatter.string(
                fromByteCount: Int64(attachment.bytes),
                countStyle: .file
            )
            return "\(label)\t\(attachment.width)×\(attachment.height) · \(size)"
        }
        return [RemoteDetailSection(
            id: "attachments",
            title: "图片",
            content: rows.joined(separator: "\n"),
            kind: .list
        )]
    }

    private static func goalState(from projections: SessionProjectionsWire?) -> RemoteGoalState? {
        goalState(from: projections?.values["goal"])
    }

    private static func goalState(from value: JSONValue?) -> RemoteGoalState? {
        guard let projection = value?.objectValue,
              let goal = projection["goal"]?.objectValue,
              let id = goal["id"]?.stringValue,
              !id.isEmpty,
              let revision = int(goal["revision"]), revision > 0,
              let objective = goal["objective"]?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !objective.isEmpty,
              let phaseValue = goal["phase"]?.stringValue,
              let phase = RemoteGoalState.Phase(rawValue: phaseValue),
              let maxRounds = int(goal["maxGoalRounds"]), maxRounds > 0,
              let roundsStarted = int(projection["roundsStarted"]), roundsStarted >= 0,
              let createdAt = projection["createdAt"]?.numberValue,
              let updatedAt = projection["updatedAt"]?.numberValue else {
            return nil
        }
        let blockedReason = goal["blockedReason"]?.objectValue
        return RemoteGoalState(
            id: id,
            revision: revision,
            objective: objective,
            phase: phase,
            blockedReasonCode: blockedReason?["code"]?.stringValue,
            blockedReasonMessage: blockedReason?["message"]?.stringValue,
            maxRounds: maxRounds,
            roundsStarted: roundsStarted,
            createdAt: Date(timeIntervalSince1970: createdAt / 1_000),
            updatedAt: Date(timeIntervalSince1970: updatedAt / 1_000)
        )
    }

    private static func planState(from projections: SessionProjectionsWire?) -> RemotePlanState? {
        guard let value = projections?.values["plan"]?.objectValue,
              let active = value["active"]?.boolValue,
              let pending = value["pending"]?.boolValue else {
            return nil
        }
        return RemotePlanState(active: active, pending: pending)
    }

    private static func imageLimits(
        from projections: SessionProjectionsWire?
    ) -> RemoteImageLimits? {
        guard let value = projections?.values["imageLimits"]?.objectValue,
              let maxImageBytes = int(value["maxImageBytes"]), maxImageBytes > 0,
              let maxImagesPerMessage = int(value["maxImagesPerMessage"]), maxImagesPerMessage > 0,
              let maxMessageImageBytes = int(value["maxMessageImageBytes"]), maxMessageImageBytes > 0,
              let maxImagePixels = int(value["maxImagePixels"]), maxImagePixels > 0 else {
            return nil
        }
        let mediaTypes = value["mediaTypes"]?.arrayValue?.compactMap(\.stringValue) ?? []
        guard !mediaTypes.isEmpty else { return nil }
        return RemoteImageLimits(
            maxImageBytes: maxImageBytes,
            maxImagesPerMessage: maxImagesPerMessage,
            maxMessageImageBytes: maxMessageImageBytes,
            maxImagePixels: maxImagePixels,
            maxImageDimension: int(value["maxImageDimension"]).flatMap { $0 > 0 ? $0 : nil },
            mediaTypes: mediaTypes
        )
    }

    private static func goalChangeItem(
        event: SessionEventWire,
        time: Date
    ) -> RemoteConversationItem {
        let data = event.data.objectValue ?? [:]
        let operation = data["operation"]?.stringValue ?? "edit"
        if operation == "clear" {
            let cleared = data["cleared"]?.objectValue
            let revision = int(cleared?["revision"])
            return RemoteConversationItem(
                id: "goal:\(event.seq)",
                sequence: event.seq,
                kind: .status,
                title: "目标已清除",
                text: "当前会话不再自动继续这个目标。",
                time: time,
                state: .info,
                metadata: revision.map { ["修订 \($0)"] } ?? [],
                symbolName: "target"
            )
        }

        guard let goal = goalState(from: event.data) else {
            return RemoteConversationItem(
                id: "goal:\(event.seq)",
                sequence: event.seq,
                kind: .status,
                title: "目标状态已变化",
                text: "Harness 已更新当前目标。",
                time: time,
                state: .info,
                symbolName: "target"
            )
        }
        let title: String = switch operation {
        case "create": "目标已创建"
        case "pause": "目标已暂停"
        case "resume": "目标已继续"
        case "complete": "目标已完成"
        case "block": "目标需要处理"
        default: "目标已更新"
        }
        return RemoteConversationItem(
            id: "goal:\(event.seq)",
            sequence: event.seq,
            kind: .status,
            title: title,
            text: goal.blockedReasonMessage ?? goal.objective,
            time: time,
            state: state(for: goal.phase),
            details: goalDetails(goal),
            metadata: ["\(goal.roundsStarted)/\(goal.maxRounds) 轮", "修订 \(goal.revision)"],
            symbolName: "target"
        )
    }

    private static func planModeItem(
        event: SessionEventWire,
        time: Date
    ) -> RemoteConversationItem {
        let active = event.data.objectValue?["active"]?.boolValue == true
        return RemoteConversationItem(
            id: "plan:\(event.seq)",
            sequence: event.seq,
            kind: .status,
            title: active ? "已进入计划模式" : "已退出计划模式",
            text: active
                ? "Harness 会先整理方案，再请求你确认是否执行。"
                : "Harness 已恢复正常执行模式。",
            time: time,
            state: active ? .running : .info,
            details: [RemoteDetailSection(
                id: "plan-mode",
                title: "计划模式",
                content: active ? "当前状态\t已开启" : "当前状态\t已关闭",
                kind: .list
            )],
            symbolName: "map"
        )
    }

    private static func goalDetails(_ goal: RemoteGoalState) -> [RemoteDetailSection] {
        var details = [RemoteDetailSection(
            id: "goal-objective",
            title: "目标",
            content: goal.objective,
            kind: .text
        )]
        let status = [
            "状态\t\(goalPhaseLabel(goal.phase))",
            "进度\t\(goal.roundsStarted) / \(goal.maxRounds) 轮",
            "修订\t\(goal.revision)",
        ]
        details.append(RemoteDetailSection(
            id: "goal-status",
            title: "状态",
            content: status.joined(separator: "\n"),
            kind: .list
        ))
        if let message = goal.blockedReasonMessage, !message.isEmpty {
            details.append(RemoteDetailSection(
                id: "goal-blocked",
                title: "需要处理",
                content: message,
                kind: .text
            ))
        }
        return details
    }

    private static func goalPhaseLabel(_ phase: RemoteGoalState.Phase) -> String {
        switch phase {
        case .active: "进行中"
        case .paused: "已暂停"
        case .blocked: "受阻"
        case .complete: "已完成"
        }
    }

    private static func state(
        for phase: RemoteGoalState.Phase
    ) -> RemoteConversationItem.State {
        switch phase {
        case .active: .running
        case .paused, .blocked: .stopped
        case .complete: .succeeded
        }
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
                text: "",
                attachment: nil
            )
        case "text-delta", "reasoning-delta":
            let blockType = type == "text-delta" ? "text" : "reasoning"
            var block = value.blocks[index] ?? StreamBlock(
                type: blockType,
                text: "",
                attachment: nil
            )
            block.type = blockType
            block.text += chunk["text"]?.stringValue ?? ""
            value.blocks[index] = block
        case "block-end":
            if let block = chunk["block"]?.objectValue,
               let blockType = block["type"]?.stringValue {
                value.blocks[index] = StreamBlock(
                    type: blockType,
                    text: block["text"]?.stringValue ?? "",
                    attachment: imageAttachments(.object(block)).first
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
        time: Date,
        attachments: [RemoteImageAttachment]
    ) -> RemoteConversationItem {
        let title = contextSourceLabel(sourceKind)
        let presentation = contextPresentation(
            sourceKind: sourceKind,
            source: source,
            text: text
        )
        return RemoteConversationItem(
            id: "context:\(sequence)", sequence: sequence, kind: .context,
            title: title,
            text: attachments.isEmpty ? presentation.preview : attachmentSummary(text, attachments),
            time: time,
            state: .info,
            details: presentation.details,
            attachments: attachments
        )
    }

    private static func contextPresentation(
        sourceKind: String,
        source: [String: JSONValue]?,
        text: String
    ) -> ContextPresentation {
        var details: [RemoteDetailSection] = []
        var preview = firstContextLine(text)

        if sourceKind == "goal",
           let round = int(source?["round"]), round > 0 {
            preview = "Goal · 第 \(round) 轮"
            var rows = ["轮次\t第 \(round) 轮"]
            if let revision = int(source?["revision"]) {
                rows.append("修订\t\(revision)")
            }
            details.append(RemoteDetailSection(
                id: "goal-source",
                title: "Goal 续跑",
                content: rows.joined(separator: "\n"),
                kind: .list
            ))
        }

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
            "goal": "目标续跑",
        ]
        return labels[sourceKind] ?? "系统上下文"
    }

    private static func toolItem(
        call: HistoryEntryWire?,
        result: HistoryEntryWire?
    ) -> RemoteConversationItem {
        guard let event = call?.event ?? result?.event else {
            preconditionFailure("tool item needs a call or result")
        }
        let data = call?.event.data.objectValue ?? [:]
        let callID = data["callId"]?.stringValue
            ?? result.flatMap(toolResultCallID)
            ?? "seq-\(event.seq)"
        let toolName = data["name"]?.stringValue ?? callID
        let callView = call?.view?.objectValue?["view"]?.objectValue
        let resultView = result?.view?.objectValue?["view"]?.objectValue
        let resultBlock = toolResultBlock(result)
        let isError = resultBlock?["isError"]?.boolValue == true
        let errorCode = result?.event.data.objectValue?["error"]?.objectValue?["code"]?.stringValue
        let state: RemoteConversationItem.State = result == nil
            ? .running
            : (errorCode == "interrupted" ? .stopped : (isError ? .failed : .succeeded))
        let title = resultView?["title"]?.stringValue
            ?? callView?["title"]?.stringValue
            ?? (call == nil ? callID : readableToolName(toolName))
        let cardName = resultView?["card"]?.stringValue ?? callView?["card"]?.stringValue
        let card = toolCard(cardName)
        let rawResult = textContent(resultBlock?["content"])
        let attachments = imageAttachments(resultBlock?["content"])
        let presentation = toolPresentation(
            card: card,
            callView: callView,
            resultView: resultView,
            rawResult: rawResult,
            state: state
        )
        var metadata: [String] = []
        if let call, let result {
            metadata.append(durationLabel(milliseconds: result.event.time - call.event.time))
        }
        if let exitCode = int(resultView?["exitCode"]) {
            metadata.append("exit \(exitCode)")
        } else if let signal = resultView?["signal"]?.stringValue {
            metadata.append(signal)
        }
        return RemoteConversationItem(
            id: "tool:\(event.seq):\(callID)",
            sequence: event.seq,
            kind: .tool,
            title: title,
            text: attachments.isEmpty
                ? presentation.summary
                : attachmentSummary(presentation.summary, attachments),
            time: Date(timeIntervalSince1970: event.time / 1_000),
            state: state,
            toolCard: card,
            toolCategory: callView?["kind"]?.stringValue,
            details: presentation.details,
            metadata: metadata,
            attachments: attachments
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

    private static func toolOccurrenceKey(_ entry: HistoryEntryWire) -> ToolOccurrenceKey? {
        guard let data = entry.event.data.objectValue,
              let turn = int(data["turn"]),
              let step = int(data["step"]) else {
            return nil
        }
        let callID = entry.event.type == "tool/call"
            ? data["callId"]?.stringValue
            : toolResultCallID(entry)
        guard let callID, !callID.isEmpty else { return nil }
        return ToolOccurrenceKey(turn: turn, step: step, callID: callID)
    }

    private static func isReplacementSurfaceEvent(_ event: SessionEventWire) -> Bool {
        event.surfaceOp?.objectValue?["op"]?.stringValue == "replace"
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
