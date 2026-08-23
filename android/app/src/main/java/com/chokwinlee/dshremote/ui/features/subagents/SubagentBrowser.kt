package com.chokwinlee.dshremote.ui.features.subagents

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.AccountTree
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
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
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.chokwinlee.dshremote.R
import com.chokwinlee.dshremote.ui.components.RemoteEmptyState
import com.chokwinlee.dshremote.ui.components.RemoteErrorState
import com.chokwinlee.dshremote.ui.components.RemoteInlineNotice
import com.chokwinlee.dshremote.ui.components.RemoteNoticeTone
import com.chokwinlee.dshremote.ui.components.RemoteStatusPill
import com.chokwinlee.dshremote.ui.features.conversation.ConversationMessageCard
import com.chokwinlee.dshremote.ui.model.SubagentActivityUi
import com.chokwinlee.dshremote.ui.model.SubagentCatalogUiState
import com.chokwinlee.dshremote.ui.model.SubagentConversationUiState
import com.chokwinlee.dshremote.ui.model.SubagentModeUi
import com.chokwinlee.dshremote.ui.model.SubagentUiModel
import com.chokwinlee.dshremote.ui.theme.RemoteDimens
import com.chokwinlee.dshremote.ui.theme.RemoteTheme
import kotlinx.coroutines.launch

internal const val SUBAGENT_TRANSCRIPT_TEST_TAG = "subagent-transcript"
internal const val SUBAGENT_COMPOSER_TEST_TAG = "subagent-composer"

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SubagentBrowserSheet(
    catalog: SubagentCatalogUiState,
    selected: SubagentConversationUiState?,
    onDismiss: () -> Unit,
    onRefresh: () -> Unit,
    onOpen: (String) -> Unit,
    onNavigateBack: () -> Unit,
    onOpenChildren: (String) -> Unit,
    onLoadOlder: (String) -> Unit,
    onContinue: (String, String) -> Unit,
    onStop: (String) -> Unit,
    onOpenAttachment: (String, String) -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = RemoteTheme.colors.canvas,
        modifier = Modifier.fillMaxHeight(0.94f),
    ) {
        if (selected == null) {
            SubagentCatalogContent(catalog, onRefresh, onOpen, onNavigateBack)
        } else {
            SubagentConversationContent(
                state = selected,
                onBack = onNavigateBack,
                onOpenChildren = { onOpenChildren(selected.subagent.id) },
                onLoadOlder = { onLoadOlder(selected.subagent.id) },
                onContinue = { onContinue(selected.subagent.id, it) },
                onStop = { onStop(selected.subagent.id) },
                onOpenAttachment = { attachmentId ->
                    onOpenAttachment(selected.subagent.id, attachmentId)
                },
            )
        }
    }
}

@Composable
private fun SubagentCatalogContent(
    state: SubagentCatalogUiState,
    onRefresh: () -> Unit,
    onOpen: (String) -> Unit,
    onBack: () -> Unit,
) {
    Column(Modifier.fillMaxSize()) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = RemoteDimens.pagePadding, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (state.navigationDepth > 0) {
                IconButton(onClick = onBack, modifier = Modifier.size(48.dp)) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.action_back))
                }
            }
            Column(Modifier.weight(1f)) {
                Text(
                    stringResource(
                        if (state.navigationDepth > 0) R.string.subagent_nested_title
                        else R.string.subagent_title,
                    ),
                    style = MaterialTheme.typography.titleLarge,
                    modifier = Modifier.semantics { heading() },
                )
                Text(
                    if (state.navigationDepth > 0 && state.parentLabel != null) {
                        stringResource(R.string.subagent_nested_subtitle, state.parentLabel)
                    } else {
                        stringResource(R.string.subagent_subtitle)
                    },
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            IconButton(onClick = onRefresh, enabled = !state.isLoading) {
                Icon(Icons.Default.Refresh, stringResource(R.string.action_refresh))
            }
        }
        HorizontalDivider(color = RemoteTheme.colors.hairline)
        when {
            state.isLoading && state.entries.isEmpty() -> {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(strokeWidth = 2.dp)
                }
            }
            state.errorMessage != null && state.entries.isEmpty() -> {
                RemoteErrorState(state.errorMessage, onRefresh)
            }
            state.entries.isEmpty() -> {
                RemoteEmptyState(
                    title = stringResource(
                        if (state.navigationDepth > 0) R.string.subagent_nested_empty_title
                        else R.string.subagent_empty_title,
                    ),
                    message = stringResource(
                        if (state.navigationDepth > 0) R.string.subagent_nested_empty_message
                        else R.string.subagent_empty_message,
                    ),
                    icon = Icons.Default.Groups,
                )
            }
            else -> {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(RemoteDimens.pagePadding),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    if (!state.parentAvailable) {
                        item("parent-unavailable") {
                            RemoteInlineNotice(
                                title = stringResource(R.string.subagent_parent_unavailable_title),
                                message = stringResource(R.string.subagent_parent_unavailable_message),
                                tone = RemoteNoticeTone.Warning,
                            )
                        }
                    }
                    state.errorMessage?.let { error ->
                        item("catalog-error") {
                            RemoteInlineNotice(
                                title = stringResource(R.string.subagent_load_failed),
                                message = error,
                                tone = RemoteNoticeTone.Danger,
                                actionText = stringResource(R.string.action_retry),
                                onAction = onRefresh,
                            )
                        }
                    }
                    items(state.entries, key = SubagentUiModel::id) { entry ->
                        SubagentRow(entry, onOpen)
                    }
                }
            }
        }
    }
}

