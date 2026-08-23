package com.chokwinlee.dshremote.ui.features.trajectory

import android.content.ClipData
import android.content.ClipboardManager
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Input
import androidx.compose.material.icons.filled.AccountTree
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Memory
import androidx.compose.material.icons.filled.Route
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.SettingsSuggest
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.chokwinlee.dshremote.R
import com.chokwinlee.dshremote.ui.components.RemoteEmptyState
import com.chokwinlee.dshremote.ui.components.RemoteStatusPill
import com.chokwinlee.dshremote.ui.features.conversation.AttachmentList
import com.chokwinlee.dshremote.ui.model.ConversationItemState
import com.chokwinlee.dshremote.ui.model.DetailSectionKind
import com.chokwinlee.dshremote.ui.model.TrajectoryKindUi
import com.chokwinlee.dshremote.ui.model.TrajectoryRecordUiModel
import com.chokwinlee.dshremote.ui.theme.RemoteDimens
import com.chokwinlee.dshremote.ui.theme.RemoteTheme

@Composable
fun TrajectoryLedger(
    records: List<TrajectoryRecordUiModel>,
    onOpenAttachment: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    var query by rememberSaveable { mutableStateOf("") }
    var selected by remember(records) { mutableStateOf<TrajectoryRecordUiModel?>(null) }
    val filteredRecords = remember(records, query) { filterTrajectoryRecords(records, query) }
    val groups = remember(filteredRecords) { groupTrajectoryRecords(filteredRecords) }

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(0.dp),
    ) {
        TrajectorySearchField(query = query, onQueryChange = { query = it })
        if (records.isNotEmpty()) {
            TrajectoryOverviewRow(trajectoryOverview(filteredRecords))
            HorizontalDivider(color = RemoteTheme.colors.hairline)
        }

        if (records.isEmpty()) {
            RemoteEmptyState(
                title = stringResource(R.string.trajectory_empty_title),
                message = stringResource(R.string.trajectory_empty_message),
                icon = Icons.Default.AccountTree,
            )
        } else if (filteredRecords.isEmpty()) {
            RemoteEmptyState(
                title = stringResource(R.string.trajectory_no_results_title),
                message = stringResource(R.string.trajectory_no_results_message),
                icon = Icons.Default.Search,
            )
        } else {
            groups.forEach { group ->
                TrajectoryGroupHeader(group)
                group.records.forEachIndexed { index, record ->
                    TrajectoryRow(
                        record = record,
                        onClick = { selected = record },
                    )
                    if (index < group.records.lastIndex) {
                        HorizontalDivider(
                            color = RemoteTheme.colors.hairline,
                            modifier = Modifier.padding(start = 42.dp),
                        )
                    }
                }
            }
        }
    }
    selected?.let { record ->
        TrajectoryDetailDialog(
            record = record,
            onOpenAttachment = onOpenAttachment,
            onDismiss = { selected = null },
        )
    }
}

@Composable
private fun TrajectorySearchField(
    query: String,
    onQueryChange: (String) -> Unit,
) {
    val description = stringResource(R.string.trajectory_search_description)
    TextField(
        value = query,
        onValueChange = onQueryChange,
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = 8.dp)
            .semantics { contentDescription = description },
        placeholder = { Text(stringResource(R.string.trajectory_search_placeholder)) },
        leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
        trailingIcon = if (query.isNotEmpty()) {
            {
                IconButton(onClick = { onQueryChange("") }) {
                    Icon(
                        Icons.Default.Clear,
                        contentDescription = stringResource(R.string.trajectory_search_clear),
                    )
                }
            }
        } else {
            null
        },
        singleLine = true,
        shape = RoundedCornerShape(RemoteDimens.controlRadius),
        textStyle = MaterialTheme.typography.bodyMedium,
        colors = TextFieldDefaults.colors(
            focusedContainerColor = RemoteTheme.colors.raisedSurface,
            unfocusedContainerColor = RemoteTheme.colors.raisedSurface,
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent,
        ),
    )
}

