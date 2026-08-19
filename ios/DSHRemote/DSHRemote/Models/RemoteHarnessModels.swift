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

struct RemoteConversationItem: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case user
        case assistant
        case tool
        case status
    }

    let id: String
    let kind: Kind
    let title: String?
    let text: String
    let time: Date
    var isStreaming = false
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
    case interaction(RemoteInteraction)
    case interactionResolved(String)
}
