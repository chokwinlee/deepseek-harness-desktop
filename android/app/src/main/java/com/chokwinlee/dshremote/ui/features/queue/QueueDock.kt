package com.chokwinlee.dshremote.ui.features.queue

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DeleteOutline
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.LowPriority
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.chokwinlee.dshremote.R
import com.chokwinlee.dshremote.ui.model.QueueActionUi
import com.chokwinlee.dshremote.ui.model.QueuePlacementUi
import com.chokwinlee.dshremote.ui.model.QueuedMessageUiModel
import com.chokwinlee.dshremote.ui.theme.RemoteDimens
import com.chokwinlee.dshremote.ui.theme.RemoteTheme

/** Compact queue disclosure that scrolls with the transcript instead of competing with it. */
@Composable
fun QueueDock(
    queue: List<QueuedMessageUiModel>,
    isRunning: Boolean,
    onUpdate: (String, QueueActionUi) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (queue.isEmpty()) return
    var expanded by remember(queue.map(QueuedMessageUiModel::id)) {
        mutableStateOf(queue.any { it.placement == QueuePlacementUi.Steering })
    }
    val disclosureState = stringResource(
        if (expanded) R.string.detail_state_expanded else R.string.detail_state_collapsed,
    )
    Column(modifier = modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 48.dp)
                .clickable(role = Role.Button) { expanded = !expanded }
                .semantics {
                    heading()
                    stateDescription = disclosureState
                }
                .padding(horizontal = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(
                imageVector = Icons.Default.LowPriority,
                contentDescription = null,
                tint = RemoteTheme.colors.accent,
                modifier = Modifier.size(19.dp),
            )
            Text(
                text = stringResource(R.string.queue_title),
                style = MaterialTheme.typography.labelLarge,
                modifier = Modifier.weight(1f),
            )
            Text(
                text = pluralStringResource(R.plurals.queue_count, queue.size, queue.size),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Icon(
                imageVector = if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        if (expanded) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(RemoteDimens.controlRadius))
                    .background(RemoteTheme.colors.surface),
            ) {
                queue.forEachIndexed { index, item ->
                    QueueRow(item = item, isRunning = isRunning, onUpdate = onUpdate)
                    if (index != queue.lastIndex) HorizontalDivider(color = RemoteTheme.colors.hairline)
                }
            }
        }
    }
}

@Composable
private fun QueueRow(
    item: QueuedMessageUiModel,
    isRunning: Boolean,
    onUpdate: (String, QueueActionUi) -> Unit,
) {
    var editing by remember(item.id) { mutableStateOf(false) }
    Row(
        modifier = Modifier.fillMaxWidth().heightIn(min = 58.dp).padding(start = 12.dp, end = 4.dp, top = 6.dp, bottom = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Column(Modifier.weight(1f)) {
            Text(
                text = item.preview,
                style = MaterialTheme.typography.bodyMedium,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = buildString {
                    append(stringResource(queuePlacementLabel(item.placement)))
                    if (item.attachmentCount > 0) append(
                        " · ${pluralStringResource(R.plurals.queue_images, item.attachmentCount, item.attachmentCount)}",
                    )
                },
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (item.attachmentCount > 0) {
                Text(
                    text = stringResource(R.string.queue_image_edit_hint),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        if (isRunning && item.placement == QueuePlacementUi.Queued) {
            TextButton(onClick = { onUpdate(item.id, QueueActionUi.Steer) }, enabled = !item.isUpdating) {
                Text(stringResource(R.string.queue_steer))
            }
        }
        IconButton(
            onClick = { editing = true },
            enabled = !item.isUpdating && item.attachmentCount == 0,
        ) {
            Icon(
                Icons.Default.Edit,
                stringResource(
                    if (item.attachmentCount > 0) R.string.queue_edit_images_disabled else R.string.queue_edit,
                ),
            )
        }
        IconButton(onClick = { onUpdate(item.id, QueueActionUi.Remove) }, enabled = !item.isUpdating) {
            Icon(Icons.Default.DeleteOutline, stringResource(R.string.queue_remove), tint = RemoteTheme.colors.danger)
        }
    }
    if (editing) {
        QueueEditDialog(
            initialText = item.text ?: item.preview,
            onDismiss = { editing = false },
            onSave = {
                onUpdate(item.id, QueueActionUi.Edit(it))
                editing = false
            },
        )
    }
}

@Composable
private fun QueueEditDialog(initialText: String, onDismiss: () -> Unit, onSave: (String) -> Unit) {
    var text by remember(initialText) { mutableStateOf(initialText) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.queue_edit_title)) },
        text = {
            TextField(
                value = text,
                onValueChange = { text = it },
                minLines = 3,
                maxLines = 8,
                label = { Text(stringResource(R.string.queue_edit_input_label)) },
                placeholder = { Text(stringResource(R.string.composer_placeholder)) },
            )
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.action_cancel)) } },
        confirmButton = {
            TextButton(onClick = { onSave(text.trim()) }, enabled = text.isNotBlank()) {
                Text(stringResource(R.string.action_save))
            }
        },
    )
}

private fun queuePlacementLabel(placement: QueuePlacementUi): Int = when (placement) {
    QueuePlacementUi.Queued -> R.string.queue_placement_queued
    QueuePlacementUi.Steering -> R.string.queue_placement_steering
    QueuePlacementUi.Context -> R.string.queue_placement_context
}
