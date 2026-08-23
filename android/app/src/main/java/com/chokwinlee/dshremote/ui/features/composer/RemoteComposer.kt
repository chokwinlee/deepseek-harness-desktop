package com.chokwinlee.dshremote.ui.features.composer

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.automirrored.filled.InsertDriveFile
import androidx.compose.material.icons.filled.AlternateEmail
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.AttachFile
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Psychology
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.chokwinlee.dshremote.R
import com.chokwinlee.dshremote.ui.components.RemoteInlineNotice
import com.chokwinlee.dshremote.ui.components.RemoteNoticeTone
import com.chokwinlee.dshremote.ui.features.images.RemoteImageThumbnail
import com.chokwinlee.dshremote.ui.model.PromptDeliveryUi
import com.chokwinlee.dshremote.ui.model.PromptImageUiModel
import com.chokwinlee.dshremote.ui.model.ReferenceCandidateKind
import com.chokwinlee.dshremote.ui.model.ReferenceCandidateUiModel
import com.chokwinlee.dshremote.ui.model.ReferenceSuggestionsUiState
import com.chokwinlee.dshremote.ui.model.SessionDetailCallbacks
import com.chokwinlee.dshremote.ui.model.SessionDetailUiState
import com.chokwinlee.dshremote.ui.theme.RemoteDimens
import com.chokwinlee.dshremote.ui.theme.RemoteTheme
import kotlinx.coroutines.delay

internal const val COMPOSER_ERROR_TEST_TAG = "composer-error"

