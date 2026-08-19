import Combine
import Foundation

@MainActor
final class RemoteHostViewModel: ObservableObject {
    @Published private(set) var sessions: [RemoteSessionSummary] = []
    @Published private(set) var workspaceSnapshot: RemoteWorkspaceSnapshot?
    @Published private(set) var archivedSessionIDs: Set<String> = []
    @Published private(set) var usesDirectoryProjectFallback = false
    @Published private(set) var isLoadingProjects = false
    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdated: Date?

    let client: any HarnessRemoteClient
    private var runningBySession: [String: Bool]?
    private var refreshGeneration = 0
    private var workspaceRefreshGeneration = 0
    private var workspaceRefreshTask: Task<Void, Never>?

    init(client: any HarnessRemoteClient) {
        self.client = client
    }

    func monitor() async {
        defer { cancelWorkspaceRefresh() }
        await refresh()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await refresh(silently: true)
        }
    }

    func refresh(silently: Bool = false) async {
        refreshGeneration += 1
        let generation = refreshGeneration
        if !silently && sessions.isEmpty && workspaceSnapshot == nil { isLoading = true }
        if !silently { cancelWorkspaceRefresh() }

        do {
            let newSessions = try await client.sessions()
            guard generation == refreshGeneration else { return }
            notifyCompletedSessions(in: newSessions)
            sessions = newSessions
            lastUpdated = Date()
            errorMessage = nil
            requestWorkspaceRefresh()
        } catch {
            guard generation == refreshGeneration else { return }
            errorMessage = error.localizedDescription
            cancelWorkspaceRefresh()
        }
        isLoading = false
    }

    private func requestWorkspaceRefresh() {
        guard workspaceRefreshTask == nil else { return }

        isLoadingProjects = true
        workspaceRefreshGeneration += 1
        let generation = workspaceRefreshGeneration
        let client = client
        workspaceRefreshTask = Task { [weak self] in
            let result: Result<RemoteWorkspaceSnapshot, Error>
            do {
                result = .success(try await client.workspaces())
            } catch {
                result = .failure(error)
            }
            self?.finishWorkspaceRefresh(
                result,
                generation: generation,
                wasCancelled: Task.isCancelled
            )
        }
    }

    private func finishWorkspaceRefresh(
        _ result: Result<RemoteWorkspaceSnapshot, Error>,
        generation: Int,
        wasCancelled: Bool
    ) {
        guard generation == workspaceRefreshGeneration else { return }
        workspaceRefreshTask = nil
        isLoadingProjects = false
        guard !wasCancelled else { return }

        switch result {
        case .success(let snapshot):
            workspaceSnapshot = snapshot
            archivedSessionIDs = snapshot.archivedSessionIDs
            usesDirectoryProjectFallback = false
        case .failure:
            workspaceSnapshot = nil
            usesDirectoryProjectFallback = true
        }
    }

    private func cancelWorkspaceRefresh() {
        workspaceRefreshGeneration += 1
        workspaceRefreshTask?.cancel()
        workspaceRefreshTask = nil
        isLoadingProjects = false
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
    @Published private(set) var trajectory: [RemoteTrajectoryRecord] = []
    @Published private(set) var queue: [RemoteQueuedMessage] = []
    @Published private(set) var stats: RemoteConversationStats?
    @Published private(set) var hasMoreHistory = false
    @Published private(set) var interaction: RemoteInteraction?
    @Published private(set) var isLoading = true
    @Published private(set) var hasLoadedInitialSnapshot = false
    @Published private(set) var isLoadingOlder = false
    @Published private(set) var isSending = false
    @Published private(set) var isResponding = false
    @Published private(set) var errorMessage: String?

    let client: any HarnessRemoteClient
    private var lastRunning: Bool?
    private var historyMessageLimit = 80

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
            async let latestSnapshot = client.conversation(
                sessionID: session.id,
                maxMessages: historyMessageLimit
            )
            async let latestSessions = client.sessions()
            let (snapshot, sessions) = try await (latestSnapshot, latestSessions)
            items = snapshot.items
            trajectory = snapshot.trajectory
            stats = snapshot.stats
            hasMoreHistory = snapshot.hasMore
            if let latest = sessions.first(where: { $0.id == session.id }) {
                apply(latest)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
        hasLoadedInitialSnapshot = true
    }

    func loadOlderHistory() async {
        guard hasMoreHistory, !isLoadingOlder else { return }
        isLoadingOlder = true
        historyMessageLimit += 80
        await refresh(silently: true)
        isLoadingOlder = false
    }

    func send(_ text: String, steer: Bool) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return false }
        isSending = true
        defer { isSending = false }
        do {
            try await client.send(trimmed, to: session.id, steer: session.running && steer)
            await refresh(silently: true)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func updateQueue(_ item: RemoteQueuedMessage, action: RemoteQueueAction) async {
        do {
            try await client.updateQueue(sessionID: session.id, itemID: item.id, action: action)
            switch action {
            case .edit(let text):
                if let index = queue.firstIndex(where: { $0.id == item.id }) {
                    queue[index] = RemoteQueuedMessage(
                        id: item.id,
                        placement: item.placement,
                        preview: text,
                        text: text
                    )
                }
            case .remove, .steer:
                queue.removeAll { $0.id == item.id }
            }
        } catch {
            errorMessage = error.localizedDescription
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
        case .queueChanged(let sessionID, let items):
            if sessionID == session.id { queue = items }
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
