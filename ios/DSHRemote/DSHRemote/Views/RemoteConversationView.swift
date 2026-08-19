import SwiftUI
import UIKit

private enum DSHRemoteTheme {
    static let accent = Color(red: 0.40, green: 0.62, blue: 1.00)
    static let thinking = Color(red: 0.55, green: 0.49, blue: 0.96)
    static let tool = Color(red: 0.92, green: 0.55, blue: 0.25)

    static let canvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.082, green: 0.082, blue: 0.090, alpha: 1)
            : UIColor(red: 0.973, green: 0.973, blue: 0.978, alpha: 1)
    })

    static let surface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.137, green: 0.137, blue: 0.141, alpha: 1)
            : UIColor.white
    })

    static let mutedSurface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.173, green: 0.173, blue: 0.180, alpha: 1)
            : UIColor(red: 0.925, green: 0.925, blue: 0.937, alpha: 1)
    })

    static let codeSurface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.095, green: 0.095, blue: 0.102, alpha: 1)
            : UIColor(red: 0.94, green: 0.94, blue: 0.95, alpha: 1)
    })

    static let hairline = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.10)
            : UIColor.black.withAlphaComponent(0.08)
    })
}

struct RemoteConversationView: View {
    private enum BusyDelivery {
        case queue
        case steer
    }

    private enum ViewMode: String, CaseIterable {
        case conversation = "Chat"
        case trajectory = "Trajectory"
    }

    @StateObject private var viewModel: RemoteConversationViewModel
    @State private var draft = ""
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
    @FocusState private var composerFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(client: any HarnessRemoteClient, session: RemoteSessionSummary) {
        _viewModel = StateObject(wrappedValue: RemoteConversationViewModel(client: client, session: session))
    }

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { viewport in
                ScrollView {
                    LazyVStack(spacing: viewMode == .conversation ? 16 : 0) {
                        if viewModel.hasMoreHistory {
                            Button {
                                Task { await viewModel.loadOlderHistory() }
                            } label: {
                                if viewModel.isLoadingOlder {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label("加载更早记录", systemImage: "clock.arrow.circlepath")
                                }
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(DSHRemoteTheme.accent)
                            .buttonStyle(.plain)
                            .padding(.vertical, 8)
                            .disabled(viewModel.isLoadingOlder)
                        }

                        if viewModel.isLoading && viewModel.items.isEmpty {
                            ProgressView("正在同步任务…")
                                .padding(.top, 54)
                        } else if viewMode == .conversation && viewModel.items.isEmpty {
                            ContentUnavailableView(
                                "开始一项任务",
                                systemImage: "text.bubble",
                                description: Text("输入你的目标，Harness 会在电脑上的当前项目中执行。")
                            )
                            .padding(.top, 38)
                        } else if viewMode == .conversation {
                            ForEach(viewModel.items) { item in
                                ConversationItemView(item: item) {
                                    selectedDetail = item
                                }
                                .id(item.id)
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
                    .opacity(contentIsPositioned ? 1 : 0)
                }
                .coordinateSpace(name: "conversation-scroll")
                .scrollDismissesKeyboard(.interactively)
                .onPreferenceChange(ConversationBottomOffsetKey.self) { bottom in
                    isNearBottom = bottom <= viewport.size.height + 140
                    if isNearBottom { unseenUpdates = 0 }
                }
                .overlay(alignment: .bottomTrailing) {
                    if unseenUpdates > 0 {
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo("conversation-bottom", anchor: .bottom)
                            }
                            unseenUpdates = 0
                        } label: {
                            Label("\(unseenUpdates) 条更新", systemImage: "arrow.down")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .foregroundStyle(.primary)
                                .background(DSHRemoteTheme.surface, in: Capsule())
                                .overlay { Capsule().stroke(DSHRemoteTheme.hairline) }
                                .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
                        }
                        .buttonStyle(.plain)
                        .padding(14)
                    }
                }
                .onChange(of: viewModel.hasLoadedInitialSnapshot) { _, loaded in
                    guard loaded, !didInitialPosition else { return }
                    DispatchQueue.main.async {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            proxy.scrollTo("conversation-bottom", anchor: .bottom)
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
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("conversation-bottom", anchor: .bottom)
                        }
                        shouldFollowNextSend = false
                    } else {
                        unseenUpdates += added
                    }
                }
                .onChange(of: viewModel.isLoadingOlder) { wasLoading, isLoading in
                    if wasLoading && !isLoading { lastItemCount = viewModel.items.count }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    bottomDock(bottomSafeArea: viewport.safeAreaInsets.bottom)
                }
            }
        }
        .background(DSHRemoteTheme.canvas)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                sessionMetaLine
                DSHConversationTabBar(selection: $viewMode)

