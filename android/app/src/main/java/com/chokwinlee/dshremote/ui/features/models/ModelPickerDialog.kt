package com.chokwinlee.dshremote.ui.features.models

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.chokwinlee.dshremote.R
import com.chokwinlee.dshremote.ui.components.RemoteInlineNotice
import com.chokwinlee.dshremote.ui.components.RemoteNoticeTone
import com.chokwinlee.dshremote.ui.model.ModelDirectoryUiState
import com.chokwinlee.dshremote.ui.model.ModelOptionUiModel
import com.chokwinlee.dshremote.ui.model.ModelProviderGroupUiModel
import com.chokwinlee.dshremote.ui.model.ModelSelectionUiModel
import com.chokwinlee.dshremote.ui.theme.RemoteTheme

@Composable
fun ModelPickerDialog(
    state: ModelDirectoryUiState,
    onLoad: () -> Unit,
    onDismiss: () -> Unit,
    onSelect: (selection: ModelSelectionUiModel, onResult: (Boolean) -> Unit) -> Unit,
) {
    var selectedProviderId by remember(state.current) { mutableStateOf(state.current?.providerId) }
    var selectedModelId by remember(state.current) { mutableStateOf(state.current?.modelId) }
    var selectedEffortId by remember(state.current) { mutableStateOf(state.current?.reasoningEffortId) }
    var awaitingResult by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { onLoad() }

    val selected = state.groups.findModel(selectedProviderId, selectedModelId)
    val selectedIsCurrent = selectedProviderId == state.current?.providerId &&
        selectedModelId == state.current?.modelId
    AlertDialog(
        onDismissRequest = { if (!state.isSelecting && !awaitingResult) onDismiss() },
        title = { Text(stringResource(R.string.model_picker_title)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                if (!state.routable) {
                    RemoteInlineNotice(
                        title = stringResource(R.string.model_unroutable_title),
                        message = stringResource(R.string.model_unroutable_message),
                        tone = RemoteNoticeTone.Warning,
                    )
                }
                if (state.groups.any { it.models.isNotEmpty() }) {
                    RemoteInlineNotice(
                        title = stringResource(R.string.model_scope_title),
                        message = stringResource(R.string.model_scope_message),
                        tone = RemoteNoticeTone.Information,
                    )
                }
                if (state.errorMessage != null) {
                    RemoteInlineNotice(
                        title = stringResource(R.string.model_load_failed),
                        message = state.errorMessage,
                        tone = RemoteNoticeTone.Danger,
                        actionText = stringResource(R.string.action_retry),
                        onAction = onLoad,
                    )
                }
                if (state.isLoading && state.groups.isEmpty()) {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(24.dp),
                        horizontalArrangement = Arrangement.Center,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        CircularProgressIndicator(strokeWidth = 2.dp)
                    }
                } else if (state.groups.isEmpty() && state.errorMessage == null) {
                    Text(
                        stringResource(R.string.model_empty),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                } else {
                    LazyColumn(
                        modifier = Modifier.fillMaxWidth().heightIn(max = 390.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        state.groups.forEach { group ->
                            item(key = "provider-${group.id}") {
                                Text(
                                    group.name,
                                    style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold),
                                    color = RemoteTheme.colors.accent,
                                    modifier = Modifier.padding(top = 8.dp, bottom = 2.dp).semantics { heading() },
                                )
                            }
                            items(group.models, key = { "${group.id}:${it.id}" }) { model ->
                                ModelRow(
                                    group = group,
                                    model = model,
                                    selected = selectedProviderId == group.id && selectedModelId == model.id,
                                    onClick = {
                                        selectedProviderId = group.id
                                        selectedModelId = model.id
                                        selectedEffortId = model.defaultReasoningEffortId
                                    },
                                )
                            }
                        }
                    }
                    if (selected != null && selected.second.reasoningEfforts.isNotEmpty()) {
                        HorizontalDivider(color = RemoteTheme.colors.hairline)
                        Text(
                            stringResource(R.string.reasoning_effort_title),
                            style = MaterialTheme.typography.labelLarge,
                        )
                        selected.second.reasoningEfforts.forEach { effort ->
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clip(RoundedCornerShape(10.dp))
                                    .clickable(role = Role.RadioButton) { selectedEffortId = effort.id }
                                    .padding(vertical = 2.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                RadioButton(selected = selectedEffortId == effort.id, onClick = null)
                                Column(Modifier.weight(1f)) {
                                    Text(effort.name, style = MaterialTheme.typography.bodyMedium)
                                    effort.description?.let {
                                        Text(
                                            it,
                                            style = MaterialTheme.typography.labelSmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss, enabled = !state.isSelecting && !awaitingResult) {
                Text(stringResource(R.string.action_cancel))
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    val (group, model) = selected ?: return@TextButton
                    val effort = model.reasoningEfforts.firstOrNull { it.id == selectedEffortId }
                    awaitingResult = true
                    val selection = ModelSelectionUiModel(
                        providerId = group.id,
                        providerName = group.name,
                        modelId = model.id,
                        modelName = model.name,
                        reasoningEffortId = effort?.id,
                        reasoningEffortName = effort?.name,
                    )
                    onSelect(selection) { succeeded ->
                        awaitingResult = false
                        if (succeeded) onDismiss()
                    }
                },
                enabled = selected != null &&
                    !state.isSelecting &&
                    !awaitingResult &&
                    (state.routable || !selectedIsCurrent),
            ) {
                if (state.isSelecting || awaitingResult) {
                    CircularProgressIndicator(Modifier.padding(end = 8.dp), strokeWidth = 2.dp)
                }
                Text(stringResource(R.string.model_use_action))
            }
        },
    )
}

@Composable
private fun ModelRow(
    group: ModelProviderGroupUiModel,
    model: ModelOptionUiModel,
    selected: Boolean,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .clickable(role = Role.RadioButton, onClick = onClick)
            .padding(vertical = 3.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RadioButton(selected = selected, onClick = null)
        Column(Modifier.weight(1f)) {
            Text(model.name, style = MaterialTheme.typography.bodyMedium)
            model.description?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

private fun List<ModelProviderGroupUiModel>.findModel(
    providerId: String?,
    modelId: String?,
): Pair<ModelProviderGroupUiModel, ModelOptionUiModel>? {
    val group = firstOrNull { it.id == providerId } ?: return null
    val model = group.models.firstOrNull { it.id == modelId } ?: return null
    return group to model
}