@Composable
private fun TrajectoryOverviewRow(overview: TrajectoryOverview) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        TrajectoryMetric(
            label = stringResource(R.string.trajectory_overview_events),
            value = overview.eventCount.toString(),
            modifier = Modifier.weight(1f),
        )
        TrajectoryMetric(
            label = stringResource(R.string.trajectory_overview_turns),
            value = overview.turnCount.toString(),
            modifier = Modifier.weight(1f),
        )
        TrajectoryMetric(
            label = stringResource(R.string.trajectory_overview_tools),
            value = overview.toolCallCount.toString(),
            modifier = Modifier.weight(1f),
        )
    }
}

@Composable
private fun TrajectoryMetric(
    label: String,
    value: String,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.semantics(mergeDescendants = true) {},
        verticalArrangement = Arrangement.spacedBy(1.dp),
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 2,
        )
        Text(
            text = value,
            style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.SemiBold),
        )
    }
}

@Composable
private fun TrajectoryGroupHeader(group: TrajectoryTurnGroup) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 12.dp, bottom = 4.dp)
            .semantics(mergeDescendants = true) { heading() },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = group.turn?.let { stringResource(R.string.trajectory_turn, it) }
                ?: stringResource(R.string.trajectory_context_group),
            style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(1f),
        )
        Text(
            text = androidx.compose.ui.res.pluralStringResource(
                R.plurals.trajectory_group_event_count,
                group.records.size,
                group.records.size,
            ),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun TrajectoryRow(
    record: TrajectoryRecordUiModel,
    onClick: () -> Unit,
) {
    val color = trajectoryColor(record)
    val largeText = LocalDensity.current.fontScale >= 1.4f
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 54.dp)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(
            modifier = Modifier
                .size(26.dp)
                .clip(CircleShape)
                .background(color.copy(alpha = 0.12f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(trajectoryIcon(record.kind), null, tint = color, modifier = Modifier.size(15.dp))
        }
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(3.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    record.title,
                    style = MaterialTheme.typography.labelLarge,
                    modifier = Modifier.weight(1f),
                    maxLines = if (largeText) 2 else 1,
                    overflow = TextOverflow.Ellipsis,
                )
                record.durationLabel?.let {
                    Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            Text(
                record.summary,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = if (largeText) 3 else 2,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                listOfNotNull(
                    record.turn?.let { stringResource(R.string.trajectory_turn, it) },
                    record.step?.let { stringResource(R.string.trajectory_step, it) },
                    record.timestampLabel.takeIf(String::isNotBlank),
                ).joinToString(" · "),
                style = MaterialTheme.typography.labelSmall,
                color = color,
            )
        }
    }
}

@Composable
private fun TrajectoryDetailDialog(
    record: TrajectoryRecordUiModel,
    onOpenAttachment: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    var copied by remember(record.id) { mutableStateOf(false) }
    val kindLabel = stringResource(trajectoryKindLabel(record.kind))
    val metadata = listOfNotNull(
        record.turn?.let { stringResource(R.string.trajectory_turn, it) },
        record.step?.let { stringResource(R.string.trajectory_step, it) },
        record.durationLabel,
        record.timestampLabel.takeIf(String::isNotBlank),
    )
    val copyLabels = TrajectoryCopyLabels(
        kind = stringResource(R.string.trajectory_copy_kind),
        sequence = stringResource(R.string.trajectory_copy_sequence),
        summary = stringResource(R.string.trajectory_copy_summary),
        details = stringResource(R.string.trajectory_copy_details),
        attachments = stringResource(R.string.trajectory_copy_attachments),
        defaultAttachment = stringResource(R.string.attachment_image),
    )
    val fullContent = trajectoryFullContent(
        record = record,
        kindLabel = kindLabel,
        metadata = metadata,
        labels = copyLabels,
    )

    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(record.title, modifier = Modifier.semantics { heading() })
                RemoteStatusPill(
                    text = stringResource(trajectoryKindLabel(record.kind)),
                    color = trajectoryColor(record),
                )
            }
        },
        text = {
            LazyColumn(
                modifier = Modifier.fillMaxWidth().heightIn(max = 480.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                item("summary") {
                    SelectionContainer {
                        Text(record.summary, style = MaterialTheme.typography.bodyMedium)
                    }
                }
                if (metadata.isNotEmpty()) {
                    item("metadata") {
                        SelectionContainer {
                            Text(
                                metadata.joinToString(" · "),
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
                item("divider") { HorizontalDivider(color = RemoteTheme.colors.hairline) }
                items(record.details, key = { "detail-${it.id}" }) { detail ->
                    val isCode = detail.kind == DetailSectionKind.Code ||
                        detail.kind == DetailSectionKind.Diff
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(10.dp))
                            .background(
                                if (isCode) RemoteTheme.colors.codeSurface
                                else RemoteTheme.colors.mutedSurface,
                            )
                            .padding(10.dp),
                        verticalArrangement = Arrangement.spacedBy(5.dp),
                    ) {
                        detail.title?.let { title ->
                            Text(
                                text = title,
                                style = MaterialTheme.typography.labelMedium.copy(
                                    fontWeight = FontWeight.SemiBold,
                                ),
                            )
                        }
                        SelectionContainer {
                            Text(
                                text = detail.content,
                                style = MaterialTheme.typography.bodyMedium.copy(
                                    fontFamily = if (isCode) FontFamily.Monospace
                                    else FontFamily.Default,
                                ),
                            )
                        }
                    }
                }
                if (record.attachments.isNotEmpty()) {
                    item("attachments") { AttachmentList(record.attachments, onOpenAttachment) }
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    context.getSystemService(ClipboardManager::class.java)?.setPrimaryClip(
                        ClipData.newPlainText(record.title, fullContent),
                    )
                    copied = true
                },
            ) {
                Icon(
                    imageVector = Icons.Default.ContentCopy,
                    contentDescription = null,
                    modifier = Modifier.size(17.dp),
                )
                Text(
                    text = stringResource(
                        if (copied) R.string.trajectory_copied
                        else R.string.trajectory_copy_all,
                    ),
                    modifier = Modifier.padding(start = 6.dp),
                )
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.action_close)) }
        },
    )
}

