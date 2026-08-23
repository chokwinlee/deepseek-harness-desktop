package com.chokwinlee.dshremote.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountTree
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Psychology
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.chokwinlee.dshremote.R
import com.chokwinlee.dshremote.ui.components.RemoteEmptyState
import com.chokwinlee.dshremote.ui.components.RemoteErrorState
import com.chokwinlee.dshremote.ui.components.RemoteIconButton
import com.chokwinlee.dshremote.ui.components.RemoteInlineNotice
import com.chokwinlee.dshremote.ui.components.RemoteLoadingState
import com.chokwinlee.dshremote.ui.components.RemoteNoticeTone
import com.chokwinlee.dshremote.ui.components.RemotePageHeader
import com.chokwinlee.dshremote.ui.features.composer.RemoteComposer
import com.chokwinlee.dshremote.ui.features.conversation.ConversationMessageCard
import com.chokwinlee.dshremote.ui.features.interaction.InteractionPanel
import com.chokwinlee.dshremote.ui.features.models.ModelPickerDialog
import com.chokwinlee.dshremote.ui.features.queue.QueueDock
import com.chokwinlee.dshremote.ui.features.session.SessionStatusBand
import com.chokwinlee.dshremote.ui.features.subagents.SubagentBrowserSheet
import com.chokwinlee.dshremote.ui.features.trajectory.TrajectoryLedger
import com.chokwinlee.dshremote.ui.model.PromptDeliveryUi
import com.chokwinlee.dshremote.ui.model.SessionDetailCallbacks
import com.chokwinlee.dshremote.ui.model.SessionDetailUiState
import com.chokwinlee.dshremote.ui.model.SessionExecutionState
import com.chokwinlee.dshremote.ui.theme.RemoteDimens
import com.chokwinlee.dshremote.ui.theme.RemoteTheme
import kotlinx.coroutines.launch

private enum class SessionViewMode { Conversation, Trajectory }

internal const val SESSION_HISTORY_TEST_TAG = "session-history"

