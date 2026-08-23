package com.chokwinlee.dshremote.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.FolderOff
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.chokwinlee.dshremote.R
import com.chokwinlee.dshremote.ui.components.RemoteCloseButton
import com.chokwinlee.dshremote.ui.components.RemoteEmptyState
import com.chokwinlee.dshremote.ui.components.RemoteErrorState
import com.chokwinlee.dshremote.ui.components.RemoteIconButton
import com.chokwinlee.dshremote.ui.components.RemoteInlineNotice
import com.chokwinlee.dshremote.ui.components.RemoteLoadingState
import com.chokwinlee.dshremote.ui.components.RemoteNoticeTone
import com.chokwinlee.dshremote.ui.components.RemotePageHeader
import com.chokwinlee.dshremote.ui.components.RemoteSectionHeader
import com.chokwinlee.dshremote.ui.components.RemoteStatusPill
import com.chokwinlee.dshremote.ui.components.RemoteSurface
import com.chokwinlee.dshremote.ui.model.ProjectListUiState
import com.chokwinlee.dshremote.ui.model.ProjectUiModel
import com.chokwinlee.dshremote.ui.model.SessionExecutionState
import com.chokwinlee.dshremote.ui.model.SessionUiModel
import com.chokwinlee.dshremote.ui.theme.RemoteDimens
import com.chokwinlee.dshremote.ui.theme.RemoteTheme