@Composable
private fun trajectoryColor(record: TrajectoryRecordUiModel): Color = when (record.state) {
    ConversationItemState.Failed -> RemoteTheme.colors.danger
    ConversationItemState.Stopped -> RemoteTheme.colors.warning
    ConversationItemState.Succeeded -> RemoteTheme.colors.success
    ConversationItemState.Running -> RemoteTheme.colors.accent
    ConversationItemState.Info -> when (record.kind) {
        TrajectoryKindUi.Tool -> RemoteTheme.colors.tool
        TrajectoryKindUi.Goal, TrajectoryKindUi.Plan -> RemoteTheme.colors.reasoning
        else -> MaterialTheme.colorScheme.onSurfaceVariant
    }
}

private fun trajectoryIcon(kind: TrajectoryKindUi): ImageVector = when (kind) {
    TrajectoryKindUi.Input -> Icons.AutoMirrored.Filled.Input
    TrajectoryKindUi.Context -> Icons.Default.Memory
    TrajectoryKindUi.Request -> Icons.Default.SettingsSuggest
    TrajectoryKindUi.Assistant -> Icons.Default.AutoAwesome
    TrajectoryKindUi.Tool -> Icons.Default.Build
    TrajectoryKindUi.Goal -> Icons.Default.Flag
    TrajectoryKindUi.Plan -> Icons.Default.Route
    TrajectoryKindUi.Lifecycle -> Icons.Default.AccountTree
}

