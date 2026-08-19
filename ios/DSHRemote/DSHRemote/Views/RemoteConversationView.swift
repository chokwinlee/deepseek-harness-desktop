import SwiftUI

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
    @State private var viewMode: ViewMode = .conversation
    @State private var trajectoryQuery = ""
    @State private var busyDelivery: BusyDelivery = .queue
    @State private var selectedDetail: RemoteConversationItem?
    @State private var didInitialPosition = false
    @State private var isNearBottom = true
    @State private var unseenUpdates = 0
    @State private var lastItemCount = 0
    @State private var shouldFollowNextSend = false

    init(client: any HarnessRemoteClient, session: RemoteSessionSummary) {
        _viewModel = StateObject(wrappedValue: RemoteConversationViewModel(client: client, session: session))
    }

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { viewport in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        statusHeader

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
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.bordered)
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

                        if viewMode == .conversation, let interaction = viewModel.interaction {
                            InteractionCard(
                                interaction: interaction,
                                isResponding: viewModel.isResponding,
                                onRespond: { decision in
                                    Task { await viewModel.respond(decision) }
                                }
                            )
                            .id(interaction.id)
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
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
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
                                .background(.regularMaterial, in: Capsule())
                                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
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
                .onChange(of: viewModel.interaction?.id) { _, newValue in
                    guard didInitialPosition, newValue != nil else { return }
                    if isNearBottom {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("conversation-bottom", anchor: .bottom)
                        }
                    } else {
                        unseenUpdates += 1
                    }
                }
                .onChange(of: viewMode) { _, _ in
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        proxy.scrollTo("conversation-bottom", anchor: .bottom)
                    }
                    unseenUpdates = 0
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                Picker("查看方式", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                if viewMode == .trajectory {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("搜索轨迹", text: $trajectoryQuery)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !trajectoryQuery.isEmpty {
                            Button {
                                trajectoryQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 11))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                }

                if viewMode == .trajectory, viewModel.interaction != nil {
                    Button {
                        viewMode = .conversation
                    } label: {
                        Label("有一项问题等待确认", systemImage: "exclamationmark.bubble.fill")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .foregroundStyle(.orange)
                            .background(Color.orange.opacity(0.08))
                    }
                    .buttonStyle(.plain)
                }
                Divider()
            }
            .background(.bar)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if !viewModel.queue.isEmpty {
                    QueueDockView(queue: viewModel.queue) { item, action in
                        Task { await viewModel.updateQueue(item, action: action) }
                    }
                }
                composer
            }
        }
        .navigationTitle(viewModel.session.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.monitor() }
        .sheet(item: $selectedDetail) { item in
            ConversationDetailSheet(item: item)
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

    private var statusHeader: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                Circle()
                    .fill(viewModel.session.running ? Color.blue : Color.green)
                    .frame(width: 8, height: 8)
                Text(viewModel.session.running ? "电脑正在执行" : "电脑已就绪")
                    .font(.caption.weight(.semibold))
                Spacer()
                if let project = viewModel.session.projectName {
                    Label(project, systemImage: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if let stats = viewModel.stats, stats.turns > 0 {
                HStack(spacing: 14) {
                    Label("\(stats.turns) 轮", systemImage: "bubble.left.and.bubble.right")
                    Label("\(stats.steps) 步", systemImage: "point.3.connected.trianglepath.dotted")
                    Spacer(minLength: 0)
                    Text("↑\(compactCount(stats.inputTokens))  ↓\(compactCount(stats.outputTokens))")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.background, in: RoundedRectangle(cornerRadius: 13))
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if viewModel.session.running {
                HStack {
                    Menu {
                        Button {
                            busyDelivery = .queue
                        } label: {
                            Label("排队到下一轮", systemImage: busyDelivery == .queue ? "checkmark" : "list.bullet")
                        }
                        Button {
                            busyDelivery = .steer
                        } label: {
                            Label("补充当前步骤", systemImage: busyDelivery == .steer ? "checkmark" : "arrow.triangle.branch")
                        }
                    } label: {
                        Label(
                            busyDelivery == .queue ? "排队到下一轮" : "补充当前步骤",
                            systemImage: busyDelivery == .queue ? "list.bullet" : "arrow.triangle.branch"
                        )
                        .font(.caption.weight(.semibold))
                    }
                    Spacer()
                    Button("停止", role: .destructive) {
                        Task { await viewModel.cancel() }
                    }
                    .font(.caption.weight(.semibold))
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("告诉 Harness 接下来要做什么", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                    .disabled(viewModel.interaction != nil)

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
                    Image(systemName: viewModel.session.running && busyDelivery == .queue ? "list.bullet" : "arrow.up")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(Color.accentColor, in: Circle())
                }
                .disabled(
                    draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || viewModel.isSending
                    || viewModel.interaction != nil
                )
                .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                .accessibilityLabel(viewModel.session.running ? "补充指令" : "发送")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 9)
        .padding(.bottom, 7)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func compactCount(_ count: Int) -> String {
        switch count {
        case 1_000_000...: String(format: "%.1fM", Double(count) / 1_000_000)
        case 1_000...: String(format: "%.1fK", Double(count) / 1_000)
        default: "\(count)"
        }
    }

    private func inspectorItem(for record: RemoteTrajectoryRecord) -> RemoteConversationItem {
        let kind: RemoteConversationItem.Kind = record.kind == .tool ? .tool : .status
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

private struct ConversationItemView: View {
    let item: RemoteConversationItem
    let onOpenDetails: () -> Void

    @State private var showsReasoning = false

    var body: some View {
        switch item.kind {
        case .user:
            HStack {
                Spacer(minLength: 44)
                VStack(alignment: .trailing, spacing: 5) {
                    if let title = item.title {
                        Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    MarkdownContent(text: item.text, inverted: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .foregroundStyle(.white)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 17))
                }
            }
        case .assistant:
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkle")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.indigo)
                    .frame(width: 28, height: 28)
                    .background(Color.indigo.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 6) {
                    if let reasoning = item.reasoning, !reasoning.isEmpty {
                        DisclosureGroup(isExpanded: $showsReasoning) {
                            Text(reasoning)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .padding(.top, 8)
                        } label: {
                            HStack(spacing: 6) {
                                if item.isStreaming { ProgressView().controlSize(.mini) }
                                Text(item.isStreaming ? "正在思考" : "思考过程")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    if !item.text.isEmpty {
                        MarkdownContent(text: item.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if item.isStreaming {
                        HStack(spacing: 5) {
                            ProgressView().controlSize(.mini)
                            Text("正在生成")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    MetadataLine(values: item.metadata)
                }
                .padding(14)
                .background(.background, in: RoundedRectangle(cornerRadius: 17))
            }
        case .tool:
            Button(action: onOpenDetails) {
                HStack(spacing: 11) {
                    Image(systemName: toolIcon)
                        .foregroundStyle(stateColor)
                        .frame(width: 34, height: 34)
                        .background(stateColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title ?? "电脑操作")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text(item.text)
                            .font(.caption)
                            .foregroundStyle(item.state == .failed ? .red : .secondary)
                            .lineLimit(2)
                        MetadataLine(values: item.metadata)
                    }
                    Spacer(minLength: 8)
                    if item.state == .running {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: stateIcon)
                            .foregroundStyle(stateColor)
                    }
                    if !item.details.isEmpty {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(12)
                .background(.background, in: RoundedRectangle(cornerRadius: 15))
            }
            .buttonStyle(.plain)
            .disabled(item.details.isEmpty)
        case .context:
            Button(action: onOpenDetails) {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title ?? "系统上下文")
                            .font(.caption.weight(.semibold))
                        Text(item.text)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        case .status:
            Button(action: onOpenDetails) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: stateIcon)
                        .foregroundStyle(stateColor)
                    VStack(alignment: .leading, spacing: 2) {
                        if let title = item.title {
                            Text(title).font(.caption.weight(.semibold))
                        }
                        Text(item.text)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !item.details.isEmpty {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(stateColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(item.details.isEmpty)
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
        VStack(spacing: 12) {
            if filteredRecords.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "暂无轨迹" : "没有匹配结果",
                    systemImage: "point.3.connected.trianglepath.dotted"
                )
                .padding(.vertical, 42)
            } else {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(group.turn.map { "第 \($0 + 1) 轮" } ?? "会话上下文")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(group.records.count) 项")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 4)

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
                                    Divider().padding(.leading, 46)
                                }
                            }
                        }
                        .background(.background, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.accentColor.opacity(0.35))
                                .frame(width: 3)
                                .padding(.vertical, 9)
                        }
                    }
                }
            }
        }
    }

    private func trajectoryRow(_ record: RemoteTrajectoryRecord) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon(for: record.kind))
                .font(.caption.weight(.semibold))
                .foregroundStyle(color(for: record.state))
                .frame(width: 28, height: 28)
                .background(color(for: record.state).opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
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
                    .lineLimit(2)
                HStack(spacing: 7) {
                    Text("#\(record.sequence)")
                    if let duration = record.duration {
                        Text(durationLabel(duration))
                    }
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 6)
            if record.state == .running {
                ProgressView().controlSize(.mini)
            } else if !record.details.isEmpty {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
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

    private func color(for state: RemoteConversationItem.State) -> Color {
        switch state {
        case .running: .blue
        case .succeeded: .green
        case .failed: .red
        case .stopped: .orange
        case .info: .secondary
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
                            .textSelection(.enabled)
                            .foregroundStyle(inverted ? Color.white : Color.primary)
                    } else {
                        Text(value)
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
                        inverted ? Color.white.opacity(0.14) : Color(.tertiarySystemFill),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
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

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title ?? "执行详情")
                            .font(.title3.weight(.bold))
                        Text(item.text)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        MetadataLine(values: item.metadata)
                    }
                    ForEach(item.details) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            if let title = section.title {
                                Text(title)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                            detailContent(section)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("轨迹详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func detailContent(_ section: RemoteDetailSection) -> some View {
        switch section.kind {
        case .text:
            MarkdownContent(text: section.content)
        case .code(let language):
            VStack(alignment: .leading, spacing: 6) {
                if let language, !language.isEmpty {
                    Text(language.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(codeBody(section.content))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        case .diff:
            ScrollView(.horizontal, showsIndicators: true) {
                Text(attributedDiff(section.content))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        case .list:
            Text(section.content)
                .font(.subheadline)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
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

private struct QueueDockView: View {
    let queue: [RemoteQueuedMessage]
    let onAction: (RemoteQueuedMessage, RemoteQueueAction) -> Void

    @State private var expanded = false
    @State private var editingItem: RemoteQueuedMessage?
    @State private var editText = ""

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack {
                    Label("等待发送 · \(queue.count)", systemImage: "tray.full")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Image(systemName: expanded ? "chevron.down" : "chevron.up")
                        .font(.caption.weight(.bold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Divider()
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(queue) { item in
                            HStack(spacing: 10) {
                                Image(systemName: item.placement == .steering ? "arrow.triangle.branch" : "text.bubble")
                                    .foregroundStyle(.secondary)
                                Text(item.preview)
                                    .font(.caption)
                                    .lineLimit(2)
                                Spacer()
                                if item.placement == .queued {
                                    Menu {
                                        Button("插入当前步骤", systemImage: "arrow.triangle.branch") {
                                            onAction(item, .steer)
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
                                        Image(systemName: "ellipsis.circle")
                                            .font(.title3)
                                    }
                                }
                            }
                            .padding(10)
                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
                .frame(maxHeight: 180)
            }
        }
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
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
        VStack(alignment: .leading, spacing: 14) {
            Label("需要你确认", systemImage: "exclamationmark.bubble.fill")
                .font(.headline)
                .foregroundStyle(.orange)

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
                        .disabled(!questions.allSatisfy(isAnswered))
                }
            }
        }
        .padding(16)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
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
                }
                .buttonStyle(.plain)
            }
            TextField("其他回答（可选）", text: customBinding(for: question.id), axis: .vertical)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func toggle(_ label: String, for question: RemoteQuestion) {
        if question.allowsMultipleSelection {
            var values = selected[question.id, default: []]
            if values.contains(label) { values.remove(label) } else { values.insert(label) }
            selected[question.id] = values
        } else {
            selected[question.id] = [label]
        }
    }

    private func isSelected(_ label: String, for question: RemoteQuestion) -> Bool {
        selected[question.id, default: []].contains(label)
    }

    private func customBinding(for id: String) -> Binding<String> {
        Binding(get: { custom[id, default: ""] }, set: { custom[id] = $0 })
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