private const val InitiallyVisibleSessions = 5

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProjectListScreen(
    state: ProjectListUiState,
    onBack: () -> Unit,
    onRefresh: () -> Unit,
    onCreateSession: (projectId: String) -> Unit,
    onSessionSelected: (sessionId: String) -> Unit,
) {
    val initialExpansionKey = state.projects.firstOrNull()?.id
    var expandedProjectIds by remember(initialExpansionKey) {
        mutableStateOf(
            buildSet {
                state.projects.firstOrNull()?.id?.let(::add)
                state.projects.filter { it.runningCount > 0 }.forEach { add(it.id) }
            },
        )
    }
    var fullyExpandedProjectIds by remember { mutableStateOf(emptySet<String>()) }
    var showNewSessionSheet by rememberSaveable { mutableStateOf(false) }
    val colors = RemoteTheme.colors
    val computerTitle = state.computerName.ifBlank { stringResource(R.string.projects_default_computer) }
    val creatableProjects = state.projects.filter { it.canCreateSession }

    LaunchedEffect(state.projects.map { "${it.id}:${it.sessions.size}:${it.runningCount}" }) {
        expandedProjectIds = expandedProjectIds + state.projects
            .filter { it.runningCount > 0 }
            .map(ProjectUiModel::id)
    }
    LaunchedEffect(state.lastCreatedSessionId) {
        if (state.lastCreatedSessionId != null) showNewSessionSheet = false
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.canvas),
    ) {
        RemotePageHeader(
            title = computerTitle,
            subtitle = stringResource(R.string.projects_screen_subtitle),
            onBack = onBack,
        ) {
            if (state.isRefreshing) {
                androidx.compose.material3.CircularProgressIndicator(
                    modifier = Modifier.size(20.dp),
                    color = colors.accent,
                    strokeWidth = 2.dp,
                )
            } else {
                RemoteIconButton(
                    imageVector = Icons.Default.Refresh,
                    contentDescription = stringResource(R.string.action_refresh),
                    onClick = onRefresh,
                )
            }
            RemoteIconButton(
                imageVector = Icons.Default.Add,
                contentDescription = stringResource(R.string.session_new_action),
                onClick = { showNewSessionSheet = true },
                tint = colors.accent,
                emphasized = true,
                enabled = creatableProjects.isNotEmpty(),
            )
        }

        when {
            state.isLoading && !state.hasLoadedOnce && state.projects.isEmpty() -> {
                RemoteLoadingState(
                    title = stringResource(R.string.projects_loading_title),
                    message = stringResource(R.string.projects_loading_message),
                    modifier = Modifier.weight(1f),
                )
            }

            state.errorMessage != null && !state.hasLoadedOnce && state.projects.isEmpty() -> {
                RemoteErrorState(
                    message = state.errorMessage,
                    onRetry = onRefresh,
                    modifier = Modifier.weight(1f),
                )
            }

            state.projects.isEmpty() && state.isDirectoryFallback -> {
                RemoteEmptyState(
                    title = stringResource(R.string.projects_unavailable_title),
                    message = stringResource(R.string.projects_unavailable_message),
                    icon = Icons.Default.FolderOff,
                    actionText = stringResource(R.string.action_retry),
                    onAction = onRefresh,
                    modifier = Modifier.weight(1f),
                )
            }

            state.projects.isEmpty() -> {
                RemoteEmptyState(
                    title = stringResource(R.string.projects_empty_title),
                    message = stringResource(R.string.projects_empty_message),
                    icon = Icons.Default.Folder,
                    modifier = Modifier.weight(1f),
                )
            }

            else -> {
                ProjectsContent(
                    state = state,
                    expandedProjectIds = expandedProjectIds,
                    fullyExpandedProjectIds = fullyExpandedProjectIds,
                    onToggleProject = { projectId ->
                        expandedProjectIds = if (projectId in expandedProjectIds) {
                            expandedProjectIds - projectId
                        } else {
                            expandedProjectIds + projectId
                        }
                    },
                    onToggleAllSessions = { projectId ->
                        fullyExpandedProjectIds = if (projectId in fullyExpandedProjectIds) {
                            fullyExpandedProjectIds - projectId
                        } else {
                            fullyExpandedProjectIds + projectId
                        }
                    },
                    onSessionSelected = onSessionSelected,
                    onRefresh = onRefresh,
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }

    if (showNewSessionSheet) {
        ModalBottomSheet(
            onDismissRequest = {
                if (state.creatingSessionProjectId == null) showNewSessionSheet = false
            },
            containerColor = colors.canvas,
            dragHandle = null,
        ) {
            NewSessionSheet(
                projects = creatableProjects,
                creatingProjectId = state.creatingSessionProjectId,
                errorMessage = state.createSessionErrorMessage,
                retryProjectId = state.lastCreateSessionProjectId,
                onClose = { showNewSessionSheet = false },
                onCreateSession = onCreateSession,
            )
        }
    }
}

@Composable
private fun ProjectsContent(
    state: ProjectListUiState,
    expandedProjectIds: Set<String>,
    fullyExpandedProjectIds: Set<String>,
    onToggleProject: (String) -> Unit,
    onToggleAllSessions: (String) -> Unit,
    onSessionSelected: (String) -> Unit,
    onRefresh: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val sessionCount = state.projects.sumOf { it.sessions.size }
    val runningCount = state.projects.sumOf { it.runningCount }
    val projectCountText = pluralStringResource(
        R.plurals.project_count,
        state.projects.size,
        state.projects.size,
    )
    val stateCountText = if (runningCount > 0) {
        pluralStringResource(R.plurals.running_count, runningCount, runningCount)
    } else {
        pluralStringResource(R.plurals.session_count, sessionCount, sessionCount)
    }

    LazyColumn(
        modifier = modifier
            .fillMaxWidth()
            .navigationBarsPadding(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(
            start = RemoteDimens.pagePadding,
            top = 12.dp,
            end = RemoteDimens.pagePadding,
            bottom = 24.dp,
        ),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        if (state.errorMessage != null) {
            item {
                RemoteInlineNotice(
                    title = stringResource(R.string.state_showing_saved_results),
                    message = state.errorMessage,
                    tone = RemoteNoticeTone.Warning,
                    actionText = stringResource(R.string.action_retry),
                    onAction = onRefresh,
                )
            }
        }

        item {
            RemoteSectionHeader(
                title = stringResource(R.string.projects_section_title),
                detail = stringResource(
                    R.string.projects_summary,
                    projectCountText,
                    stateCountText,
                ),
            )
        }

        if (state.isDirectoryFallback) {
            item {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .semantics(mergeDescendants = true) {},
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        imageVector = Icons.Default.FolderOff,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(17.dp),
                    )
                    Text(
                        text = stringResource(R.string.projects_directory_fallback),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }

        item {
            RemoteSurface(modifier = Modifier.fillMaxWidth()) {
                Column {
                    state.projects.forEachIndexed { index, project ->
                        ProjectGroup(
                            project = project,
                            isExpanded = project.id in expandedProjectIds,
                            showsAllSessions = project.id in fullyExpandedProjectIds,
                            onToggleProject = { onToggleProject(project.id) },
                            onToggleAllSessions = { onToggleAllSessions(project.id) },
                            onSessionSelected = onSessionSelected,
                        )
                        if (index < state.projects.lastIndex) {
                            Hairline(startPadding = 44.dp)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ProjectGroup(
    project: ProjectUiModel,
    isExpanded: Boolean,
    showsAllSessions: Boolean,
    onToggleProject: () -> Unit,
    onToggleAllSessions: () -> Unit,
    onSessionSelected: (String) -> Unit,
) {
    val visibleSessions = if (showsAllSessions) {
        project.sessions
    } else {
        project.sessions.take(InitiallyVisibleSessions)
    }
    val sessionCountText = pluralStringResource(
        R.plurals.session_count,
        project.sessions.size,
        project.sessions.size,
    )
    val expandState = stringResource(
        if (isExpanded) R.string.project_expanded_state else R.string.project_collapsed_state,
    )

    Column(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 64.dp)
                .clickable(role = Role.Button, onClick = onToggleProject)
                .padding(horizontal = 14.dp, vertical = 10.dp)
                .semantics {
                    role = Role.Button
                    stateDescription = expandState
                },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Icon(
                imageVector = Icons.Default.Folder,
                contentDescription = null,
                tint = RemoteTheme.colors.accent,
                modifier = Modifier.size(20.dp),
            )
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(
                    text = project.title,
                    style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    text = project.path ?: sessionCountText,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    if (project.runningCount > 0) {
                        RemoteStatusPill(
                            text = pluralStringResource(
                                R.plurals.running_count,
                                project.runningCount,
                                project.runningCount,
                            ),
                            color = RemoteTheme.colors.accent,
                        )
                    }
                    Text(
                        text = sessionCountText,
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Icon(
                imageVector = Icons.Default.ExpandMore,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.graphicsLayer { rotationZ = if (isExpanded) 180f else 0f },
            )
        }

        if (isExpanded) {
            Hairline(startPadding = 44.dp)
            if (project.sessions.isEmpty()) {
                Text(
                    text = stringResource(R.string.sessions_empty_message),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(start = 44.dp, top = 14.dp, end = 16.dp, bottom = 16.dp),
                )
            } else {
                visibleSessions.forEachIndexed { index, session ->
                    SessionRow(session = session, onClick = { onSessionSelected(session.id) })
                    if (index < visibleSessions.lastIndex) Hairline(startPadding = 44.dp)
                }
                if (project.sessions.size > InitiallyVisibleSessions) {
                    Hairline(startPadding = 44.dp)
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 48.dp)
                            .clickable(role = Role.Button, onClick = onToggleAllSessions)
                            .padding(start = 44.dp, end = 16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            text = if (showsAllSessions) {
                                stringResource(R.string.sessions_show_less)
                            } else {
                                pluralStringResource(
                                    R.plurals.sessions_show_more,
                                    project.sessions.size - InitiallyVisibleSessions,
                                    project.sessions.size - InitiallyVisibleSessions,
                                )
                            },
                            style = MaterialTheme.typography.labelLarge,
                            color = RemoteTheme.colors.accent,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun SessionRow(
    session: SessionUiModel,
    onClick: () -> Unit,
) {
    val (statusText, statusColor) = sessionStatus(session.state)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 58.dp)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(start = 44.dp, top = 8.dp, end = 12.dp, bottom = 8.dp)
            .semantics {
                role = Role.Button
                stateDescription = statusText
            },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(
            modifier = Modifier
                .size(6.dp)
                .clip(RoundedCornerShape(50))
                .background(statusColor),
        )
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(3.dp),
        ) {
            Text(
                text = session.title,
                style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Medium),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    text = statusText,
                    style = MaterialTheme.typography.labelSmall,
                    color = statusColor,
                )
                if (session.updatedLabel.isNotBlank()) {
                    Text(
                        text = stringResource(R.string.metadata_separator, session.updatedLabel),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
        Icon(
            imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.65f),
            modifier = Modifier.size(18.dp),
        )
    }
}

@Composable
private fun sessionStatus(state: SessionExecutionState): Pair<String, Color> = when (state) {
    SessionExecutionState.Idle -> stringResource(R.string.session_state_idle) to
        MaterialTheme.colorScheme.onSurfaceVariant
    SessionExecutionState.Running -> stringResource(R.string.session_state_running) to
        RemoteTheme.colors.accent
    SessionExecutionState.WaitingForApproval -> stringResource(R.string.session_state_waiting) to
        RemoteTheme.colors.warning
    SessionExecutionState.Completed -> stringResource(R.string.session_state_completed) to
        RemoteTheme.colors.success
    SessionExecutionState.Failed -> stringResource(R.string.session_state_failed) to
        RemoteTheme.colors.danger
}

@Composable
private fun Hairline(startPadding: androidx.compose.ui.unit.Dp) {
    Box(
        Modifier
            .fillMaxWidth()
            .padding(start = startPadding)
            .height(1.dp)
            .background(RemoteTheme.colors.hairline),
    )
}

@Composable
private fun NewSessionSheet(
    projects: List<ProjectUiModel>,
    creatingProjectId: String?,
    errorMessage: String?,
    retryProjectId: String?,
    onClose: () -> Unit,
    onCreateSession: (projectId: String) -> Unit,
) {
    val creatingLabel = stringResource(R.string.session_creating)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .navigationBarsPadding()
            .padding(horizontal = RemoteDimens.pagePadding, vertical = 14.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = stringResource(R.string.session_new_title),
                    style = MaterialTheme.typography.titleMedium,
                )
                Text(
                    text = stringResource(R.string.session_new_subtitle),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (creatingProjectId == null) RemoteCloseButton(onClick = onClose)
        }
        errorMessage?.let { message ->
            RemoteInlineNotice(
                title = stringResource(R.string.session_create_failed_title),
                message = message,
                tone = RemoteNoticeTone.Danger,
                actionText = retryProjectId?.let { stringResource(R.string.action_retry) },
                onAction = retryProjectId?.let { projectId -> { onCreateSession(projectId) } },
            )
        }
        RemoteSectionHeader(
            title = stringResource(R.string.projects_section_title),
            detail = pluralStringResource(R.plurals.project_count, projects.size, projects.size),
        )
        RemoteSurface(modifier = Modifier.fillMaxWidth()) {
            Column {
                projects.forEachIndexed { index, project ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = RemoteDimens.compactRowHeight)
                            .clickable(
                                enabled = creatingProjectId == null,
                                role = Role.Button,
                            ) { onCreateSession(project.id) }
                            .padding(horizontal = 14.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Default.Folder,
                            contentDescription = null,
                            tint = RemoteTheme.colors.accent,
                            modifier = Modifier.size(20.dp),
                        )
                        Column(modifier = Modifier.weight(1f)) {
                            Text(text = project.title, style = MaterialTheme.typography.labelLarge)
                            if (!project.path.isNullOrBlank()) {
                                Text(
                                    text = project.path,
                                    style = MaterialTheme.typography.labelMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                            }
                            if (creatingProjectId == project.id) {
                                Text(
                                    text = creatingLabel,
                                    style = MaterialTheme.typography.labelMedium,
                                    color = RemoteTheme.colors.accent,
                                )
                            }
                        }
                        if (creatingProjectId == project.id) {
                            androidx.compose.material3.CircularProgressIndicator(
                                modifier = Modifier
                                    .size(20.dp)
                                    .semantics {
                                        stateDescription = creatingLabel
                                    },
                                strokeWidth = 2.dp,
                            )
                        } else {
                            Icon(
                                imageVector = Icons.Default.Add,
                                contentDescription = null,
                                tint = RemoteTheme.colors.accent,
                            )
                        }
                    }
                    if (index < projects.lastIndex) Hairline(startPadding = 44.dp)
                }
            }
        }
        Text(
            text = stringResource(R.string.session_new_privacy_note),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(2.dp))
    }
}
