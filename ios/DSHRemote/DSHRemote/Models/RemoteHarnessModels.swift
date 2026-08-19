import Foundation

enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var arrayValue: [JSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    var numberValue: Double? {
        guard case .number(let value) = self else { return nil }
        return value
    }
}

struct RemoteHostDescription: Sendable {
    let version: String
    let attachedSessions: Int
}

struct RemoteSessionSummary: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let updatedAt: Date
    let running: Bool
    let projectName: String?
}

struct RemoteConversationSnapshot: Hashable, Sendable {
    let items: [RemoteConversationItem]
    let hasMore: Bool
    let stats: RemoteConversationStats?
    var trajectory: [RemoteTrajectoryRecord] = []
}

struct RemoteConversationStats: Hashable, Sendable {
    let turns: Int
    let steps: Int
    let llmDuration: TimeInterval
    let toolDuration: TimeInterval
    let inputTokens: Int
    let outputTokens: Int
}

struct RemoteDetailSection: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case text
        case code(language: String?)
        case diff
        case list
    }

    let id: String
    let title: String?
    let content: String
    let kind: Kind
}

struct RemoteConversationItem: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case user
        case assistant
        case tool
        case context
        case status
    }

    enum State: Hashable, Sendable {
        case info
        case running
        case succeeded
        case failed
        case stopped
    }

    enum ToolCard: Hashable, Sendable {
        case generic
        case terminal
        case diff
        case search
        case read
        case web
    }

    let id: String
    var sequence: Int = 0
    let kind: Kind
    let title: String?
    let text: String
    let time: Date
    var state: State = .info
    var toolCard: ToolCard? = nil
    var toolCategory: String? = nil
    var reasoning: String? = nil
    var details: [RemoteDetailSection] = []
    var metadata: [String] = []
    var isStreaming = false
}

struct RemoteQueuedMessage: Identifiable, Hashable, Sendable {
    enum Placement: String, Hashable, Sendable {
        case queued
        case steering
        case context
    }

    let id: String
    let placement: Placement
    let preview: String
    let text: String?
}

struct RemoteTrajectoryRecord: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case input
        case context
        case request
        case assistant
        case tool
        case lifecycle
    }

    let id: String
    let sequence: Int
    let turn: Int?
    let step: Int?
    let kind: Kind
    let title: String
    let summary: String
    let time: Date
    let duration: TimeInterval?
    let state: RemoteConversationItem.State
    var details: [RemoteDetailSection] = []
}

enum RemoteQueueAction: Hashable, Sendable {
    case edit(String)
    case remove
    case steer
}

struct RemoteQuestion: Identifiable, Hashable, Sendable {
    struct Option: Identifiable, Hashable, Sendable {
        let label: String
        let description: String?

        var id: String { label }
    }

    let id: String
    let header: String?
    let question: String
    let detail: String?
    let options: [Option]
    let allowsMultipleSelection: Bool
}

struct RemoteInteraction: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case approval(toolName: String, reason: String?)
        case questions([RemoteQuestion])
    }

    let id: String
    let rpcID: String
    let sessionID: String
    let approvalID: String?
    let kind: Kind
}

struct RemoteQuestionAnswer: Hashable, Sendable {
    let questionID: String
    let selected: [String]
    let custom: String?
}

enum RemoteInteractionDecision: Hashable, Sendable {
    case allowOnce
    case reject
    case answer([RemoteQuestionAnswer])
    case cancelQuestions
}

enum RemoteLiveEvent: Hashable, Sendable {
    case sessionChanged(String)
    case queueChanged(sessionID: String, items: [RemoteQueuedMessage])
    case interaction(RemoteInteraction)
    case interactionResolved(String)
}
