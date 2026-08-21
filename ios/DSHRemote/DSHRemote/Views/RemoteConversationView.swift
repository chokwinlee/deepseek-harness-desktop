import SwiftUI
import UIKit
import ImageIO
import PhotosUI
import UniformTypeIdentifiers

private struct RemoteDraftReference: Identifiable, Hashable {
    enum Kind: Hashable {
        case file
        case session
    }

    let id: UUID
    var range: NSRange
    let displayText: String
    let submissionText: String
    let kind: Kind
}

private struct RemoteActiveReferenceToken: Hashable {
    let range: NSRange
    let query: String
    let quoted: Bool
}

struct RemoteConversationView: View {
    private enum BusyDelivery {
        case queue
        case steer
    }

    private enum ViewMode: String, CaseIterable {
        case conversation = "对话"
        case trajectory = "轨迹"
    }

    @StateObject private var viewModel: RemoteConversationViewModel
    @State private var draft = ""
    @State private var draftReferences: [RemoteDraftReference] = []
    @State private var composerSelection = NSRange(location: 0, length: 0)
    @State private var composerTextHeight: CGFloat = 38
    @State private var draftImages: [RemotePromptImage] = []
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isPreparingImages = false
    @State private var composerNotice: String?
    @State private var showsReferenceSuggestions = false
    @State private var showsSubagents = false
    @State private var viewMode: ViewMode = .conversation
    @State private var trajectoryQuery = ""
    @State private var busyDelivery: BusyDelivery = .queue
    @State private var selectedDetail: RemoteConversationItem?
    @State private var didInitialPosition = false
    @State private var isNearBottom = true
    @State private var unseenUpdates = 0
    @State private var lastItemCount = 0
    @State private var shouldFollowNextSend = false
    @State private var showsModelPicker = false
    @State private var conversationVisibleAnchor: String?
    @State private var trajectoryVisibleAnchor: String?
    @State private var conversationVisibleAlignment: UnitPoint = .top
    @State private var trajectoryVisibleAlignment: UnitPoint = .top
    @State private var isRestoringViewMode = false
    @State private var pendingFollowAfterModeRestore = false
    @State private var viewModeGeneration = 0
    #if DEBUG
    @State private var didRunLiveAcceptance = false
    @State private var debugSubagent: RemoteSubagentEntry?
    #endif
    @FocusState private var composerFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    init(client: any HarnessRemoteClient, session: RemoteSessionSummary) {
        _viewModel = StateObject(wrappedValue: RemoteConversationViewModel(client: client, session: session))
        #if DEBUG
        let scenario = ProcessInfo.processInfo.environment["DSH_REMOTE_SCENARIO"]
        let liveView = scenario == "live-acceptance"
            ? ProcessInfo.processInfo.environment["DSH_REMOTE_LIVE_VIEW"]
            : nil
        _viewMode = State(initialValue:
            scenario == "trajectory" || scenario == "rc8-trajectory" ? .trajectory : .conversation
        )
        _showsModelPicker = State(initialValue: scenario == "models" || liveView == "models")
        if scenario == "details" {
            _selectedDetail = State(initialValue: Self.debugDetailItem)
        }
        if scenario == "references" || liveView == "references" {
            let liveReferenceQuery = ProcessInfo.processInfo.environment[
                "DSH_REMOTE_LIVE_REFERENCE_QUERY"
            ] ?? "README"
            let referenceDraft = liveView == "references"
                ? "@\(liveReferenceQuery)"
                : "@Sou"
            _draft = State(initialValue: referenceDraft)
            _composerSelection = State(initialValue: NSRange(
                location: (referenceDraft as NSString).length,
                length: 0
            ))
            _showsReferenceSuggestions = State(initialValue: true)
        }
        if scenario == "image-draft", let image = Self.debugDraftImage {
            _draftImages = State(initialValue: [image])
        }
        if scenario == "subagents" || liveView == "subagents" {
            _showsSubagents = State(initialValue: true)
        }
        if scenario == "live-acceptance",
           liveView == "subagent",
           let childID = ProcessInfo.processInfo.environment["DSH_REMOTE_LIVE_SUBAGENT_ID"],
           !childID.isEmpty {
            let activity = RemoteSubagentEntry.Activity(
                rawValue: ProcessInfo.processInfo.environment["DSH_REMOTE_LIVE_SUBAGENT_ACTIVITY"] ?? "inactive"
            ) ?? .inactive
            _debugSubagent = State(initialValue: RemoteSubagentEntry(
                id: childID,
                mode: .continuable,
                activity: activity,
                hasChildren: ProcessInfo.processInfo.environment[
                    "DSH_REMOTE_LIVE_SUBAGENT_HAS_CHILDREN"
                ] == "true",
                label: ProcessInfo.processInfo.environment["DSH_REMOTE_LIVE_SUBAGENT_LABEL"] ?? "remote-acceptance",
                diagnosticReason: nil
            ))
        }
        #endif
    }

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { viewport in
                ScrollView {
                    LazyVStack(spacing: viewMode == .conversation ? 16 : 0) {
                        if viewModel.hasMoreHistory {
                            Button {
                                let anchor = viewMode == .conversation
                                    ? viewModel.items.first?.id
                                    : (trajectoryVisibleAnchor
                                       ?? (trajectoryQuery.isEmpty
                                           ? (viewModel.trajectory.first?.id ?? "trajectory-top")
                                           : "trajectory-top"))
                                Task {
                                    await viewModel.loadOlderHistory()
                                    guard let anchor else { return }
                                    DispatchQueue.main.async {
                                        var transaction = Transaction()
                                        transaction.disablesAnimations = true
                                        withTransaction(transaction) {
                                            proxy.scrollTo(anchor, anchor: .top)
                                        }
                                    }
                                }
                            } label: {
                                if viewModel.isLoadingOlder {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label("加载更早记录", systemImage: "clock.arrow.circlepath")
                                }
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(RemoteTheme.accent)
                            .buttonStyle(RemotePressableRowButtonStyle(cornerRadius: 9))
                            .frame(minHeight: 44)
                            .disabled(viewModel.isLoadingOlder)
                        }

                        if viewModel.isLoading && viewModel.items.isEmpty {
                            RemoteLoadingState(
                                icon: "arrow.triangle.2.circlepath",
                                title: "正在同步会话",
                                message: "从你的电脑读取对话、轨迹和运行状态"
                            )
                            .padding(.top, 46)
                        } else if !viewModel.hasLoadedConversationSnapshot,
                                  let error = viewModel.errorMessage {
                            RemoteEmptyState(
                                icon: "wifi.exclamationmark",
                                title: "暂时无法读取会话",
                                message: error,
                                action: { Task { await viewModel.refresh() } }
                            ) {
                                Label("重新连接", systemImage: "arrow.clockwise")
                            }
                            .padding(.top, 38)
                        } else if viewMode == .conversation && viewModel.items.isEmpty {
                            RemoteEmptyState(
                                icon: "text.bubble",
                                title: "开始一项任务",
                                message: "输入你的目标，Harness 会在电脑上的当前项目中执行。"
                            )
                            .padding(.top, 38)
                        } else if viewMode == .conversation {
                            ForEach(viewModel.items) { item in
                                ConversationItemView(
                                    item: item,
                                    loadAttachment: { attachment in
                                        try await viewModel.attachmentData(for: attachment)
                                    },
                                    onOpenDetails: { selectedDetail = item }
                                )
                                .id(item.id)
                                .background {
                                    GeometryReader { itemGeometry in
                                        Color.clear.preference(
                                            key: ConversationVisibleAnchorPreferenceKey.self,
                                            value: [
                                                "conversation:\(item.id)": itemGeometry.frame(
                                                    in: .named("conversation-scroll")
                                                ),
                                            ]
                                        )
                                    }
                                }
                            }
                        } else {
                            TrajectoryLedgerView(
                                records: viewModel.trajectory,
                                query: $trajectoryQuery
                            ) { record in
                                selectedDetail = inspectorItem(for: record)
                            }
                        }

                        GeometryReader { marker in
                            Color.clear.preference(
                                key: ConversationBottomOffsetKey.self,
                                value: marker.frame(in: .named("conversation-scroll")).minY
                            )
                        }
                        .frame(height: 1)
                        .id("conversation-bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 20)
                    .opacity(contentIsPositioned && !isRestoringViewMode ? 1 : 0)
                }
                .coordinateSpace(name: "conversation-scroll")
                .scrollDismissesKeyboard(.interactively)
                .onPreferenceChange(ConversationBottomOffsetKey.self) { bottom in
                    guard viewMode == .conversation,
                          didInitialPosition,
                          !isRestoringViewMode else { return }
                    isNearBottom = bottom <= viewport.size.height + 140
                    if isNearBottom { unseenUpdates = 0 }
                }
                .onPreferenceChange(ConversationVisibleAnchorPreferenceKey.self) { positions in
                    guard didInitialPosition, !isRestoringViewMode else { return }
                    let prefix = viewMode == .conversation ? "conversation:" : "trajectory:"
                    let visible = positions.filter {
                        $0.key.hasPrefix(prefix)
                            && $0.value.maxY >= 0
                            && $0.value.minY <= viewport.size.height
                    }
                    guard let nearest = visible.min(by: {
                        visibleDistanceToTop($0.value) < visibleDistanceToTop($1.value)
                    }) else {
                        return
                    }
                    let anchor = String(nearest.key.dropFirst(prefix.count))
                    let alignment = scrollAlignment(
                        for: nearest.value,
                        viewportHeight: viewport.size.height
                    )
                    if viewMode == .conversation {
                        conversationVisibleAnchor = anchor
                        conversationVisibleAlignment = alignment
                    } else {
                        trajectoryVisibleAnchor = anchor
                        trajectoryVisibleAlignment = alignment
                    }
                }
                .onChange(of: viewMode) { _, mode in
                    restoreViewMode(mode, proxy: proxy)
                }
                .overlay(alignment: .bottomTrailing) {
                    if viewMode == .conversation, unseenUpdates > 0 {
                        Button {
                            withAnimation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 1)) {
                                proxy.scrollTo("conversation-bottom", anchor: .bottom)
                            }
                            unseenUpdates = 0
                        } label: {
                            Label("有新内容", systemImage: "arrow.down")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .foregroundStyle(.primary)
                                .background(RemoteTheme.surface, in: Capsule())
                                .overlay { Capsule().stroke(RemoteTheme.hairline) }
                                .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
                        }
                        .buttonStyle(RemotePressableRowButtonStyle(cornerRadius: 22))
                        .padding(14)
                    }
                }
                .onChange(of: viewModel.hasLoadedInitialSnapshot) { _, loaded in
                    guard loaded, !didInitialPosition else { return }
                    DispatchQueue.main.async {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            #if DEBUG
                            if let target = debugInitialScrollTarget {
                                proxy.scrollTo(target, anchor: .top)
                            } else if viewMode == .trajectory,
                                      let first = viewModel.trajectory.first?.id {
                                proxy.scrollTo(first, anchor: .top)
                                trajectoryVisibleAnchor = first
                            } else if viewMode == .trajectory {
                                proxy.scrollTo("trajectory-top", anchor: .top)
                            } else {
                                proxy.scrollTo("conversation-bottom", anchor: .bottom)
                            }
                            #else
                            if viewMode == .trajectory,
                               let first = viewModel.trajectory.first?.id {
                                proxy.scrollTo(first, anchor: .top)
                                trajectoryVisibleAnchor = first
                            } else if viewMode == .trajectory {
                                proxy.scrollTo("trajectory-top", anchor: .top)
                            } else {
                                proxy.scrollTo("conversation-bottom", anchor: .bottom)
                            }
                            #endif
                        }
                        lastItemCount = viewModel.items.count
                        didInitialPosition = true
                    }
                }
                .onChange(of: viewModel.items.last) { _, _ in
                    guard didInitialPosition else { return }
                    let added = max(viewModel.items.count - lastItemCount, 1)
                    lastItemCount = viewModel.items.count
                    guard viewMode == .conversation else {
                        shouldFollowNextSend = false
                        unseenUpdates = max(added, 1)
                        return
                    }
                    if isRestoringViewMode {
                        if isNearBottom || shouldFollowNextSend {
                            pendingFollowAfterModeRestore = true
                        } else {
                            unseenUpdates = max(added, 1)
                        }
                        return
                    }
                    if isNearBottom || shouldFollowNextSend {
                        if shouldFollowNextSend, !reduceMotion {
                            withAnimation(.spring(response: 0.30, dampingFraction: 1)) {
                                proxy.scrollTo("conversation-bottom", anchor: .bottom)
                            }
                        } else {
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                proxy.scrollTo("conversation-bottom", anchor: .bottom)
                            }
                        }
                        shouldFollowNextSend = false
                    } else {
                        unseenUpdates = max(added, 1)
                    }
                }
                .onChange(of: viewModel.isLoadingOlder) { wasLoading, isLoading in
                    if wasLoading && !isLoading { lastItemCount = viewModel.items.count }
                }
                .onChange(of: viewModel.goal) { _, _ in
                    guard viewMode == .conversation,
                          didInitialPosition,
                          !isRestoringViewMode,
                          isNearBottom else { return }
                    DispatchQueue.main.async {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            proxy.scrollTo("conversation-bottom", anchor: .bottom)
                        }
                    }
                }
                .onChange(of: viewModel.plan) { _, _ in
                    guard viewMode == .conversation,
                          didInitialPosition,
                          !isRestoringViewMode,
                          isNearBottom else { return }
                    DispatchQueue.main.async {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            proxy.scrollTo("conversation-bottom", anchor: .bottom)
                        }
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if viewModel.hasLoadedConversationSnapshot {
                        bottomDock(bottomSafeArea: viewport.safeAreaInsets.bottom)
                    }
                }
            }
        }
        .background(RemoteTheme.canvas)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                RemotePageHeader(
                    title: viewModel.session.title,
                    subtitle: viewModel.session.projectName ?? "Harness 会话"
                ) {
                    HStack(spacing: 6) {
                        Button {
                            showsSubagents = true
                        } label: {
                            HStack(spacing: 5) {
                                if viewModel.isLoadingSubagents,
                                   viewModel.subagentCatalog == nil {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Image(systemName: "person.2")
                                        .font(.caption.weight(.semibold))
                                }
                                if subagentCount > 0 {
                                    Text("\(subagentCount)")
                                        .font(.caption2.monospacedDigit().weight(.bold))
                                }
                            }
                            .foregroundStyle(subagentCount > 0 ? RemoteTheme.accent : Color.secondary)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 34)
                            .background(RemoteTheme.mutedSurface, in: Capsule())
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RemotePressableRowButtonStyle(cornerRadius: 12))
                        .accessibilityLabel("子代理")
                        .accessibilityValue(subagentCount > 0 ? "\(subagentCount) 个" : "暂无")

                        RemoteStatusPill(
                            text: viewModel.session.running ? "执行中" : "待命",
                            color: viewModel.session.running ? RemoteTheme.accent : RemoteTheme.success,
                            icon: viewModel.session.running ? "waveform" : "checkmark"
                        )
                    }
                }
                sessionSummaryLine
                DSHConversationTabBar(selection: Binding(
                    get: { viewMode },
                    set: { selectViewMode($0) }
                ))

                if viewMode == .trajectory {
                    trajectorySearch
                }

                if viewMode == .trajectory, viewModel.interaction != nil {
                    Button {
                        selectViewMode(.conversation)
                    } label: {
                        Label("有一项问题等待确认", systemImage: "exclamationmark.bubble.fill")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .foregroundStyle(RemoteTheme.warning)
                            .background(RemoteTheme.warning.opacity(0.08))
                    }
                    .buttonStyle(RemotePressableRowButtonStyle(cornerRadius: 9))
                }

                if let error = viewModel.errorMessage, viewModel.hasLoadedConversationSnapshot {
                    RemoteInlineNotice(
                        title: "操作没有完成",
                        message: error,
                        icon: "exclamationmark.triangle.fill",
                        tone: .danger,
                        actionTitle: "关闭",
                        action: viewModel.dismissError
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                }
                Rectangle()
                    .fill(RemoteTheme.hairline)
                    .frame(height: 0.5)
            }
            .background(RemoteTheme.canvas)
        }
        .remoteNavigationChromeHidden()
        .onAppear {
            RemoteNotificationManager.shared.setActiveSession(viewModel.session.id)
        }
        .onDisappear {
            RemoteNotificationManager.shared.clearActiveSession(viewModel.session.id)
        }
        .task { await viewModel.monitor() }
        #if DEBUG
        .task { await runLiveAcceptanceIfRequested() }
        #endif
        .onChange(of: viewModel.session.running) { wasRunning, isRunning in
            if !wasRunning && isRunning { busyDelivery = .queue }
        }
        .onChange(of: selectedPhotoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await preparePhotoItems(items) }
        }
        .onChange(of: draft) { _, _ in
            updateReferenceSuggestionVisibility()
        }
        .onChange(of: composerSelection) { _, _ in
            updateReferenceSuggestionVisibility()
        }
        .onChange(of: trajectoryQuery) { _, _ in
            trajectoryVisibleAnchor = nil
            trajectoryVisibleAlignment = .top
        }
        .onChange(of: composerNotice) { _, notice in
            guard let notice, !notice.isEmpty else { return }
            UIAccessibility.post(notification: .announcement, argument: notice)
        }
        .onChange(of: viewModel.errorMessage) { _, message in
            guard let message, !message.isEmpty else { return }
            UIAccessibility.post(
                notification: .announcement,
                argument: "操作没有完成，\(message)"
            )
        }
        .onChange(of: viewModel.modelErrorMessage) { _, message in
            guard let message, !message.isEmpty else { return }
            UIAccessibility.post(
                notification: .announcement,
                argument: "模型操作没有完成，\(message)"
            )
        }
        .sheet(item: $selectedDetail) { item in
            ConversationDetailSheet(
                item: item,
                loadAttachment: { attachment in
                    try await viewModel.attachmentData(for: attachment)
                }
            )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(RemoteTheme.canvas)
        }
        .sheet(isPresented: $showsModelPicker) {
            RemoteModelSelectionSheet(viewModel: viewModel)
                .presentationDetents(
                    dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large]
                )
                .presentationDragIndicator(.visible)
                .presentationBackground(RemoteTheme.canvas)
        }
        .sheet(isPresented: $showsSubagents, onDismiss: {
            Task { await viewModel.refreshSubagents() }
        }) {
            RemoteSubagentBrowserView(viewModel: viewModel)
                .presentationDetents(
                    dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large]
                )
                .presentationDragIndicator(.visible)
                .presentationBackground(RemoteTheme.canvas)
        }
        #if DEBUG
        .sheet(item: $debugSubagent) { child in
            NavigationStack {
                RemoteSubagentConversationView(
                    parentViewModel: viewModel,
                    parentSessionID: viewModel.session.id,
                    parentAvailable: true,
                    child: child
                )
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .presentationBackground(RemoteTheme.canvas)
        }
        #endif
    }

    private var contentIsPositioned: Bool {
        !viewModel.hasLoadedInitialSnapshot || viewModel.items.isEmpty || didInitialPosition
    }

    #if DEBUG
    private var debugInitialScrollTarget: String? {
        guard ProcessInfo.processInfo.environment["DSH_REMOTE_SCENARIO"] == "live-acceptance",
              ProcessInfo.processInfo.environment["DSH_REMOTE_LIVE_VIEW"] == "image-history" else {
            return nil
        }
        return viewModel.items.last(where: { !$0.attachments.isEmpty })?.id
    }
    #endif

    #if DEBUG
    @MainActor
    private func runLiveAcceptanceIfRequested() async {
        guard !didRunLiveAcceptance,
              ProcessInfo.processInfo.environment["DSH_REMOTE_SCENARIO"] == "live-acceptance",
              let action = ProcessInfo.processInfo.environment["DSH_REMOTE_LIVE_ACTION"],
              ["send-deepseek-references", "send-openrouter-image"].contains(action) else {
            return
        }
        didRunLiveAcceptance = true

        for _ in 0..<100 where !viewModel.hasLoadedConversationSnapshot {
            try? await Task.sleep(for: .milliseconds(100))
            if Task.isCancelled { return }
        }
        guard viewModel.hasLoadedConversationSnapshot else {
            composerNotice = "真实验收未能读取会话。"
            return
        }

        do {
            let files = try await viewModel.fileReferences(query: "README")
            let sessions = try await viewModel.sessionReferences(query: "Tauri")
            let fileMention = files
                .first(where: { $0.kind == .file })
                .flatMap { Self.formattedFileMention($0, preserveQuote: false) }
                ?? "@README.md"
            let sessionMention = sessions.first?.mention
            let context = [fileMention, sessionMention]
                .compactMap { $0 }
                .joined(separator: " ")
            let sent: Bool
            if action == "send-deepseek-references" {
                _ = await viewModel.selectModel(RemoteModelSelection(
                    provider: "deepseek-official",
                    model: "deepseek-v4-flash",
                    reasoningEffort: "off"
                ))
                let prompt = """
                DSH Remote v0.3 端到端验收。请读取并引用 \(context)，随后使用 subagent 工具创建一个名为 remote-acceptance 的 continuable 子代理，让它检查本项目 Remote 的安全边界并返回一句结论。最后简短汇总。
                """
                sent = await viewModel.send(prompt, images: [], steer: false)
            } else {
                _ = await viewModel.selectModel(RemoteModelSelection(
                    provider: "openrouter",
                    model: "google/gemini-2.5-flash-lite",
                    reasoningEffort: nil
                ))
                guard let sourceImage = Self.debugDraftImage else {
                    throw RemoteImagePreparationError.unreadable
                }
                let image = try await RemoteImagePreparer.prepare(
                    data: sourceImage.data,
                    declaredMediaType: sourceImage.mediaType,
                    name: "remote-acceptance.png",
                    limits: effectiveImageLimits
                )
                let prompt = """
                图片与引用回归验收。请读取 \(context)，并用一句话说明附图的主要形状与配色。
                """
                sent = await viewModel.send(prompt, images: [image], steer: false)
            }
            if !sent {
                composerNotice = viewModel.errorMessage ?? "真实验收消息发送失败。"
            }
        } catch {
            composerNotice = error.localizedDescription
        }
    }
    #endif

    private var subagentCount: Int {
        viewModel.subagentCatalog?.entries.lazy.filter { !$0.isDiagnostic }.count ?? 0
    }

    private func bottomDock(bottomSafeArea: CGFloat) -> some View {
        VStack(spacing: 0) {
            if viewModel.interaction == nil,
               let goal = viewModel.goal,
               goal.phase != .complete {
                RemoteGoalStatusDock(goal: goal) {
                    selectedDetail = goalDetailItem(goal)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, -5)
                .zIndex(0)
            }
            if viewModel.queue.contains(where: { $0.placement == .queued }) {
                QueueDockView(queue: viewModel.queue, isRunning: viewModel.session.running) { item, action in
                    Task { await viewModel.updateQueue(item, action: action) }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, -5)
                .zIndex(0)
            }
            if let interaction = viewModel.interaction {
                InteractionCard(
                    interaction: interaction,
                    isResponding: viewModel.isResponding,
                    onRespond: { decision in
                        Task {
                            let responded = await viewModel.respond(decision)
                            UINotificationFeedbackGenerator().notificationOccurred(
                                responded ? .success : .error
                            )
                        }
                    }
                )
                .id(interaction.id)
                .zIndex(1)
            } else {
                composer
                    .zIndex(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(
            .bottom,
            dockBottomPadding(bottomSafeArea: bottomSafeArea)
        )
        .background(
            LinearGradient(
                colors: [RemoteTheme.canvas.opacity(0), RemoteTheme.canvas],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
        )
    }

    private func dockBottomPadding(bottomSafeArea: CGFloat) -> CGFloat {
        guard !composerFocused, viewModel.interaction == nil else { return 2 }
        guard bottomSafeArea >= 30 else { return bottomSafeArea > 0 ? 0 : 2 }
        return -min(8, bottomSafeArea - 24)
    }

    @ViewBuilder
    private var sessionSummaryLine: some View {
        if let stats = viewModel.stats, stats.turns > 0 {
            HStack {
                Spacer(minLength: 8)
                Text("\(stats.turns) 轮 · \(stats.steps) 次调用")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 2)
        }
    }

    private var trajectorySearch: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("搜索标题、内容或工具输出", text: $trajectoryQuery)
                .font(.caption)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !trajectoryQuery.isEmpty {
                Button {
                    trajectoryQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(RemoteToolbarButtonStyle())
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 44)
        .background(RemoteTheme.mutedSurface, in: RoundedRectangle(cornerRadius: 9))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsReferenceSuggestions, let token = activeReferenceToken {
                RemoteReferenceSuggestions(
                    token: token,
                    fileLoader: { query in
                        try await viewModel.fileReferences(query: query)
                    },
                    sessionLoader: { query in
                        try await viewModel.sessionReferences(query: query)
                    },
                    onSelectFile: insertFileReference,
                    onSelectSession: insertSessionReference,
                    onDismiss: { showsReferenceSuggestions = false }
                )
            }

            if !draftImages.isEmpty || isPreparingImages {
                RemoteDraftImageRail(
                    images: draftImages,
                    isPreparing: isPreparingImages,
                    onRemove: removeDraftImage
                )
            }

            ZStack(alignment: .topLeading) {
                if draft.isEmpty {
                    Text("告诉 Harness 接下来要做什么")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                RemoteComposerTextView(
                    text: $draft,
                    references: $draftReferences,
                    selection: $composerSelection,
                    measuredHeight: $composerTextHeight,
                    isFocused: Binding(
                        get: { composerFocused },
                        set: { composerFocused = $0 }
                    ),
                    isEnabled: viewModel.interaction == nil,
                    maxHeight: verticalSizeClass == .compact ? 88 : 142
                )
                .frame(height: composerTextHeight)
            }

            if let composerNotice {
                Label(composerNotice, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(RemoteTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !modelIsRoutable {
                Label("当前模型不可用，请重新选择", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(RemoteTheme.warning)
            }

            composerControls
        }
        .padding(12)
        .background(RemoteTheme.surface, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(RemoteTheme.hairline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.10), radius: 12, y: 5)
    }

    @ViewBuilder
    private var composerControls: some View {
        if dynamicTypeSize.isAccessibilitySize
            && (viewModel.session.running || planStatusVisible) {
            VStack(spacing: 2) {
                HStack(spacing: 8) {
                    composerAddMenu
                    if viewModel.session.running {
                        deliverySelector
                    }
                    if planStatusVisible {
                        RemotePlanStatusLabel(plan: viewModel.plan!)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    modelSelector
                    Spacer(minLength: 0)
                    composerActions
                }
            }
        } else {
            HStack(spacing: 7) {
                composerAddMenu
                if viewModel.session.running {
                    deliverySelector
                }
                if planStatusVisible {
                    RemotePlanStatusLabel(plan: viewModel.plan!)
                }
                modelSelector
                Spacer(minLength: 0)
                composerActions
            }
        }
    }

    private var planStatusVisible: Bool {
        viewModel.plan?.effectiveActive == true
    }

    private var deliverySelector: some View {
        Menu {
            Button {
                busyDelivery = .queue
            } label: {
                Label("排队发送", systemImage: busyDelivery == .queue ? "checkmark" : "list.bullet")
            }
            Button {
                busyDelivery = .steer
            } label: {
                Label("插话发送", systemImage: busyDelivery == .steer ? "checkmark" : "arrow.triangle.branch")
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: busyDelivery == .queue ? "list.bullet" : "arrow.triangle.branch")
                Text(busyDelivery == .queue ? "排队" : "插话")
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .frame(minHeight: 34)
            .background(RemoteTheme.mutedSurface, in: Capsule())
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Capsule())
        }
        .accessibilityLabel("发送方式")
        .accessibilityValue(busyDelivery == .queue ? "排队发送" : "插话发送")
    }

    private var composerAddMenu: some View {
        Menu {
            PhotosPicker(
                selection: $selectedPhotoItems,
                maxSelectionCount: max(remainingImageSlots, 1),
                matching: .images
            ) {
                Label("从照片中选择", systemImage: "photo.on.rectangle")
            }
            .disabled(remainingImageSlots == 0)

            Button {
                pasteImage()
            } label: {
                Label("粘贴图片", systemImage: "doc.on.clipboard")
            }
            .disabled(remainingImageSlots == 0)

            Button {
                beginReferenceInsertion()
            } label: {
                Label(
                    viewModel.supportsReferences == false
                        ? "引用需要 Desktop v0.3.0"
                        : "引用文件或会话",
                    systemImage: "at"
                )
            }
            .disabled(viewModel.supportsReferences == false)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(RemoteTheme.mutedSurface, in: Circle())
                .frame(width: 44, height: 44)
        }
        .disabled(isPreparingImages || viewModel.interaction != nil)
        .accessibilityLabel("添加图片或引用")
    }

    private var modelSelector: some View {
        Button {
            showsModelPicker = true
        } label: {
            HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: 4) {
                if viewModel.isLoadingModels && viewModel.modelDirectory == nil {
                    ProgressView()
                        .controlSize(.mini)
                } else if viewModel.modelErrorMessage != nil && viewModel.modelDirectory == nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(RemoteTheme.warning)
                }
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(modelTriggerName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let effort = selectedEffortName {
                            Text(effort)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                } else {
                    Text(modelTriggerName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let effort = selectedEffortName {
                        Text("· \(effort)")
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(
                maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 170,
                minHeight: 44,
                alignment: .leading
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(RemotePressableRowButtonStyle(cornerRadius: 10))
        .disabled(viewModel.isSelectingModel)
        .accessibilityLabel(modelAccessibilityLabel)
        .accessibilityHint("打开模型选择")
        .layoutPriority(1)
    }

    private var composerActions: some View {
        HStack(spacing: 2) {
            if viewModel.session.running {
                Button {
                    Task { await viewModel.cancel() }
                } label: {
                    Group {
                        if viewModel.isCancelling {
                            ProgressView()
                                .controlSize(.small)
                                .tint(RemoteTheme.danger)
                        } else {
                            Image(systemName: "stop.fill")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(RemoteTheme.danger)
                        }
                    }
                    .frame(width: 34, height: 34)
                    .background(RemoteTheme.danger.opacity(0.10), in: Circle())
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(RemotePressableRowButtonStyle(cornerRadius: 22))
                .disabled(viewModel.isCancelling || viewModel.isSending)
                .accessibilityLabel(viewModel.isCancelling ? "正在停止任务" : "停止任务")
            }

            Button {
                let outgoing = submissionText
                let outgoingImages = draftImages
                shouldFollowNextSend = true
                Task {
                    if await viewModel.send(
                        outgoing,
                        images: outgoingImages,
                        steer: busyDelivery == .steer
                    ) {
                        draft = ""
                        draftReferences = []
                        composerSelection = NSRange(location: 0, length: 0)
                        draftImages = []
                        selectedPhotoItems = []
                        composerNotice = nil
                        showsReferenceSuggestions = false
                    } else {
                        shouldFollowNextSend = false
                    }
                }
            } label: {
                Group {
                    if viewModel.isSending {
                        ProgressView()
                            .tint(.white)
                            .controlSize(.small)
                    } else {
                        Image(systemName: viewModel.session.running && busyDelivery == .queue ? "text.badge.plus" : "arrow.up")
                            .font(.caption.weight(.bold))
                    }
                }
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(RemoteTheme.accentFill, in: Circle())
                .frame(width: 44, height: 44)
            }
            .buttonStyle(RemotePressableRowButtonStyle(cornerRadius: 22))
            .disabled(!canSendDraft)
            .opacity(canSendDraft ? 1 : 0.45)
            .accessibilityLabel(sendAccessibilityLabel)
        }
    }

    private var canSendDraft: Bool {
        (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draftImages.isEmpty)
            && !viewModel.isSending
            && !viewModel.isCancelling
            && !isPreparingImages
            && !viewModel.isSelectingModel
            && viewModel.interaction == nil
            && modelIsRoutable
    }

    private var effectiveImageLimits: RemoteImageLimits {
        viewModel.imageLimits ?? RemoteImageLimits(
            maxImageBytes: 3_670_016,
            maxImagesPerMessage: 20,
            maxMessageImageBytes: 100 * 1_024 * 1_024,
            maxImagePixels: 40_000_000,
            maxImageDimension: nil,
            mediaTypes: ["image/png", "image/jpeg", "image/webp", "image/gif"]
        )
    }

    private var remainingImageSlots: Int {
        max(effectiveImageLimits.maxImagesPerMessage - draftImages.count, 0)
    }

    private var submissionText: String {
        var value = draft as NSString
        for reference in draftReferences.sorted(by: { $0.range.location > $1.range.location }) {
            guard NSMaxRange(reference.range) <= value.length else { continue }
            value = value.replacingCharacters(
                in: reference.range,
                with: reference.submissionText
            ) as NSString
        }
        return value as String
    }

    private var activeReferenceToken: RemoteActiveReferenceToken? {
        guard let token = Self.activeReferenceToken(
            in: draft,
            selection: composerSelection
        ), !draftReferences.contains(where: {
            NSIntersectionRange($0.range, token.range).length > 0
        }) else { return nil }
        return token
    }

    private func preparePhotoItems(_ items: [PhotosPickerItem]) async {
        guard !isPreparingImages else { return }
        isPreparingImages = true
        composerNotice = nil
        defer {
            isPreparingImages = false
            selectedPhotoItems = []
        }
        let limits = effectiveImageLimits
        guard items.count <= remainingImageSlots else {
            composerNotice = RemoteImagePreparationError
                .tooMany(limits.maxImagesPerMessage)
                .localizedDescription
            return
        }
        var preparedBatch: [RemotePromptImage] = []
        var batchBytes = draftImages.reduce(0) { $0 + $1.data.count }
        for (index, item) in items.enumerated() {
            do {
                try Task.checkCancellation()
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw RemoteImagePreparationError.unreadable
                }
                let contentType = item.supportedContentTypes.first
                let fileExtension = contentType?.preferredFilenameExtension ?? "jpg"
                let image = try await RemoteImagePreparer.prepare(
                    data: data,
                    declaredMediaType: contentType?.preferredMIMEType,
                    name: "照片-\(draftImages.count + index + 1).\(fileExtension)",
                    limits: limits
                )
                batchBytes += image.data.count
                guard batchBytes <= limits.maxMessageImageBytes else {
                    throw RemoteImagePreparationError.totalTooLarge(
                        limits.maxMessageImageBytes
                    )
                }
                preparedBatch.append(image)
            } catch {
                guard !Task.isCancelled else { return }
                composerNotice = error.localizedDescription
                return
            }
        }
        draftImages.append(contentsOf: preparedBatch)
        if !preparedBatch.isEmpty {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func pasteImage() {
        guard let provider = UIPasteboard.general.itemProviders.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
        }), let typeIdentifier = provider.registeredTypeIdentifiers.first(where: {
            UTType($0)?.conforms(to: .image) == true
        }) else {
            composerNotice = "剪贴板中没有可用图片。"
            return
        }
        isPreparingImages = true
        composerNotice = nil
        let limits = effectiveImageLimits
        Task {
            defer { isPreparingImages = false }
            do {
                let data = try await pasteboardData(
                    from: provider,
                    typeIdentifier: typeIdentifier
                )
                try Task.checkCancellation()
                let type = UTType(typeIdentifier)
                let prepared = try await RemoteImagePreparer.prepare(
                    data: data,
                    declaredMediaType: type?.preferredMIMEType,
                    name: "粘贴图片.\(type?.preferredFilenameExtension ?? "png")",
                    limits: limits
                )
                try appendPreparedImage(prepared, limits: limits)
            } catch {
                guard !Task.isCancelled else { return }
                composerNotice = error.localizedDescription
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    private func pasteboardData(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: RemoteImagePreparationError.unreadable)
                }
            }
        }
    }

    private func appendPreparedImage(
        _ image: RemotePromptImage,
        limits: RemoteImageLimits
    ) throws {
        guard draftImages.count < limits.maxImagesPerMessage else {
            throw RemoteImagePreparationError.tooMany(limits.maxImagesPerMessage)
        }
        let total = draftImages.reduce(0) { $0 + $1.data.count } + image.data.count
        guard total <= limits.maxMessageImageBytes else {
            throw RemoteImagePreparationError.totalTooLarge(limits.maxMessageImageBytes)
        }
        draftImages.append(image)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func removeDraftImage(_ id: UUID) {
        draftImages.removeAll { $0.id == id }
        if draftImages.isEmpty { composerNotice = nil }
    }

    private func beginReferenceInsertion() {
        let insertion = draft.isEmpty || draft.last?.isWhitespace == true ? "@" : " @"
        replaceDraftText(in: composerSelection, with: insertion)
        composerFocused = true
        showsReferenceSuggestions = true
    }

    private func insertFileReference(_ candidate: RemoteFileReferenceCandidate) {
        guard let token = activeReferenceToken,
              let formatted = Self.formattedFileMention(candidate, preserveQuote: token.quoted) else {
            composerNotice = "这个路径无法安全插入提示词。"
            return
        }
        if candidate.kind == .directory {
            replaceDraftText(in: token.range, with: formatted)
            showsReferenceSuggestions = true
            return
        }
        insertReference(
            displayText: formatted,
            submissionText: formatted,
            kind: .file,
            replacing: token.range
        )
    }

    private func insertSessionReference(_ candidate: RemoteSessionReferenceCandidate) {
        guard draftReferences.filter({ $0.kind == .session }).count < 3 else {
            composerNotice = "每条消息最多引用 3 个会话。"
            return
        }
        guard let token = activeReferenceToken else { return }
        insertReference(
            displayText: "@\(candidate.label)",
            submissionText: candidate.mention,
            kind: .session,
            replacing: token.range
        )
    }

    private func insertReference(
        displayText: String,
        submissionText: String,
        kind: RemoteDraftReference.Kind,
        replacing range: NSRange
    ) {
        replaceDraftText(in: range, with: "\(displayText) ", adding: RemoteDraftReference(
            id: UUID(),
            range: NSRange(location: range.location, length: (displayText as NSString).length),
            displayText: displayText,
            submissionText: submissionText,
            kind: kind
        ))
        showsReferenceSuggestions = false
        composerNotice = nil
    }

    private func replaceDraftText(
        in range: NSRange,
        with replacement: String,
        adding reference: RemoteDraftReference? = nil
    ) {
        let source = draft as NSString
        let safeLocation = min(max(range.location, 0), source.length)
        let safeLength = min(max(range.length, 0), source.length - safeLocation)
        let safeRange = NSRange(location: safeLocation, length: safeLength)
        let delta = (replacement as NSString).length - safeRange.length
        draftReferences = draftReferences.compactMap { existing in
            if NSIntersectionRange(existing.range, safeRange).length > 0 { return nil }
            var shifted = existing
            if existing.range.location >= NSMaxRange(safeRange) {
                shifted.range.location += delta
            }
            return shifted
        }
        if let reference { draftReferences.append(reference) }
        draft = source.replacingCharacters(in: safeRange, with: replacement)
        composerSelection = NSRange(
            location: safeRange.location + (replacement as NSString).length,
            length: 0
        )
    }

    private func updateReferenceSuggestionVisibility() {
        if activeReferenceToken != nil {
            showsReferenceSuggestions = true
        } else if showsReferenceSuggestions {
            showsReferenceSuggestions = false
        }
    }

    private static func activeReferenceToken(
        in text: String,
        selection: NSRange
    ) -> RemoteActiveReferenceToken? {
        guard selection.length == 0 else { return nil }
        let source = text as NSString
        guard selection.location >= 0, selection.location <= source.length else { return nil }
        let beforeCursor = source.substring(to: selection.location) as NSString
        let lineRange = beforeCursor.range(of: "\n", options: .backwards)
        let lineStart = lineRange.location == NSNotFound ? 0 : NSMaxRange(lineRange)
        let line = beforeCursor.substring(from: lineStart)
        let regex = try! NSRegularExpression(pattern: #"(?:^|\s)(@"([^"]*)|@([^\s]*))$"#)
        guard let match = regex.firstMatch(
            in: line,
            range: NSRange(location: 0, length: (line as NSString).length)
        ) else { return nil }
        let tokenRange = match.range(at: 1)
        let quotedRange = match.range(at: 2)
        let plainRange = match.range(at: 3)
        let queryRange = quotedRange.location != NSNotFound ? quotedRange : plainRange
        guard queryRange.location != NSNotFound else { return nil }
        return RemoteActiveReferenceToken(
            range: NSRange(location: lineStart + tokenRange.location, length: tokenRange.length),
            query: (line as NSString).substring(with: queryRange),
            quoted: quotedRange.location != NSNotFound
        )
    }

    private static func formattedFileMention(
        _ candidate: RemoteFileReferenceCandidate,
        preserveQuote: Bool
    ) -> String? {
        var path = candidate.path
        if candidate.kind == .directory,
           !path.hasSuffix("/"),
           !path.hasSuffix("\\") {
            path.append("/")
        }
        guard path.rangeOfCharacter(from: CharacterSet.controlCharacters) == nil,
              !path.contains("\"") else { return nil }
        let quoted = preserveQuote || path.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
        guard quoted else { return "@\(path)" }
        return candidate.kind == .directory ? "@\"\(path)" : "@\"\(path)\""
    }

    private var modelIsRoutable: Bool {
        viewModel.modelDirectory?.routable != false
    }

    private var selectedAdvertisedModel: (group: RemoteModelProviderGroup, model: RemoteModelCatalogEntry)? {
        guard let directory = viewModel.modelDirectory else { return nil }
        for group in directory.groups {
            if let model = group.models.first(where: {
                group.id == directory.current.provider && $0.id == directory.current.model
            }) {
                return (group, model)
            }
        }
        return nil
    }

    private var modelTriggerName: String {
        if let selectedAdvertisedModel { return selectedAdvertisedModel.model.name }
        if viewModel.isLoadingModels && viewModel.modelDirectory == nil { return "读取模型…" }
        return "选择模型"
    }

    private var selectedEffortName: String? {
        guard let directory = viewModel.modelDirectory,
              let reasoning = selectedAdvertisedModel?.model.reasoning else { return nil }
        let effortID = directory.current.reasoningEffort ?? reasoning.defaultEffort
        guard let effortID else { return "默认" }
        return reasoning.efforts.first(where: { $0.id == effortID })?.name ?? effortID
    }

    private var modelAccessibilityLabel: String {
        if let effort = selectedEffortName {
            return "模型，\(modelTriggerName)，推理强度 \(effort)"
        }
        return "模型，\(modelTriggerName)"
    }

    private var sendAccessibilityLabel: String {
        guard viewModel.session.running else { return "发送" }
        return busyDelivery == .queue ? "排队发送" : "插话发送"
    }

    private struct DSHConversationTabBar: View {
        @Binding var selection: ViewMode

        var body: some View {
            HStack(spacing: 24) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Button {
                        selection = mode
                    } label: {
                        VStack(spacing: 7) {
                            Text(mode.rawValue)
                                .font(.subheadline.weight(selection == mode ? .semibold : .regular))
                                .foregroundStyle(selection == mode ? Color.primary : Color.secondary)
                            Rectangle()
                                .fill(selection == mode ? RemoteTheme.accent : Color.clear)
                                .frame(
                                    width: mode == .conversation ? 36 : 70,
                                    height: 2
                                )
                        }
                        .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(RemotePressableRowButtonStyle(cornerRadius: 8))
                    .accessibilityAddTraits(selection == mode ? .isSelected : [])
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
    }

    #if DEBUG
    private static var debugDraftImage: RemotePromptImage? {
        let size = CGSize(width: 320, height: 180)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor(red: 0.11, green: 0.18, blue: 0.28, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.40, green: 0.62, blue: 1, alpha: 1).setStroke()
            context.cgContext.setLineWidth(16)
            context.cgContext.move(to: CGPoint(x: 54, y: 126))
            context.cgContext.addLine(to: CGPoint(x: 140, y: 54))
            context.cgContext.addLine(to: CGPoint(x: 262, y: 110))
            context.cgContext.strokePath()
        }
        guard let data = image.pngData() else { return nil }
        return RemotePromptImage(
            data: data,
            mediaType: "image/png",
            name: "界面草稿.png",
            width: 320,
            height: 180
        )
    }

    private static var debugDetailItem: RemoteConversationItem {
        RemoteConversationItem(
            id: "debug-instruction-detail",
            kind: .context,
            title: "项目指令",
            text: "AGENTS.md · 已载入",
            time: Date(),
            state: .succeeded,
            details: [
                RemoteDetailSection(
                    id: "instruction-sources",
                    title: "指令来源",
                    content: "AGENTS.md\t已载入\ndocs/AGENTS.md\t已载入",
                    kind: .list
                ),
                RemoteDetailSection(
                    id: "context-raw",
                    title: "模型接收的内容",
                    content: """
                    <system-reminder>
                    The following workspace instructions may be relevant to your work.

                    Instructions from:

                    [AGENTS.md](AGENTS.md)

                    # Project rules

                    - Read `docs/architecture.md` before changing packages.
                    - Run focused tests before release.
                    - Keep credentials and model calls on the user's computer.

                    ```sh
                    npm test
                    ```
                    </system-reminder>
                    """,
                    kind: .text
                ),
            ]
        )
    }
    #endif

    private func inspectorItem(for record: RemoteTrajectoryRecord) -> RemoteConversationItem {
        let kind: RemoteConversationItem.Kind = switch record.kind {
        case .input: .user
        case .context: .context
        case .request: .status
        case .assistant: .assistant
        case .tool: .tool
        case .goal, .plan: .status
        case .lifecycle: .status
        }
        return RemoteConversationItem(
            id: "inspect:\(record.id)", sequence: record.sequence, kind: kind,
            title: record.title, text: record.summary, time: record.time,
            state: record.state, details: record.details,
            metadata: record.duration.map { [durationText($0)] } ?? [],
            attachments: record.attachments,
            symbolName: record.kind == .goal ? "target" : (record.kind == .plan ? "map" : nil)
        )
    }

    private func goalDetailItem(_ goal: RemoteGoalState) -> RemoteConversationItem {
        var details = [RemoteDetailSection(
            id: "goal-objective",
            title: "目标",
            content: goal.objective,
            kind: .text
        )]
        let stateRows = [
            "状态\t\(goalPhaseLabel(goal.phase))",
            "进度\t\(goal.roundsStarted) / \(goal.maxRounds) 轮",
            "修订\t\(goal.revision)",
        ]
        details.append(RemoteDetailSection(
            id: "goal-status",
            title: "状态",
            content: stateRows.joined(separator: "\n"),
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
        return RemoteConversationItem(
            id: "current-goal:\(goal.id):\(goal.revision)",
            kind: .status,
            title: "当前 Goal",
            text: goal.objective,
            time: goal.updatedAt,
            state: goalConversationState(goal.phase),
            details: details,
            metadata: ["\(goal.roundsStarted)/\(goal.maxRounds) 轮"],
            symbolName: "target"
        )
    }

    private func goalPhaseLabel(_ phase: RemoteGoalState.Phase) -> String {
        switch phase {
        case .active: "进行中"
        case .paused: "已暂停"
        case .blocked: "受阻"
        case .complete: "已完成"
        }
    }

    private func goalConversationState(
        _ phase: RemoteGoalState.Phase
    ) -> RemoteConversationItem.State {
        switch phase {
        case .active: .running
        case .paused, .blocked: .stopped
        case .complete: .succeeded
        }
    }

    private func durationText(_ value: TimeInterval) -> String {
        value < 1 ? "\(Int(value * 1_000)) ms" : String(format: "%.1f 秒", value)
    }

    private func restoreViewMode(_ mode: ViewMode, proxy: ScrollViewProxy) {
        isRestoringViewMode = true
        let generation = viewModeGeneration

        DispatchQueue.main.async {
            guard generation == viewModeGeneration, mode == viewMode else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                switch mode {
                case .conversation:
                    if let conversationVisibleAnchor {
                        proxy.scrollTo(
                            conversationVisibleAnchor,
                            anchor: conversationVisibleAlignment
                        )
                    } else {
                        proxy.scrollTo("conversation-bottom", anchor: .bottom)
                    }
                case .trajectory:
                    if let trajectoryVisibleAnchor {
                        proxy.scrollTo(
                            trajectoryVisibleAnchor,
                            anchor: trajectoryVisibleAlignment
                        )
                    } else {
                        proxy.scrollTo("trajectory-top", anchor: .top)
                    }
                }
            }
            DispatchQueue.main.async {
                guard generation == viewModeGeneration, mode == viewMode else { return }
                if mode == .conversation, pendingFollowAfterModeRestore {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        proxy.scrollTo("conversation-bottom", anchor: .bottom)
                    }
                    pendingFollowAfterModeRestore = false
                    shouldFollowNextSend = false
                }
                isRestoringViewMode = false
            }
        }
    }

    private func selectViewMode(_ mode: ViewMode) {
        guard mode != viewMode else { return }
        viewModeGeneration += 1
        if mode == .trajectory { pendingFollowAfterModeRestore = false }
        isRestoringViewMode = true
        viewMode = mode
    }

    private func visibleDistanceToTop(_ frame: CGRect) -> CGFloat {
        frame.minY <= 0 && frame.maxY >= 0 ? 0 : abs(frame.minY)
    }

    private func scrollAlignment(for frame: CGRect, viewportHeight: CGFloat) -> UnitPoint {
        guard frame.minY < 0, frame.height > viewportHeight else { return .top }
        let denominator = max(frame.height - viewportHeight, 1)
        let y = min(max(-frame.minY / denominator, 0), 1)
        return UnitPoint(x: 0.5, y: y)
    }

}

private struct RemoteComposerTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var references: [RemoteDraftReference]
    @Binding var selection: NSRange
    @Binding var measuredHeight: CGFloat
    @Binding var isFocused: Bool
    let isEnabled: Bool
    let maxHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        view.font = .preferredFont(forTextStyle: .body)
        view.keyboardDismissMode = .interactive
        view.returnKeyType = .default
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.autocorrectionType = .yes
        view.spellCheckingType = .yes
        view.showsVerticalScrollIndicator = false
        view.tintColor = UIColor(RemoteTheme.accent)
        view.accessibilityLabel = "消息"
        view.accessibilityHint = "输入发送给 Harness 的内容"
        context.coordinator.render(view, force: true)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        view.isEditable = isEnabled
        view.isSelectable = isEnabled
        view.alpha = isEnabled ? 1 : 0.62
        view.tintColor = UIColor(RemoteTheme.accent)
        context.coordinator.render(view)
        context.coordinator.updateMeasuredHeight(view)

        let textLength = (text as NSString).length
        let safeLocation = min(max(selection.location, 0), textLength)
        let safeSelection = NSRange(
            location: safeLocation,
            length: min(max(selection.length, 0), textLength - safeLocation)
        )
        if view.selectedRange != safeSelection, !context.coordinator.isApplyingChange {
            context.coordinator.isApplyingChange = true
            view.selectedRange = safeSelection
            context.coordinator.isApplyingChange = false
        }

        if isFocused, !view.isFirstResponder {
            DispatchQueue.main.async { view.becomeFirstResponder() }
        } else if !isFocused, view.isFirstResponder {
            DispatchQueue.main.async { view.resignFirstResponder() }
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UITextView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width else { return nil }
        let measured = uiView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        return CGSize(width: width, height: min(max(measured.height, 38), maxHeight))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: RemoteComposerTextView
        var isApplyingChange = false
        private var pendingEdit: (range: NSRange, replacementLength: Int)?
        private var renderedText = ""
        private var renderedReferences: [RemoteDraftReference] = []

        init(parent: RemoteComposerTextView) {
            self.parent = parent
        }

        func render(_ view: UITextView, force: Bool = false) {
            guard force || renderedText != parent.text || renderedReferences != parent.references else {
                return
            }
            guard view.markedTextRange == nil else { return }
            let selected = view.selectedRange
            isApplyingChange = true
            if view.text != parent.text {
                view.textStorage.replaceCharacters(
                    in: NSRange(location: 0, length: view.textStorage.length),
                    with: parent.text
                )
            }
            let fullRange = NSRange(location: 0, length: view.textStorage.length)
            view.textStorage.beginEditing()
            view.textStorage.setAttributes(
                [
                    .font: UIFont.preferredFont(forTextStyle: .body),
                    .foregroundColor: UIColor.label,
                ],
                range: fullRange
            )
            for reference in parent.references {
                guard NSMaxRange(reference.range) <= view.textStorage.length else { continue }
                view.textStorage.addAttributes(
                    [
                        .foregroundColor: UIColor(RemoteTheme.accent),
                        .backgroundColor: UIColor(RemoteTheme.accent).withAlphaComponent(0.11),
                    ],
                    range: reference.range
                )
            }
            view.textStorage.endEditing()
            view.selectedRange = NSRange(
                location: min(selected.location, view.textStorage.length),
                length: min(
                    selected.length,
                    max(view.textStorage.length - min(selected.location, view.textStorage.length), 0)
                )
            )
            isApplyingChange = false
            renderedText = parent.text
            renderedReferences = parent.references
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText replacement: String
        ) -> Bool {
            let references = parent.references
            if range.length == 0,
               let reference = references.first(where: {
                   range.location > $0.range.location && range.location < NSMaxRange($0.range)
               }) {
                textView.selectedRange = NSRange(location: NSMaxRange(reference.range), length: 0)
                parent.selection = textView.selectedRange
                return false
            }

            let intersecting = references.filter {
                NSIntersectionRange($0.range, range).length > 0
            }
            if !intersecting.isEmpty {
                var expanded = range
                for reference in intersecting {
                    expanded = NSUnionRange(expanded, reference.range)
                }
                applyAtomicReplacement(
                    in: textView,
                    range: expanded,
                    replacement: replacement
                )
                return false
            }

            pendingEdit = (range, (replacement as NSString).length)
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingChange else { return }
            let nextText = textView.text ?? ""
            if let edit = pendingEdit {
                let delta = edit.replacementLength - edit.range.length
                parent.references = parent.references.compactMap { reference in
                    if NSIntersectionRange(reference.range, edit.range).length > 0 { return nil }
                    var shifted = reference
                    if reference.range.location >= NSMaxRange(edit.range) {
                        shifted.range.location += delta
                    }
                    return shifted
                }
            }
            pendingEdit = nil
            parent.text = nextText
            parent.selection = textView.selectedRange
            render(textView, force: true)
            updateMeasuredHeight(textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingChange else { return }
            var next = textView.selectedRange
            if next.length == 0,
               let reference = parent.references.first(where: {
                   next.location > $0.range.location && next.location < NSMaxRange($0.range)
               }) {
                next = NSRange(location: NSMaxRange(reference.range), length: 0)
                isApplyingChange = true
                textView.selectedRange = next
                isApplyingChange = false
            }
            parent.selection = next
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFocused = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isFocused = false
        }

        private func applyAtomicReplacement(
            in textView: UITextView,
            range: NSRange,
            replacement: String
        ) {
            let source = parent.text as NSString
            guard NSMaxRange(range) <= source.length else { return }
            let delta = (replacement as NSString).length - range.length
            parent.references = parent.references.compactMap { reference in
                if NSIntersectionRange(reference.range, range).length > 0 { return nil }
                var shifted = reference
                if reference.range.location >= NSMaxRange(range) {
                    shifted.range.location += delta
                }
                return shifted
            }
            parent.text = source.replacingCharacters(in: range, with: replacement)
            parent.selection = NSRange(
                location: range.location + (replacement as NSString).length,
                length: 0
            )
            renderedText = ""
            render(textView, force: true)
            textView.selectedRange = parent.selection
            updateMeasuredHeight(textView)
        }

        func updateMeasuredHeight(_ view: UITextView) {
            let width = view.bounds.width
            guard width > 1 else { return }
            let fitting = view.sizeThatFits(
                CGSize(width: width, height: .greatestFiniteMagnitude)
            ).height
            let next = min(max(ceil(fitting), 38), parent.maxHeight)
            view.isScrollEnabled = fitting > parent.maxHeight
            guard abs(parent.measuredHeight - next) > 0.5 else { return }
            DispatchQueue.main.async {
                if abs(self.parent.measuredHeight - next) > 0.5 {
                    self.parent.measuredHeight = next
                }
            }
        }
    }
}

private struct RemoteReferenceSuggestions: View {
    private struct LoadKey: Hashable {
        let token: RemoteActiveReferenceToken
        let revision: Int
    }

    let token: RemoteActiveReferenceToken
    let fileLoader: (String) async throws -> [RemoteFileReferenceCandidate]
    let sessionLoader: (String) async throws -> [RemoteSessionReferenceCandidate]
    let onSelectFile: (RemoteFileReferenceCandidate) -> Void
    let onSelectSession: (RemoteSessionReferenceCandidate) -> Void
    let onDismiss: () -> Void

    @State private var files: [RemoteFileReferenceCandidate] = []
    @State private var sessions: [RemoteSessionReferenceCandidate] = []
    @State private var isLoading = true
    @State private var errorMessages: [String] = []
    @State private var revision = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "at")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(RemoteTheme.accent)
                Text(token.quoted ? "引用项目文件" : "引用文件或会话")
                    .font(.caption.weight(.semibold))
                Spacer()
                if isLoading { ProgressView().controlSize(.mini) }
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(RemoteToolbarButtonStyle())
                .foregroundStyle(.secondary)
                .accessibilityLabel("关闭引用建议")
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .frame(minHeight: 40)

            Rectangle().fill(RemoteTheme.hairline).frame(height: 0.5)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(files.prefix(8))) { candidate in
                        suggestionRow(
                            icon: candidate.kind == .directory ? "folder" : "doc.text",
                            title: fileCandidateTitle(candidate),
                            subtitle: fileCandidateSubtitle(candidate)
                        ) {
                            onSelectFile(candidate)
                        }
                    }

                    if !token.quoted, !files.isEmpty, !sessions.isEmpty {
                        Rectangle()
                            .fill(RemoteTheme.hairline)
                            .frame(height: 0.5)
                            .padding(.vertical, 4)
                    }

                    if !token.quoted {
                        ForEach(Array(sessions.prefix(5))) { candidate in
                            suggestionRow(
                                icon: "bubble.left.and.bubble.right",
                                title: candidate.label,
                                subtitle: candidate.cwd ?? "Harness 会话"
                            ) {
                                onSelectSession(candidate)
                            }
                        }
                    }

                    if !isLoading, files.isEmpty, sessions.isEmpty {
                        VStack(spacing: 7) {
                            Image(systemName: errorMessages.isEmpty ? "magnifyingglass" : "wifi.exclamationmark")
                                .foregroundStyle(.tertiary)
                            Text(errorMessages.isEmpty ? "没有匹配的引用" : "暂时无法读取引用")
                                .font(.caption.weight(.medium))
                            if !errorMessages.isEmpty {
                                Button("重试") { revision += 1 }
                                    .font(.caption.weight(.semibold))
                                    .buttonStyle(RemotePressableRowButtonStyle(cornerRadius: 8))
                                    .foregroundStyle(RemoteTheme.accent)
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }

                    if !isLoading,
                       !errorMessages.isEmpty,
                       (!files.isEmpty || !sessions.isEmpty) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(RemoteTheme.warning)
                            Text("部分引用未加载")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("重试") { revision += 1 }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(RemoteTheme.accent)
                                .frame(minWidth: 44, minHeight: 44)
                                .buttonStyle(RemotePressableRowButtonStyle(cornerRadius: 8))
                        }
                        .padding(.horizontal, 10)
                    }
                }
            }
            .frame(height: suggestionListHeight)
        }
        .background(RemoteTheme.raisedSurface, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(RemoteTheme.hairline, lineWidth: 1)
        }
        .task(id: LoadKey(token: token, revision: revision)) {
            await load()
        }
    }

    private func suggestionRow(
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(RemoteTheme.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 7 : 0)
            .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 76 : 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(RemotePressableRowButtonStyle(cornerRadius: 9))
    }

    private func fileCandidateTitle(_ candidate: RemoteFileReferenceCandidate) -> String {
        pathComponents(candidate.path).last ?? candidate.path
    }

    private func fileCandidateSubtitle(_ candidate: RemoteFileReferenceCandidate) -> String {
        let components = pathComponents(candidate.path)
        let parent = components.dropLast().joined(separator: "/")
        let location = parent.isEmpty ? "项目根目录" : parent
        return candidate.kind == .directory ? "\(location) · 继续浏览" : location
    }

    private func pathComponents(_ path: String) -> [String] {
        path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).map(String.init)
    }

    private var suggestionListHeight: CGFloat {
        if isLoading, files.isEmpty, sessions.isEmpty { return 64 }
        let fileCount = min(files.count, 8)
        let sessionCount = token.quoted ? 0 : min(sessions.count, 5)
        if fileCount + sessionCount == 0 { return 92 }
        let divider: CGFloat = fileCount > 0 && sessionCount > 0 ? 9 : 0
        let errorRow: CGFloat = errorMessages.isEmpty ? 0 : 44
        let rowHeight: CGFloat = dynamicTypeSize.isAccessibilitySize ? 90 : 48
        let maximumHeight: CGFloat = verticalSizeClass == .compact
            ? 132
            : (dynamicTypeSize.isAccessibilitySize ? 280 : 220)
        return min(CGFloat(fileCount + sessionCount) * rowHeight + divider + errorRow, maximumHeight)
    }

    private func load() async {
        isLoading = true
        errorMessages = []
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled else { return }

        async let fileResult = Self.capture { try await fileLoader(token.query) }
        async let sessionResult = Self.capture {
            token.quoted ? [] : try await sessionLoader(token.query)
        }
        let (nextFiles, nextSessions) = await (fileResult, sessionResult)
        guard !Task.isCancelled else { return }

        switch nextFiles {
        case .success(let values): files = values
        case .failure(let error):
            files = []
            errorMessages.append(error.localizedDescription)
        }
        switch nextSessions {
        case .success(let values): sessions = values
        case .failure(let error):
            sessions = []
            errorMessages.append(error.localizedDescription)
        }
        isLoading = false
    }

    private static func capture<Value>(
        _ operation: () async throws -> Value
    ) async -> Result<Value, Error> {
        do { return .success(try await operation()) }
        catch { return .failure(error) }
    }
}

private struct RemoteDraftImageRail: View {
    let images: [RemotePromptImage]
    let isPreparing: Bool
    let onRemove: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 9) {
                ForEach(images) { image in
                    ZStack(alignment: .topTrailing) {
                        Group {
                            if let preview = UIImage(data: image.thumbnailData) {
                                Image(uiImage: preview)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Image(systemName: "photo")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .frame(width: 64, height: 64)
                        .background(RemoteTheme.mutedSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        Button { onRemove(image.id) } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(.black.opacity(0.68), in: Circle())
                                .frame(width: 44, height: 44, alignment: .topTrailing)
                        }
                        .buttonStyle(RemotePressableRowButtonStyle(cornerRadius: 22))
                        .offset(x: 8, y: -8)
                        .accessibilityLabel("移除\(image.name ?? "图片")")
                    }
                    .padding(.top, 8)
                    .accessibilityElement(children: .contain)
                }

                if isPreparing {
                    VStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("处理图片")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 64, height: 64)
                    .background(RemoteTheme.mutedSurface, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 80)
    }
}

private enum RemoteImagePreparationError: LocalizedError {
    case unreadable
    case unsupported
    case tooLarge(Int)
    case tooMany(Int)
    case totalTooLarge(Int)

    var errorDescription: String? {
        switch self {
        case .unreadable:
            "无法读取这张图片。"
        case .unsupported:
            "电脑当前不支持可安全转换的图片格式。"
        case .tooLarge(let bytes):
            "图片处理后仍超过单张 \(Self.byteText(bytes)) 的限制。"
        case .tooMany(let count):
            "每条消息最多添加 \(count) 张图片。"
        case .totalTooLarge(let bytes):
            "这些图片合计超过 \(Self.byteText(bytes)) 的限制。"
        }
    }

    private static func byteText(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

private enum RemoteImagePreparer {
    static func prepare(
        data: Data,
        declaredMediaType: String?,
        name: String?,
        limits: RemoteImageLimits
    ) async throws -> RemotePromptImage {
        try await Task.detached(priority: .userInitiated) {
            try prepareSynchronously(
                data: data,
                declaredMediaType: declaredMediaType,
                name: name,
                limits: limits
            )
        }.value
    }

    private static func prepareSynchronously(
        data: Data,
        declaredMediaType: String?,
        name: String?,
        limits: RemoteImageLimits
    ) throws -> RemotePromptImage {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, [
                  kCGImageSourceShouldCache: false,
              ] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = number(properties[kCGImagePropertyPixelWidth]),
              let height = number(properties[kCGImagePropertyPixelHeight]),
              width > 0,
              height > 0 else {
            throw RemoteImagePreparationError.unreadable
        }

        let allowed = Set(limits.mediaTypes.map { $0.lowercased() })
        let supportsJPEG = allowed.isEmpty || allowed.contains("image/jpeg") || allowed.contains("image/jpg")
        let supportsPNG = allowed.isEmpty || allowed.contains("image/png")
        guard supportsJPEG || supportsPNG else {
            throw RemoteImagePreparationError.unsupported
        }

        let originalMax = max(width, height)
        var targetMax = min(originalMax, max(limits.maxImageDimension ?? originalMax, 1), 6_000)
        let originalPixels = Int64(width) * Int64(height)
        if originalPixels > Int64(max(limits.maxImagePixels, 1)) {
            let pixelScale = sqrt(Double(max(limits.maxImagePixels, 1)) / Double(originalPixels))
            targetMax = min(targetMax, max(Int(floor(Double(originalMax) * pixelScale)), 1))
        }

        var currentMax = max(targetMax, 1)
        while currentMax >= 1 {
            guard let image = thumbnail(from: source, maxDimension: currentMax) else {
                throw RemoteImagePreparationError.unreadable
            }

            if supportsPNG, hasAlpha(image),
               let encoded = encode(image, type: UTType.png.identifier, quality: nil),
               encoded.count <= limits.maxImageBytes {
                return promptImage(
                    data: encoded,
                    mediaType: "image/png",
                    name: normalizedName(name, extension: "png"),
                    image: image
                )
            }

            if supportsJPEG {
                let flattened = hasAlpha(image) ? flattenOnWhite(image) ?? image : image
                for quality in stride(from: 0.90, through: 0.42, by: -0.08) {
                    if let encoded = encode(
                        flattened,
                        type: UTType.jpeg.identifier,
                        quality: quality
                    ), encoded.count <= limits.maxImageBytes {
                        return promptImage(
                            data: encoded,
                            mediaType: "image/jpeg",
                            name: normalizedName(name, extension: "jpg"),
                            image: flattened
                        )
                    }
                }
            } else if supportsPNG,
                      let encoded = encode(image, type: UTType.png.identifier, quality: nil),
                      encoded.count <= limits.maxImageBytes {
                return promptImage(
                    data: encoded,
                    mediaType: "image/png",
                    name: normalizedName(name, extension: "png"),
                    image: image
                )
            }

            guard currentMax > 1 else { break }
            let next = max(Int(floor(Double(currentMax) * 0.80)), 1)
            currentMax = next < currentMax ? next : currentMax - 1
        }

        throw RemoteImagePreparationError.tooLarge(limits.maxImageBytes)
    }

    private static func number(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    private static func thumbnail(
        from source: CGImageSource,
        maxDimension: Int
    ) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary)
    }

    private static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast:
            true
        default:
            false
        }
    }

    private static func flattenOnWhite(_ image: CGImage) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    private static func encode(
        _ image: CGImage,
        type: String,
        quality: Double?
    ) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            type as CFString,
            1,
            nil
        ) else { return nil }
        var properties: [CFString: Any] = [:]
        if let quality {
            properties[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private static func promptImage(
        data: Data,
        mediaType: String,
        name: String?,
        image: CGImage
    ) -> RemotePromptImage {
        RemotePromptImage(
            data: data,
            thumbnailData: previewData(for: image),
            mediaType: mediaType,
            name: name,
            width: image.width,
            height: image.height
        )
    }

    private static func normalizedName(_ name: String?, extension fileExtension: String) -> String? {
        guard let name, !name.isEmpty else { return nil }
        let base = (name as NSString).deletingPathExtension
        return "\(base.isEmpty ? "图片" : base).\(fileExtension)"
    }

    private static func previewData(for image: CGImage) -> Data? {
        let maxPreviewDimension = 192
        let scale = min(
            1,
            Double(maxPreviewDimension) / Double(max(image.width, image.height))
        )
        let width = max(Int((Double(image.width) * scale).rounded()), 1)
        let height = max(Int((Double(image.height) * scale).rounded()), 1)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let preview = context.makeImage() else { return nil }
        return encode(
            preview,
            type: UTType.jpeg.identifier,
            quality: 0.72
        )
    }
}

private extension RemoteSubagentEntry {
    var remoteActivityLabel: String {
        switch activity {
        case .running: "运行中"
        case .inactive: mode == .continuable ? "未运行" : "已结束"
        case nil: "不可用"
        }
    }

    var remoteActivityColor: Color {
        switch activity {
        case .running: RemoteTheme.accent
        case .inactive: Color.secondary
        case nil: RemoteTheme.warning
        }
    }

    var remoteActivityIcon: String {
        switch activity {
        case .running: "waveform"
        case .inactive: mode == .continuable ? "pause" : "checkmark"
        case nil: "exclamationmark"
        }
    }
}

private struct RemoteSubagentBrowserView: View {
    @ObservedObject var viewModel: RemoteConversationViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                RemoteSheetHeader(
                    title: "子代理",
                    subtitle: "查看由这个会话派出的工作，并在支持时继续跟进"
                ) {
                    Button {
                        Task { await viewModel.refreshSubagents() }
                    } label: {
                        Group {
                            if viewModel.isLoadingSubagents {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                    }
                    .buttonStyle(RemoteToolbarButtonStyle())
                    .disabled(viewModel.isLoadingSubagents)
                    .accessibilityLabel("刷新子代理")
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if let catalog = viewModel.subagentCatalog,
                           !catalog.parentAvailable {
                            RemoteInlineNotice(
                                title: "父会话暂时不可用",
                                message: "已保存的子代理仍可查看，但部分操作可能失败。",
                                icon: "exclamationmark.triangle.fill",
                                tone: .warning
                            )
                        }

                        if let error = viewModel.subagentErrorMessage {
                            RemoteInlineNotice(
                                title: "无法读取子代理",
                                message: error,
                                icon: "wifi.exclamationmark",
                                tone: .danger,
                                actionTitle: "重试",
                                action: { Task { await viewModel.refreshSubagents() } }
                            )
                        }

                        let entries = viewModel.subagentCatalog?.entries ?? []
                        if viewModel.isLoadingSubagents, entries.isEmpty {
                            RemoteLoadingState(
                                icon: "person.2",
                                title: "正在读取子代理",
                                message: "从你的电脑同步派出的工作"
                            )
                            .padding(.top, 42)
                        } else if entries.isEmpty, viewModel.subagentErrorMessage == nil {
                            RemoteEmptyState(
                                icon: "person.2",
                                title: "还没有子代理",
                                message: "当 Harness 将工作交给子代理后，会在这里出现。"
                            )
                            .padding(.top, 42)
                        } else {
                            RemoteSectionHeader(
                                title: "派出的工作",
                                detail: "\(entries.filter { !$0.isDiagnostic }.count) 个"
                            )
                            VStack(spacing: 0) {
                                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                    if entry.isDiagnostic {
                                        diagnosticRow(entry)
                                    } else {
                                        NavigationLink {
                                            RemoteSubagentConversationView(
                                                parentViewModel: viewModel,
                                                parentSessionID: viewModel.session.id,
                                                parentAvailable: viewModel.subagentCatalog?.parentAvailable ?? true,
                                                child: entry
                                            )
                                        } label: {
                                            subagentRow(entry)
                                        }
                                        .buttonStyle(RemotePressableRowButtonStyle(cornerRadius: 10))
                                    }
                                    if index < entries.count - 1 {
                                        Rectangle()
                                            .fill(RemoteTheme.hairline)
                                            .frame(height: 0.5)
                                            .padding(.leading, 42)
                                    }
                                }
                            }
                            .background(RemoteTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(RemoteTheme.hairline, lineWidth: 1)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 30)
                }
                .refreshable { await viewModel.refreshSubagents() }
            }
            .background(RemoteTheme.canvas)
            .remoteNavigationChromeHidden()
        }
    }

    @ViewBuilder
    private func subagentRow(_ entry: RemoteSubagentEntry) -> some View {
        let title = entry.label ?? shortIdentifier(entry.id)
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .top, spacing: 11) {
                        subagentIcon(entry)
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tertiary)
                            .frame(minWidth: 24, minHeight: 32)
                    }
                    HStack(alignment: .center, spacing: 8) {
                        subagentMode(entry)
                        Spacer(minLength: 8)
                        RemoteStatusPill(
                            text: entry.remoteActivityLabel,
                            color: entry.remoteActivityColor,
                            icon: entry.remoteActivityIcon
                        )
                    }
                }
            } else {
                HStack(spacing: 6) {
                    subagentIcon(entry)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        subagentMode(entry)
                    }
                    Spacer(minLength: 8)
                    RemoteStatusPill(
                        text: entry.remoteActivityLabel,
                        color: entry.remoteActivityColor,
                        icon: entry.remoteActivityIcon
                    )
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 11 : 8)
        .frame(minHeight: 58)
        .contentShape(Rectangle())
        .background(
            entry.activity == .running ? RemoteTheme.accent.opacity(0.05) : Color.clear
        )
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开子代理对话")
    }

    private func subagentIcon(_ entry: RemoteSubagentEntry) -> some View {
        Image(systemName: entry.activity == .running ? "waveform" : "person.crop.circle")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(entry.activity == .running ? RemoteTheme.accent : Color.secondary)
            .frame(width: 30, height: 30)
            .background(
                (entry.activity == .running ? RemoteTheme.accent : Color.secondary)
                    .opacity(0.10),
                in: Circle()
            )
    }

    private func subagentMode(_ entry: RemoteSubagentEntry) -> some View {
        HStack(spacing: 6) {
            Text(entry.mode == .continuable ? "可继续" : "一次性")
            if entry.hasChildren {
                Text("·")
                Label("包含子任务", systemImage: "arrow.triangle.branch")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func diagnosticRow(_ entry: RemoteSubagentEntry) -> some View {
        HStack(spacing: 11) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(RemoteTheme.warning)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text("无法读取一个子代理")
                    .font(.subheadline.weight(.semibold))
                Text(diagnosticLabel(entry.diagnosticReason))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(minHeight: 58)
        .accessibilityElement(children: .combine)
    }

    private func diagnosticLabel(_ reason: RemoteSubagentEntry.DiagnosticReason?) -> String {
        switch reason {
        case .corrupt: "本地记录已损坏"
        case .unsupported: "记录格式暂不支持"
        case .unavailable: "记录暂时不可用"
        case nil: "记录暂时不可用"
        }
    }

    private func shortIdentifier(_ value: String) -> String {
        let compact = value.replacingOccurrences(of: "-", with: "")
        return "子代理 \(compact.prefix(8))"
    }
}

private struct RemoteNestedSubagentCatalogView: View {
    @ObservedObject var parentViewModel: RemoteConversationViewModel
    let parentSessionID: String
    let title: String

    @State private var catalog: RemoteSubagentCatalog?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            RemotePageHeader(
                title: "下级子代理",
                subtitle: title
            ) {
                Button {
                    Task { await refresh() }
                } label: {
                    Group {
                        if isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
                .buttonStyle(RemoteToolbarButtonStyle())
                .disabled(isLoading)
                .accessibilityLabel("刷新下级子代理")
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if catalog?.parentAvailable == false {
                        RemoteInlineNotice(
                            title: "这个子代理暂时不可用",
                            message: "已保存的下级工作仍可查看。",
                            icon: "exclamationmark.triangle.fill",
                            tone: .warning
                        )
                    }
                    if let errorMessage {
                        RemoteInlineNotice(
                            title: "无法读取下级子代理",
                            message: errorMessage,
                            icon: "wifi.exclamationmark",
                            tone: .danger,
                            actionTitle: "重试",
                            action: { Task { await refresh() } }
                        )
                    }

                    let entries = catalog?.entries ?? []
                    if isLoading, entries.isEmpty {
                        RemoteLoadingState(
                            icon: "arrow.triangle.branch",
                            title: "正在读取下级工作",
                            message: "从电脑同步子代理树"
                        )
                        .padding(.top, 42)
                    } else if entries.isEmpty, errorMessage == nil {
                        RemoteEmptyState(
                            icon: "arrow.triangle.branch",
                            title: "没有下级子代理",
                            message: "这项工作没有继续派出其他任务。"
                        )
                        .padding(.top, 42)
                    } else {
                        RemoteSectionHeader(
                            title: "下级工作",
                            detail: "\(entries.filter { !$0.isDiagnostic }.count) 个"
                        )
                        VStack(spacing: 0) {
                            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                if entry.isDiagnostic {
                                    HStack(spacing: 10) {
                                        Image(systemName: "exclamationmark.triangle")
                                            .foregroundStyle(RemoteTheme.warning)
                                            .frame(width: 30)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(entry.id)
                                                .font(.subheadline.weight(.semibold))
                                                .lineLimit(1)
                                            Text("这条子代理记录暂时无法读取")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 11)
                                    .frame(minHeight: 58)
                                    .accessibilityElement(children: .combine)
                                } else {
                                    NavigationLink {
                                        RemoteSubagentConversationView(
                                            parentViewModel: parentViewModel,
                                            parentSessionID: parentSessionID,
                                            parentAvailable: catalog?.parentAvailable ?? true,
                                            child: entry
                                        )
                                    } label: {
                                        nestedSubagentRow(entry)
                                        .padding(.horizontal, 11)
                                        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 11 : 8)
                                        .frame(minHeight: 58)
                                        .contentShape(Rectangle())
                                        .accessibilityElement(children: .combine)
                                        .accessibilityHint("打开子代理对话")
                                    }
                                    .buttonStyle(RemotePressableRowButtonStyle(cornerRadius: 10))
                                }

                                if index < entries.count - 1 {
                                    Rectangle()
                                        .fill(RemoteTheme.hairline)
                                        .frame(height: 0.5)
                                        .padding(.leading, 42)
                                }
                            }
                        }
                        .background(RemoteTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(RemoteTheme.hairline, lineWidth: 1)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 30)
            }
            .refreshable { await refresh() }
        }
        .background(RemoteTheme.canvas)
        .remoteNavigationChromeHidden()
        .task { await monitor() }
    }

    private func monitor() async {
        await refresh()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await refresh(silently: true)
        }
    }

    private func refresh(silently: Bool = false) async {
        if !silently { isLoading = true }
        do {
            catalog = try await parentViewModel.client.subagents(
                parentSessionID: parentSessionID
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func subtitle(for entry: RemoteSubagentEntry) -> String {
        var parts = [entry.mode == .continuable ? "可继续" : "一次性"]
        parts.append(entry.remoteActivityLabel)
        if entry.hasChildren { parts.append("包含下级工作") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func nestedSubagentRow(_ entry: RemoteSubagentEntry) -> some View {
        let title = entry.label ?? entry.id
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 11) {
                    nestedIcon(entry)
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .frame(minWidth: 24, minHeight: 32)
                }
                HStack(alignment: .top, spacing: 8) {
                    Text(capabilitySubtitle(for: entry))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Text(entry.remoteActivityLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(entry.remoteActivityColor)
                }
            }
        } else {
            HStack(spacing: 11) {
                nestedIcon(entry)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(subtitle(for: entry))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if entry.activity == .running {
                    Circle()
                        .fill(RemoteTheme.accent)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func nestedIcon(_ entry: RemoteSubagentEntry) -> some View {
        Image(systemName: entry.activity == .running ? "waveform" : "person.crop.circle")
            .font(.caption.weight(.semibold))
            .foregroundStyle(entry.activity == .running ? RemoteTheme.accent : Color.secondary)
            .frame(width: 30, height: 30)
            .background(
                (entry.activity == .running ? RemoteTheme.accent : Color.secondary)
                    .opacity(0.10),
                in: Circle()
            )
    }

    private func capabilitySubtitle(for entry: RemoteSubagentEntry) -> String {
        var parts = [entry.mode == .continuable ? "可继续" : "一次性"]
        if entry.hasChildren { parts.append("包含下级工作") }
        return parts.joined(separator: " · ")
    }
}

private struct RemoteSubagentConversationView: View {
    @ObservedObject private var parentViewModel: RemoteConversationViewModel
    @StateObject private var viewModel: RemoteSubagentConversationViewModel
    @State private var draft = ""
    @State private var didInitialPosition = false
    @State private var isNearBottom = true
    @State private var unseenUpdates = 0
    @State private var lastItemCount = 0
    @State private var shouldFollowNextSend = false
    @State private var selectedDetail: RemoteConversationItem?
    @FocusState private var composerFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if DEBUG
    @State private var didRunLiveSubagentAction = false
    #endif

    init(
        parentViewModel: RemoteConversationViewModel,
        parentSessionID: String,
        parentAvailable: Bool,
        child: RemoteSubagentEntry
    ) {
        self.parentViewModel = parentViewModel
        _viewModel = StateObject(wrappedValue: RemoteSubagentConversationViewModel(
            client: parentViewModel.client,
            parentSessionID: parentSessionID,
            parentAvailable: parentAvailable,
            child: child
        ))
    }

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { viewport in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if viewModel.hasMoreHistory {
                            Button {
                                let anchor = viewModel.items.first?.id
                                Task {
                                    await viewModel.loadOlderHistory()
                                    guard let anchor else { return }
                                    DispatchQueue.main.async {
                                        var transaction = Transaction()
                                        transaction.disablesAnimations = true
                                        withTransaction(transaction) {
                                            proxy.scrollTo(anchor, anchor: .top)
                                        }
                                    }
                                }
                            } label: {
                                if viewModel.isLoadingOlder {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label("加载更早记录", systemImage: "clock.arrow.circlepath")
                                }
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(RemoteTheme.accent)
                            .frame(minHeight: 44)
                            .buttonStyle(RemotePressableRowButtonStyle(cornerRadius: 9))
                            .disabled(viewModel.isLoadingOlder)
                        }

                        if viewModel.isLoading, viewModel.items.isEmpty {
                            RemoteLoadingState(
                                icon: "arrow.triangle.2.circlepath",
                                title: "正在同步子代理",
                                message: "读取这项工作的对话记录"
                            )
                            .padding(.top, 42)
                        } else if viewModel.items.isEmpty, let error = viewModel.errorMessage {
                            RemoteEmptyState(
                                icon: "wifi.exclamationmark",
                                title: "暂时无法读取",
                                message: error,
                                action: { Task { await viewModel.refresh() } }
                            ) {
                                Label("重试", systemImage: "arrow.clockwise")
                            }
                            .padding(.top, 38)
                        } else if viewModel.items.isEmpty {
                            RemoteEmptyState(
                                icon: "bubble.left.and.bubble.right",
                                title: "还没有对话记录",
                                message: viewModel.child.mode == .continuable
                                    ? "可以从下方给这个子代理补充信息。"
                                    : "这项一次性工作尚未留下可展示的消息。"
                            )
                            .padding(.top, 38)
                        } else {
                            ForEach(viewModel.items) { item in
                                ConversationItemView(
                                    item: item,
                                    loadAttachment: { attachment in
                                        try await parentViewModel.attachmentData(
                                            for: attachment,
                                            sessionID: viewModel.child.id
                                        )
                                    },
                                    onOpenDetails: { selectedDetail = item }
                                )
                                .id(item.id)
                            }
                        }

                        GeometryReader { marker in
                            Color.clear.preference(
                                key: SubagentBottomOffsetKey.self,
                                value: marker.frame(in: .named("subagent-scroll")).minY
                            )
                        }
                        .frame(height: 1)
                        .id("subagent-bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 20)
                    .opacity(contentIsPositioned ? 1 : 0)
                }
                .coordinateSpace(name: "subagent-scroll")
                .scrollDismissesKeyboard(.interactively)
                .onPreferenceChange(SubagentBottomOffsetKey.self) { bottom in
                    isNearBottom = bottom <= viewport.size.height + 140
                    if isNearBottom { unseenUpdates = 0 }
                }
                .overlay(alignment: .bottomTrailing) {
                    if unseenUpdates > 0 {
                        Button {
                            withAnimation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 1)) {
                                proxy.scrollTo("subagent-bottom", anchor: .bottom)
                            }
                            unseenUpdates = 0
                        } label: {
                            Label("有新内容", systemImage: "arrow.down")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .foregroundStyle(.primary)
                                .background(RemoteTheme.surface, in: Capsule())
                                .overlay { Capsule().stroke(RemoteTheme.hairline) }
                        }
                        .buttonStyle(RemotePressableRowButtonStyle(cornerRadius: 22))
                        .padding(14)
                    }
                }
                .onChange(of: viewModel.isLoading) { _, loading in
                    guard !loading, !didInitialPosition else { return }
                    DispatchQueue.main.async {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            proxy.scrollTo("subagent-bottom", anchor: .bottom)
                        }
                        lastItemCount = viewModel.items.count
                        didInitialPosition = true
                    }
                }
                .onChange(of: viewModel.items.last) { _, _ in
                    guard didInitialPosition else { return }
                    let added = max(viewModel.items.count - lastItemCount, 1)
                    lastItemCount = viewModel.items.count
                    if isNearBottom || shouldFollowNextSend {
                        if shouldFollowNextSend, !reduceMotion {
                            withAnimation(.spring(response: 0.30, dampingFraction: 1)) {
                                proxy.scrollTo("subagent-bottom", anchor: .bottom)
                            }
                        } else {
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                proxy.scrollTo("subagent-bottom", anchor: .bottom)
                            }
                        }
                        shouldFollowNextSend = false
                    } else {
                        unseenUpdates = max(added, 1)
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if viewModel.child.mode == .continuable,
                       viewModel.parentAvailable || viewModel.child.activity == .running {
                        subagentComposer
                            .padding(.horizontal, 10)
                            .padding(.bottom, composerFocused ? 2 : 6)
                            .background(
                                LinearGradient(
                                    colors: [RemoteTheme.canvas.opacity(0), RemoteTheme.canvas],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                                .ignoresSafeArea()
                            )
                    }
                }
            }
        }
        .background(RemoteTheme.canvas)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                RemotePageHeader(
                    title: viewModel.child.label ?? "子代理",
                    subtitle: viewModel.child.mode == .continuable ? "可继续对话" : "一次性工作"
                ) {
                    HStack(spacing: 6) {
                        if viewModel.child.hasChildren {
                            NavigationLink {
                                RemoteNestedSubagentCatalogView(
                                    parentViewModel: parentViewModel,
                                    parentSessionID: viewModel.child.id,
                                    title: viewModel.child.label ?? "子代理"
                                )
                            } label: {
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(RemoteTheme.accent)
                                    .frame(width: 34, height: 34)
                                    .background(RemoteTheme.accent.opacity(0.10), in: Circle())
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(RemotePressableRowButtonStyle(cornerRadius: 22))
                            .accessibilityLabel("查看下级子代理")
                        }
                        RemoteStatusPill(
                            text: viewModel.child.remoteActivityLabel,
                            color: viewModel.child.remoteActivityColor,
                            icon: viewModel.child.remoteActivityIcon
                        )
                    }
                }
                if let error = viewModel.errorMessage, !viewModel.items.isEmpty {
                    RemoteInlineNotice(
                        title: "操作没有完成",
                        message: error,
                        icon: "exclamationmark.triangle.fill",
                        tone: .danger,
                        actionTitle: "关闭",
                        action: viewModel.dismissError
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                }
                if !viewModel.parentAvailable {
                    RemoteInlineNotice(
                        title: "父会话暂时不可用",
                        message: viewModel.child.activity == .running
                            ? "不能继续补充，但仍可停止正在运行的子代理。"
                            : (viewModel.child.mode == .continuable
                                ? "历史仍可阅读，恢复父会话后才能继续这项工作。"
                                : "历史仍可阅读；这项一次性工作不支持继续。"),
                        icon: "exclamationmark.triangle.fill",
                        tone: .warning
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                }
            }
            .background(RemoteTheme.canvas)
        }
        .remoteNavigationChromeHidden()
        .task { await viewModel.monitor() }
        #if DEBUG
        .task { await runLiveSubagentActionIfRequested() }
        #endif
        .onDisappear {
            Task { await parentViewModel.refreshSubagents() }
        }
        .sheet(item: $selectedDetail) { item in
            ConversationDetailSheet(
                item: item,
                loadAttachment: { attachment in
                    try await parentViewModel.attachmentData(
                        for: attachment,
                        sessionID: viewModel.child.id
                    )
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .presentationBackground(RemoteTheme.canvas)
        }
    }

    private var contentIsPositioned: Bool {
        viewModel.isLoading || viewModel.items.isEmpty || didInitialPosition
    }

    #if DEBUG
    @MainActor
    private func runLiveSubagentActionIfRequested() async {
        guard !didRunLiveSubagentAction,
              ProcessInfo.processInfo.environment["DSH_REMOTE_SCENARIO"] == "live-acceptance",
              let action = ProcessInfo.processInfo.environment["DSH_REMOTE_LIVE_SUBAGENT_ACTION"] else {
            return
        }
        didRunLiveSubagentAction = true
        for _ in 0..<100 where viewModel.isLoading {
            try? await Task.sleep(for: .milliseconds(100))
            if Task.isCancelled { return }
        }
        switch action {
        case "followup":
            _ = await viewModel.send("请再补充一句：移动端只开放了哪些最小 Remote 能力？")
        case "long-running":
            _ = await viewModel.send("请运行 sleep 45，然后只回复 done。")
        case "spawn-grandchild":
            _ = await viewModel.send(
                "请使用 subagent 工具创建一个名为 nested-remote-acceptance 的 continuable 子代理，让它只回复 nested ok；等待它返回后再结束。"
            )
        case "interrupt":
            for _ in 0..<100 where viewModel.child.activity != .running {
                try? await Task.sleep(for: .milliseconds(100))
                if Task.isCancelled { return }
            }
            await viewModel.interrupt()
        default:
            break
        }
    }
    #endif

    private var subagentComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.parentAvailable {
                TextField("给子代理补充信息", text: $draft, axis: .vertical)
                    .font(.body)
                    .lineLimit(1...6)
                    .textFieldStyle(.plain)
                    .focused($composerFocused)
                    .disabled(viewModel.isSending)
            } else {
                Label("父会话不可用，暂时不能补充", systemImage: "pause.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 38)
            }

            HStack(spacing: 4) {
                Text(viewModel.child.activity == .running ? "子代理正在执行" : "继续这项工作")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                if viewModel.child.activity == .running {
                    Button {
                        Task { await viewModel.interrupt() }
                    } label: {
                        Group {
                            if viewModel.isInterrupting {
                                ProgressView().controlSize(.small).tint(RemoteTheme.danger)
                            } else {
                                Image(systemName: "stop.fill")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(RemoteTheme.danger)
                            }
                        }
                        .frame(width: 34, height: 34)
                        .background(RemoteTheme.danger.opacity(0.10), in: Circle())
                        .frame(width: 44, height: 44)
                    }
                    .buttonStyle(RemotePressableRowButtonStyle(cornerRadius: 22))
                    .disabled(viewModel.isInterrupting || viewModel.isSending)
                    .accessibilityLabel("停止子代理")
                }
                if viewModel.parentAvailable {
                    Button {
                        let outgoing = draft
                        shouldFollowNextSend = true
                        Task {
                            if await viewModel.send(outgoing) {
                                draft = ""
                            } else {
                                shouldFollowNextSend = false
                            }
                        }
                    } label: {
                        Group {
                            if viewModel.isSending {
                                ProgressView().controlSize(.small).tint(.white)
                            } else {
                                Image(systemName: "arrow.up")
                                    .font(.caption.weight(.bold))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(RemoteTheme.accentFill, in: Circle())
                        .frame(width: 44, height: 44)
                    }
                    .buttonStyle(RemotePressableRowButtonStyle(cornerRadius: 22))
                    .disabled(
                        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || viewModel.isSending
                            || viewModel.isInterrupting
                    )
                    .opacity(
                        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1
                    )
                    .accessibilityLabel("发送给子代理")
                }
            }
        }
        .padding(12)
        .background(RemoteTheme.surface, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(RemoteTheme.hairline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.10), radius: 12, y: 5)
    }
}

private struct SubagentBottomOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct RemoteModelSelectionSheet: View {
    private struct EffortOption: Identifiable {
        let id: String
        let value: String?
        let name: String
        let description: String?
    }

    @ObservedObject var viewModel: RemoteConversationViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            RemoteSheetHeader(
                title: "模型与推理",
                subtitle: selectedCatalogModel.map { "当前：\($0.name)" } ?? "选择下一次请求使用的模型"
            ) {
                if viewModel.isLoadingModels || viewModel.isSelectingModel {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 32, height: 44)
                        .accessibilityLabel(
                            viewModel.isSelectingModel ? "正在切换模型" : "正在读取模型"
                        )
                }
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: RemoteTheme.sectionSpacing) {
                if viewModel.modelDirectory == nil && viewModel.isLoadingModels {
                    RemoteInlineNotice(
                        title: "正在读取电脑上的模型",
                        message: "模型目录由 DSH Desktop 提供。",
                        icon: "cpu",
                        tone: .info
                    )
                }

                if let error = viewModel.modelErrorMessage {
                    RemoteInlineNotice(
                        title: "模型操作失败",
                        message: error,
                        icon: "exclamationmark.triangle.fill",
                        tone: .danger,
                        actionTitle: "重新读取",
                        action: { Task { await viewModel.refreshModels() } }
                    )
                }

                if let directory = viewModel.modelDirectory {
                    if !directory.routable {
                        RemoteInlineNotice(
                            title: "当前模型不可用",
                            message: "请选择一个可路由模型后再继续发送。",
                            icon: "exclamationmark.triangle.fill",
                            tone: .warning
                        )
                    } else if selectedCatalogModel == nil {
                        RemoteInlineNotice(
                            title: "当前模型已不在目录中",
                            message: "现有路由仍可用，但建议选择新的模型。",
                            icon: "info.circle",
                            tone: .info
                        )
                    }

                    RemoteInlineNotice(
                        title: "切换范围",
                        message: "选择会从这个会话的下一次请求生效，电脑也会尝试保存为 Harness 的默认模型。",
                        icon: "arrow.triangle.2.circlepath",
                        tone: .info
                    )

                    ForEach(directory.groups) { group in
                        VStack(alignment: .leading, spacing: 9) {
                            RemoteSectionHeader(title: group.name, detail: "\(group.models.count) 个模型")
                            VStack(spacing: 0) {
                                ForEach(Array(group.models.enumerated()), id: \.element.id) { index, model in
                                    Button {
                                        chooseModel(provider: group.id, model: model.id)
                                    } label: {
                                        selectionRow(
                                            title: model.name,
                                            description: model.description,
                                            selected: directory.current.provider == group.id
                                                && directory.current.model == model.id
                                        )
                                    }
                                    .buttonStyle(RemotePressableRowButtonStyle(cornerRadius: 10))
                                    .disabled(viewModel.isSelectingModel)

                                    if index < group.models.count - 1 {
                                        Rectangle()
                                            .fill(RemoteTheme.hairline)
                                            .frame(height: 0.5)
                                            .padding(.leading, 14)
                                    }
                                }
                            }
                            .remoteSurface(cornerRadius: 14)
                        }
                    }

                    if !effortOptions.isEmpty {
                        VStack(alignment: .leading, spacing: 9) {
                            RemoteSectionHeader(title: "推理强度")
                            VStack(spacing: 0) {
                                ForEach(Array(effortOptions.enumerated()), id: \.element.id) { index, option in
                                    Button {
                                        chooseEffort(option.value)
                                    } label: {
                                        selectionRow(
                                            title: option.name,
                                            description: option.description,
                                            selected: effectiveEffort == option.value
                                        )
                                    }
                                    .buttonStyle(RemotePressableRowButtonStyle(cornerRadius: 10))
                                    .disabled(viewModel.isSelectingModel)

                                    if index < effortOptions.count - 1 {
                                        Rectangle()
                                            .fill(RemoteTheme.hairline)
                                            .frame(height: 0.5)
                                            .padding(.leading, 14)
                                    }
                                }
                            }
                            .remoteSurface(cornerRadius: 14)
                        }
                    }

                    if directory.groups.allSatisfy({ $0.models.isEmpty }) {
                        RemoteEmptyState(
                            icon: "cpu",
                            title: "没有可选择的模型",
                            message: "请先在 DSH Desktop 中配置模型提供方。"
                        )
                        .padding(.vertical, 28)
                    }

                    if !directory.failures.isEmpty {
                        VStack(alignment: .leading, spacing: 9) {
                            RemoteSectionHeader(title: "部分提供方不可用")
                            VStack(spacing: 0) {
                                ForEach(Array(directory.failures.enumerated()), id: \.element.id) { index, failure in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(failure.name)
                                        .font(.subheadline.weight(.medium))
                                    Text(failure.message)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(13)

                                    if index < directory.failures.count - 1 {
                                        Rectangle()
                                            .fill(RemoteTheme.hairline)
                                            .frame(height: 0.5)
                                            .padding(.leading, 13)
                                    }
                                }
                            }
                            .remoteSurface(cornerRadius: 14)
                        }
                    }
                }
                }
                .padding(.horizontal, RemoteTheme.pagePadding)
                .padding(.top, 18)
                .padding(.bottom, 32)
            }
            .refreshable { await viewModel.refreshModels() }
        }
        .background(RemoteTheme.canvas.ignoresSafeArea())
        .task { await viewModel.refreshModels() }
    }

    private var selectedCatalogModel: RemoteModelCatalogEntry? {
        guard let directory = viewModel.modelDirectory else { return nil }
        return directory.groups
            .first(where: { $0.id == directory.current.provider })?
            .models.first(where: { $0.id == directory.current.model })
    }

    private var effortOptions: [EffortOption] {
        guard let reasoning = selectedCatalogModel?.reasoning else { return [] }
        var options: [EffortOption] = []
        if reasoning.defaultEffort == nil {
            options.append(EffortOption(
                id: "provider-default",
                value: nil,
                name: "提供方默认",
                description: "由当前模型提供方决定推理强度"
            ))
        }
        options.append(contentsOf: reasoning.efforts.map {
            EffortOption(id: "effort:\($0.id)", value: $0.id, name: $0.name, description: $0.description)
        })
        return options
    }

    private var effectiveEffort: String? {
        guard let directory = viewModel.modelDirectory else { return nil }
        return directory.current.reasoningEffort ?? selectedCatalogModel?.reasoning?.defaultEffort
    }

    private func selectionRow(
        title: String,
        description: String?,
        selected: Bool
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                if let description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if selected {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(RemoteTheme.accentFill, in: Circle())
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func chooseModel(provider: String, model: String) {
        guard let directory = viewModel.modelDirectory else { return }
        if directory.current.provider == provider && directory.current.model == model {
            dismiss()
            return
        }
        Task {
            if await viewModel.selectModel(RemoteModelSelection(
                provider: provider,
                model: model,
                reasoningEffort: nil
            )) {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            }
        }
    }

    private func chooseEffort(_ effort: String?) {
        guard let current = viewModel.modelDirectory?.current else { return }
        if effectiveEffort == effort {
            dismiss()
            return
        }
        Task {
            if await viewModel.selectModel(RemoteModelSelection(
                provider: current.provider,
                model: current.model,
                reasoningEffort: effort
            )) {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            }
        }
    }
}

private struct ConversationItemView: View {
    let item: RemoteConversationItem
    let loadAttachment: (RemoteImageAttachment) async throws -> Data
    let onOpenDetails: () -> Void

    @State private var showsReasoning = false
    @State private var showsToolDetails = false
    @State private var copied = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch item.kind {
        case .user:
            HStack {
                Spacer(minLength: 56)
                VStack(alignment: .trailing, spacing: 5) {
                    if let title = item.title {
                        Text(title)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    if !item.attachments.isEmpty {
                        RemoteMessageImageGallery(
                            attachments: item.attachments,
                            alignment: .trailing,
                            loadAttachment: loadAttachment
                        )
                    }
                    if !item.text.isEmpty {
                        MarkdownContent(text: item.text)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(RemoteTheme.userBubble, in: RoundedRectangle(cornerRadius: 22))
                    }
                }
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 10) {
                if let reasoning = item.reasoning, !reasoning.isEmpty {
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 1)) {
                            showsReasoning.toggle()
                        }
                    } label: {
                        HStack(spacing: 7) {
                            if item.isStreaming {
                                ProgressView()
                                    .controlSize(.mini)
                                    .tint(RemoteTheme.thinking)
                            } else {
                                Image(systemName: "brain.head.profile")
                                    .font(.caption)
                                    .foregroundStyle(RemoteTheme.thinking)
                            }
                            Text(item.isStreaming ? "思考中" : "思考")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(reasoningPreview(reasoning))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Image(systemName: showsReasoning ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RemotePressableRowButtonStyle(cornerRadius: 9))
                    .accessibilityValue(showsReasoning ? "已展开" : "已收起")

                    if showsReasoning {
                        Text(reasoning)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 23)
                            .padding(.vertical, 4)
                    }
                }
                if !item.attachments.isEmpty {
                    RemoteMessageImageGallery(
                        attachments: item.attachments,
                        alignment: .leading,
                        loadAttachment: loadAttachment
                    )
                }
                if !item.text.isEmpty {
                    MarkdownContent(text: item.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if item.isStreaming {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("生成中")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if !item.text.isEmpty || !item.metadata.isEmpty {
                    HStack(spacing: 12) {
                        Button {
                            UIPasteboard.general.string = item.text
                            copied = true
                            Task {
                                try? await Task.sleep(for: .seconds(1.4))
                                copied = false
                            }
                        } label: {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(RemoteToolbarButtonStyle(tint: Color.secondary))
                        .accessibilityLabel(copied ? "已复制" : "复制回答")
                        MetadataLine(values: item.metadata)
                        Spacer(minLength: 0)
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .tool:
            VStack(alignment: .leading, spacing: 0) {
                if item.details.isEmpty && item.attachments.isEmpty {
                    toolHeader
                        .accessibilityElement(children: .combine)
                } else {
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 1)) {
                            showsToolDetails.toggle()
                        }
                    } label: {
                        toolHeader
                    }
                    .buttonStyle(RemotePressableRowButtonStyle(cornerRadius: 9))
                    .accessibilityValue(showsToolDetails ? "已展开" : "已收起")
                    .accessibilityHint(showsToolDetails ? "收起工具详情" : "展开工具详情")
                }

                if showsToolDetails {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(stateColor)
                                .frame(width: 6, height: 6)
                            Text(stateLabel)
                                .font(.caption2.weight(.semibold))
                            MetadataLine(values: item.metadata)
                            Spacer()
                        }
                        if let detail = item.details.first {
                            toolDetailPreview(detail)
                        }
                        if !item.attachments.isEmpty {
                            RemoteMessageImageGallery(
                                attachments: item.attachments,
                                alignment: .leading,
                                loadAttachment: loadAttachment
                            )
                        }
                        HStack {
                            if item.details.count > 1 {
                                Text("另有 \(item.details.count - 1) 段详情")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Button("查看详情", action: onOpenDetails)
                                .buttonStyle(RemoteActionButtonStyle(
                                    kind: .secondary,
                                    fillsWidth: false,
                                    compact: true
                                ))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
            }
            .background(showsToolDetails ? RemoteTheme.surface : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                if showsToolDetails {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(RemoteTheme.accent.opacity(0.65), lineWidth: 1)
                }
            }
        case .context:
            VStack(alignment: .leading, spacing: 4) {
                if item.details.isEmpty {
                    contextRow
                        .accessibilityElement(children: .combine)
                } else {
                    Button(action: onOpenDetails) {
                        contextRow
                    }
                    .buttonStyle(RemotePressableRowButtonStyle(cornerRadius: 9))
                    .accessibilityHint("查看上下文详情")
                }
                if !item.attachments.isEmpty {
                    RemoteMessageImageGallery(
                        attachments: item.attachments,
                        alignment: .leading,
                        loadAttachment: loadAttachment
                    )
                    .padding(.leading, 26)
                }
            }
        case .status:
            if item.details.isEmpty {
                statusRow
                    .accessibilityElement(children: .combine)
            } else {
                Button(action: onOpenDetails) {
                    statusRow
                }
                .buttonStyle(RemotePressableRowButtonStyle(cornerRadius: 9))
                .accessibilityHint("查看状态详情")
            }
        }
    }

    private var contextRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(item.title ?? "上下文")
                .font(.caption.weight(.semibold))
            Text("·")
                .foregroundStyle(.tertiary)
            Text(item.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 6)
            if !item.details.isEmpty {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 7)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private var statusRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: item.symbolName ?? stateIcon)
                .font(.caption)
                .foregroundStyle(stateColor)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                if let title = item.title {
                    Text(title).font(.caption.weight(.semibold))
                }
                Text(item.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            if !item.details.isEmpty {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 7)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private var toolHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: toolIcon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(RemoteTheme.tool)
                .frame(width: 18)
            Text(item.title ?? "工具")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            if !item.text.isEmpty {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(item.text)
                    .font(.caption)
                    .foregroundStyle(item.state == .failed ? RemoteTheme.danger : .secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if item.state == .running {
                ProgressView().controlSize(.mini)
            } else {
                Circle()
                    .fill(stateColor)
                    .frame(width: 6, height: 6)
            }
            if !item.details.isEmpty || !item.attachments.isEmpty {
                Image(systemName: showsToolDetails ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, showsToolDetails ? 10 : 0)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func reasoningPreview(_ value: String) -> String {
        value
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
    }

    @ViewBuilder
    private func toolDetailPreview(_ detail: RemoteDetailSection) -> some View {
        switch detail.kind {
        case .text:
            Text(detail.content)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(6)
                .textSelection(.enabled)
        case .code(_), .diff, .list:
            ScrollView(.horizontal, showsIndicators: false) {
                Text(detail.content)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(8)
                    .fixedSize(horizontal: true, vertical: false)
                    .textSelection(.enabled)
            }
            .padding(8)
            .background(RemoteTheme.codeSurface, in: RoundedRectangle(cornerRadius: 7))
        }
    }

    private var stateLabel: String {
        switch item.state {
        case .running: "执行中"
        case .succeeded: "已完成"
        case .failed: "失败"
        case .stopped: "已停止"
        case .info: "信息"
        }
    }

    private var stateColor: Color {
        if item.symbolName == "map", item.state == .running { return RemoteTheme.warning }
        return switch item.state {
        case .running: RemoteTheme.accent
        case .succeeded: RemoteTheme.success
        case .failed: RemoteTheme.danger
        case .stopped: RemoteTheme.warning
        case .info: .secondary
        }
    }

    private var stateIcon: String {
        switch item.state {
        case .running: "hourglass"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .stopped: "stop.circle.fill"
        case .info: "info.circle.fill"
        }
    }

    private var toolIcon: String {
        switch item.toolCategory {
        case "read": return "doc.text"
        case "edit": return "square.and.pencil"
        case "delete": return "trash"
        case "move": return "folder.badge.arrow.forward"
        case "search": return "magnifyingglass"
        case "execute": return "terminal.fill"
        case "fetch": return "globe"
        default: break
        }
        return switch item.toolCard {
        case .terminal: "terminal.fill"
        case .diff: "plus.forwardslash.minus"
        case .search: "magnifyingglass"
        case .read: "doc.text"
        case .web: "globe"
        default: "wrench.and.screwdriver.fill"
        }
    }
}

private struct TrajectoryLedgerView: View {
    let records: [RemoteTrajectoryRecord]
    @Binding var query: String
    let onOpenDetails: (RemoteTrajectoryRecord) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            ledgerToolbar
                .id("trajectory-top")
            if !dynamicTypeSize.isAccessibilitySize {
                trajectoryOverview
                    .padding(.bottom, 8)
            }
            Rectangle()
                .fill(RemoteTheme.hairline)
                .frame(height: 0.5)

            if filteredRecords.isEmpty {
                RemoteEmptyState(
                    icon: query.isEmpty ? "point.3.connected.trianglepath.dotted" : "magnifyingglass",
                    title: query.isEmpty ? "暂无轨迹" : "没有匹配结果",
                    message: query.isEmpty ? "Harness 开始执行后，步骤会按顺序出现在这里。" : "换一个关键词搜索标题、摘要或工具输出。"
                )
                .padding(.vertical, 42)
            } else {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(groupTitle(group))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Text("\(group.records.count) 条事件")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.top, 13)
                        .padding(.bottom, 5)

                        VStack(spacing: 0) {
                            ForEach(Array(group.records.enumerated()), id: \.element.id) { index, record in
                                Group {
                                    if record.details.isEmpty {
                                        trajectoryRow(record)
                                            .accessibilityElement(children: .combine)
                                    } else {
                                        Button {
                                            onOpenDetails(record)
                                        } label: {
                                            trajectoryRow(record)
                                        }
                                        .buttonStyle(RemotePressableRowButtonStyle(cornerRadius: 8))
                                        .accessibilityHint("查看事件详情")
                                    }
                                }
                                .id(record.id)
                                .background {
                                    GeometryReader { rowGeometry in
                                        Color.clear.preference(
                                            key: ConversationVisibleAnchorPreferenceKey.self,
                                            value: [
                                                "trajectory:\(record.id)": rowGeometry.frame(
                                                    in: .named("conversation-scroll")
                                                ),
                                            ]
                                        )
                                    }
                                }

                                if index < group.records.count - 1 {
                                    Rectangle()
                                        .fill(RemoteTheme.hairline)
                                        .frame(height: 0.5)
                                        .padding(.leading, 31)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func trajectoryRow(_ record: RemoteTrajectoryRecord) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .top, spacing: 9) {
                        trajectoryIcon(record)
                        Text(record.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                    }
                    Text(record.summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    trajectoryMetadata(record)
                }
            } else {
                HStack(alignment: .center, spacing: 9) {
                    trajectoryIcon(record)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(record.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if let step = record.step {
                                Text("步骤 \(step + 1)")
                                    .font(.caption2.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Text(record.summary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    trajectoryMetadata(record)
                }
            }
        }
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func trajectoryIcon(_ record: RemoteTrajectoryRecord) -> some View {
        Image(systemName: icon(for: record.kind))
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(kindColor(record))
            .frame(width: 24, height: 24)
            .background(kindColor(record).opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func trajectoryMetadata(_ record: RemoteTrajectoryRecord) -> some View {
        if record.state == .running
            && record.kind != .goal
            && record.kind != .plan {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("执行中")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 8) {
                if let step = record.step, dynamicTypeSize.isAccessibilitySize {
                    Text("步骤 \(step + 1)")
                }
                if let duration = record.duration {
                    Text(durationLabel(duration))
                }
                Text("#\(record.sequence)")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.tertiary)
        }
    }

    private var ledgerToolbar: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                Text("总耗时 \(durationLabel(trajectoryDuration)) · \(Set(filteredRecords.compactMap(\.turn)).count) 轮 · \(filteredRecords.filter { $0.kind == .tool }.count) 次调用")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 13) {
                    metric("耗时", value: durationLabel(trajectoryDuration))
                    metric("轮次", value: "\(Set(filteredRecords.compactMap(\.turn)).count)")
                    metric("调用", value: "\(filteredRecords.filter { $0.kind == .tool }.count)")
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.vertical, 9)
    }

    private var trajectoryDuration: TimeInterval {
        let completedTurnDurations = filteredRecords
            .filter { $0.kind == .lifecycle }
            .compactMap(\.duration)
        if !completedTurnDurations.isEmpty {
            return completedTurnDurations.reduce(0, +)
        }
        return filteredRecords.compactMap(\.duration).max() ?? 0
    }

    private func metric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var trajectoryOverview: some View {
        VStack(spacing: 5) {
            timelineLane("输入", kinds: [.input, .context])
            timelineLane("模型", kinds: [.request, .assistant])
            timelineLane("工具", kinds: [.tool])
            timelineLane("状态", kinds: [.goal, .plan, .lifecycle])
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(RemoteTheme.surface, in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(RemoteTheme.hairline, lineWidth: 1)
        }
    }

    private func timelineLane(
        _ title: String,
        kinds: [RemoteTrajectoryRecord.Kind]
    ) -> some View {
        HStack(spacing: 7) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
                .frame(width: 34, alignment: .leading)
            GeometryReader { geometry in
                let visible = filteredRecords.filter { kinds.contains($0.kind) }
                let minimum = filteredRecords.map(\.sequence).min() ?? 0
                let maximum = filteredRecords.map(\.sequence).max() ?? minimum
                let span = max(maximum - minimum, 1)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(RemoteTheme.hairline)
                        .frame(height: 2)
                    ForEach(visible) { record in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(kindColor(record))
                            .frame(width: 6, height: 7)
                            .offset(
                                x: CGFloat(record.sequence - minimum)
                                    / CGFloat(span)
                                    * max(geometry.size.width - 6, 0)
                            )
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 8)
        }
    }

    private var filteredRecords: [RemoteTrajectoryRecord] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return records }
        return records.filter {
            $0.title.localizedCaseInsensitiveContains(normalized)
                || $0.summary.localizedCaseInsensitiveContains(normalized)
                || $0.details.contains { $0.content.localizedCaseInsensitiveContains(normalized) }
        }
    }

    private struct TrajectoryGroup: Identifiable {
        let turn: Int?
        let records: [RemoteTrajectoryRecord]
        var id: String { turn.map { "turn:\($0)" } ?? "context" }
    }

    private var groups: [TrajectoryGroup] {
        let grouped = Dictionary(grouping: filteredRecords, by: \.turn)
        return grouped.keys.sorted { lhs, rhs in
            switch (lhs, rhs) {
            case (nil, nil): false
            case (nil, _): true
            case (_, nil): false
            case (.some(let left), .some(let right)): left < right
            }
        }.map { TrajectoryGroup(turn: $0, records: grouped[$0, default: []]) }
    }

    private func groupTitle(_ group: TrajectoryGroup) -> String {
        if let turn = group.turn { return "第 \(turn + 1) 轮" }
        return group.records.contains(where: { [.goal, .plan].contains($0.kind) })
            ? "会话状态与上下文"
            : "会话上下文"
    }

    private func icon(for kind: RemoteTrajectoryRecord.Kind) -> String {
        switch kind {
        case .input: "text.bubble.fill"
        case .context: "doc.text.magnifyingglass"
        case .request: "arrow.up.forward.app"
        case .assistant: "sparkle"
        case .tool: "wrench.and.screwdriver.fill"
        case .goal: "target"
        case .plan: "map"
        case .lifecycle: "flag.checkered"
        }
    }

    private func kindColor(_ record: RemoteTrajectoryRecord) -> Color {
        if record.state == .failed { return RemoteTheme.danger }
        if record.state == .stopped { return RemoteTheme.warning }
        return switch record.kind {
        case .input: RemoteTheme.accent
        case .context: RemoteTheme.success
        case .request: .cyan
        case .assistant: RemoteTheme.thinking
        case .tool: RemoteTheme.tool
        case .goal: record.state == .succeeded ? RemoteTheme.success : RemoteTheme.accent
        case .plan: RemoteTheme.warning
        case .lifecycle: .secondary
        }
    }

    private func durationLabel(_ value: TimeInterval) -> String {
        value < 1 ? "\(Int(value * 1_000)) ms" : String(format: "%.1f 秒", value)
    }
}

private struct MetadataLine: View {
    let values: [String]

    var body: some View {
        if !values.isEmpty {
            Text(values.joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }
}

private struct RemoteMessageImageGallery: View {
    let attachments: [RemoteImageAttachment]
    let alignment: Alignment
    let loadAttachment: (RemoteImageAttachment) async throws -> Data

    var body: some View {
        Group {
            if let attachment = attachments.first, attachments.count == 1 {
                let size = singleImageSize(attachment)
                RemoteMessageImageView(
                    attachment: attachment,
                    size: size,
                    contentMode: .fit,
                    loadAttachment: loadAttachment
                )
                .frame(maxWidth: .infinity, alignment: alignment)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 64, maximum: 64), spacing: 10)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(Array(attachments.enumerated()), id: \.offset) { _, attachment in
                        RemoteMessageImageView(
                            attachment: attachment,
                            size: CGSize(width: 64, height: 64),
                            contentMode: .fill,
                            loadAttachment: loadAttachment
                        )
                    }
                }
                .frame(maxWidth: 286, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: alignment)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func singleImageSize(_ attachment: RemoteImageAttachment) -> CGSize {
        let rawRatio = CGFloat(attachment.width) / CGFloat(attachment.height)
        let ratio = min(max(rawRatio, 0.25), 4)
        if ratio >= 1 {
            return CGSize(width: 240, height: 240 / ratio)
        }
        return CGSize(width: 240 * ratio, height: 240)
    }
}

private struct RemoteMessageImageView: View {
    private enum Phase {
        case loading
        case loaded(UIImage)
        case failed
    }

    let attachment: RemoteImageAttachment
    let size: CGSize
    let contentMode: ContentMode
    let loadAttachment: (RemoteImageAttachment) async throws -> Data

    @State private var phase: Phase = .loading
    @State private var retryGeneration = 0
    @State private var showsViewer = false

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ZStack {
                    RemoteTheme.mutedSurface
                    VStack(spacing: 7) {
                        ProgressView().controlSize(.small)
                        Text("图片加载中")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel("图片加载中")
            case .loaded(let image):
                Button {
                    showsViewer = true
                } label: {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(width: size.width, height: size.height)
                        .background(RemoteTheme.mutedSurface)
                        .clipped()
                        .contentShape(Rectangle())
                }
                .buttonStyle(RemotePressableRowButtonStyle(cornerRadius: 10))
                .accessibilityLabel(attachment.name ?? "图片")
                .accessibilityHint("打开图片预览")
            case .failed:
                Button {
                    phase = .loading
                    retryGeneration += 1
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                        Text("加载失败")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RemotePressableRowButtonStyle(cornerRadius: 10))
                .background(RemoteTheme.mutedSurface)
                .accessibilityLabel("图片加载失败，重试")
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(RemoteTheme.hairline, lineWidth: 1)
        }
        .task(id: retryGeneration) {
            await load()
        }
        .fullScreenCover(isPresented: $showsViewer) {
            if case .loaded(let image) = phase {
                RemoteImageViewer(image: image, name: attachment.name)
            }
        }
    }

    private func load() async {
        do {
            let data = try await loadAttachment(attachment)
            let targetPixels = max(size.width, size.height) * UIScreen.main.scale * 3
            let image = try await Task.detached(priority: .utility) {
                try Self.downsampledImage(data: data, maxPixelSize: targetPixels)
            }.value
            guard !Task.isCancelled else { return }
            phase = .loaded(image)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed
        }
    }

    nonisolated private static func downsampledImage(
        data: Data,
        maxPixelSize: CGFloat
    ) throws -> UIImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw HarnessRemoteClientError.invalidResponse
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(Int(maxPixelSize), 320),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            throw HarnessRemoteClientError.invalidResponse
        }
        return UIImage(cgImage: image)
    }
}

private struct RemoteImageViewer: View {
    let image: UIImage
    let name: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RemoteZoomableImageView(
                image: image,
                accessibilityName: name ?? "图片",
                reduceMotion: reduceMotion
            )
            .ignoresSafeArea()
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 10) {
                Text(name ?? "图片预览")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(RemoteToolbarButtonStyle(tint: .white))
                .foregroundStyle(.white)
                .accessibilityLabel("关闭图片预览")
            }
            .padding(.horizontal, 12)
        }
        .accessibilityAction(.escape) { dismiss() }
    }
}

private struct RemoteZoomableImageView: UIViewRepresentable {
    let image: UIImage
    let accessibilityName: String
    let reduceMotion: Bool

    func makeUIView(context: Context) -> RemoteZoomCanvas {
        RemoteZoomCanvas()
    }

    func updateUIView(_ view: RemoteZoomCanvas, context: Context) {
        view.configure(
            image: image,
            accessibilityName: accessibilityName,
            reduceMotion: reduceMotion
        )
    }
}

private final class RemoteZoomCanvas: UIView, UIScrollViewDelegate {
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private var renderedImage: UIImage?
    private var reduceMotion = false
    private var previousBoundsSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = .black
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.bouncesZoom = true
        scrollView.decelerationRate = .normal
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = false
        scrollView.addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        isAccessibilityElement = true
        accessibilityTraits = .image
        accessibilityHint = "使用放大和缩小操作调整图片"
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "放大", target: self, selector: #selector(zoomIn)),
            UIAccessibilityCustomAction(name: "缩小", target: self, selector: #selector(zoomOut)),
        ]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != previousBoundsSize else { return }
        previousBoundsSize = bounds.size
        resetLayout()
    }

    func configure(image: UIImage, accessibilityName: String, reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        accessibilityLabel = accessibilityName
        if renderedImage !== image {
            renderedImage = image
            imageView.image = image
            previousBoundsSize = .zero
            setNeedsLayout()
        }
        updateAccessibilityValue()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
        updateAccessibilityValue()
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: !reduceMotion)
        } else {
            zoom(to: 2.5, around: gesture.location(in: imageView))
        }
    }

    @objc private func zoomIn() -> Bool {
        let next = min(scrollView.zoomScale + 0.5, scrollView.maximumZoomScale)
        zoom(to: next, around: CGPoint(x: imageView.bounds.midX, y: imageView.bounds.midY))
        return true
    }

    @objc private func zoomOut() -> Bool {
        let next = max(scrollView.zoomScale - 0.5, scrollView.minimumZoomScale)
        scrollView.setZoomScale(next, animated: !reduceMotion)
        return true
    }

    private func resetLayout() {
        guard let image = renderedImage,
              scrollView.bounds.width > 0,
              scrollView.bounds.height > 0 else { return }
        scrollView.setZoomScale(1, animated: false)
        let available = CGSize(
            width: max(scrollView.bounds.width - 16, 1),
            height: max(scrollView.bounds.height, 1)
        )
        let source = CGSize(width: max(image.size.width, 1), height: max(image.size.height, 1))
        let scale = min(available.width / source.width, available.height / source.height)
        imageView.transform = .identity
        imageView.frame = CGRect(
            origin: .zero,
            size: CGSize(width: source.width * scale, height: source.height * scale)
        )
        scrollView.contentSize = imageView.frame.size
        centerImage()
        updateAccessibilityValue()
    }

    private func centerImage() {
        let contentSize = scrollView.contentSize
        let horizontalInset = max((scrollView.bounds.width - contentSize.width) / 2, 0)
        let verticalInset = max((scrollView.bounds.height - contentSize.height) / 2, 0)
        scrollView.contentInset = UIEdgeInsets(
            top: verticalInset,
            left: horizontalInset,
            bottom: verticalInset,
            right: horizontalInset
        )
    }

    private func zoom(to scale: CGFloat, around point: CGPoint) {
        let target = min(max(scale, scrollView.minimumZoomScale), scrollView.maximumZoomScale)
        let rect = CGRect(
            x: point.x - scrollView.bounds.width / (target * 2),
            y: point.y - scrollView.bounds.height / (target * 2),
            width: scrollView.bounds.width / target,
            height: scrollView.bounds.height / target
        )
        scrollView.zoom(to: rect, animated: !reduceMotion)
    }

    private func updateAccessibilityValue() {
        accessibilityValue = scrollView.zoomScale <= 1.01
            ? "适合屏幕"
            : "已放大 \(Int(scrollView.zoomScale * 100))%"
    }
}

private struct MarkdownContent: View {
    let text: String
    var inverted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .markdown(let value):
                    if let attributed = try? AttributedString(
                        markdown: value,
                        options: .init(interpretedSyntax: .full)
                    ) {
                        Text(attributed)
                            .font(.body)
                            .lineSpacing(5)
                            .textSelection(.enabled)
                            .foregroundStyle(inverted ? Color.white : Color.primary)
                    } else {
                        Text(value)
                            .font(.body)
                            .lineSpacing(5)
                            .textSelection(.enabled)
                            .foregroundStyle(inverted ? Color.white : Color.primary)
                    }
                case .code(let language, let value):
                    VStack(alignment: .leading, spacing: 7) {
                        if let language, !language.isEmpty {
                            Text(language.uppercased())
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(value)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .padding(11)
                    .background(
                        inverted ? Color.white.opacity(0.14) : RemoteTheme.codeSurface,
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(inverted ? Color.white.opacity(0.08) : RemoteTheme.hairline)
                    }
                }
            }
        }
    }

    private enum Segment {
        case markdown(String)
        case code(language: String?, value: String)
    }

    private var segments: [Segment] {
        let pieces = text.components(separatedBy: "```")
        guard pieces.count > 1 else { return [.markdown(text)] }
        return pieces.enumerated().compactMap { index, piece in
            guard !piece.isEmpty else { return nil }
            if index.isMultiple(of: 2) { return .markdown(piece) }
            let lines = piece.split(separator: "\n", omittingEmptySubsequences: false)
            let language = lines.first.map(String.init)
            let body = lines.dropFirst().joined(separator: "\n")
            return .code(language: language, value: body)
        }
    }
}

private struct ConversationDetailSheet: View {
    let item: RemoteConversationItem
    let loadAttachment: (RemoteImageAttachment) async throws -> Data
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedSectionID: String?
    @State private var copied = false

    init(
        item: RemoteConversationItem,
        loadAttachment: @escaping (RemoteImageAttachment) async throws -> Data
    ) {
        self.item = item
        self.loadAttachment = loadAttachment
        let preferred = item.details.first(where: { $0.id == "context-raw" })
            ?? item.details.first
        _selectedSectionID = State(initialValue: preferred?.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            detailHeader
            if item.details.count > 1 {
                detailTabs
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if !item.attachments.isEmpty {
                        RemoteMessageImageGallery(
                            attachments: item.attachments,
                            alignment: .leading,
                            loadAttachment: loadAttachment
                        )
                    }
                    if let summaryText {
                        Text(summaryText)
                            .font(.subheadline)
                            .lineSpacing(3)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let section = activeSection {
                        VStack(alignment: .leading, spacing: 6) {
                            if let label = inlineSectionLabel(section) {
                                Text(label)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                            detailContent(section)
                        }
                    } else if !item.text.isEmpty {
                        MarkdownContent(text: item.text)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .id(selectedSectionID)
        }
        .background(RemoteTheme.canvas)
    }

    private var detailHeader: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 5) {
                    detailHeaderIdentity
                    HStack {
                        Spacer(minLength: 0)
                        detailHeaderActions
                    }
                }
            } else {
                HStack(spacing: 8) {
                    detailHeaderIdentity
                    Spacer(minLength: 4)
                    detailHeaderActions
                }
            }
        }
        .frame(minHeight: 44)
        .padding(.leading, 12)
        .padding(.trailing, 2)
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 6 : 0)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(RemoteTheme.hairline)
                .frame(height: 0.5)
        }
    }

    private var detailHeaderIdentity: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(kindColor)
                .frame(width: 5, height: 5)
                .padding(.top, 7)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 3) {
                    Text(headerTitle)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(3)
                    if let metadata = item.metadata.first, !metadata.isEmpty {
                        Text(metadata)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                }
            } else {
                Text(headerTitle)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if let metadata = item.metadata.first, !metadata.isEmpty {
                    Text(metadata)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private var detailHeaderActions: some View {
        HStack(spacing: 2) {
            Button {
                copy(copyPayload)
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(RemoteToolbarButtonStyle(tint: copied ? RemoteTheme.success : Color.secondary))
            .accessibilityLabel(copied ? "已复制" : copyAccessibilityLabel)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(RemoteToolbarButtonStyle(tint: .secondary))
            .accessibilityLabel("关闭详情")
        }
    }

    private var detailTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 1) {
                ForEach(item.details) { section in
                    Button {
                        selectedSectionID = section.id
                    } label: {
                        Text(tabTitle(section))
                            .font(.subheadline)
                            .foregroundStyle(
                                selectedSectionID == section.id
                                    ? RemoteTheme.accent
                                    : Color.secondary
                            )
                            .padding(.horizontal, 9)
                            .frame(minHeight: 44)
                            .overlay(alignment: .bottom) {
                                if selectedSectionID == section.id {
                                    Rectangle()
                                        .fill(RemoteTheme.accent)
                                        .frame(height: 2)
                                }
                            }
                    }
                    .buttonStyle(RemotePressableRowButtonStyle(cornerRadius: 8))
                    .accessibilityAddTraits(selectedSectionID == section.id ? .isSelected : [])
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(minHeight: 44)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(RemoteTheme.hairline)
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    private func detailContent(_ section: RemoteDetailSection) -> some View {
        switch section.kind {
        case .text:
            if item.kind == .context, section.id == "context-raw" {
                InstructionDocumentView(rawText: section.content)
            } else {
                MarkdownContent(text: section.content)
            }
        case .code(let language):
            VStack(alignment: .leading, spacing: 6) {
                if let language, !language.isEmpty {
                    Text(language.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                Text(codeBody(section.content))
                    .font(.system(.caption, design: .monospaced))
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(RemoteTheme.codeSurface, in: RoundedRectangle(cornerRadius: 12))
        case .diff:
            ScrollView(.horizontal, showsIndicators: true) {
                Text(attributedDiff(section.content))
                    .font(.system(.caption, design: .monospaced))
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(14)
            .background(RemoteTheme.codeSurface, in: RoundedRectangle(cornerRadius: 12))
        case .list:
            if section.id == "instruction-sources" {
                InstructionSourcesView(content: section.content)
            } else {
                Text(section.content)
                    .font(.subheadline)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RemoteTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                    .overlay { RoundedRectangle(cornerRadius: 10).stroke(RemoteTheme.hairline) }
            }
        }
    }

    private var activeSection: RemoteDetailSection? {
        item.details.first(where: { $0.id == selectedSectionID }) ?? item.details.first
    }

    private var headerTitle: String {
        if let title = item.title, !title.isEmpty { return title }
        return switch item.kind {
        case .user: "用户消息"
        case .assistant: "模型输出"
        case .tool: "工具详情"
        case .context: "上下文"
        case .status: "执行详情"
        }
    }

    private var summaryText: String? {
        guard item.kind != .context else { return nil }
        let value = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              value != item.title,
              value != "<system-reminder>",
              value != "</system-reminder>" else { return nil }
        return value
    }

    private func inlineSectionLabel(_ section: RemoteDetailSection) -> String? {
        guard item.details.count == 1,
              let title = section.title,
              !title.isEmpty,
              title != item.title,
              title != "完整内容" else { return nil }
        return title
    }

    private func tabTitle(_ section: RemoteDetailSection) -> String {
        switch section.id {
        case "context-raw", "message": return "内容"
        case "instruction-sources": return "来源"
        default: return section.title ?? "详情"
        }
    }

    private var copyPayload: String {
        if let original = item.details.first(where: { $0.id == "context-raw" })?.content {
            return original
        }
        guard let section = activeSection else { return item.text }
        if case .code = section.kind { return codeBody(section.content) }
        return section.content
    }

    private var copyAccessibilityLabel: String {
        item.kind == .context ? "复制模型接收的原文" : "复制当前详情"
    }

    private func copy(_ value: String) {
        UIPasteboard.general.setItems(
            [["public.utf8-plain-text": value]],
            options: [.localOnly: true]
        )
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            copied = false
        }
    }

    private var kindColor: Color {
        switch item.kind {
        case .user: RemoteTheme.accent
        case .assistant: RemoteTheme.thinking
        case .tool: RemoteTheme.tool
        case .context: RemoteTheme.success
        case .status: .secondary
        }
    }

    private func attributedDiff(_ value: String) -> AttributedString {
        var result = AttributedString()
        for line in value.split(separator: "\n", omittingEmptySubsequences: false) {
            var part = AttributedString(String(line) + "\n")
            if line.hasPrefix("+") && !line.hasPrefix("+++") {
                part.foregroundColor = .green
            } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                part.foregroundColor = .red
            }
            result.append(part)
        }
        return result
    }

    private func codeBody(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return value }
        var lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
        if !lines.isEmpty { lines.removeFirst() }
        if lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```" {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }
}

private struct InstructionDocumentView: View {
    let rawText: String

    private let displayLimit = 20_000

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if presentation.isSystemReminder {
                Label("模型上下文", systemImage: "shield.lefthalf.filled")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(RemoteTheme.success)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RemoteTheme.success.opacity(0.09), in: Capsule())
            }

            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }

            if isTruncated {
                Label("正文仅展示前 \(displayLimit.formatted()) 个字符；复制仍包含完整原文", systemImage: "ellipsis.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            inlineText(text)
                .font(level == 1 ? .headline : .subheadline.weight(.semibold))
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        case .paragraph(let text):
            inlineText(text)
                .font(.subheadline)
                .lineSpacing(5)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        case .listItem(let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker)
                    .font(.system(.footnote, design: .monospaced).weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 12, alignment: .trailing)
                inlineText(text)
                    .font(.subheadline)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .quote(let text):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(RemoteTheme.hairline)
                    .frame(width: 2)
                inlineText(text)
                    .font(.footnote)
                    .lineSpacing(4)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .code(let language, let text):
            VStack(alignment: .leading, spacing: 7) {
                if let language, !language.isEmpty {
                    Text(language.uppercased())
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .foregroundStyle(.secondary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(text)
                        .font(.system(.caption, design: .monospaced))
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(14)
            .background(RemoteTheme.codeSurface, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func inlineText(_ value: String) -> Text {
        guard let attributed = try? AttributedString(
            markdown: value,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else { return Text(value) }
        return Text(attributed)
    }

    private var presentation: (text: String, isSystemReminder: Bool) {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.components(separatedBy: .newlines)
        guard lines.count >= 2,
              lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "<system-reminder>",
              lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "</system-reminder>" else {
            return (trimmed, false)
        }
        return (lines.dropFirst().dropLast().joined(separator: "\n"), true)
    }

    private var displayedText: String {
        String(presentation.text.prefix(displayLimit))
    }

    private var isTruncated: Bool {
        presentation.text.count > displayLimit
    }

    private enum Block {
        case heading(level: Int, text: String)
        case paragraph(String)
        case listItem(marker: String, text: String)
        case quote(String)
        case code(language: String?, text: String)
    }

    private var blocks: [Block] {
        let lines = displayedText.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        var result: [Block] = []
        var paragraph: [String] = []
        var index = 0

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            result.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph.removeAll(keepingCapacity: true)
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let fence = fenceInfo(trimmed) {
                flushParagraph()
                var codeLines: [String] = []
                index += 1
                while index < lines.count, !isClosingFence(lines[index], fence: fence) {
                    codeLines.append(lines[index])
                    index += 1
                }
                result.append(.code(language: fence.language, text: codeLines.joined(separator: "\n")))
            } else if trimmed.isEmpty {
                flushParagraph()
            } else if let heading = headingInfo(trimmed) {
                flushParagraph()
                result.append(.heading(level: heading.level, text: heading.text))
            } else if let item = listItemInfo(trimmed) {
                flushParagraph()
                result.append(.listItem(marker: item.marker, text: item.text))
            } else if trimmed.hasPrefix("> ") {
                flushParagraph()
                result.append(.quote(String(trimmed.dropFirst(2))))
            } else {
                paragraph.append(line)
            }
            index += 1
        }
        flushParagraph()
        return result
    }

    private func headingInfo(_ line: String) -> (level: Int, text: String)? {
        let level = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(level),
              line.dropFirst(level).first == " " else { return nil }
        return (level, String(line.dropFirst(level + 1)))
    }

    private func listItemInfo(_ line: String) -> (marker: String, text: String)? {
        for prefix in ["- ", "* ", "+ "] where line.hasPrefix(prefix) {
            return ("•", String(line.dropFirst(prefix.count)))
        }
        let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else { return nil }
        let marker = String(parts[0])
        guard let suffix = marker.last,
              suffix == "." || suffix == ")",
              marker.dropLast().allSatisfy(\.isNumber),
              !marker.dropLast().isEmpty else { return nil }
        return (marker, String(parts[1]))
    }

    private func fenceInfo(_ line: String) -> (character: Character, count: Int, language: String?)? {
        guard let character = line.first, character == "`" || character == "~" else { return nil }
        let count = line.prefix(while: { $0 == character }).count
        guard count >= 3 else { return nil }
        let language = line.dropFirst(count).trimmingCharacters(in: .whitespaces)
        return (character, count, language.isEmpty ? nil : language)
    }

    private func isClosingFence(
        _ line: String,
        fence: (character: Character, count: Int, language: String?)
    ) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.prefix(while: { $0 == fence.character }).count >= fence.count
            && trimmed.allSatisfy { $0 == fence.character }
    }
}

private struct InstructionSourcesView: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Harness 在本轮同步的项目规则")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Rectangle()
                        .fill(RemoteTheme.hairline)
                        .frame(height: 0.5)
                        .padding(.leading, 38)
                }
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Image(systemName: "doc.text")
                        .font(.caption)
                        .foregroundStyle(RemoteTheme.success)
                        .frame(width: 16)
                    Text(row.path)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.action)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
        .background(RemoteTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(RemoteTheme.hairline) }
    }

    private struct Row {
        let path: String
        let action: String
    }

    private var rows: [Row] {
        content.split(separator: "\n", omittingEmptySubsequences: true).map { line in
            let values = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            return Row(
                path: values.first.map(String.init) ?? String(line),
                action: values.count > 1 ? String(values[1]) : ""
            )
        }
    }
}

private struct RemoteGoalStatusDock: View {
    let goal: RemoteGoalState
    let onOpen: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "target")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tone)
                    .frame(width: 28, height: 28)
                    .background(tone.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(phaseTitle)
                            .font(.caption.weight(.semibold))
                        Text("\(goal.roundsStarted)/\(goal.maxRounds) 轮")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(RemotePressableRowButtonStyle(cornerRadius: 12))
        .background(RemoteTheme.mutedSurface, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(RemoteTheme.hairline, lineWidth: 1)
        }
        .accessibilityLabel(phaseTitle)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("查看 Goal 详情")
    }

    private var summary: String {
        if goal.phase == .blocked,
           let reason = goal.blockedReasonMessage,
           !reason.isEmpty {
            return reason
        }
        return goal.objective
    }

    private var accessibilityValue: String {
        if goal.phase == .blocked,
           let reason = goal.blockedReasonMessage,
           !reason.isEmpty {
            return "\(goal.objective)，受阻原因：\(reason)，\(goal.roundsStarted) / \(goal.maxRounds) 轮"
        }
        return "\(goal.objective)，\(goal.roundsStarted) / \(goal.maxRounds) 轮"
    }

    private var phaseTitle: String {
        switch goal.phase {
        case .active: "进行中的 Goal"
        case .paused: "已暂停的 Goal"
        case .blocked: "受阻的 Goal"
        case .complete: "已完成的 Goal"
        }
    }

    private var tone: Color {
        switch goal.phase {
        case .active: RemoteTheme.accent
        case .paused, .blocked: RemoteTheme.warning
        case .complete: RemoteTheme.success
        }
    }
}

private struct RemotePlanStatusLabel: View {
    let plan: RemotePlanState

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "map")
                .font(.system(size: 10, weight: .semibold))
            Text(plan.pending ? "Plan · 待生效" : "Plan")
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(RemoteTheme.warning)
        .padding(.horizontal, 9)
        .frame(minHeight: 30)
        .background(RemoteTheme.warning.opacity(0.10), in: Capsule())
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(plan.pending ? "计划模式等待生效" : "计划模式已开启")
    }
}

private struct QueueDockView: View {
    let queue: [RemoteQueuedMessage]
    let isRunning: Bool
    let onAction: (RemoteQueuedMessage, RemoteQueueAction) -> Void

    @State private var expanded = false
    @State private var editingItem: RemoteQueuedMessage?
    @State private var editText = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if queued.count > 1 {
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 1)) {
                        expanded.toggle()
                    }
                } label: {
                    queueHeader
                }
                .buttonStyle(RemotePressableRowButtonStyle(cornerRadius: 10))
                .accessibilityHint(expanded ? "收起排队消息" : "展开排队消息")
            } else {
                queueHeader
                    .accessibilityElement(children: .combine)
            }

            if expanded || queued.count == 1 {
                Rectangle()
                    .fill(RemoteTheme.hairline)
                    .frame(height: 0.5)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(queued.enumerated()), id: \.element.id) { index, item in
                            HStack(spacing: 10) {
                                Image(systemName: "text.bubble")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(item.preview)
                                    .font(.caption)
                                    .lineLimit(2)
                                Spacer()
                                Menu {
                                    if isRunning {
                                        Button("插话发送", systemImage: "arrow.triangle.branch") {
                                            onAction(item, .steer)
                                        }
                                    }
                                    if let text = item.text, item.attachmentCount == 0 {
                                        Button("编辑", systemImage: "pencil") {
                                            editText = text
                                            editingItem = item
                                        }
                                    }
                                    Button("删除", systemImage: "trash", role: .destructive) {
                                        onAction(item, .remove)
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.caption.weight(.bold))
                                        .frame(width: 44, height: 44)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .frame(minHeight: 44)

                            if index < queued.count - 1 {
                                Rectangle()
                                    .fill(RemoteTheme.hairline)
                                    .frame(height: 0.5)
                                    .padding(.leading, 34)
                            }
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
        .background(RemoteTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(RemoteTheme.hairline) }
        .sheet(item: $editingItem) { item in
            VStack(spacing: 0) {
                RemoteSheetHeader(
                    title: "编辑等待消息",
                    subtitle: "保存后会更新电脑上的排队内容"
                ) {
                    Button("保存") {
                        let value = editText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !value.isEmpty { onAction(item, .edit(value)) }
                        editingItem = nil
                    }
                    .buttonStyle(RemoteActionButtonStyle(kind: .primary, fillsWidth: false, compact: true))
                    .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                TextEditor(text: $editText)
                    .scrollContentBackground(.hidden)
                    .padding(13)
                    .background(RemoteTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(RemoteTheme.hairline, lineWidth: 1)
                    }
                    .padding(16)
            }
            .background(RemoteTheme.canvas.ignoresSafeArea())
            .presentationDetents([.medium])
        }
    }

    private var queued: [RemoteQueuedMessage] {
        queue.filter { $0.placement == .queued }
    }

    private var queueHeader: some View {
        HStack {
            Label("排队 · \(queued.count)", systemImage: "tray.full")
                .font(.caption.weight(.semibold))
            Spacer()
            if queued.count > 1 {
                Image(systemName: expanded ? "chevron.down" : "chevron.up")
                    .font(.caption.weight(.bold))
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

private struct ConversationBottomOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = .greatestFiniteMagnitude

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ConversationVisibleAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(
        value: inout [String: CGRect],
        nextValue: () -> [String: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct InteractionCard: View {
    let interaction: RemoteInteraction
    let isResponding: Bool
    let onRespond: (RemoteInteractionDecision) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var selected: [String: Set<String>] = [:]
    @State private var custom: [String: String] = [:]

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "exclamationmark.bubble.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(RemoteTheme.warning)
                    .frame(width: 32, height: 32)
                    .background(RemoteTheme.warning.opacity(0.11), in: RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 2) {
                    Text("需要你确认")
                        .font(.subheadline.weight(.semibold))
                    Text("Harness 已暂停，等待你的选择")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Rectangle()
                .fill(RemoteTheme.hairline)
                .frame(height: 0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch interaction.kind {
                    case .approval(let toolName, let reason):
                        VStack(alignment: .leading, spacing: 8) {
                            RemoteStatusPill(text: toolName, color: RemoteTheme.tool, icon: "wrench.and.screwdriver")
                            Text(reason ?? "Harness 请求在电脑上执行这项操作。")
                                .font(.body)
                                .lineSpacing(3)
                        }
                    case .questions(let questions):
                        ForEach(Array(questions.enumerated()), id: \.element.id) { index, question in
                            questionView(question)
                            if index < questions.count - 1 {
                                Rectangle()
                                    .fill(RemoteTheme.hairline)
                                    .frame(height: 0.5)
                            }
                        }
                    }
                }
                .padding(14)
            }
            .frame(maxHeight: verticalSizeClass == .compact
                   ? 148
                   : (dynamicTypeSize.isAccessibilitySize ? 238 : 318))

            Rectangle()
                .fill(RemoteTheme.hairline)
                .frame(height: 0.5)

            interactionActions
                .padding(12)
                .background(RemoteTheme.raisedSurface.opacity(0.62))
        }
        .background(RemoteTheme.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(RemoteTheme.warning.opacity(0.28), lineWidth: 1)
        }
        .shadow(color: RemoteTheme.shadow.opacity(0.55), radius: 10, y: 4)
        .disabled(isResponding)
        .overlay {
            if isResponding {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(reduceTransparency ? RemoteTheme.surface : RemoteTheme.surface.opacity(0.82))
                    VStack(spacing: 9) {
                        ProgressView()
                        Text("正在提交…")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func questionView(_ question: RemoteQuestion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let header = question.header {
                Text(header)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(RemoteTheme.warning)
            }
            Text(question.question)
                .font(.body.weight(.semibold))
                .lineSpacing(2)
            if let detail = question.detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(question.options.enumerated()), id: \.element.id) { index, option in
                    Button {
                        toggle(option.label, for: question)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: isSelected(option.label, for: question)
                                  ? (question.allowsMultipleSelection ? "checkmark.square.fill" : "checkmark.circle.fill")
                                  : (question.allowsMultipleSelection ? "square" : "circle"))
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(
                                    isSelected(option.label, for: question)
                                        ? RemoteTheme.accent
                                        : Color.secondary
                                )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.label).font(.subheadline.weight(.semibold))
                                if let description = option.description {
                                    Text(description).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .frame(minHeight: 50)
                        .background(
                            isSelected(option.label, for: question)
                                ? RemoteTheme.accent.opacity(0.10)
                                : Color.clear
                        )
                    }
                    .buttonStyle(RemotePressableRowButtonStyle(cornerRadius: 10))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(optionAccessibilityLabel(option))
                    .accessibilityValue(
                        isSelected(option.label, for: question) ? "已选择" : "未选择"
                    )
                    .accessibilityHint(
                        question.allowsMultipleSelection
                            ? "可多选，双击切换"
                            : "单选，双击选择"
                    )
                    .accessibilityAddTraits(
                        isSelected(option.label, for: question) ? .isSelected : []
                    )

                    if index < question.options.count - 1 {
                        Rectangle()
                            .fill(RemoteTheme.hairline)
                            .frame(height: 0.5)
                            .padding(.leading, 40)
                    }
                }
            }
            .background(RemoteTheme.raisedSurface.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(RemoteTheme.hairline, lineWidth: 1)
            }

            TextField("其他回答（可选）", text: customBinding(for: question), axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .remoteFieldSurface()
                .accessibilityLabel("\(question.header ?? question.question)的其他回答")
        }
    }

    @ViewBuilder
    private var interactionActions: some View {
        switch interaction.kind {
        case .approval:
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    Button("仅允许本次") { onRespond(.allowOnce) }
                        .buttonStyle(RemoteActionButtonStyle(kind: .primary, compact: true))
                    Button("拒绝") { onRespond(.reject) }
                        .buttonStyle(RemoteActionButtonStyle(kind: .danger, compact: true))
                }
            } else {
                HStack(spacing: 10) {
                    Button("拒绝") { onRespond(.reject) }
                        .buttonStyle(RemoteActionButtonStyle(kind: .danger, compact: true))
                    Button("仅允许本次") { onRespond(.allowOnce) }
                        .buttonStyle(RemoteActionButtonStyle(kind: .primary, compact: true))
                }
            }
        case .questions(let questions):
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    Button("确认选择") { onRespond(.answer(answers(for: questions))) }
                        .buttonStyle(RemoteActionButtonStyle(kind: .primary, compact: true))
                        .disabled(!questions.allSatisfy(isAnswered))
                    Button("暂不处理") { onRespond(.cancelQuestions) }
                        .buttonStyle(RemoteActionButtonStyle(kind: .ghost, compact: true))
                }
            } else {
                HStack(spacing: 10) {
                    Button("暂不处理") { onRespond(.cancelQuestions) }
                        .buttonStyle(RemoteActionButtonStyle(kind: .ghost, compact: true))
                    Button("确认选择") { onRespond(.answer(answers(for: questions))) }
                        .buttonStyle(RemoteActionButtonStyle(kind: .primary, compact: true))
                        .disabled(!questions.allSatisfy(isAnswered))
                }
            }
        }
    }

    private func toggle(_ label: String, for question: RemoteQuestion) {
        UISelectionFeedbackGenerator().selectionChanged()
        if question.allowsMultipleSelection {
            var values = selected[question.id, default: []]
            if values.contains(label) { values.remove(label) } else { values.insert(label) }
            selected[question.id] = values
        } else {
            selected[question.id] = [label]
            custom[question.id] = ""
        }
    }

    private func isSelected(_ label: String, for question: RemoteQuestion) -> Bool {
        selected[question.id, default: []].contains(label)
    }

    private func optionAccessibilityLabel(_ option: RemoteQuestion.Option) -> String {
        guard let description = option.description, !description.isEmpty else {
            return option.label
        }
        return "\(option.label)，\(description)"
    }

    private func customBinding(for question: RemoteQuestion) -> Binding<String> {
        Binding(
            get: { custom[question.id, default: ""] },
            set: { value in
                custom[question.id] = value
                if !question.allowsMultipleSelection,
                   !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    selected[question.id] = []
                }
            }
        )
    }

    private func isAnswered(_ question: RemoteQuestion) -> Bool {
        !selected[question.id, default: []].isEmpty
            || !custom[question.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func answers(for questions: [RemoteQuestion]) -> [RemoteQuestionAnswer] {
        questions.map { question in
            let customText = custom[question.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            return RemoteQuestionAnswer(
                questionID: question.id,
                selected: Array(selected[question.id, default: []]).sorted(),
                custom: customText.isEmpty ? nil : customText
            )
        }
    }
}
