import SwiftUI
import UIKit
import UniformTypeIdentifiers

private enum RemoteProjectsTheme {
    static let accent = Color(red: 0.40, green: 0.62, blue: 1.00)

    static let canvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.082, green: 0.082, blue: 0.090, alpha: 1)
            : UIColor(red: 0.965, green: 0.965, blue: 0.975, alpha: 1)
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

    static let hairline = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.10)
            : UIColor.black.withAlphaComponent(0.08)
    })
}

struct RemoteSessionView: View {
    @StateObject private var viewModel: RemoteHostViewModel
    @State private var expandedProjectIDs: Set<String> = []
    @State private var fullyExpandedProjectIDs: Set<String> = []
    @State private var didChooseInitialExpansion = false
    @State private var didManuallyChangeExpansion = false
    @State private var previousProjectPathsByID: [String: String] = [:]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(host: RemoteHost) {
        let client = LiveHarnessRemoteClient(
            baseURL: host.baseURL,
            displayName: host.name,
            accessToken: host.accessToken
        )
        _viewModel = StateObject(wrappedValue: RemoteHostViewModel(client: client))
    }

    init(demoClient: DemoHarnessRemoteClient = DemoHarnessRemoteClient()) {
        _viewModel = StateObject(wrappedValue: RemoteHostViewModel(client: demoClient))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if viewModel.isLoading && viewModel.lastUpdated == nil {
                    ProjectsLoadingView()
                } else if let error = viewModel.errorMessage, viewModel.lastUpdated == nil {
                    ProjectsConnectionError(message: error) {
                        Task { await viewModel.refresh() }
                    }
                } else {
                    if let error = viewModel.errorMessage {
                        StaleProjectsBanner(message: error) {
                            Task { await viewModel.refresh() }
                        }
                    }

                    if projectGroups.isEmpty, viewModel.isLoadingProjects {
                        projectCatalogLoadingView
                    } else if projectGroups.isEmpty, viewModel.usesDirectoryProjectFallback {
                        projectCatalogUnavailableView
                    } else if projectGroups.isEmpty {
                        emptyProjectsView
                    } else {
                        projectsHeading

                        if viewModel.usesDirectoryProjectFallback {
                            Label("项目分组暂不可用，当前按目录显示", systemImage: "folder.badge.questionmark")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 2)
                        } else if viewModel.workspaceSnapshot == nil, viewModel.isLoadingProjects {
                            HStack(spacing: 7) {
                                ProgressView()
                                    .controlSize(.mini)
                                Text("正在读取电脑上的项目分组…")
                            }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 2)
                        }

                        ForEach(projectGroups) { project in
                            RemoteProjectCard(
                                project: project,
                                client: viewModel.client,
                                isExpanded: expandedProjectIDs.contains(project.id),
                                showsAllSessions: fullyExpandedProjectIDs.contains(project.id),
                                toggleExpanded: { toggleProject(project.id) },
                                toggleAllSessions: { toggleAllSessions(project.id) }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .background(RemoteProjectsTheme.canvas.ignoresSafeArea())
        .navigationTitle(viewModel.client.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.monitor() }
        .onChange(of: projectExpansionKey, initial: true) { _, _ in
            synchronizeProjectExpansion()
        }
    }

    @ViewBuilder
    private var projectsHeading: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                Text("项目")
                    .font(.title2.weight(.bold))
                Text(projectSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)
            .accessibilityElement(children: .combine)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("项目")
                    .font(.title2.weight(.bold))

                Spacer(minLength: 8)

                Text(projectSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 2)
            .accessibilityElement(children: .combine)
        }
    }

    private var emptyProjectsView: some View {
        ContentUnavailableView(
            "还没有项目",
            systemImage: "folder",
            description: Text("先在 Harness Desktop 中添加项目或打开一个目录。")
        )
        .frame(maxWidth: .infinity)
        .padding(.top, 72)
    }

    private var projectCatalogLoadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("正在读取电脑上的项目…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 92)
    }

    private var projectCatalogUnavailableView: some View {
        ContentUnavailableView(
            "暂时无法读取项目",
            systemImage: "folder.badge.questionmark",
            description: Text("会话服务已响应，但项目分组暂不可用。下拉即可重试。")
        )
        .frame(maxWidth: .infinity)
        .padding(.top, 72)
    }

    private var projectSummary: String {
        let sessionCount = projectGroups.reduce(0) { $0 + $1.sessions.count }
        let runningCount = projectGroups.reduce(0) { $0 + $1.runningCount }
        if runningCount > 0 {
            return "\(projectGroups.count) 个项目 · \(runningCount) 个运行中"
        }
        return "\(projectGroups.count) 个项目 · \(sessionCount) 个会话"
    }

