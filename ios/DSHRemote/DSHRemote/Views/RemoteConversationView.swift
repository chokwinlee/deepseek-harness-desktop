import SwiftUI

struct RemoteConversationView: View {
    @StateObject private var viewModel: RemoteConversationViewModel
    @State private var draft = ""

    init(client: any HarnessRemoteClient, session: RemoteSessionSummary) {
        _viewModel = StateObject(wrappedValue: RemoteConversationViewModel(client: client, session: session))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    statusHeader

                    if viewModel.isLoading && viewModel.items.isEmpty {
                        ProgressView("正在同步任务…")
                            .padding(.top, 54)
                    } else if viewModel.items.isEmpty {
                        ContentUnavailableView(
                            "开始一项任务",
                            systemImage: "text.bubble",
                            description: Text("输入你的目标，Harness 会在电脑上的当前项目中执行。")
                        )
                        .padding(.top, 38)
                    } else {
                        ForEach(viewModel.items) { item in
                            ConversationItemView(item: item)
                                .id(item.id)
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
                    }

                    Color.clear.frame(height: 1).id("conversation-bottom")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.items.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("conversation-bottom", anchor: .bottom)
                }
            }
            .onChange(of: viewModel.interaction?.id) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("conversation-bottom", anchor: .bottom)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .navigationTitle(viewModel.session.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.monitor() }
        .alert("连接出现问题", isPresented: errorBinding) {
            Button("好", role: .cancel) { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage ?? "未知错误")
        }
    }

    private var statusHeader: some View {
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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.background, in: RoundedRectangle(cornerRadius: 13))
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if viewModel.session.running {
                HStack {
                    Label("发送内容会补充到当前步骤", systemImage: "arrow.triangle.branch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    Task {
                        if await viewModel.send(outgoing) { draft = "" }
                    }
                } label: {
                    Image(systemName: viewModel.session.running ? "arrow.trianglehead.branch" : "arrow.up")
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

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.dismissError() } }
        )
    }
}

private struct ConversationItemView: View {
    let item: RemoteConversationItem

    var body: some View {
        switch item.kind {
        case .user:
            HStack {
                Spacer(minLength: 44)
                VStack(alignment: .trailing, spacing: 5) {
                    if let title = item.title {
                        Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    Text(item.text)
                        .textSelection(.enabled)
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
                    Text(item.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if item.isStreaming {
                        HStack(spacing: 5) {
                            ProgressView().controlSize(.mini)
                            Text("正在生成")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .background(.background, in: RoundedRectangle(cornerRadius: 17))
            }
        case .tool:
            HStack(spacing: 11) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title ?? "电脑操作")
                        .font(.subheadline.weight(.semibold))
                    Text(item.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .padding(12)
            .background(.background, in: RoundedRectangle(cornerRadius: 15))
        case .status:
            Text(item.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color(.tertiarySystemFill), in: Capsule())
        }
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
