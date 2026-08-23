package com.chokwinlee.dshremote.ui.features.conversation

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BrokenImage
import androidx.compose.material.icons.filled.Code
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Terminal
import androidx.compose.material.icons.filled.TravelExplore
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.chokwinlee.dshremote.R
import com.chokwinlee.dshremote.ui.components.RemoteInlineNotice
import com.chokwinlee.dshremote.ui.components.RemoteNoticeTone
import com.chokwinlee.dshremote.ui.features.images.RemoteImagePreview
import com.chokwinlee.dshremote.ui.model.ConversationActor
import com.chokwinlee.dshremote.ui.model.ConversationItemState
import com.chokwinlee.dshremote.ui.model.ConversationMessageUiModel
import com.chokwinlee.dshremote.ui.model.DetailSectionKind
import com.chokwinlee.dshremote.ui.model.DetailSectionUiModel
import com.chokwinlee.dshremote.ui.model.ImageAttachmentUiModel
import com.chokwinlee.dshremote.ui.model.ToolCardKind
import com.chokwinlee.dshremote.ui.theme.RemoteDimens
import com.chokwinlee.dshremote.ui.theme.RemoteTheme

@Composable
fun ConversationMessageCard(
    message: ConversationMessageUiModel,
    onOpenAttachment: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    when (message.actor) {
        ConversationActor.User -> UserMessage(message, onOpenAttachment, modifier)
        ConversationActor.Assistant -> AssistantMessage(message, onOpenAttachment, modifier)
        ConversationActor.Tool -> ToolMessage(message, onOpenAttachment, modifier)
        ConversationActor.Context -> ContextMessage(message, onOpenAttachment, modifier)
        ConversationActor.System -> RemoteInlineNotice(
            title = message.title ?: stringResource(R.string.conversation_status_label),
            message = message.text,
            tone = noticeTone(message.state),
            modifier = modifier,
        )
    }
}

@Composable
private fun UserMessage(
    message: ConversationMessageUiModel,
    onOpenAttachment: (String) -> Unit,
    modifier: Modifier,
) {
    Column(
        modifier = modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.End,
    ) {
        Column(
            modifier = Modifier
                .widthIn(max = 340.dp)
                .clip(RoundedCornerShape(RemoteDimens.composerRadius))
                .background(RemoteTheme.colors.userMessage)
                .padding(horizontal = 15.dp, vertical = 12.dp)
                .semantics(mergeDescendants = true) {},
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            if (message.text.isNotBlank()) Text(message.text, style = MaterialTheme.typography.bodyLarge)
            AttachmentList(message.attachments, onOpenAttachment)
            MessageMetadata(message)
        }
    }
}

@Composable
private fun AssistantMessage(
    message: ConversationMessageUiModel,
    onOpenAttachment: (String) -> Unit,
    modifier: Modifier,
) {
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                text = message.title ?: stringResource(R.string.conversation_assistant_label),
                style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold),
                color = RemoteTheme.colors.accent,
                modifier = Modifier.semantics { heading() },
            )
            if (message.state != ConversationItemState.Info && message.state != ConversationItemState.Succeeded) {
                MessageStateText(message.state)
            }
        }
        CollapsibleReasoning(message.reasoning)
        if (message.text.isNotBlank()) Text(message.text, style = MaterialTheme.typography.bodyLarge)
        AttachmentList(message.attachments, onOpenAttachment)
        DetailList(message.details)
        MessageMetadata(message)
    }
}

