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
                sessionID: session.id,
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
    @Published private(set) var imageLimits: RemoteImageLimits?
    @Published private(set) var fileReferencesSupported: Bool?
    @Published private(set) var sessionReferencesSupported: Bool?
    @Published private(set) var subagentCatalog: RemoteSubagentCatalog?
    @Published private(set) var isLoadingSubagents = false
    @Published private(set) var subagentErrorMessage: String?
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
    private var refreshGeneration = 0
    private var modelGeneration = 0
    private var attachmentCache: [AttachmentKey: CachedAttachment] = [:]
    private var attachmentTasks: [AttachmentKey: Task<RemoteImageAttachmentPayload, Error>] = [:]
    private var attachmentAccessCounter = 0
    private var attachmentCacheBytes = 0
    private let attachmentLimiter = RemoteAttachmentLimiter(limit: 3)
    private var subagentRefreshGeneration = 0
    private var subagentRefreshTask: Task<Void, Never>?

    private struct CachedAttachment {
        let data: Data
        var lastAccess: Int
    }

    private struct AttachmentKey: Hashable {
        let sessionID: String
        let attachmentID: String
    }

    private static let attachmentCacheLimit = 32 * 1_024 * 1_024

    init(client: any HarnessRemoteClient, session: RemoteSessionSummary) {
        self.client = client
        self.session = session
    }

    var supportsReferences: Bool? {
        if fileReferencesSupported == true || sessionReferencesSupported == true { return true }
        if fileReferencesSupported == false && sessionReferencesSupported == false { return false }
        return nil
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
            subagentRefreshGeneration += 1
            subagentRefreshTask?.cancel()
            subagentRefreshTask = nil
        }

        await refresh()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(session.running ? 1 : 3))
            guard !Task.isCancelled else { return }
            await refresh(silently: true)
        }
    }

    func refresh(silently: Bool = false) async {
        refreshGeneration += 1
        let generation = refreshGeneration
        if !silently && items.isEmpty { isLoading = true }
        do {
            async let latestSnapshot = client.conversation(
                sessionID: session.id,
                maxMessages: historyMessageLimit
            )
            async let latestSessions = client.sessions()
            let (snapshot, sessions) = try await (latestSnapshot, latestSessions)
            guard generation == refreshGeneration, !Task.isCancelled else { return }
            items = snapshot.items
            trajectory = snapshot.trajectory
            stats = snapshot.stats
            goal = snapshot.goal
            plan = snapshot.plan
            imageLimits = snapshot.imageLimits
            hasMoreHistory = snapshot.hasMore
            hasLoadedConversationSnapshot = true
            if let latest = sessions.first(where: { $0.id == session.id }) {
                apply(latest)
            }
            errorMessage = nil
            requestSubagentRefresh()
        } catch {
            guard generation == refreshGeneration, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
        guard generation == refreshGeneration else { return }
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

    func send(
        _ text: String,
        images: [RemotePromptImage],
        steer: Bool
    ) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!trimmed.isEmpty || !images.isEmpty),
              !isSending,
              !isCancelling else { return false }
        isSending = true
        defer { isSending = false }
        do {
            try await client.send(
                trimmed,
                images: images,
                to: session.id,
                steer: session.running && steer
            )
            await refresh(silently: true)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func fileReferences(query: String) async throws -> [RemoteFileReferenceCandidate] {
        do {
            let values = try await client.fileReferences(sessionID: session.id, query: query)
            fileReferencesSupported = true
            return values
        } catch {
            return try handleReferenceError(error, domain: .file)
        }
    }

    func sessionReferences(query: String) async throws -> [RemoteSessionReferenceCandidate] {
        do {
            let values = try await client.sessionReferences(sessionID: session.id, query: query)
            sessionReferencesSupported = true
            return values
        } catch {
            return try handleReferenceError(error, domain: .session)
        }
    }

    func refreshSubagents() async {
        subagentRefreshGeneration += 1
        subagentRefreshTask?.cancel()
        subagentRefreshTask = nil
        requestSubagentRefresh()
        await subagentRefreshTask?.value
    }

    func attachmentData(
        for attachment: RemoteImageAttachment,
        sessionID: String? = nil
    ) async throws -> Data {
        let resolvedSessionID = sessionID ?? session.id
        let key = AttachmentKey(
            sessionID: resolvedSessionID,
            attachmentID: attachment.attachmentID
        )
        attachmentAccessCounter += 1
        if var cached = attachmentCache[key] {
            cached.lastAccess = attachmentAccessCounter
            attachmentCache[key] = cached
            return cached.data
        }

        let task: Task<RemoteImageAttachmentPayload, Error>
        if let existing = attachmentTasks[key] {
            task = existing
        } else {
            let client = client
            let limiter = attachmentLimiter
            task = Task {
                try await limiter.run {
                    try await client.attachment(
                        sessionID: resolvedSessionID,
                        attachmentID: attachment.attachmentID
                    )
                }
            }
            attachmentTasks[key] = task
        }

        do {
            let payload = try await task.value
            attachmentTasks[key] = nil
            guard payload.attachment == attachment else {
                throw HarnessRemoteClientError.mismatchedResponse
            }
            attachmentAccessCounter += 1
            if var cached = attachmentCache[key] {
                cached.lastAccess = attachmentAccessCounter
                attachmentCache[key] = cached
                return cached.data
            }
            attachmentCache[key] = CachedAttachment(
                data: payload.data,
                lastAccess: attachmentAccessCounter
            )
            attachmentCacheBytes += payload.data.count
            trimAttachmentCache(protecting: key)
            return payload.data
        } catch {
            attachmentTasks[key] = nil
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
        guard session.running, !isCancelling, !isSending else { return }
        isCancelling = true
        defer { isCancelling = false }
        do {
            try await client.cancel(sessionID: session.id)
            await refresh(silently: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func respond(_ decision: RemoteInteractionDecision) async -> Bool {
        guard let interaction, !isResponding else { return false }
        isResponding = true
        defer { isResponding = false }
        do {
            try await client.respond(to: interaction, decision: decision)
            self.interaction = nil
            await refresh(silently: true)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
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
                sessionID: session.id,
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
            sessionID: latest.id,
            body: "“\(latest.title)”已在你的电脑上完成。"
        ))
    }

    private func requestSubagentRefresh() {
        guard subagentRefreshTask == nil else { return }
        isLoadingSubagents = true
        subagentRefreshGeneration += 1
        let generation = subagentRefreshGeneration
        let client = client
        let parentSessionID = session.id
        subagentRefreshTask = Task { [weak self] in
            let result: Result<RemoteSubagentCatalog, Error>
            do {
                result = .success(try await client.subagents(parentSessionID: parentSessionID))
            } catch {
                result = .failure(error)
            }
            guard let self,
                  generation == self.subagentRefreshGeneration,
                  !Task.isCancelled else { return }
            self.subagentRefreshTask = nil
            self.isLoadingSubagents = false
            switch result {
            case .success(let catalog):
                self.subagentCatalog = catalog
                self.subagentErrorMessage = nil
            case .failure(let error):
                self.subagentErrorMessage = error.localizedDescription
            }
        }
    }

    private enum ReferenceDomain {
        case file
        case session
    }

    private func handleReferenceError<Value>(
        _ error: Error,
        domain: ReferenceDomain
    ) throws -> Value {
        if let remoteError = error as? HarnessRemoteClientError,
           case .server(404) = remoteError {
            switch domain {
            case .file: fileReferencesSupported = false
            case .session: sessionReferencesSupported = false
            }
            throw HarnessRemoteClientError.api(
                code: "references-unsupported",
                message: "当前电脑版本不支持引用，请更新到 DSH Desktop v0.3.0 或更高版本。"
            )
        }
        throw error
    }

    private func trimAttachmentCache(protecting protectedKey: AttachmentKey) {
        while attachmentCacheBytes > Self.attachmentCacheLimit,
              let candidate = attachmentCache
                .filter({ $0.key != protectedKey })
                .min(by: { $0.value.lastAccess < $1.value.lastAccess }) {
            attachmentCacheBytes -= candidate.value.data.count
            attachmentCache[candidate.key] = nil
        }
    }
}

@MainActor
final class RemoteSubagentConversationViewModel: ObservableObject {
    @Published private(set) var child: RemoteSubagentEntry
    @Published private(set) var parentAvailable: Bool
    @Published private(set) var items: [RemoteConversationItem] = []
    @Published private(set) var hasMoreHistory = false
    @Published private(set) var isLoading = true
    @Published private(set) var isLoadingOlder = false
    @Published private(set) var isSending = false
    @Published private(set) var isInterrupting = false
    @Published private(set) var errorMessage: String?

    let client: any HarnessRemoteClient
    let parentSessionID: String
    private var historyMessageLimit = 80
    private var refreshGeneration = 0
    private var catalogGeneration = 0
    private var catalogTask: Task<Void, Never>?

    init(
        client: any HarnessRemoteClient,
        parentSessionID: String,
        parentAvailable: Bool,
        child: RemoteSubagentEntry
    ) {
        self.client = client
        self.parentSessionID = parentSessionID
        self.parentAvailable = parentAvailable
        self.child = child
    }

    func monitor() async {
        defer {
            catalogGeneration += 1
            catalogTask?.cancel()
            catalogTask = nil
        }
        await refresh()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(child.activity == .running ? 1 : 3))
            guard !Task.isCancelled else { return }
            await refresh(silently: true)
        }
    }

    func refresh(silently: Bool = false) async {
        refreshGeneration += 1
        let generation = refreshGeneration
        if !silently && items.isEmpty { isLoading = true }
        do {
            let snapshot = try await client.subagentConversation(
                parentSessionID: parentSessionID,
                child: child,
                maxMessages: historyMessageLimit
            )
            guard generation == refreshGeneration, !Task.isCancelled else { return }
            items = snapshot.items
            hasMoreHistory = snapshot.hasMore
            errorMessage = nil
            requestCatalogRefresh()
        } catch {
            guard generation == refreshGeneration, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
        guard generation == refreshGeneration else { return }
        isLoading = false
    }

    func loadOlderHistory() async {
        guard hasMoreHistory, !isLoadingOlder else { return }
        isLoadingOlder = true
        historyMessageLimit += 80
        await refresh(silently: true)
        isLoadingOlder = false
    }

    func send(_ text: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard child.mode == .continuable,
              parentAvailable,
              !trimmed.isEmpty,
              !isSending,
              !isInterrupting else { return false }
        isSending = true
        defer { isSending = false }
        do {
            try await client.promptSubagent(
                parentSessionID: parentSessionID,
                child: child,
                text: trimmed
            )
            child = replacingActivity(.running)
            await refresh(silently: true)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func interrupt() async {
        guard child.mode == .continuable,
              child.activity == .running,
              !isInterrupting,
              !isSending else { return }
        isInterrupting = true
        defer { isInterrupting = false }
        do {
            try await client.interruptSubagent(
                parentSessionID: parentSessionID,
                child: child
            )
            await refresh(silently: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    private func replacingActivity(
        _ activity: RemoteSubagentEntry.Activity
    ) -> RemoteSubagentEntry {
        RemoteSubagentEntry(
            id: child.id,
            mode: child.mode,
            activity: activity,
            hasChildren: child.hasChildren,
            label: child.label,
            diagnosticReason: child.diagnosticReason
        )
    }

    private func requestCatalogRefresh() {
        guard catalogTask == nil else { return }
        catalogGeneration += 1
        let generation = catalogGeneration
        let client = client
        let parentSessionID = parentSessionID
        let childID = child.id
        catalogTask = Task { [weak self] in
            let catalog = try? await client.subagents(parentSessionID: parentSessionID)
            guard let self,
                  generation == self.catalogGeneration,
                  !Task.isCancelled else { return }
            self.catalogTask = nil
            if let catalog { self.parentAvailable = catalog.parentAvailable }
            if let latest = catalog?.entries.first(where: { $0.id == childID }) {
                self.child = latest
            }
        }
    }
}