@Composable
fun SessionDetailScreen(
    state: SessionDetailUiState,
    onBack: () -> Unit,
    onRefresh: () -> Unit,
    onSendMessage: (String) -> Unit,
    onStopSession: () -> Unit,
    featureCallbacks: SessionDetailCallbacks = SessionDetailCallbacks(
        onRefresh = onRefresh,
        onSendPrompt = { text, _: PromptDeliveryUi -> onSendMessage(text) },
        onStopSession = onStopSession,
    ),
) {
    val session = state.session
    val colors = RemoteTheme.colors
    val listState = rememberLazyListState()
    val coroutineScope = rememberCoroutineScope()
    var viewModeName by rememberSaveable(session?.id) { mutableStateOf(SessionViewMode.Conversation.name) }
    val viewMode = SessionViewMode.valueOf(viewModeName)
    var showModels by rememberSaveable { mutableStateOf(false) }
    var showSubagents by rememberSaveable { mutableStateOf(false) }
    var showSessionActions by remember { mutableStateOf(false) }
    var didPositionInitialHistory by remember(session?.id) { mutableStateOf(false) }
    var followAfterMessageCount by remember(session?.id) { mutableStateOf<Int?>(null) }
    var modelSelectionFeedback by rememberSaveable(session?.id) { mutableStateOf<String?>(null) }
    val isNearBottom by remember {
        derivedStateOf {
            val lastVisible = listState.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: -1
            val total = listState.layoutInfo.totalItemsCount
            total == 0 || lastVisible >= total - 3
        }
    }

    val tailRevision = state.messages.lastOrNull()?.let { message ->
        listOf(
            message.id,
            message.text,
            message.state,
            message.attachments,
            message.isStreaming,
        ).hashCode()
    }
    LaunchedEffect(state.messages.size, tailRevision, viewMode, session?.id) {
        if (viewMode != SessionViewMode.Conversation || state.messages.isEmpty()) return@LaunchedEffect
        withFrameNanos { }
        val bottomIndex = listState.layoutInfo.totalItemsCount.minus(1).coerceAtLeast(0)
        if (!didPositionInitialHistory) {
            listState.scrollToItem(bottomIndex)
            didPositionInitialHistory = true
        } else if (isNearBottom || followAfterMessageCount?.let { state.messages.size > it } == true) {
            listState.animateScrollToItem(bottomIndex)
            followAfterMessageCount = null
        }
    }

    BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
        val interactionMaxHeight = maxHeight * 0.58f
        Column(
            modifier = Modifier.fillMaxSize().background(colors.canvas),
        ) {
        RemotePageHeader(
            title = session?.title ?: stringResource(R.string.session_default_title),
            subtitle = state.projectName.ifBlank { stringResource(R.string.session_screen_subtitle) },
            onBack = onBack,
        ) {
            if (session != null) {
                Box {
                    IconButton(
                        onClick = { showSessionActions = true },
                        modifier = Modifier.size(48.dp),
                    ) {
                        Icon(Icons.Default.MoreVert, stringResource(R.string.session_more_actions))
                    }
                    DropdownMenu(
                        expanded = showSessionActions,
                        onDismissRequest = { showSessionActions = false },
                    ) {
                        if (state.plan != null || state.stats != null) {
                            DropdownMenuItem(
                                text = {
                                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                        Text(
                                            text = stringResource(R.string.session_details_label),
                                            style = MaterialTheme.typography.labelSmall,
                                        )
                                        state.plan?.let { plan ->
                                            Text(
                                                text = stringResource(
                                                    when {
                                                        plan.pending -> R.string.session_planning_pending
                                                        plan.effectiveActive -> R.string.session_planning_active
                                                        else -> R.string.session_planning_inactive
                                                    },
                                                ),
                                                style = MaterialTheme.typography.bodyMedium,
                                            )
                                        }
                                        state.stats?.let { stats ->
                                            val turns = pluralStringResource(
                                                R.plurals.session_stats_turns,
                                                stats.turns,
                                                stats.turns,
                                            )
                                            val steps = pluralStringResource(
                                                R.plurals.session_stats_steps,
                                                stats.steps,
                                                stats.steps,
                                            )
                                            Text(
                                                text = stringResource(
                                                    R.string.session_stats,
                                                    turns,
                                                    steps,
                                                    stats.tokenLabel,
                                                ),
                                                style = MaterialTheme.typography.labelMedium,
                                            )
                                        }
                                    }
                                },
                                enabled = false,
                                onClick = {},
                            )
                            HorizontalDivider(color = RemoteTheme.colors.hairline)
                        }
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.subagent_open)) },
                            leadingIcon = { Icon(Icons.Default.Groups, contentDescription = null) },
                            onClick = {
                                showSessionActions = false
                                showSubagents = true
                                featureCallbacks.onRefreshSubagents()
                            },
                        )
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.model_open)) },
                            leadingIcon = { Icon(Icons.Default.Psychology, contentDescription = null) },
                            enabled = !state.models.isSelecting,
                            onClick = {
                                showSessionActions = false
                                showModels = true
                            },
                        )
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.action_refresh)) },
                            leadingIcon = { Icon(Icons.Default.Refresh, contentDescription = null) },
                            enabled = !state.isLoading,
                            onClick = {
                                showSessionActions = false
                                featureCallbacks.onRefresh()
                            },
                        )
                    }
                }
            }
        }

            if (session != null) {
                SessionStatusBand(
                    sessionState = session.state,
                    goal = state.goal,
                )
                SessionModeBar(
                    selected = viewMode,
                    onSelected = {
                        viewModeName = it.name
                        didPositionInitialHistory = it != SessionViewMode.Conversation
                    },
                )
            }

            Box(modifier = Modifier.weight(1f)) {
            when {
                state.isLoading && !state.hasLoadedOnce && state.messages.isEmpty() -> {
                    RemoteLoadingState(
                        title = stringResource(R.string.session_loading_title),
                        message = stringResource(R.string.session_loading_message),
                    )
                }
                state.errorMessage != null && !state.hasLoadedOnce && state.messages.isEmpty() -> {
                    RemoteErrorState(message = state.errorMessage, onRetry = featureCallbacks.onRefresh)
                }
                session == null -> {
                    RemoteEmptyState(
                        title = stringResource(R.string.session_unavailable_title),
                        message = stringResource(R.string.session_unavailable_message),
                    )
                }
                else -> {
                    SessionHistory(
                        state = state,
                        mode = viewMode,
                        listState = listState,
                        callbacks = featureCallbacks,
                    )
                    if (!isNearBottom && viewMode == SessionViewMode.Conversation && state.messages.isNotEmpty()) {
                        RemoteIconButton(
                            imageVector = Icons.Default.ArrowDownward,
                            contentDescription = stringResource(R.string.conversation_jump_latest),
                            onClick = {
                                coroutineScope.launch {
                                    val bottom = listState.layoutInfo.totalItemsCount.minus(1).coerceAtLeast(0)
                                    listState.animateScrollToItem(bottom)
                                }
                            },
                            tint = colors.accent,
                            emphasized = true,
                            modifier = Modifier.align(Alignment.BottomEnd).padding(16.dp),
                        )
                    }
                }
            }
        }

            if (session != null) {
                modelSelectionFeedback?.let { selectionLabel ->
                    RemoteInlineNotice(
                        title = stringResource(R.string.model_selection_applied_title),
                        message = stringResource(R.string.model_selection_applied, selectionLabel),
                        tone = RemoteNoticeTone.Success,
                        actionText = stringResource(R.string.action_close),
                        onAction = { modelSelectionFeedback = null },
                        modifier = Modifier.padding(horizontal = RemoteDimens.pagePadding, vertical = 6.dp),
                    )
                }
                if (state.interaction != null) {
                    InteractionPanel(
                        interaction = state.interaction,
                        onResolve = featureCallbacks.onResolveInteraction,
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(max = interactionMaxHeight)
                            .navigationBarsPadding(),
                    )
                } else {
                    RemoteComposer(
                        state = state,
                        callbacks = featureCallbacks.copy(
                            onSendPrompt = { text, delivery ->
                                followAfterMessageCount = state.messages.size
                                featureCallbacks.onSendPrompt(text, delivery)
                            },
                        ),
                        onOpenModels = { showModels = true },
                    )
                }
            }
        }
    }

    if (showModels) {
        ModelPickerDialog(
            state = state.models,
            onLoad = featureCallbacks.onLoadModels,
            onDismiss = { showModels = false },
            onSelect = { selection, onResult ->
                featureCallbacks.onSelectModel(selection) { succeeded ->
                    onResult(succeeded)
                    if (succeeded) {
                        modelSelectionFeedback = listOfNotNull(
                            selection.modelName,
                            selection.reasoningEffortName,
                        ).joinToString(" · ")
                    }
                }
            },
        )
    }
    if (showSubagents) {
        SubagentBrowserSheet(
            catalog = state.subagents,
            selected = state.selectedSubagent,
            onDismiss = {
                showSubagents = false
                featureCallbacks.onDismissSubagents()
            },
            onRefresh = featureCallbacks.onRefreshSubagents,
            onOpen = featureCallbacks.onOpenSubagent,
            onNavigateBack = featureCallbacks.onNavigateBackSubagents,
            onOpenChildren = featureCallbacks.onOpenSubagentChildren,
            onLoadOlder = featureCallbacks.onLoadOlderSubagentHistory,
            onContinue = featureCallbacks.onContinueSubagent,
            onStop = featureCallbacks.onStopSubagent,
            onOpenAttachment = featureCallbacks.onOpenSubagentAttachment,
        )
    }
}