    private var projectGroups: [RemoteProjectGroup] {
        if let snapshot = viewModel.workspaceSnapshot {
            return authoritativeGroups(snapshot: snapshot, sessions: viewModel.sessions)
        }
        return directoryFallbackGroups(sessions: viewModel.sessions.filter {
            !viewModel.archivedSessionIDs.contains($0.id)
        })
    }

    private var projectExpansionKey: [String] {
        projectGroups.map { "\($0.id):\($0.sessions.count):\($0.runningCount)" }
    }

    private func authoritativeGroups(
        snapshot: RemoteWorkspaceSnapshot,
        sessions: [RemoteSessionSummary]
    ) -> [RemoteProjectGroup] {
        let sessionsByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        var claimedSessionIDs = Set<String>()
        var groups: [RemoteProjectGroup] = []

        for workspace in snapshot.items {
            let members = workspace.sessionIDs.compactMap { sessionID -> RemoteSessionSummary? in
                guard !snapshot.archivedSessionIDs.contains(sessionID),
                      claimedSessionIDs.insert(sessionID).inserted else { return nil }
                return sessionsByID[sessionID]
            }
            groups.append(RemoteProjectGroup(
                id: "workspace:\(workspace.id)",
                title: displayProjectTitle(workspace.title, path: workspace.path),
                path: workspace.path,
                sessions: members
            ))
        }

        let ungrouped = sessions.filter {
            !snapshot.archivedSessionIDs.contains($0.id) && !claimedSessionIDs.contains($0.id)
        }
        if !ungrouped.isEmpty {
            groups.append(RemoteProjectGroup(
                id: "workspace:__ungrouped__",
                title: "未分组",
                path: nil,
                sessions: ungrouped
            ))
        }
        return groups
    }

    private func directoryFallbackGroups(sessions: [RemoteSessionSummary]) -> [RemoteProjectGroup] {
        var groupOrder: [String] = []
        var grouped: [String: [RemoteSessionSummary]] = [:]
        var metadata: [String: (title: String, path: String?)] = [:]

        for session in sessions {
            let path = nonBlank(session.projectPath)
            let id = path.map { "directory:\(fallbackPathIdentity($0))" } ?? "directory:__ungrouped__"
            if grouped[id] == nil {
                groupOrder.append(id)
                metadata[id] = (
                    path == nil ? "未分组" : (session.projectName ?? path.map(crossPlatformBasename) ?? "未命名项目"),
                    path
                )
            }
            grouped[id, default: []].append(session)
        }

        return groupOrder.compactMap { id in
            guard let details = metadata[id] else { return nil }
            return RemoteProjectGroup(
                id: id,
                title: details.title,
                path: details.path,
                sessions: grouped[id] ?? []
            )
        }
    }

    private func synchronizeProjectExpansion() {
        let groups = projectGroups
        guard !groups.isEmpty else { return }
        let currentIDs = Set(groups.map(\.id))
        let currentPathsByID = Dictionary(uniqueKeysWithValues: groups.map {
            ($0.id, projectPathIdentity($0))
        })

        if didManuallyChangeExpansion,
           !expandedProjectIDs.isSubset(of: currentIDs) {
            let expandedPaths = Set(expandedProjectIDs.compactMap { previousProjectPathsByID[$0] })
            let stableIDs = expandedProjectIDs.intersection(currentIDs)
            let migratedIDs = Set(groups.compactMap { group in
                expandedPaths.contains(projectPathIdentity(group)) ? group.id : nil
            })
            expandedProjectIDs = stableIDs.union(migratedIDs)
        }

        if !fullyExpandedProjectIDs.isSubset(of: currentIDs) {
            let expandedPaths = Set(fullyExpandedProjectIDs.compactMap { previousProjectPathsByID[$0] })
            let stableIDs = fullyExpandedProjectIDs.intersection(currentIDs)
            let migratedIDs = Set(groups.compactMap { group in
                expandedPaths.contains(projectPathIdentity(group)) ? group.id : nil
            })
            fullyExpandedProjectIDs = stableIDs.union(migratedIDs)
        }

        let needsInitialChoice = !didChooseInitialExpansion
            || (!didManuallyChangeExpansion && expandedProjectIDs.isDisjoint(with: currentIDs))
        if needsInitialChoice {
            didChooseInitialExpansion = true
            expandedProjectIDs = Set(groups.filter { $0.runningCount > 0 }.map(\.id))
            expandedProjectIDs.insert(groups[0].id)
        }
        previousProjectPathsByID = currentPathsByID
    }