@Composable
private fun SubagentRow(entry: SubagentUiModel, onOpen: (String) -> Unit) {
    val activeColor = when (entry.activity) {
        SubagentActivityUi.Running -> RemoteTheme.colors.accent
        SubagentActivityUi.Inactive -> RemoteTheme.colors.success
        SubagentActivityUi.Unavailable -> RemoteTheme.colors.danger
    }
    val enabled = entry.diagnosticMessage == null
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(RemoteDimens.rowRadius))
            .background(RemoteTheme.colors.surface)
            .clickable(enabled = enabled, role = Role.Button) { onOpen(entry.id) }
            .heightIn(min = 56.dp)
            .semantics(mergeDescendants = true) { role = Role.Button }
            .padding(13.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(11.dp),
    ) {
        Box(
            modifier = Modifier.size(36.dp).clip(CircleShape).background(activeColor.copy(alpha = 0.11f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                if (enabled) Icons.Default.AccountTree else Icons.Default.ErrorOutline,
                contentDescription = null,
                tint = activeColor,
                modifier = Modifier.size(19.dp),
            )
        }
        Column(Modifier.weight(1f)) {
            Text(entry.label, style = MaterialTheme.typography.labelLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(
                entry.diagnosticMessage ?: buildString {
                    append(stringResource(subagentModeLabel(entry.mode)))
                    if (entry.hasChildren) append(" · ${stringResource(R.string.subagent_has_children)}")
                },
                style = MaterialTheme.typography.labelSmall,
                color = if (enabled) MaterialTheme.colorScheme.onSurfaceVariant else RemoteTheme.colors.danger,
            )
        }
        RemoteStatusPill(
            text = stringResource(subagentActivityLabel(entry.activity)),
            color = activeColor,
        )
    }
}

@Composable
internal fun SubagentConversationContent(
    state: SubagentConversationUiState,
    onBack: () -> Unit,
    onOpenChildren: () -> Unit,
    onLoadOlder: () -> Unit,
    onContinue: (String) -> Unit,
    onStop: () -> Unit,
    onOpenAttachment: (String) -> Unit,
) {
    var draft by rememberSaveable(state.subagent.id) { mutableStateOf("") }
    var didInitialPosition by remember(state.subagent.id) { mutableStateOf(false) }
    var unseenUpdates by remember(state.subagent.id) { mutableIntStateOf(0) }
    var previousMessageIds by remember(state.subagent.id) { mutableStateOf<Set<String>>(emptySet()) }
    var previousTailHash by remember(state.subagent.id) { mutableStateOf<Int?>(null) }
    var followNextUpdate by remember(state.subagent.id) { mutableStateOf(false) }
    val inputLabel = stringResource(R.string.subagent_input_label)
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()
    val isNearBottom by remember {
        derivedStateOf {
            val layout = listState.layoutInfo
            layout.totalItemsCount == 0 ||
                (layout.visibleItemsInfo.lastOrNull()?.index ?: 0) >= layout.totalItemsCount - 3
        }
    }

    LaunchedEffect(isNearBottom) {
        if (isNearBottom) unseenUpdates = 0
    }
    val tailRevision = state.messages.lastOrNull()?.let { message ->
        listOf(
            message.id,
            message.text,
            message.title,
            message.state,
            message.reasoning,
            message.details,
            message.metadata,
            message.isStreaming,
        ).hashCode()
    }
    LaunchedEffect(state.isLoading, tailRevision) {
        if (state.isLoading) return@LaunchedEffect
        val messageIds = state.messages.mapTo(linkedSetOf()) { it.id }
        if (!didInitialPosition) {
            withFrameNanos { }
            listState.layoutInfo.totalItemsCount.takeIf { it > 0 }?.let { count ->
                listState.scrollToItem(count - 1)
            }
            previousMessageIds = messageIds
            previousTailHash = tailRevision
            didInitialPosition = true
            return@LaunchedEffect
        }
        if (tailRevision == previousTailHash) {
            previousMessageIds = messageIds
            return@LaunchedEffect
        }
        val added = messageIds.count { it !in previousMessageIds }.coerceAtLeast(1)
        previousMessageIds = messageIds
        previousTailHash = tailRevision
        if (isNearBottom || followNextUpdate) {
            withFrameNanos { }
            listState.layoutInfo.totalItemsCount.takeIf { it > 0 }?.let { count ->
                listState.scrollToItem(count - 1)
            }
            unseenUpdates = 0
            followNextUpdate = false
        } else {
            unseenUpdates += added
        }
    }

    Column(Modifier.fillMaxSize()) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 6.dp, vertical = 5.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onBack, modifier = Modifier.size(48.dp)) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.action_back))
            }
            Column(Modifier.weight(1f)) {
                Text(state.subagent.label, style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
                Text(
                    stringResource(subagentModeLabel(state.subagent.mode)),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (state.subagent.hasChildren) {
                IconButton(onClick = onOpenChildren, modifier = Modifier.size(48.dp)) {
                    Icon(
                        Icons.Default.AccountTree,
                        stringResource(R.string.subagent_open_children),
                    )
                }
            }
            RemoteStatusPill(
                text = stringResource(subagentActivityLabel(state.subagent.activity)),
                color = when (state.subagent.activity) {
                    SubagentActivityUi.Running -> RemoteTheme.colors.accent
                    SubagentActivityUi.Inactive -> RemoteTheme.colors.success
                    SubagentActivityUi.Unavailable -> RemoteTheme.colors.danger
                },
            )
        }
        HorizontalDivider(color = RemoteTheme.colors.hairline)
        Box(Modifier.weight(1f)) {
            LazyColumn(
                state = listState,
                modifier = Modifier.fillMaxSize().testTag(SUBAGENT_TRANSCRIPT_TEST_TAG),
                contentPadding = PaddingValues(RemoteDimens.pagePadding),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                if (state.hasMoreHistory) {
                    item("older") {
                        TextButton(onClick = onLoadOlder, enabled = !state.isLoadingOlder, modifier = Modifier.fillMaxWidth()) {
                            if (state.isLoadingOlder) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                            Spacer(Modifier.width(6.dp))
                            Text(stringResource(R.string.history_load_older))
                        }
                    }
                }
                state.errorMessage?.let { error ->
                    item("error") {
                        RemoteInlineNotice(
                            title = stringResource(R.string.subagent_load_failed),
                            message = error,
                            tone = RemoteNoticeTone.Danger,
                        )
                    }
                }
                if (state.isLoading && state.messages.isEmpty()) {
                    item("loading") {
                        Box(Modifier.fillMaxWidth().padding(40.dp), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator(strokeWidth = 2.dp)
                        }
                    }
                } else if (state.messages.isEmpty()) {
                    item("empty") {
                        RemoteEmptyState(
                            title = stringResource(R.string.subagent_history_empty_title),
                            message = stringResource(R.string.subagent_history_empty_message),
                        )
                    }
                } else {
                    items(state.messages, key = { it.id }) { message ->
                        ConversationMessageCard(message, onOpenAttachment)
                    }
                }
                item("subagent-bottom") { Spacer(Modifier.size(1.dp)) }
            }
            if (unseenUpdates > 0) {
                TextButton(
                    onClick = {
                        scope.launch {
                            listState.layoutInfo.totalItemsCount.takeIf { it > 0 }?.let { count ->
                                listState.scrollToItem(count - 1)
                            }
                            unseenUpdates = 0
                        }
                    },
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .padding(12.dp)
                        .heightIn(min = 48.dp)
                        .clip(RoundedCornerShape(24.dp))
                        .background(RemoteTheme.colors.surface)
                        .semantics {
                            role = Role.Button
                            liveRegion = LiveRegionMode.Polite
                        },
                ) {
                    Icon(Icons.Default.KeyboardArrowDown, contentDescription = null)
                    Spacer(Modifier.width(4.dp))
                    Text(pluralStringResource(R.plurals.subagent_new_updates, unseenUpdates, unseenUpdates))
                }
            }
        }
        if (!state.parentAvailable) {
            RemoteInlineNotice(
                title = stringResource(R.string.subagent_parent_unavailable_title),
                message = stringResource(R.string.subagent_continue_unavailable),
                tone = RemoteNoticeTone.Warning,
                modifier = Modifier.padding(horizontal = RemoteDimens.pagePadding, vertical = 6.dp),
            )
        }
        if (state.subagent.mode == SubagentModeUi.Continuable &&
            (state.parentAvailable || state.subagent.activity == SubagentActivityUi.Running)
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(RemoteTheme.colors.surface)
                    .imePadding()
                    .navigationBarsPadding()
                    .testTag(SUBAGENT_COMPOSER_TEST_TAG)
                    .padding(10.dp),
                verticalAlignment = Alignment.Bottom,
                horizontalArrangement = Arrangement.spacedBy(7.dp),
            ) {
                if (state.parentAvailable) {
                    TextField(
                        value = draft,
                        onValueChange = { draft = it },
                        modifier = Modifier
                            .weight(1f)
                            .heightIn(min = 52.dp, max = 120.dp)
                            .semantics { contentDescription = inputLabel },
                        placeholder = { Text(stringResource(R.string.subagent_continue_placeholder)) },
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
                        keyboardActions = KeyboardActions(onSend = {
                            if (draft.isNotBlank() && !state.isSending) {
                                followNextUpdate = true
                                onContinue(draft.trim())
                                draft = ""
                            }
                        }),
                        enabled = !state.isSending && !state.isStopping,
                        colors = TextFieldDefaults.colors(
                            focusedContainerColor = RemoteTheme.colors.raisedSurface,
                            unfocusedContainerColor = RemoteTheme.colors.raisedSurface,
                            focusedIndicatorColor = Color.Transparent,
                            unfocusedIndicatorColor = Color.Transparent,
                        ),
                    )
                } else {
                    Spacer(Modifier.weight(1f))
                }
                IconButton(
                    onClick = {
                        if (state.subagent.activity == SubagentActivityUi.Running) onStop()
                        else if (draft.isNotBlank()) {
                            followNextUpdate = true
                            onContinue(draft.trim())
                            draft = ""
                        }
                    },
                    enabled = !state.isSending && !state.isStopping && (
                        state.subagent.activity == SubagentActivityUi.Running ||
                            (state.parentAvailable && draft.isNotBlank())
                        ),
                    modifier = Modifier.size(48.dp).clip(RoundedCornerShape(15.dp)).background(RemoteTheme.colors.accentFill),
                ) {
                    if (state.isSending || state.isStopping) {
                        CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = Color.White)
                    } else {
                        Icon(
                            if (state.subagent.activity == SubagentActivityUi.Running) Icons.Default.Stop else Icons.AutoMirrored.Filled.Send,
                            stringResource(
                                if (state.subagent.activity == SubagentActivityUi.Running) R.string.subagent_stop
                                else R.string.subagent_continue_send,
                            ),
                            tint = Color.White,
                        )
                    }
                }
            }
        }
    }
}

private fun subagentModeLabel(mode: SubagentModeUi): Int = when (mode) {
    SubagentModeUi.OneShot -> R.string.subagent_mode_one_shot
    SubagentModeUi.Continuable -> R.string.subagent_mode_continuable
    SubagentModeUi.Unknown -> R.string.subagent_mode_unknown
}

private fun subagentActivityLabel(activity: SubagentActivityUi): Int = when (activity) {
    SubagentActivityUi.Running -> R.string.subagent_activity_running
    SubagentActivityUi.Inactive -> R.string.subagent_activity_inactive
    SubagentActivityUi.Unavailable -> R.string.subagent_activity_unavailable
}
