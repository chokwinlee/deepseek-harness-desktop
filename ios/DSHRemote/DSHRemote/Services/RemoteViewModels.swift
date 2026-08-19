import Combine
import Foundation

@MainActor
final class RemoteHostViewModel: ObservableObject {
    @Published private(set) var sessions: [RemoteSessionSummary] = []
    @Published private(set) var description: RemoteHostDescription?
    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdated: Date?

    let client: any HarnessRemoteClient
    private var runningBySession: [String: Bool]?

    init(client: any HarnessRemoteClient) {
        self.client = client
    }

    func monitor() async {
        await refresh()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await refresh(silently: true)
        }
    }

    func refresh(silently: Bool = false) async {
        if !silently && sessions.isEmpty { isLoading = true }
        do {
            async let description = client.describe()
            async let sessions = client.sessions()
            let (newDescription, newSessions) = try await (description, sessions)
            notifyCompletedSessions(in: newSessions)
            self.description = newDescription
            self.sessions = newSessions
            lastUpdated = Date()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func notifyCompletedSessions(in sessions: [RemoteSessionSummary]) {
        let next = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0.running) })
        defer { runningBySession = next }
        guard let previous = runningBySession else { return }
        for session in sessions where previous[session.id] == true && !session.running {
            RemoteNotificationManager.shared.deliver(RemoteNotificationEvent(
                id: "completed:\(session.id):\(session.updatedAt.timeIntervalSince1970)",
                kind: .completed,
                body: "“\(session.title)”已在你的电脑上完成。"
            ))
        }
    }
}

@MainActor
final class RemoteConversationViewModel: ObservableObject {
    @Published private(set) var session: RemoteSessionSummary
    @Published private(set) var items: [RemoteConversationItem] = []
    @Published private(set) var interaction: RemoteInteraction?
    @Published private(set) var isLoading = true
    @Published private(set) var isSending = false
    @Published private(set) var isResponding = false
    @Published private(set) var errorMessage: String?

    let client: any HarnessRemoteClient
    private var lastRunning: Bool?

    init(client: any HarnessRemoteClient, session: RemoteSessionSummary) {
        self.client = client
        self.session = session
    }

    func monitor() async {
        let eventsTask = Task { [weak self] in
            guard let self else { return }
            for await event in client.liveEvents() {
                guard !Task.isCancelled else { return }
                await handle(event)
            }
        }
        defer { eventsTask.cancel() }

        await refresh()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(session.running ? 1 : 3))
            guard !Task.isCancelled else { return }
            await refresh(silently: true)
        }
    }

    func refresh(silently: Bool = false) async {
        if !silently && items.isEmpty { isLoading = true }
        do {
            async let latestItems = client.conversation(sessionID: session.id)
            async let latestSessions = client.sessions()
            let (newItems, sessions) = try await (latestItems, latestSessions)
            items = newItems
            if let latest = sessions.first(where: { $0.id == session.id }) {
                apply(latest)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func send(_ text: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return false }
        isSending = true
        defer { isSending = false }
        do {
            try await client.send(trimmed, to: session.id, steer: session.running)
            await refresh(silently: true)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func cancel() async {
        guard session.running else { return }
        do {
            try await client.cancel(sessionID: session.id)
            await refresh(silently: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func respond(_ decision: RemoteInteractionDecision) async {
        guard let interaction, !isResponding else { return }
        isResponding = true
        defer { isResponding = false }
        do {
            try await client.respond(to: interaction, decision: decision)
            self.interaction = nil
            await refresh(silently: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    private func handle(_ event: RemoteLiveEvent) async {
        switch event {
        case .sessionChanged(let sessionID):
            if sessionID == session.id { await refresh(silently: true) }
        case .interaction(let interaction):
            guard interaction.sessionID == session.id else { return }
            self.interaction = interaction
            RemoteNotificationManager.shared.deliver(RemoteNotificationEvent(
                id: "attention:\(interaction.id)",
                kind: .attention,
                body: "“\(session.title)”正在等待你的确认。"
            ))
        case .interactionResolved(let id):
            if interaction?.id == id { interaction = nil }
        }
    }

    private func apply(_ latest: RemoteSessionSummary) {
        defer {
            lastRunning = latest.running
            session = latest
        }
        guard lastRunning == true && !latest.running else { return }
        RemoteNotificationManager.shared.deliver(RemoteNotificationEvent(
            id: "completed:\(latest.id):\(latest.updatedAt.timeIntervalSince1970)",
            kind: .completed,
            body: "“\(latest.title)”已在你的电脑上完成。"
        ))
    }
}