    private func toggleProject(_ id: String) {
        didManuallyChangeExpansion = true
        withAnimation(.snappy(duration: 0.22)) {
            if expandedProjectIDs.contains(id) {
                expandedProjectIDs.remove(id)
            } else {
                expandedProjectIDs.insert(id)
            }
        }
    }

    private func toggleAllSessions(_ id: String) {
        withAnimation(.snappy(duration: 0.22)) {
            if fullyExpandedProjectIDs.contains(id) {
                fullyExpandedProjectIDs.remove(id)
            } else {
                fullyExpandedProjectIDs.insert(id)
            }
        }
    }

    private func displayProjectTitle(_ title: String, path: String) -> String {
        normalized(title) ?? normalized(path).map(crossPlatformBasename) ?? "未命名项目"
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func nonBlank(_ value: String?) -> String? {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    private func fallbackPathIdentity(_ path: String) -> String {
        let thirdCharacter = path.count >= 3
            ? path[path.index(path.startIndex, offsetBy: 2)]
            : nil
        let isDrivePath = path.count >= 3
            && path[path.index(after: path.startIndex)] == ":"
            && (thirdCharacter == "/" || thirdCharacter == "\\")
        let isUNCPath = path.hasPrefix("\\\\")
        var identity = (isDrivePath || isUNCPath)
            ? path.replacingOccurrences(of: "\\", with: "/")
            : path
        while identity.count > 1 && identity.hasSuffix("/") {
            identity.removeLast()
        }
        if isDrivePath {
            identity = identity.prefix(1).lowercased() + identity.dropFirst()
        }
        return identity
    }

    private func projectPathIdentity(_ group: RemoteProjectGroup) -> String {
        group.path.map(fallbackPathIdentity) ?? "__ungrouped__"
    }

    private func crossPlatformBasename(_ path: String) -> String {
        path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? path
    }
}

private struct RemoteProjectGroup: Identifiable {
    let id: String
    let title: String
    let path: String?
    let sessions: [RemoteSessionSummary]

    var runningCount: Int { sessions.count(where: \.running) }
}

private struct RemoteProjectCard: View {
    private let collapsedSessionLimit = 5

    let project: RemoteProjectGroup
    let client: any HarnessRemoteClient
    let isExpanded: Bool
    let showsAllSessions: Bool
    let toggleExpanded: () -> Void
    let toggleAllSessions: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            Button(action: toggleExpanded) {
                projectHeader
            }
            .buttonStyle(.plain)
            .accessibilityLabel(project.title)
            .accessibilityValue(projectAccessibilityValue)
            .accessibilityHint(isExpanded ? "轻点收起会话" : "轻点展开会话")

            if isExpanded {
                Divider()
                    .overlay(RemoteProjectsTheme.hairline)
                    .padding(.leading, 48)

                if project.sessions.isEmpty {
                    Label("暂无会话", systemImage: "bubble.left")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                } else {
                    ForEach(Array(visibleSessions.enumerated()), id: \.element.id) { index, session in
                        NavigationLink {
                            RemoteConversationView(client: client, session: session)
                        } label: {
                            RemoteProjectSessionRow(session: session)
                        }
                        .buttonStyle(.plain)

                        if index < visibleSessions.count - 1 || hasHiddenSessions || showsAllSessions {
                            Divider()
                                .overlay(RemoteProjectsTheme.hairline)
                                .padding(.leading, 48)
                        }
                    }

                    if hasHiddenSessions || showsAllSessions {
                        Button(action: toggleAllSessions) {
                            HStack(spacing: 6) {
                                Text(showsAllSessions
                                     ? "收起会话"
                                     : "查看其余 \(project.sessions.count - collapsedSessionLimit) 个会话")
                                Image(systemName: showsAllSessions ? "chevron.up" : "chevron.down")
                                    .font(.caption.weight(.semibold))
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(RemoteProjectsTheme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .background(RemoteProjectsTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(RemoteProjectsTheme.hairline, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var projectHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                projectIdentity
                statusBadge
                    .padding(.leading, 56)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 12) {
                projectIdentity
                Spacer(minLength: 8)
                statusBadge
            }
            .padding(16)
            .frame(minHeight: 66)
        }
    }

    private var projectIdentity: some View {
        HStack(spacing: 11) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.tertiary)
                .frame(width: 12)

            Image(systemName: isExpanded ? "folder.fill" : "folder")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(RemoteProjectsTheme.accent)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(project.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)

                if let path = project.path {
                    Text(abbreviatedPath(path))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .contextMenu {
                            Button {
                                UIPasteboard.general.setItems(
                                    [[UTType.plainText.identifier: path]],
                                    options: [.localOnly: true]
                                )
                            } label: {
                                Label("复制完整路径", systemImage: "doc.on.doc")
                            }
                        }
                }
            }
        }
    }

    private var statusBadge: some View {
        Text(project.runningCount > 0
             ? "\(project.runningCount) 个运行中"
             : "\(project.sessions.count) 个会话")
            .font(.caption.weight(.semibold))
            .foregroundStyle(project.runningCount > 0 ? RemoteProjectsTheme.accent : .secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                project.runningCount > 0
                    ? RemoteProjectsTheme.accent.opacity(0.13)
                    : RemoteProjectsTheme.mutedSurface,
                in: Capsule()
            )
            .fixedSize(horizontal: true, vertical: false)
    }

    private var visibleSessions: [RemoteSessionSummary] {
        if showsAllSessions { return project.sessions }
        return Array(project.sessions.prefix(collapsedSessionLimit))
    }

    private var hasHiddenSessions: Bool {
        !showsAllSessions && project.sessions.count > collapsedSessionLimit
    }

    private var projectAccessibilityValue: String {
        let expansion = isExpanded ? "已展开" : "已收起"
        if project.runningCount > 0 {
            return "\(project.sessions.count) 个会话，\(project.runningCount) 个运行中，\(expansion)"
        }
        return "\(project.sessions.count) 个会话，\(expansion)"
    }

    private func abbreviatedPath(_ path: String) -> String {
        let separator = path.contains("\\") ? "\\" : "/"
        let components = path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).map(String.init)
        guard components.count > 2 else { return path }
        return "…\(separator)\(components.suffix(2).joined(separator: separator))"
    }
}

private struct RemoteProjectSessionRow: View {
    let session: RemoteSessionSummary

    var body: some View {
        HStack(spacing: 12) {
            statusIndicator
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 5) {
                Text(session.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if session.running {
                        Text("执行中")
                            .foregroundStyle(RemoteProjectsTheme.accent)
                    }
                    Text(relativeUpdate)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 58)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(session.title)
        .accessibilityValue(session.running ? "执行中，\(relativeUpdate)" : relativeUpdate)
        .accessibilityHint("打开会话")
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if session.running {
            ZStack {
                Circle()
                    .fill(RemoteProjectsTheme.accent.opacity(0.16))
                    .frame(width: 20, height: 20)
                Image(systemName: "waveform")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(RemoteProjectsTheme.accent)
            }
        } else {
            Color.clear
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
        }
    }

    private var relativeUpdate: String {
        let seconds = max(0, Date().timeIntervalSince(session.updatedAt))
        if seconds < 60 { return "刚刚更新" }
        if seconds < 3_600 { return "\(Int(seconds / 60)) 分钟前" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600)) 小时前" }
        if seconds < 604_800 { return "\(Int(seconds / 86_400)) 天前" }
        return session.updatedAt.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct StaleProjectsBanner: View {
    let message: String
    let retry: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    bannerMessage
                    Button("重试", action: retry)
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(RemoteProjectsTheme.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 11) {
                    bannerMessage
                    Spacer(minLength: 8)
                    Button("重试", action: retry)
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(RemoteProjectsTheme.accent)
                }
            }
        }
        .padding(13)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.18), lineWidth: 1)
        }
    }

    private var bannerMessage: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("连接中断 · 显示上次结果")
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
            }
        }
    }
}