                if viewMode == .trajectory {
                    trajectorySearch
                }

                if viewMode == .trajectory, viewModel.interaction != nil {
                    Button {
                        viewMode = .conversation
                    } label: {
                        Label("有一项问题等待确认", systemImage: "exclamationmark.bubble.fill")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .foregroundStyle(.orange)
                            .background(Color.orange.opacity(0.08))
                    }
                    .buttonStyle(.plain)
                }
                Rectangle()
                    .fill(DSHRemoteTheme.hairline)
                    .frame(height: 0.5)
            }
            .background(DSHRemoteTheme.canvas.opacity(0.98))
        }
        .navigationTitle(viewModel.session.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DSHRemoteTheme.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { await viewModel.monitor() }
        .onChange(of: viewModel.session.running) { wasRunning, isRunning in
            if !wasRunning && isRunning { busyDelivery = .queue }
        }
        .sheet(item: $selectedDetail) { item in
            ConversationDetailSheet(item: item)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsModelPicker) {
            RemoteModelSelectionSheet(viewModel: viewModel)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert("连接出现问题", isPresented: errorBinding) {
            Button("好", role: .cancel) { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage ?? "未知错误")
        }
    }

    private var contentIsPositioned: Bool {
        !viewModel.hasLoadedInitialSnapshot || viewModel.items.isEmpty || didInitialPosition
    }

    private func bottomDock(bottomSafeArea: CGFloat) -> some View {
        VStack(spacing: 8) {
            if viewModel.queue.contains(where: { $0.placement == .queued }) {
                QueueDockView(queue: viewModel.queue, isRunning: viewModel.session.running) { item, action in
                    Task { await viewModel.updateQueue(item, action: action) }
                }
            }
            if let interaction = viewModel.interaction {
                InteractionCard(
                    interaction: interaction,
                    isResponding: viewModel.isResponding,
                    onRespond: { decision in
                        Task { await viewModel.respond(decision) }
                    }
                )
                .id(interaction.id)
            } else {
                composer
            }
        }
        .padding(.horizontal, 10)
        .padding(
            .bottom,
            dockBottomPadding(bottomSafeArea: bottomSafeArea)
        )
        .background(
            LinearGradient(
                colors: [DSHRemoteTheme.canvas.opacity(0), DSHRemoteTheme.canvas],
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

    private var sessionMetaLine: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(viewModel.session.running ? DSHRemoteTheme.accent : Color.green)
                .frame(width: 7, height: 7)
            Text(viewModel.session.running ? "Running" : "Ready")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(viewModel.session.running ? DSHRemoteTheme.accent : .secondary)
            if let project = viewModel.session.projectName {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(project)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let stats = viewModel.stats, stats.turns > 0 {
                Text("\(stats.turns) turns · \(stats.steps) calls")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 7)
        .padding(.bottom, 3)
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
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(DSHRemoteTheme.mutedSurface, in: RoundedRectangle(cornerRadius: 9))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("告诉 Harness 接下来要做什么", text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .font(.body)
                .focused($composerFocused)
                .disabled(viewModel.interaction != nil || !modelIsRoutable)

            if !modelIsRoutable {
                Label("当前模型不可用，请重新选择", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            composerControls
        }
        .padding(12)
        .background(DSHRemoteTheme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(DSHRemoteTheme.hairline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.10), radius: 12, y: 5)
    }

    @ViewBuilder
    private var composerControls: some View {
        if dynamicTypeSize.isAccessibilitySize && viewModel.session.running {
            VStack(spacing: 2) {
                HStack(spacing: 8) {
                    modelSelector
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    deliverySelector
                    Spacer(minLength: 0)
                    composerActions
                }
            }
        } else {
            HStack(spacing: 7) {
                if viewModel.session.running {
                    deliverySelector
                }
                modelSelector
                Spacer(minLength: 0)
                composerActions
            }
        }
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
            .background(DSHRemoteTheme.mutedSurface, in: Capsule())
            .contentShape(Capsule())
            .frame(minHeight: 44)
        }
        .accessibilityLabel("发送方式")
        .accessibilityValue(busyDelivery == .queue ? "排队发送" : "插话发送")
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
                        .foregroundStyle(.orange)
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
        .buttonStyle(.plain)
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
                                .tint(.red)
                        } else {
                            Image(systemName: "stop.fill")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.red)
                        }
                    }
                    .frame(width: 34, height: 34)
                    .background(Color.red.opacity(0.10), in: Circle())
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isCancelling)
                .accessibilityLabel(viewModel.isCancelling ? "正在停止任务" : "停止任务")
            }

            Button {
                let outgoing = draft
                shouldFollowNextSend = true
                Task {
                    if await viewModel.send(outgoing, steer: busyDelivery == .steer) {
                        draft = ""
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
                .background(DSHRemoteTheme.accent, in: Circle())
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(!canSendDraft)
            .opacity(canSendDraft ? 1 : 0.45)
            .accessibilityLabel(sendAccessibilityLabel)
        }
    }

    private var canSendDraft: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !viewModel.isSending
            && !viewModel.isSelectingModel
            && viewModel.interaction == nil
            && modelIsRoutable
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
                                .fill(selection == mode ? DSHRemoteTheme.accent : Color.clear)
                                .frame(
                                    width: mode == .conversation ? 36 : 70,
                                    height: 2
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == mode ? .isSelected : [])
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
    }

    private func inspectorItem(for record: RemoteTrajectoryRecord) -> RemoteConversationItem {
        let kind: RemoteConversationItem.Kind = switch record.kind {
        case .input: .user
        case .context: .context
        case .request: .status
        case .assistant: .assistant
        case .tool: .tool
        case .lifecycle: .status
        }
        return RemoteConversationItem(
            id: "inspect:\(record.id)", sequence: record.sequence, kind: kind,
            title: record.title, text: record.summary, time: record.time,
            state: record.state, details: record.details,
            metadata: record.duration.map { [durationText($0)] } ?? []
        )
    }

    private func durationText(_ value: TimeInterval) -> String {
        value < 1 ? "\(Int(value * 1_000)) ms" : String(format: "%.1f 秒", value)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.dismissError() } }
        )
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
        NavigationStack {
            List {
                if viewModel.modelDirectory == nil && viewModel.isLoadingModels {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("正在读取电脑上的模型…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let error = viewModel.modelErrorMessage {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("模型操作失败", systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("重新载入") {
                                Task { await viewModel.refreshModels() }
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                        .padding(.vertical, 3)
                    }
                }

                if let directory = viewModel.modelDirectory {
                    if !directory.routable {
                        Section {
                            Label(
                                "当前模型无法路由。选择可用模型后才能继续发送。",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                        }
                    } else if selectedCatalogModel == nil {
                        Section {
                            Label(
                                "当前路由仍可用，但该模型已不在目录中。请选择新的模型。",
                                systemImage: "info.circle"
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                    }

                    Section {
                        Text("选择会在这个会话的下一次请求生效，电脑也会尝试将它保存为 Harness 的默认模型。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(directory.groups) { group in
                        Section(group.name) {
                            ForEach(group.models) { model in
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
                                .buttonStyle(.plain)
                                .disabled(viewModel.isSelectingModel)
                            }
                        }
                    }

                    if !effortOptions.isEmpty {
                        Section("推理强度") {
                            ForEach(effortOptions) { option in
                                Button {
                                    chooseEffort(option.value)
                                } label: {
                                    selectionRow(
                                        title: option.name,
                                        description: option.description,
                                        selected: effectiveEffort == option.value
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(viewModel.isSelectingModel)
                            }
                        }
                    }

                    if directory.groups.allSatisfy({ $0.models.isEmpty }) {
                        Section {
                            ContentUnavailableView(
                                "没有可选择的模型",
                                systemImage: "cpu",
                                description: Text("请先在 Harness Desktop 中配置模型提供方。")
                            )
                        }
                    }

                    if !directory.failures.isEmpty {
                        Section("部分提供方不可用") {
                            ForEach(directory.failures) { failure in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(failure.name)
                                        .font(.subheadline.weight(.medium))
                                    Text(failure.message)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }

                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("选择模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isLoadingModels || viewModel.isSelectingModel {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel(
                                viewModel.isSelectingModel ? "正在切换模型" : "正在读取模型"
                            )
                    }
                }
            }
            .refreshable { await viewModel.refreshModels() }
            .task { await viewModel.refreshModels() }
        }
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
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DSHRemoteTheme.accent)
                    .accessibilityHidden(true)
            }
        }
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
                dismiss()
            }
        }
    }
}