private fun trajectoryKindLabel(kind: TrajectoryKindUi): Int = when (kind) {
    TrajectoryKindUi.Input -> R.string.trajectory_kind_input
    TrajectoryKindUi.Context -> R.string.trajectory_kind_context
    TrajectoryKindUi.Request -> R.string.trajectory_kind_request
    TrajectoryKindUi.Assistant -> R.string.trajectory_kind_assistant
    TrajectoryKindUi.Tool -> R.string.trajectory_kind_tool
    TrajectoryKindUi.Goal -> R.string.trajectory_kind_goal
    TrajectoryKindUi.Plan -> R.string.trajectory_kind_plan
    TrajectoryKindUi.Lifecycle -> R.string.trajectory_kind_lifecycle
}

internal data class TrajectoryOverview(
    val eventCount: Int,
    val turnCount: Int,
    val toolCallCount: Int,
)

internal data class TrajectoryTurnGroup(
    val turn: Int?,
    val records: List<TrajectoryRecordUiModel>,
)

internal fun trajectoryOverview(records: List<TrajectoryRecordUiModel>) = TrajectoryOverview(
    eventCount = records.size,
    turnCount = records.mapNotNull(TrajectoryRecordUiModel::turn).distinct().size,
    toolCallCount = records.count { it.kind == TrajectoryKindUi.Tool },
)

internal fun filterTrajectoryRecords(
    records: List<TrajectoryRecordUiModel>,
    query: String,
): List<TrajectoryRecordUiModel> {
    val normalized = query.trim()
    if (normalized.isEmpty()) return records
    return records.filter { record ->
        record.title.contains(normalized, ignoreCase = true) ||
            record.summary.contains(normalized, ignoreCase = true) ||
            record.timestampLabel.contains(normalized, ignoreCase = true) ||
            record.durationLabel?.contains(normalized, ignoreCase = true) == true ||
            record.details.any { detail ->
                detail.title?.contains(normalized, ignoreCase = true) == true ||
                    detail.content.contains(normalized, ignoreCase = true)
            }
    }
}

internal fun groupTrajectoryRecords(
    records: List<TrajectoryRecordUiModel>,
): List<TrajectoryTurnGroup> {
    val grouped = records.groupBy(TrajectoryRecordUiModel::turn)
    return grouped.keys.sortedWith(compareBy<Int?> { it != null }.thenBy { it ?: Int.MIN_VALUE })
        .map { turn ->
            TrajectoryTurnGroup(
                turn = turn,
                records = grouped.getValue(turn).sortedBy(TrajectoryRecordUiModel::sequence),
            )
        }
}

internal data class TrajectoryCopyLabels(
    val kind: String,
    val sequence: String,
    val summary: String,
    val details: String,
    val attachments: String,
    val defaultAttachment: String,
)

internal fun trajectoryFullContent(
    record: TrajectoryRecordUiModel,
    kindLabel: String,
    metadata: List<String>,
    labels: TrajectoryCopyLabels,
): String = buildString {
    appendLine(record.title)
    appendLine("${labels.kind}: $kindLabel")
    appendLine("${labels.sequence}: #${record.sequence}")
    if (metadata.isNotEmpty()) appendLine(metadata.joinToString(" · "))
    appendLine()
    appendLine(labels.summary)
    appendLine(record.summary)

    if (record.details.isNotEmpty()) {
        appendLine()
        appendLine(labels.details)
        record.details.forEach { detail ->
            detail.title?.takeIf(String::isNotBlank)?.let { appendLine(it) }
            appendLine(detail.content)
        }
    }

    if (record.attachments.isNotEmpty()) {
        appendLine()
        appendLine(labels.attachments)
        record.attachments.forEach { attachment ->
            appendLine(
                listOfNotNull(
                    attachment.name ?: labels.defaultAttachment,
                    "${attachment.width} × ${attachment.height}",
                    attachment.sizeLabel,
                    attachment.mediaType,
                    attachment.errorMessage,
                ).joinToString(" · "),
            )
        }
    }
}.trim()