private struct ProjectsConnectionError: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("无法连接这台电脑", systemImage: "wifi.exclamationmark")
        } description: {
            VStack(spacing: 6) {
                Text("请确认电脑上的 Harness Desktop 与 Remote 已开启。")
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        } actions: {
            Button("重新连接", action: retry)
                .buttonStyle(.borderedProminent)
                .tint(RemoteProjectsTheme.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 72)
    }
}

private struct ProjectsLoadingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("项目")
                    .font(.title2.weight(.bold))
                Spacer()
                ProgressView()
                    .controlSize(.small)
            }
            .padding(.horizontal, 2)

            ForEach(0..<2, id: \.self) { index in
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "folder")
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 7) {
                            RoundedRectangle(cornerRadius: 3)
                                .frame(width: index == 0 ? 128 : 96, height: 15)
                            RoundedRectangle(cornerRadius: 3)
                                .frame(width: index == 0 ? 190 : 150, height: 10)
                        }
                    }
                    Divider()
                    RoundedRectangle(cornerRadius: 3)
                        .frame(height: 42)
                }
                .foregroundStyle(.secondary.opacity(0.22))
                .padding(16)
                .background(RemoteProjectsTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(RemoteProjectsTheme.hairline, lineWidth: 1)
                }
                .accessibilityHidden(true)
            }

            Text("正在读取电脑上的项目与会话…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }
}