@Composable
fun RemoteComposer(
    state: SessionDetailUiState,
    callbacks: SessionDetailCallbacks,
    onOpenModels: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val session = state.session ?: return
    var draft by rememberSaveable(session.id, stateSaver = TextFieldValue.Saver) {
        mutableStateOf(TextFieldValue())
    }
    var draftReferences by rememberSaveable(session.id, stateSaver = DraftReferencesSaver) {
        mutableStateOf(emptyList())
    }
    var composerNotice by rememberSaveable(session.id) { mutableStateOf<String?>(null) }
    var delivery by rememberSaveable(session.id) {
        mutableStateOf(if (session.state == com.chokwinlee.dshremote.ui.model.SessionExecutionState.Running) PromptDeliveryUi.Queue else PromptDeliveryUi.Send)
    }
    var deliveryMenu by remember { mutableStateOf(false) }
    var mediaMenu by remember { mutableStateOf(false) }
    var manualReferenceSearch by remember { mutableStateOf(false) }
    val focusManager = LocalFocusManager.current
    val isRunning = session.state == com.chokwinlee.dshremote.ui.model.SessionExecutionState.Running
    val composerInputLabel = stringResource(R.string.composer_input_label)
    val invalidReferenceMessage = stringResource(R.string.reference_path_invalid)
    val sessionReferenceLimitMessage = pluralStringResource(
        R.plurals.reference_session_limit,
        MAX_SESSION_REFERENCES,
        MAX_SESSION_REFERENCES,
    )
    val referenceToken = remember(draft.text, draft.selection, draftReferences) {
        if (!draft.selection.collapsed) {
            null
        } else {
            activeReferenceToken(draft.text, draft.selection.end)?.takeIf { token ->
                draftReferences.none { reference ->
                    token.start < reference.endExclusive && token.endExclusive > reference.start
                }
            }
        }
    }
    val referenceQuery = referenceToken?.query

    LaunchedEffect(isRunning) {
        if (!isRunning) delivery = PromptDeliveryUi.Send
        else if (delivery == PromptDeliveryUi.Send) delivery = PromptDeliveryUi.Queue
    }
    LaunchedEffect(referenceQuery, manualReferenceSearch) {
        val query = when {
            referenceQuery != null -> referenceQuery
            manualReferenceSearch -> ""
            else -> return@LaunchedEffect
        }
        delay(180)
        callbacks.onSearchReferences(query)
    }

    val enabled = !state.isSending && !state.isCancelling && state.interaction == null
    val submitPrompt = {
        if (canSubmit(draft.text, state)) {
            callbacks.onSendPrompt(submissionText(draft.text, draftReferences).trim(), delivery)
            draft = TextFieldValue()
            draftReferences = emptyList()
            composerNotice = null
            focusManager.clearFocus()
        }
    }
    val composerField: @Composable (Modifier) -> Unit = { fieldModifier ->
        TextField(
            value = draft,
            onValueChange = { updated ->
                draftReferences = updateDraftReferences(draft.text, updated.text, draftReferences)
                draft = updated
                composerNotice = null
            },
            modifier = fieldModifier
                .heightIn(min = 54.dp, max = 144.dp)
                .semantics { contentDescription = composerInputLabel },
            enabled = enabled,
            placeholder = { Text(stringResource(R.string.composer_placeholder)) },
            shape = RoundedCornerShape(RemoteDimens.composerRadius),
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
            keyboardActions = KeyboardActions(
                onSend = {
                    if (!isRunning) submitPrompt()
                },
            ),
            colors = TextFieldDefaults.colors(
                focusedContainerColor = RemoteTheme.colors.raisedSurface,
                unfocusedContainerColor = RemoteTheme.colors.raisedSurface,
                disabledContainerColor = RemoteTheme.colors.raisedSurface.copy(alpha = 0.60f),
                focusedIndicatorColor = Color.Transparent,
                unfocusedIndicatorColor = Color.Transparent,
                disabledIndicatorColor = Color.Transparent,
            ),
        )
    }
    val actionButtons: @Composable RowScope.() -> Unit = {
        if (isRunning) {
            IconButton(
                onClick = callbacks.onStopSession,
                enabled = !state.isCancelling,
                modifier = Modifier
                    .size(48.dp)
                    .clip(RoundedCornerShape(15.dp))
                    .background(RemoteTheme.colors.danger.copy(alpha = 0.11f)),
            ) {
                if (state.isCancelling) {
                    CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp, color = RemoteTheme.colors.danger)
                } else {
                    Icon(Icons.Default.Stop, stringResource(R.string.conversation_stop), tint = RemoteTheme.colors.danger)
                }
            }
            Box {
                IconButton(
                    onClick = { deliveryMenu = true },
                    enabled = enabled,
                    modifier = Modifier
                        .size(48.dp)
                        .clip(RoundedCornerShape(15.dp))
                        .background(RemoteTheme.colors.raisedSurface),
                ) {
                    Icon(
                        Icons.Default.ArrowDropDown,
                        stringResource(R.string.composer_delivery_options),
                        tint = RemoteTheme.colors.accent,
                    )
                }
                DropdownMenu(expanded = deliveryMenu, onDismissRequest = { deliveryMenu = false }) {
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.composer_queue)) },
                        onClick = { delivery = PromptDeliveryUi.Queue; deliveryMenu = false },
                    )
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.composer_steer)) },
                        onClick = { delivery = PromptDeliveryUi.Steer; deliveryMenu = false },
                    )
                }
            }
        }
        IconButton(
            onClick = submitPrompt,
            enabled = canSubmit(draft.text, state),
            modifier = Modifier
                .size(48.dp)
                .clip(RoundedCornerShape(15.dp))
                .background(RemoteTheme.colors.accentFill),
        ) {
            if (state.isSending) {
                CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp, color = Color.White)
            } else {
                Icon(
                    Icons.AutoMirrored.Filled.Send,
                    stringResource(deliveryDescription(delivery)),
                    tint = Color.White,
                )
            }
        }
    }
    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(RemoteTheme.colors.surface)
            .navigationBarsPadding()
            .imePadding(),
    ) {
        if (state.pendingImages.isNotEmpty() || state.isPreparingImages) {
            PendingImageRow(
                images = state.pendingImages,
                isPreparing = state.isPreparingImages,
                onRemove = callbacks.onRemovePendingImage,
            )
        }
        val showReferences = (referenceQuery != null || manualReferenceSearch) &&
            (state.references.isLoading || state.references.errorMessage != null || state.references.candidates.isNotEmpty())
        if (showReferences) {
            ReferenceSuggestions(
                state = state.references,
                onSelect = { candidate ->
                    val token = referenceToken ?: return@ReferenceSuggestions
                    val insertion = when (candidate.kind) {
                        ReferenceCandidateKind.File, ReferenceCandidateKind.Directory -> {
                            val formatted = formattedFileMention(
                                pathValue = candidate.mention,
                                kind = candidate.kind,
                                preserveQuote = token.quoted,
                            )
                            if (formatted == null) {
                                composerNotice = invalidReferenceMessage
                                return@ReferenceSuggestions
                            }
                            insertReference(
                                oldText = draft.text,
                                oldReferences = draftReferences,
                                token = token,
                                displayText = formatted,
                                submissionText = formatted.takeIf { candidate.kind == ReferenceCandidateKind.File },
                                kind = candidate.kind,
                                appendSpace = candidate.kind == ReferenceCandidateKind.File,
                            )
                        }
                        ReferenceCandidateKind.Session -> {
                            if (draftReferences.count { it.kind == ReferenceCandidateKind.Session } >= MAX_SESSION_REFERENCES) {
                                composerNotice = sessionReferenceLimitMessage
                                return@ReferenceSuggestions
                            }
                            insertReference(
                                oldText = draft.text,
                                oldReferences = draftReferences,
                                token = token,
                                displayText = "@${candidate.label}",
                                submissionText = candidate.mention,
                                kind = candidate.kind,
                                appendSpace = true,
                            )
                        }
                    }
                    draft = TextFieldValue(insertion.text, TextRange(insertion.cursor))
                    draftReferences = insertion.references
                    manualReferenceSearch = candidate.kind == ReferenceCandidateKind.Directory
                    composerNotice = null
                    callbacks.onReferenceSelected(candidate)
                },
                onClose = { manualReferenceSearch = false },
            )
        }
        composerNotice?.let { notice ->
            RemoteInlineNotice(
                title = stringResource(R.string.reference_notice_title),
                message = notice,
                tone = RemoteNoticeTone.Warning,
                actionText = stringResource(R.string.action_close),
                onAction = { composerNotice = null },
                modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
            )
        }
        state.errorMessage?.let { error ->
            RemoteInlineNotice(
                title = stringResource(R.string.composer_error_title),
                message = error,
                tone = RemoteNoticeTone.Danger,
                actionText = stringResource(R.string.action_close),
                onAction = callbacks.onDismissError,
                modifier = Modifier
                    .padding(horizontal = 10.dp, vertical = 4.dp)
                    .testTag(COMPOSER_ERROR_TEST_TAG),
            )
        }
        Row(
            modifier = Modifier.fillMaxWidth().padding(start = 8.dp, end = 8.dp, top = 7.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box {
                IconButton(
                    onClick = { mediaMenu = true },
                    enabled = enabled && state.imageInputAvailable && !state.isPreparingImages,
                ) {
                    Icon(Icons.Default.AttachFile, stringResource(R.string.composer_add_images))
                }
                DropdownMenu(expanded = mediaMenu, onDismissRequest = { mediaMenu = false }) {
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.composer_choose_images)) },
                        onClick = {
                            mediaMenu = false
                            callbacks.onPickImages()
                        },
                    )
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.composer_paste_image)) },
                        onClick = {
                            mediaMenu = false
                            callbacks.onPasteImages()
                        },
                        leadingIcon = { Icon(Icons.Default.ContentPaste, contentDescription = null) },
                    )
                }
            }
            IconButton(
                onClick = {
                    manualReferenceSearch = !manualReferenceSearch
                    if (referenceToken == null) {
                        val start = draft.selection.min
                        val end = draft.selection.max
                        val prefixNeedsSpace = start > 0 && !draft.text[start - 1].isWhitespace()
                        val insertion = if (prefixNeedsSpace) " @" else "@"
                        val updatedText = draft.text.replaceRange(start, end, insertion)
                        draftReferences = updateDraftReferences(draft.text, updatedText, draftReferences)
                        draft = TextFieldValue(updatedText, TextRange(start + insertion.length))
                    }
                },
                enabled = enabled && state.references.isSupported,
            ) {
                Icon(Icons.Default.AlternateEmail, stringResource(R.string.composer_add_reference))
            }
            TextButton(onClick = onOpenModels, enabled = enabled && !state.models.isSelecting) {
                Icon(Icons.Default.Psychology, contentDescription = null, modifier = Modifier.size(17.dp))
                Spacer(Modifier.width(5.dp))
                Text(
                    state.models.current?.let { selection ->
                        listOfNotNull(selection.modelName, selection.reasoningEffortName).joinToString(" · ")
                    } ?: stringResource(R.string.model_default_label),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            Spacer(Modifier.weight(1f))
            state.imageLimitLabel?.let {
                Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        BoxWithConstraints(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 8.dp),
        ) {
            val stackActions = maxWidth < 360.dp || LocalDensity.current.fontScale >= 1.4f
            if (stackActions) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    composerField(Modifier.fillMaxWidth())
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(7.dp, Alignment.End),
                        verticalAlignment = Alignment.CenterVertically,
                        content = actionButtons,
                    )
                }
            } else {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.Bottom,
                    horizontalArrangement = Arrangement.spacedBy(7.dp),
                ) {
                    composerField(Modifier.weight(1f))
                    actionButtons()
                }
            }
        }
        if (state.interaction != null) {
            Text(
                stringResource(R.string.composer_disabled_interaction),
                style = MaterialTheme.typography.labelSmall,
                color = RemoteTheme.colors.warning,
                modifier = Modifier.padding(horizontal = RemoteDimens.pagePadding, vertical = 3.dp).semantics {
                    liveRegion = LiveRegionMode.Polite
                },
            )
        } else if (isRunning) {
            Text(
                stringResource(
                    if (delivery == PromptDeliveryUi.Steer) R.string.composer_steer_hint else R.string.composer_queue_hint,
                ),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = RemoteDimens.pagePadding, vertical = 3.dp),
            )
        }
    }
}