private struct ConversationItemView: View {
    let item: RemoteConversationItem
    let onOpenDetails: () -> Void

    @State private var showsReasoning = false
    @State private var showsToolDetails = false
    @State private var copied = false

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
                    MarkdownContent(text: item.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(DSHRemoteTheme.mutedSurface, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 10) {
                if let reasoning = item.reasoning, !reasoning.isEmpty {
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) {
                            showsReasoning.toggle()
                        }
                    } label: {
                        HStack(spacing: 7) {
                            if item.isStreaming {
                                ProgressView()
                                    .controlSize(.mini)
                                    .tint(DSHRemoteTheme.thinking)
                            } else {
                                Image(systemName: "brain.head.profile")
                                    .font(.caption)
                                    .foregroundStyle(DSHRemoteTheme.thinking)
                            }
                            Text(item.isStreaming ? "Thinking" : "Think")
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
                        .frame(minHeight: 36)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

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
                if !item.text.isEmpty {
                    MarkdownContent(text: item.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if item.isStreaming {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Generating")
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
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
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
                Button {
                    guard !item.details.isEmpty else { return }
                    withAnimation(.easeOut(duration: 0.16)) {
                        showsToolDetails.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: toolIcon)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DSHRemoteTheme.tool)
                            .frame(width: 18)
                        Text(item.title ?? "Tool")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if !item.text.isEmpty {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(item.text)
                                .font(.caption)
                                .foregroundStyle(item.state == .failed ? .red : .secondary)
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
                        if !item.details.isEmpty {
                            Image(systemName: showsToolDetails ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, showsToolDetails ? 10 : 0)
                    .padding(.vertical, 8)
                    .frame(minHeight: 40)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showsToolDetails, let detail = item.details.first {
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
                        toolDetailPreview(detail)
                        HStack {
                            if item.details.count > 1 {
                                Text("另有 \(item.details.count - 1) 段详情")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Button("查看详情", action: onOpenDetails)
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
            }
            .background(showsToolDetails ? DSHRemoteTheme.surface : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                if showsToolDetails {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(DSHRemoteTheme.accent.opacity(0.65), lineWidth: 1)
                }
            }
        case .context:
            Button(action: onOpenDetails) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    Text(item.title ?? "Context")
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
                .frame(minHeight: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(item.details.isEmpty)
        case .status:
            Button(action: onOpenDetails) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: stateIcon)
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
                .frame(minHeight: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(item.details.isEmpty)
        }
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
            .background(DSHRemoteTheme.codeSurface, in: RoundedRectangle(cornerRadius: 7))
        }
    }

    private var stateLabel: String {
        switch item.state {
        case .running: "Running"
        case .succeeded: "Done"
        case .failed: "Failed"
        case .stopped: "Stopped"
        case .info: "Info"
        }
    }

    private var stateColor: Color {
        switch item.state {
        case .running: .blue
        case .succeeded: .green
        case .failed: .red
        case .stopped: .orange
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

    var body: some View {
        VStack(spacing: 0) {
            ledgerToolbar
            trajectoryOverview
                .padding(.bottom, 8)
            Rectangle()
                .fill(DSHRemoteTheme.hairline)
                .frame(height: 0.5)

            if filteredRecords.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "暂无轨迹" : "没有匹配结果",
                    systemImage: "point.3.connected.trianglepath.dotted"
                )
                .padding(.vertical, 42)
            } else {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(group.turn.map { "TURN \($0 + 1)" } ?? "CONTEXT")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Text("\(group.records.count) EVENTS")
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.top, 13)
                        .padding(.bottom, 5)

                        VStack(spacing: 0) {
                            ForEach(Array(group.records.enumerated()), id: \.element.id) { index, record in
                                Button {
                                    onOpenDetails(record)
                                } label: {
                                    trajectoryRow(record)
                                }
                                .buttonStyle(.plain)
                                .disabled(record.details.isEmpty)

                                if index < group.records.count - 1 {
                                    Rectangle()
                                        .fill(DSHRemoteTheme.hairline)
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
        HStack(alignment: .center, spacing: 9) {
            Image(systemName: icon(for: record.kind))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 19, height: 19)
                .background(kindColor(record).opacity(0.92), in: RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(record.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let step = record.step {
                        Text("STEP \(step + 1)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(record.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if record.state == .running {
                ProgressView().controlSize(.mini)
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    if let duration = record.duration {
                        Text(durationLabel(duration))
                    }
                    Text("#\(record.sequence)")
                }
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private var ledgerToolbar: some View {
        HStack(spacing: 13) {
            metric("Duration", value: durationLabel(trajectoryDuration))
            metric("Turns", value: "\(Set(filteredRecords.compactMap(\.turn)).count)")
            metric("Calls", value: "\(filteredRecords.filter { $0.kind == .tool }.count)")
            Spacer(minLength: 0)
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
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var trajectoryOverview: some View {
        VStack(spacing: 5) {
            timelineLane("Input", kinds: [.input, .context])
            timelineLane("Model", kinds: [.request, .assistant])
            timelineLane("Tools", kinds: [.tool, .lifecycle])
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(DSHRemoteTheme.surface, in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(DSHRemoteTheme.hairline, lineWidth: 1)
        }
    }

    private func timelineLane(
        _ title: String,
        kinds: [RemoteTrajectoryRecord.Kind]
    ) -> some View {
        HStack(spacing: 7) {
            Text(title)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 34, alignment: .leading)
            GeometryReader { geometry in
                let visible = filteredRecords.filter { kinds.contains($0.kind) }
                let minimum = filteredRecords.map(\.sequence).min() ?? 0
                let maximum = filteredRecords.map(\.sequence).max() ?? minimum
                let span = max(maximum - minimum, 1)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DSHRemoteTheme.hairline)
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

    private struct Group: Identifiable {
        let turn: Int?
        let records: [RemoteTrajectoryRecord]
        var id: String { turn.map { "turn:\($0)" } ?? "context" }
    }

    private var groups: [Group] {
        let grouped = Dictionary(grouping: filteredRecords, by: \.turn)
        return grouped.keys.sorted { lhs, rhs in
            switch (lhs, rhs) {
            case (nil, nil): false
            case (nil, _): true
            case (_, nil): false
            case (.some(let left), .some(let right)): left < right
            }
        }.map { Group(turn: $0, records: grouped[$0, default: []]) }
    }

    private func icon(for kind: RemoteTrajectoryRecord.Kind) -> String {
        switch kind {
        case .input: "text.bubble.fill"
        case .context: "doc.text.magnifyingglass"
        case .request: "arrow.up.forward.app"
        case .assistant: "sparkle"
        case .tool: "wrench.and.screwdriver.fill"
        case .lifecycle: "flag.checkered"
        }
    }

    private func kindColor(_ record: RemoteTrajectoryRecord) -> Color {
        if record.state == .failed { return .red }
        if record.state == .stopped { return .orange }
        return switch record.kind {
        case .input: DSHRemoteTheme.accent
        case .context: .green
        case .request: .cyan
        case .assistant: DSHRemoteTheme.thinking
        case .tool: DSHRemoteTheme.tool
        case .lifecycle: .secondary
        }
    }

    private func durationLabel(_ value: TimeInterval) -> String {
        value < 1 ? "\(Int(value * 1_000)) ms" : String(format: "%.1f s", value)
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
                        inverted ? Color.white.opacity(0.14) : DSHRemoteTheme.codeSurface,
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(inverted ? Color.white.opacity(0.08) : DSHRemoteTheme.hairline)
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
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSectionID: String?
    @State private var copied = false

    init(item: RemoteConversationItem) {
        self.item = item
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
                    if let summaryText {
                        Text(summaryText)
                            .font(.system(size: 13))
                            .lineSpacing(3)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let section = activeSection {
                        VStack(alignment: .leading, spacing: 6) {
                            if let label = inlineSectionLabel(section) {
                                Text(label)
                                    .font(.system(size: 12, weight: .medium))
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
        .background(DSHRemoteTheme.canvas)
    }

    private var detailHeader: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(kindColor)
                .frame(width: 5, height: 5)
            Text(headerTitle)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
            if let metadata = item.metadata.first, !metadata.isEmpty {
                Text(metadata)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button {
                copy(copyPayload)
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 44, height: 42)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(copied ? Color.green : Color.secondary)
            .accessibilityLabel(copied ? "已复制" : copyAccessibilityLabel)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 44, height: 42)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("关闭详情")
        }
        .frame(height: 42)
        .padding(.leading, 12)
        .padding(.trailing, 2)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DSHRemoteTheme.hairline)
                .frame(height: 0.5)
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
                            .font(.system(size: 13))
                            .foregroundStyle(
                                selectedSectionID == section.id
                                    ? DSHRemoteTheme.accent
                                    : Color.secondary
                            )
                            .padding(.horizontal, 9)
                            .frame(height: 34)
                            .overlay(alignment: .bottom) {
                                if selectedSectionID == section.id {
                                    Rectangle()
                                        .fill(DSHRemoteTheme.accent)
                                        .frame(height: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedSectionID == section.id ? .isSelected : [])
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 34)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DSHRemoteTheme.hairline)
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
                    .font(.system(size: 12, design: .monospaced))
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(DSHRemoteTheme.codeSurface, in: RoundedRectangle(cornerRadius: 12))
        case .diff:
            ScrollView(.horizontal, showsIndicators: true) {
                Text(attributedDiff(section.content))
                    .font(.system(size: 12, design: .monospaced))
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(14)
            .background(DSHRemoteTheme.codeSurface, in: RoundedRectangle(cornerRadius: 12))
        case .list:
            if section.id == "instruction-sources" {
                InstructionSourcesView(content: section.content)
            } else {
                Text(section.content)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(DSHRemoteTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                    .overlay { RoundedRectangle(cornerRadius: 10).stroke(DSHRemoteTheme.hairline) }
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
        case .user: DSHRemoteTheme.accent
        case .assistant: DSHRemoteTheme.thinking
        case .tool: DSHRemoteTheme.tool
        case .context: .green
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
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.green.opacity(0.09), in: Capsule())
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
                .font(.system(
                    size: level == 1 ? 16 : (level == 2 ? 15 : 14),
                    weight: .semibold
                ))
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        case .paragraph(let text):
            inlineText(text)
                .font(.system(size: 14))
                .lineSpacing(5)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        case .listItem(let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 12, alignment: .trailing)
                inlineText(text)
                    .font(.system(size: 14))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .quote(let text):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(DSHRemoteTheme.hairline)
                    .frame(width: 2)
                inlineText(text)
                    .font(.system(size: 13))
                    .lineSpacing(4)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .code(let language, let text):
            VStack(alignment: .leading, spacing: 7) {
                if let language, !language.isEmpty {
                    Text(language.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(text)
                        .font(.system(size: 12, design: .monospaced))
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(14)
            .background(DSHRemoteTheme.codeSurface, in: RoundedRectangle(cornerRadius: 12))
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
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Rectangle()
                        .fill(DSHRemoteTheme.hairline)
                        .frame(height: 0.5)
                        .padding(.leading, 38)
                }
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                        .frame(width: 16)
                    Text(row.path)
                        .font(.system(size: 12, design: .monospaced))
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
        .background(DSHRemoteTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(DSHRemoteTheme.hairline) }
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

private struct QueueDockView: View {
    let queue: [RemoteQueuedMessage]
    let isRunning: Bool
    let onAction: (RemoteQueuedMessage, RemoteQueueAction) -> Void

    @State private var expanded = false
    @State private var editingItem: RemoteQueuedMessage?
    @State private var editText = ""

    var body: some View {
        VStack(spacing: 0) {
            Button {
                guard queued.count > 1 else { return }
                withAnimation(.easeOut(duration: 0.18)) { expanded.toggle() }
            } label: {
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
                .frame(height: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded || queued.count == 1 {
                Rectangle()
                    .fill(DSHRemoteTheme.hairline)
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
                                    if let text = item.text {
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
                                        .frame(width: 30, height: 30)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .frame(minHeight: 38)

                            if index < queued.count - 1 {
                                Rectangle()
                                    .fill(DSHRemoteTheme.hairline)
                                    .frame(height: 0.5)
                                    .padding(.leading, 34)
                            }
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
        .background(DSHRemoteTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(DSHRemoteTheme.hairline) }
        .sheet(item: $editingItem) { item in
            NavigationStack {
                TextEditor(text: $editText)
                    .padding(12)
                    .navigationTitle("编辑等待消息")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") { editingItem = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("保存") {
                                let value = editText.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !value.isEmpty { onAction(item, .edit(value)) }
                                editingItem = nil
                            }
                        }
                    }
            }
            .presentationDetents([.medium])
        }
    }

    private var queued: [RemoteQueuedMessage] {
        queue.filter { $0.placement == .queued }
    }
}

private struct ConversationBottomOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = .greatestFiniteMagnitude

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct InteractionCard: View {
    let interaction: RemoteInteraction
    let isResponding: Bool
    let onRespond: (RemoteInteractionDecision) -> Void

    @State private var selected: [String: Set<String>] = [:]
    @State private var custom: [String: String] = [:]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.bubble.fill")
                Text("需要你确认")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("Harness paused")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.orange)
            .padding(.horizontal, 13)
            .frame(height: 38)
            .background(Color.orange.opacity(0.08))

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch interaction.kind {
                    case .approval(let toolName, let reason):
                        Text(reason ?? "Harness 请求在电脑上执行 \(toolName)。")
                            .font(.body)
                        HStack {
                            Button("拒绝", role: .destructive) { onRespond(.reject) }
                                .buttonStyle(.bordered)
                            Spacer()
                            Button("仅允许本次") { onRespond(.allowOnce) }
                                .buttonStyle(.borderedProminent)
                                .tint(DSHRemoteTheme.accent)
                        }
                    case .questions(let questions):
                        ForEach(questions) { question in
                            questionView(question)
                        }
                        HStack {
                            Button("暂不处理", role: .cancel) { onRespond(.cancelQuestions) }
                                .buttonStyle(.bordered)
                            Spacer()
                            Button("确认选择") { onRespond(.answer(answers(for: questions))) }
                                .buttonStyle(.borderedProminent)
                                .tint(DSHRemoteTheme.accent)
                                .disabled(!questions.allSatisfy(isAnswered))
                        }
                    }
                }
                .padding(14)
            }
            .frame(maxHeight: 360)
        }
        .background(DSHRemoteTheme.surface, in: RoundedRectangle(cornerRadius: 17))
        .overlay {
            RoundedRectangle(cornerRadius: 17)
                .stroke(Color.orange.opacity(0.30), lineWidth: 1)
        }
        .disabled(isResponding)
        .overlay {
            if isResponding {
                ProgressView()
                    .padding(14)
                    .background(.regularMaterial, in: Circle())
            }
        }
    }

    @ViewBuilder
    private func questionView(_ question: RemoteQuestion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let header = question.header {
                Text(header.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            Text(question.question).font(.body.weight(.semibold))
            if let detail = question.detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(question.options) { option in
                Button {
                    toggle(option.label, for: question)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: isSelected(option.label, for: question)
                              ? (question.allowsMultipleSelection ? "checkmark.square.fill" : "checkmark.circle.fill")
                              : (question.allowsMultipleSelection ? "square" : "circle"))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.label).font(.subheadline.weight(.semibold))
                            if let description = option.description {
                                Text(description).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(9)
                    .background(
                        isSelected(option.label, for: question)
                            ? DSHRemoteTheme.accent.opacity(0.10)
                            : DSHRemoteTheme.mutedSurface.opacity(0.55),
                        in: RoundedRectangle(cornerRadius: 9)
                    )
                }
                .buttonStyle(.plain)
            }
            TextField("其他回答（可选）", text: customBinding(for: question), axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(DSHRemoteTheme.mutedSurface, in: RoundedRectangle(cornerRadius: 9))
        }
    }

    private func toggle(_ label: String, for question: RemoteQuestion) {
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