@Composable
private fun ToolMessage(
    message: ConversationMessageUiModel,
    onOpenAttachment: (String) -> Unit,
    modifier: Modifier,
) {
    var expanded by remember(message.id) { mutableStateOf(message.state == ConversationItemState.Failed) }
    val stateDescription = messageStateLabel(message.state)
    val visibleTitle = message.title ?: stringResource(R.string.tool_default_title)
    val disclosureState = stringResource(
        if (expanded) R.string.detail_state_expanded else R.string.detail_state_collapsed,
    )
    val contentPadding = if (expanded) PaddingValues(12.dp) else PaddingValues(vertical = 6.dp)
    Column(
        modifier = modifier
            .fillMaxWidth()
            .then(
                if (expanded) {
                    Modifier
                        .clip(RoundedCornerShape(RemoteDimens.rowRadius))
                        .background(RemoteTheme.colors.raisedSurface)
                } else {
                    Modifier
                },
            )
            .heightIn(min = 48.dp)
            .clickable(role = Role.Button) { expanded = !expanded }
            .padding(contentPadding)
            .semantics {
                role = Role.Button
                this.stateDescription = disclosureState
                contentDescription = listOfNotNull(
                    visibleTitle,
                    stateDescription,
                    message.text.takeIf { it.isNotBlank() },
                ).joinToString(". ")
            },
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(9.dp)) {
            Icon(
                imageVector = toolIcon(message.toolCard),
                contentDescription = null,
                tint = RemoteTheme.colors.tool,
                modifier = Modifier.size(19.dp),
            )
            Column(Modifier.weight(1f)) {
                Text(
                    text = visibleTitle,
                    style = MaterialTheme.typography.labelLarge,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                if (message.text.isNotBlank()) {
                    Text(
                        text = message.text,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = if (expanded) 8 else 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            if (message.state != ConversationItemState.Info) MessageStateText(message.state)
            Icon(
                imageVector = if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                contentDescription = null,
            )
        }
        if (expanded) {
            HorizontalDivider(color = RemoteTheme.colors.hairline)
            CollapsibleReasoning(message.reasoning, initiallyExpanded = true)
            DetailList(message.details)
            AttachmentList(message.attachments, onOpenAttachment)
            MessageMetadata(message)
        }
    }
}

@Composable
private fun ContextMessage(
    message: ConversationMessageUiModel,
    onOpenAttachment: (String) -> Unit,
    modifier: Modifier,
) {
    var expanded by remember(message.id) { mutableStateOf(false) }
    val disclosureState = stringResource(
        if (expanded) R.string.detail_state_expanded else R.string.detail_state_collapsed,
    )
    Column(
        modifier = modifier
            .fillMaxWidth()
            .then(
                if (expanded) {
                    Modifier
                        .clip(RoundedCornerShape(RemoteDimens.controlRadius))
                        .background(RemoteTheme.colors.raisedSurface)
                        .padding(horizontal = 10.dp, vertical = 6.dp)
                } else {
                    Modifier
                },
            ),
        verticalArrangement = Arrangement.spacedBy(7.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 48.dp)
                .clickable(role = Role.Button) { expanded = !expanded }
                .semantics { stateDescription = disclosureState }
                .padding(vertical = 2.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Default.Description, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.padding(4.dp))
            Column(Modifier.weight(1f)) {
                Text(message.title ?: stringResource(R.string.context_default_title), style = MaterialTheme.typography.labelLarge)
                Text(message.text, style = MaterialTheme.typography.bodyMedium, maxLines = if (expanded) 8 else 2)
            }
            Icon(
                if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                contentDescription = null,
            )
        }
        if (expanded) {
            DetailList(message.details)
            AttachmentList(message.attachments, onOpenAttachment)
            MessageMetadata(message)
        }
    }
}

@Composable
private fun CollapsibleReasoning(reasoning: String?, initiallyExpanded: Boolean = false) {
    if (reasoning.isNullOrBlank()) return
    var expanded by remember(reasoning) { mutableStateOf(initiallyExpanded) }
    val disclosureState = stringResource(
        if (expanded) R.string.detail_state_expanded else R.string.detail_state_collapsed,
    )
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .then(
                if (expanded) {
                    Modifier
                        .clip(RoundedCornerShape(RemoteDimens.controlRadius))
                        .background(RemoteTheme.colors.mutedSurface)
                        .padding(horizontal = 10.dp, vertical = 4.dp)
                } else {
                    Modifier
                },
            ),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 48.dp)
                .clickable(role = Role.Button) { expanded = !expanded }
                .semantics { stateDescription = disclosureState },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                stringResource(R.string.reasoning_title),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.weight(1f),
            )
            Icon(
                if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        if (expanded) {
            Text(
                reasoning,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 8.dp),
            )
        }
    }
}

@Composable
fun DetailList(details: List<DetailSectionUiModel>, modifier: Modifier = Modifier) {
    if (details.isEmpty()) return
    Column(modifier = modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        details.forEach { detail -> DetailSection(detail) }
    }
}