@Composable
private fun PendingImageRow(
    images: List<PromptImageUiModel>,
    isPreparing: Boolean,
    onRemove: (String) -> Unit,
) {
    LazyRow(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 7.dp),
        horizontalArrangement = Arrangement.spacedBy(7.dp),
    ) {
        items(images, key = PromptImageUiModel::id) { image ->
            val imageDescription = listOfNotNull(
                image.name ?: stringResource(R.string.attachment_image),
                image.dimensionsLabel,
                image.sizeLabel,
                image.errorMessage,
            ).joinToString(". ")
            Row(
                modifier = Modifier
                    .clip(RoundedCornerShape(11.dp))
                    .background(
                        if (image.errorMessage != null) RemoteTheme.colors.danger.copy(alpha = 0.10f)
                        else RemoteTheme.colors.raisedSurface,
                    )
                    .padding(start = 9.dp, top = 6.dp, bottom = 6.dp)
                    .semantics(mergeDescendants = true) { contentDescription = imageDescription },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (image.isPreparing) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                else RemoteImageThumbnail(uri = image.previewUri, contentDescription = null)
                Spacer(Modifier.width(6.dp))
                Text(
                    image.name ?: stringResource(R.string.attachment_image),
                    style = MaterialTheme.typography.labelMedium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                IconButton(onClick = { onRemove(image.id) }, modifier = Modifier.size(48.dp)) {
                    Icon(Icons.Default.Close, stringResource(R.string.attachment_remove), modifier = Modifier.size(17.dp))
                }
            }
        }
        if (isPreparing && images.none(PromptImageUiModel::isPreparing)) {
            item("preparing") {
                Row(
                    modifier = Modifier.clip(RoundedCornerShape(11.dp)).background(RemoteTheme.colors.raisedSurface).padding(10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                    Spacer(Modifier.width(7.dp))
                    Text(stringResource(R.string.attachment_preparing), style = MaterialTheme.typography.labelMedium)
                }
            }
        }
    }
}

@Composable
private fun ReferenceSuggestions(
    state: ReferenceSuggestionsUiState,
    onSelect: (ReferenceCandidateUiModel) -> Unit,
    onClose: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(RemoteTheme.colors.raisedSurface)
            .padding(horizontal = 10.dp, vertical = 7.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.reference_title),
                style = MaterialTheme.typography.labelLarge,
                modifier = Modifier.weight(1f),
            )
            if (state.isLoading) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
            IconButton(onClick = onClose, modifier = Modifier.size(48.dp)) {
                Icon(Icons.Default.Close, stringResource(R.string.action_close), modifier = Modifier.size(17.dp))
            }
        }
        state.errorMessage?.let {
            RemoteInlineNotice(
                title = stringResource(R.string.reference_failed),
                message = it,
                tone = RemoteNoticeTone.Danger,
            )
        }
        state.candidates.take(6).forEach { candidate ->
            val candidateDescription = listOfNotNull(candidate.label, candidate.detail).joinToString(". ")
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(8.dp))
                    .clickable(role = Role.Button) { onSelect(candidate) }
                    .padding(horizontal = 8.dp, vertical = 8.dp)
                    .semantics { contentDescription = candidateDescription; role = Role.Button },
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(9.dp),
            ) {
                Icon(referenceIcon(candidate.kind), contentDescription = null, modifier = Modifier.size(18.dp))
                Column(Modifier.weight(1f)) {
                    Text(candidate.label, style = MaterialTheme.typography.bodyMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    candidate.detail?.let {
                        Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
    HorizontalDivider(color = RemoteTheme.colors.hairline)
}

private fun canSubmit(draft: String, state: SessionDetailUiState): Boolean =
    (draft.isNotBlank() || state.pendingImages.isNotEmpty()) &&
        !state.isSending && !state.isCancelling && !state.isPreparingImages && state.interaction == null

private fun referenceIcon(kind: ReferenceCandidateKind): ImageVector = when (kind) {
    ReferenceCandidateKind.File -> Icons.AutoMirrored.Filled.InsertDriveFile
    ReferenceCandidateKind.Directory -> Icons.Default.Folder
    ReferenceCandidateKind.Session -> Icons.Default.History
}

private fun deliveryDescription(delivery: PromptDeliveryUi): Int = when (delivery) {
    PromptDeliveryUi.Send -> R.string.conversation_send
    PromptDeliveryUi.Queue -> R.string.composer_queue
    PromptDeliveryUi.Steer -> R.string.composer_steer
}

private const val MAX_SESSION_REFERENCES = 3

private val DraftReferencesSaver = listSaver<List<DraftReference>, String>(
    save = { references ->
        references.flatMap { reference ->
            listOf(
                reference.start.toString(),
                reference.endExclusive.toString(),
                reference.displayText,
                reference.submissionText,
                reference.kind.name,
            )
        }
    },
    restore = { values ->
        values.chunked(5).mapNotNull { fields ->
            if (fields.size != 5) return@mapNotNull null
            val start = fields[0].toIntOrNull() ?: return@mapNotNull null
            val end = fields[1].toIntOrNull() ?: return@mapNotNull null
            val kind = runCatching { ReferenceCandidateKind.valueOf(fields[4]) }.getOrNull()
                ?: return@mapNotNull null
            DraftReference(start, end, fields[2], fields[3], kind)
        }
    },
)
