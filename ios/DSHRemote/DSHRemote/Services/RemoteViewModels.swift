import Combine
import Foundation

private actor RemoteAttachmentLimiter {
    private let limit: Int
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = max(limit, 1)
    }

    func run<Value: Sendable>(
        _ operation: @Sendable () async throws -> Value
    ) async throws -> Value {
        await acquire()
        defer { release() }
        try Task.checkCancellation()
        return try await operation()
    }

    private func acquire() async {
        if active < limit {
            active += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            active -= 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}

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
    @Published private(set) var goal: RemoteGoalState?
    @Published private(set) var plan: RemotePlanState?
    @Published private(set) var modelDirectory: RemoteModelDirectory?
    @Published private(set) var isLoadingModels = false
    @Published private(set) var isSelectingModel = false
    @Published private(set) var modelErrorMessage: String?
    @Published private(set) var hasMoreHistory = false
    @Published private(set) var interaction: RemoteInteraction?
    @Published private(set) var isLoading = true
    @Published private(set) var hasLoadedInitialSnapshot = false
    @Published private(set) var hasLoadedConversationSnapshot = false
    @Published private(set) var isLoadingOlder = false
    @Published private(set) var isSending = false
    @Published private(set) var isCancelling = false
    @Published private(set) var isResponding = false
    @Published private(set) var errorMessage: String?

    let client: any HarnessRemoteClient
    private var lastRunning: Bool?
    private var historyMessageLimit = 80
    private var modelGeneration = 0
    private var attachmentCache: [String: CachedAttachment] = [:]
    private var attachmentTasks: [String: Task<RemoteImageAttachmentPayload, Error>] = [:]
    private var attachmentAccessCounter = 0
    private var attachmentCacheBytes = 0
    private let attachmentLimiter = RemoteAttachmentLimiter(limit: 3)

    private struct CachedAttachment {
        let data: Data
        var lastAccess: Int
    }

    private static let attachmentCacheLimit = 32 * 1_024 * 1_024

    init(client: any HarnessRemoteClient, session: RemoteSessionSummary) {
        self.client = client
        self.session = session
    }

    func monitor() async {
        let modelsTask = Task { [weak self] in
            await self?.refreshModels()
        }
        let eventsTask = Task { [weak self] in
            guard let self else { return }
            for await event in client.liveEvents() {
                guard !Task.isCancelled else { return }
                await handle(event)
            }
        }
        defer {
            modelsTask.cancel()
            eventsTask.cancel()
            attachmentTasks.values.forEach { $0.cancel() }
            attachmentTasks.removeAll()
        }

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
            goal = snapshot.goal
            plan = snapshot.plan
            hasMoreHistory = snapshot.hasMore
            hasLoadedConversationSnapshot = true
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

    func refreshModels() async {
        guard !isSelectingModel else { return }
        modelGeneration += 1
        let generation = modelGeneration
        isSelectingModel = false
        isLoadingModels = true
        defer {
            if generation == modelGeneration { isLoadingModels = false }
        }

        do {
            let directory = try await client.models(sessionID: session.id)
            guard generation == modelGeneration, !Task.isCancelled else { return }
            modelDirectory = directory
            modelErrorMessage = nil
        } catch {
            guard generation == modelGeneration, !Task.isCancelled else { return }
            modelErrorMessage = error.localizedDescription
        }
    }

    func selectModel(_ selection: RemoteModelSelection) async -> Bool {
        guard !isSelectingModel else { return false }
        modelGeneration += 1
        let generation = modelGeneration
        isLoadingModels = false
        isSelectingModel = true
        defer {
            if generation == modelGeneration { isSelectingModel = false }
        }

        do {
            let selected = try await client.selectModel(sessionID: session.id, selection: selection)
            guard generation == modelGeneration, !Task.isCancelled else { return false }
            if let directory = modelDirectory {
                modelDirectory = RemoteModelDirectory(
                    current: selected,
                    routable: true,
                    groups: directory.groups,
                    failures: directory.failures
                )
            } else {
                modelDirectory = RemoteModelDirectory(
                    current: selected,
                    routable: true,
                    groups: [],
                    failures: []
                )
            }
            modelErrorMessage = nil
            return true
        } catch {
            guard generation == modelGeneration, !Task.isCancelled else { return false }
            modelErrorMessage = error.localizedDescription
            return false
        }
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

    func attachmentData(for attachment: RemoteImageAttachment) async throws -> Data {
        attachmentAccessCounter += 1
        if var cached = attachmentCache[attachment.attachmentID] {
            cached.lastAccess = attachmentAccessCounter
            attachmentCache[attachment.attachmentID] = cached
            return cached.data
        }

        let task: Task<RemoteImageAttachmentPayload, Error>
        if let existing = attachmentTasks[attachment.attachmentID] {
            task = existing
        } else {
            let client = client
            let sessionID = session.id
            let limiter = attachmentLimiter
            task = Task {
                try await limiter.run {
                    try await client.attachment(
                        sessionID: sessionID,
                        attachmentID: attachment.attachmentID
                    )
                }
            }
            attachmentTasks[attachment.attachmentID] = task
        }

        do {
            let payload = try await task.value
            attachmentTasks[attachment.attachmentID] = nil
            guard payload.attachment == attachment else {
                throw HarnessRemoteClientError.mismatchedResponse
            }
            attachmentAccessCounter += 1
            if var cached = attachmentCache[attachment.attachmentID] {
                cached.lastAccess = attachmentAccessCounter
                attachmentCache[attachment.attachmentID] = cached
                return cached.data
            }
            attachmentCache[attachment.attachmentID] = CachedAttachment(
                data: payload.data,
                lastAccess: attachmentAccessCounter
            )
            attachmentCacheBytes += payload.data.count
            trimAttachmentCache(protecting: attachment.attachmentID)
            return payload.data
        } catch {
            attachmentTasks[attachment.attachmentID] = nil
            throw error
        }
    }

    func updateQueue(_ item: RemoteQueuedMessage, action: RemoteQueueAction) async {
        if case .edit = action, item.attachmentCount > 0 {
            errorMessage = "带图片的排队消息不能只编辑文字；请删除后重新发送。"
            return
        }
        do {
            try await client.updateQueue(sessionID: session.id, itemID: item.id, action: action)
            switch action {
            case .edit(let text):
                if let index = queue.firstIndex(where: { $0.id == item.id }) {
                    queue[index] = RemoteQueuedMessage(
                        id: item.id,
                        placement: item.placement,
                        preview: text,
                        text: text,
                        attachmentCount: item.attachmentCount
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
        guard session.running, !isCancelling else { return }
        isCancelling = true
        defer { isCancelling = false }
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

    private func trimAttachmentCache(protecting protectedID: String) {
        while attachmentCacheBytes > Self.attachmentCacheLimit,
              let candidate = attachmentCache
                .filter({ $0.key != protectedID })
                .min(by: { $0.value.lastAccess < $1.value.lastAccess }) {
            attachmentCacheBytes -= candidate.value.data.count
            attachmentCache[candidate.key] = nil
        }
    }
}