@Composable
private fun DetailSection(detail: DetailSectionUiModel) {
    var expanded by remember(detail.id) { mutableStateOf(detail.kind == DetailSectionKind.Diff) }
    val isCode = detail.kind == DetailSectionKind.Code || detail.kind == DetailSectionKind.Diff
    val disclosureState = stringResource(
        if (expanded) R.string.detail_state_expanded else R.string.detail_state_collapsed,
    )
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .background(if (isCode) RemoteTheme.colors.codeSurface else RemoteTheme.colors.mutedSurface),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 48.dp)
                .clickable(role = Role.Button) { expanded = !expanded }
                .semantics { stateDescription = disclosureState }
                .padding(horizontal = 10.dp, vertical = 9.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(
                if (isCode) Icons.Default.Code else Icons.Default.Description,
                contentDescription = null,
                modifier = Modifier.size(17.dp),
            )
            Text(
                detail.title ?: detail.language ?: stringResource(R.string.detail_default_title),
                style = MaterialTheme.typography.labelMedium,
                modifier = Modifier.weight(1f),
            )
            Icon(
                if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                contentDescription = null,
                modifier = Modifier.size(18.dp),
            )
        }
        if (expanded) {
            HorizontalDivider(color = RemoteTheme.colors.hairline)
            Text(
                text = detail.content,
                style = MaterialTheme.typography.bodyMedium.copy(
                    fontFamily = if (isCode) FontFamily.Monospace else FontFamily.Default,
                ),
                modifier = Modifier
                    .then(if (isCode) Modifier.horizontalScroll(rememberScrollState()) else Modifier)
                    .padding(10.dp),
                color = if (detail.kind == DetailSectionKind.Diff) RemoteTheme.colors.success
                else MaterialTheme.colorScheme.onSurface,
            )
        }
    }
}

@Composable
fun AttachmentList(
    attachments: List<ImageAttachmentUiModel>,
    onOpenAttachment: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (attachments.isEmpty()) return
    val defaultImageLabel = stringResource(R.string.attachment_image)
    var pendingPreviewId by remember { mutableStateOf<String?>(null) }
    var selectedPreviewId by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(attachments, pendingPreviewId) {
        val pending = pendingPreviewId ?: return@LaunchedEffect
        val attachment = attachments.firstOrNull { it.id == pending } ?: return@LaunchedEffect
        if (!attachment.previewUri.isNullOrBlank()) {
            selectedPreviewId = pending
            pendingPreviewId = null
        } else if (attachment.errorMessage != null) {
            pendingPreviewId = null
        }
    }
    val openAttachment: (ImageAttachmentUiModel) -> Unit = { attachment ->
        if (!attachment.previewUri.isNullOrBlank()) {
            selectedPreviewId = attachment.id
        } else if (!attachment.isLoading) {
            pendingPreviewId = attachment.id
            onOpenAttachment(attachment.id)
        }
    }

    Column(modifier = modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (attachments.size == 1) {
            AttachmentTile(
                attachment = attachments.first(),
                defaultImageLabel = defaultImageLabel,
                large = true,
                onClick = { openAttachment(attachments.first()) },
            )
        } else {
            attachments.chunked(2).forEach { rowAttachments ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    rowAttachments.forEach { attachment ->
                        AttachmentTile(
                            attachment = attachment,
                            defaultImageLabel = defaultImageLabel,
                            large = false,
                            onClick = { openAttachment(attachment) },
                            modifier = Modifier.weight(1f),
                        )
                    }
                    if (rowAttachments.size == 1) Spacer(Modifier.weight(1f))
                }
            }
        }
    }

    selectedPreviewId?.let { selectedId ->
        attachments.firstOrNull { it.id == selectedId }?.let { attachment ->
            AttachmentPreviewDialog(
                attachment = attachment,
                defaultImageLabel = defaultImageLabel,
                onDismiss = { selectedPreviewId = null },
            )
        }
    }
}