@Composable
private fun SessionModeBar(
    selected: SessionViewMode,
    onSelected: (SessionViewMode) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(RemoteTheme.colors.canvas)
            .padding(horizontal = RemoteDimens.pagePadding)
            .selectableGroup(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        SessionViewMode.entries.forEach { mode ->
            val active = selected == mode
            val label = stringResource(
                if (mode == SessionViewMode.Conversation) R.string.conversation_tab
                else R.string.trajectory_tab,
            )
            Column(
                modifier = Modifier
                    .widthIn(min = 82.dp)
                    .heightIn(min = 48.dp)
                    .selectable(
                        selected = active,
                        role = Role.Tab,
                        onClick = { onSelected(mode) },
                    )
                    .padding(horizontal = 4.dp, vertical = 8.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    label,
                    style = MaterialTheme.typography.labelLarge,
                    color = if (active) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Box(
                    Modifier
                        .width(24.dp)
                        .height(2.dp)
                        .background(if (active) RemoteTheme.colors.accent else Color.Transparent),
                )
            }
        }
    }
    HorizontalDivider(color = RemoteTheme.colors.hairline)
}

@Composable
private fun SessionHistory(
    state: SessionDetailUiState,
    mode: SessionViewMode,
    listState: androidx.compose.foundation.lazy.LazyListState,
    callbacks: SessionDetailCallbacks,
) {
    LazyColumn(
        state = listState,
        modifier = Modifier.fillMaxSize().testTag(SESSION_HISTORY_TEST_TAG),
        contentPadding = PaddingValues(
            start = RemoteDimens.pagePadding,
            top = 14.dp,
            end = RemoteDimens.pagePadding,
            bottom = 24.dp,
        ),
        verticalArrangement = Arrangement.spacedBy(15.dp),
    ) {
        if (state.queue.isNotEmpty()) {
            item("queued-instructions") {
                QueueDock(
                    queue = state.queue,
                    isRunning = state.session?.state == SessionExecutionState.Running,
                    onUpdate = callbacks.onUpdateQueue,
                )
            }
        }
        if (state.hasMoreHistory) {
            item("older-history") {
                TextButton(
                    onClick = callbacks.onLoadOlderHistory,
                    enabled = !state.isLoadingOlder,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    if (state.isLoadingOlder) {
                        CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                        Spacer(Modifier.width(7.dp))
                    }
                    Text(stringResource(R.string.history_load_older))
                }
            }
        }
        if (state.errorMessage != null && state.hasLoadedOnce) {
            item("stale-error") {
                RemoteInlineNotice(
                    title = stringResource(R.string.state_showing_saved_results),
                    message = state.errorMessage,
                    tone = RemoteNoticeTone.Warning,
                    actionText = stringResource(R.string.action_retry),
                    onAction = callbacks.onRefresh,
                )
            }
        }
        if (mode == SessionViewMode.Conversation) {
            if (state.messages.isEmpty()) {
                item("empty-conversation") {
                    RemoteEmptyState(
                        title = stringResource(R.string.conversation_empty_title),
                        message = stringResource(R.string.conversation_empty_message),
                    )
                }
            } else {
                items(
                    count = state.messages.size,
                    key = { index -> state.messages[index].id },
                ) { index ->
                    ConversationMessageCard(
                        message = state.messages[index],
                        onOpenAttachment = callbacks.onOpenAttachment,
                    )
                }
            }
            if (state.isStreaming) {
                item("streaming") {
                    Row(
                        modifier = Modifier.fillMaxWidth().semantics { liveRegion = LiveRegionMode.Polite },
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp, color = RemoteTheme.colors.accent)
                        Spacer(Modifier.width(8.dp))
                        Text(
                            stringResource(R.string.conversation_streaming),
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        } else {
            item("trajectory-ledger") {
                TrajectoryLedger(
                    records = state.trajectory,
                    onOpenAttachment = callbacks.onOpenAttachment,
                )
            }
        }
    }
}