@Composable
private fun AttachmentTile(
    attachment: ImageAttachmentUiModel,
    defaultImageLabel: String,
    large: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val label = attachment.name ?: defaultImageLabel
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(12.dp))
            .background(RemoteTheme.colors.mutedSurface)
            .clickable(enabled = !attachment.isLoading, role = Role.Button, onClick = onClick)
            .semantics {
                contentDescription = listOfNotNull(
                    label,
                    "${attachment.width} × ${attachment.height}",
                    attachment.sizeLabel,
                    attachment.errorMessage,
                ).joinToString(". ")
            },
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(if (large) 220.dp else 126.dp),
            contentAlignment = Alignment.Center,
        ) {
            when {
                attachment.isLoading -> CircularProgressIndicator(Modifier.size(26.dp), strokeWidth = 2.dp)
                attachment.errorMessage != null -> Icon(
                    Icons.Default.BrokenImage,
                    null,
                    tint = RemoteTheme.colors.danger,
                    modifier = Modifier.size(28.dp),
                )
                else -> RemoteImagePreview(
                    uri = attachment.previewUri,
                    contentDescription = null,
                    modifier = Modifier.fillMaxWidth().height(if (large) 220.dp else 126.dp),
                    contentScale = if (large) ContentScale.Fit else ContentScale.Crop,
                )
            }
        }
        Column(Modifier.padding(horizontal = 10.dp, vertical = 8.dp)) {
            Text(
                label,
                style = MaterialTheme.typography.labelLarge,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                attachment.errorMessage ?: "${attachment.width} × ${attachment.height} · ${attachment.sizeLabel}",
                style = MaterialTheme.typography.labelSmall,
                color = if (attachment.errorMessage != null) RemoteTheme.colors.danger
                else MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun AttachmentPreviewDialog(
    attachment: ImageAttachmentUiModel,
    defaultImageLabel: String,
    onDismiss: () -> Unit,
) {
    val label = attachment.name ?: defaultImageLabel
    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(label, maxLines = 2, overflow = TextOverflow.Ellipsis)
        },
        text = {
            RemoteImagePreview(
                uri = attachment.previewUri,
                contentDescription = label,
                modifier = Modifier.fillMaxWidth().heightIn(min = 220.dp, max = 520.dp),
            )
        },
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Icon(Icons.Default.Close, contentDescription = null)
                Text(
                    text = stringResource(R.string.attachment_preview_close),
                    modifier = Modifier.padding(start = 6.dp),
                )
            }
        },
        containerColor = RemoteTheme.colors.surface,
        tonalElevation = 0.dp,
    )
}

@Composable
private fun MessageMetadata(message: ConversationMessageUiModel) {
    val metadata = message.metadata + listOfNotNull(message.timestampLabel.takeIf(String::isNotBlank))
    if (metadata.isNotEmpty()) {
        Text(
            metadata.joinToString(" · "),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun MessageStateText(state: ConversationItemState) {
    Text(
        text = messageStateLabel(state),
        style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.SemiBold),
        color = messageStateColor(state),
    )
}

@Composable
private fun messageStateLabel(state: ConversationItemState): String = stringResource(
    when (state) {
        ConversationItemState.Info -> R.string.item_state_info
        ConversationItemState.Running -> R.string.item_state_running
        ConversationItemState.Succeeded -> R.string.item_state_succeeded
        ConversationItemState.Failed -> R.string.item_state_failed
        ConversationItemState.Stopped -> R.string.item_state_stopped
    },
)

@Composable
private fun messageStateColor(state: ConversationItemState): Color = when (state) {
    ConversationItemState.Info -> MaterialTheme.colorScheme.onSurfaceVariant
    ConversationItemState.Running -> RemoteTheme.colors.accent
    ConversationItemState.Succeeded -> RemoteTheme.colors.success
    ConversationItemState.Failed -> RemoteTheme.colors.danger
    ConversationItemState.Stopped -> RemoteTheme.colors.warning
}

private fun noticeTone(state: ConversationItemState): RemoteNoticeTone = when (state) {
    ConversationItemState.Failed -> RemoteNoticeTone.Danger
    ConversationItemState.Stopped -> RemoteNoticeTone.Warning
    ConversationItemState.Succeeded -> RemoteNoticeTone.Success
    ConversationItemState.Info, ConversationItemState.Running -> RemoteNoticeTone.Information
}

private fun toolIcon(card: ToolCardKind?): ImageVector = when (card) {
    ToolCardKind.Terminal -> Icons.Default.Terminal
    ToolCardKind.Search, ToolCardKind.Web -> Icons.Default.TravelExplore
    ToolCardKind.Diff, ToolCardKind.Read -> Icons.Default.Code
    ToolCardKind.Generic, null -> Icons.Default.Description
}
