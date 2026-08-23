package com.chokwinlee.dshremote.ui.features.interaction

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.HelpOutline
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.EditNote
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.GppMaybe
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.chokwinlee.dshremote.R
import com.chokwinlee.dshremote.ui.components.RemoteActionButton
import com.chokwinlee.dshremote.ui.components.RemoteActionKind
import com.chokwinlee.dshremote.ui.components.RemoteInlineNotice
import com.chokwinlee.dshremote.ui.components.RemoteNoticeTone
import com.chokwinlee.dshremote.ui.model.InteractionDecisionUi
import com.chokwinlee.dshremote.ui.model.InteractionKindUi
import com.chokwinlee.dshremote.ui.model.InteractionUiModel
import com.chokwinlee.dshremote.ui.model.QuestionAnswerUiModel
import com.chokwinlee.dshremote.ui.model.QuestionOptionUiModel
import com.chokwinlee.dshremote.ui.model.StructuredQuestionUiModel
import com.chokwinlee.dshremote.ui.theme.RemoteDimens
import com.chokwinlee.dshremote.ui.theme.RemoteTheme

/** Sticky bottom action surface. Transcript state remains visible behind and above it. */
@Composable
fun InteractionPanel(
    interaction: InteractionUiModel,
    onResolve: (String, InteractionDecisionUi) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(RemoteTheme.colors.surface),
    ) {
        HorizontalDivider(color = RemoteTheme.colors.strongHairline)
        when (interaction.kind) {
            InteractionKindUi.Approval -> ApprovalSheet(interaction, onResolve)
            InteractionKindUi.Questions -> QuestionSheet(interaction, onResolve)
        }
    }
}

@Composable
private fun ApprovalSheet(
    interaction: InteractionUiModel,
    onResolve: (String, InteractionDecisionUi) -> Unit,
) {
    Column(Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier
                .weight(1f, fill = false)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = RemoteDimens.pagePadding, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            InteractionHeading(
                icon = { Icon(Icons.Default.GppMaybe, null, tint = RemoteTheme.colors.warning) },
                eyebrow = stringResource(R.string.interaction_pending_label),
                title = interaction.title,
            )
            interaction.toolName?.let {
                Text(
                    text = stringResource(R.string.approval_tool, it),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            interaction.detail?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
            interaction.errorMessage?.let {
                RemoteInlineNotice(
                    title = stringResource(R.string.interaction_failed),
                    message = it,
                    tone = RemoteNoticeTone.Danger,
                )
            }
        }
        StickyActions {
            RemoteActionButton(
                text = stringResource(R.string.approval_reject),
                onClick = { onResolve(interaction.id, InteractionDecisionUi.Reject) },
                kind = RemoteActionKind.Destructive,
                fillsWidth = false,
                enabled = !interaction.isResponding,
                modifier = Modifier.weight(1f),
            )
            RemoteActionButton(
                text = stringResource(R.string.approval_allow_once),
                onClick = { onResolve(interaction.id, InteractionDecisionUi.AllowOnce) },
                fillsWidth = false,
                enabled = !interaction.isResponding,
                modifier = Modifier.weight(1f),
            )
        }
    }
}

@Composable
private fun QuestionSheet(
    interaction: InteractionUiModel,
    onResolve: (String, InteractionDecisionUi) -> Unit,
) {
    val selections = remember(interaction.id) { mutableStateMapOf<String, Set<String>>() }
    val customAnswers = remember(interaction.id) { mutableStateMapOf<String, String>() }
    val customExpanded = remember(interaction.id) { mutableStateMapOf<String, Boolean>() }
    val complete = interaction.questions.all { question ->
        !selections[question.id].isNullOrEmpty() || !customAnswers[question.id].isNullOrBlank()
    }
    Column(Modifier.fillMaxWidth()) {
        LazyColumn(
            modifier = Modifier.weight(1f, fill = false),
            contentPadding = PaddingValues(horizontal = RemoteDimens.pagePadding, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            item("interaction-heading") {
                Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                    InteractionEyebrow(
                        icon = { Icon(Icons.AutoMirrored.Filled.HelpOutline, null, tint = RemoteTheme.colors.accent) },
                        text = stringResource(R.string.interaction_pending_label),
                    )
                    interaction.detail?.let {
                        Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            itemsIndexed(interaction.questions, key = { _, question -> question.id }) { index, question ->
                QuestionBlock(
                    index = index,
                    questionCount = interaction.questions.size,
                    question = question,
                    selected = selections[question.id].orEmpty(),
                    customAnswer = customAnswers[question.id].orEmpty(),
                    customIsExpanded = customExpanded[question.id] == true,
                    onOptionSelected = { option ->
                        val previous = selections[question.id].orEmpty()
                        selections[question.id] = if (question.allowsMultipleSelection) {
                            if (option in previous) previous - option else previous + option
                        } else {
                            setOf(option)
                        }
                    },
                    onCustomExpandedChange = { customExpanded[question.id] = it },
                    onCustomAnswerChange = { customAnswers[question.id] = it },
                )
            }
            interaction.errorMessage?.let { error ->
                item("interaction-error") {
                    RemoteInlineNotice(
                        title = stringResource(R.string.interaction_failed),
                        message = error,
                        tone = RemoteNoticeTone.Danger,
                    )
                }
            }
        }
        StickyActions {
            RemoteActionButton(
                text = stringResource(R.string.action_cancel),
                onClick = { onResolve(interaction.id, InteractionDecisionUi.CancelQuestions) },
                kind = RemoteActionKind.Secondary,
                fillsWidth = false,
                enabled = !interaction.isResponding,
                modifier = Modifier.weight(1f),
            )
            RemoteActionButton(
                text = stringResource(R.string.question_submit),
                onClick = {
                    onResolve(
                        interaction.id,
                        InteractionDecisionUi.Answer(
                            interaction.questions.map { question ->
                                QuestionAnswerUiModel(
                                    questionId = question.id,
                                    selected = selections[question.id].orEmpty().toList(),
                                    custom = customAnswers[question.id]?.trim()?.takeIf(String::isNotEmpty),
                                )
                            },
                        ),
                    )
                },
                fillsWidth = false,
                enabled = complete && !interaction.isResponding,
                modifier = Modifier.weight(1f),
            )
        }
    }
}

@Composable
private fun InteractionEyebrow(
    icon: @Composable () -> Unit,
    text: String,
) {
    Row(
        modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(9.dp),
    ) {
        Box(Modifier.size(20.dp), contentAlignment = Alignment.Center) { icon() }
        Text(
            text = text,
            style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun InteractionHeading(
    icon: @Composable () -> Unit,
    eyebrow: String,
    title: String,
) {
    Row(
        modifier = Modifier.semantics {
            heading()
            liveRegion = LiveRegionMode.Polite
        },
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(Modifier.padding(top = 2.dp).size(22.dp), contentAlignment = Alignment.Center) { icon() }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                text = eyebrow,
                style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(text = title, style = MaterialTheme.typography.titleMedium)
        }
    }
}

@Composable
private fun QuestionBlock(
    index: Int,
    questionCount: Int,
    question: StructuredQuestionUiModel,
    selected: Set<String>,
    customAnswer: String,
    customIsExpanded: Boolean,
    onOptionSelected: (String) -> Unit,
    onCustomExpandedChange: (Boolean) -> Unit,
    onCustomAnswerChange: (String) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
        if (questionCount > 1) {
            Text(
                text = stringResource(R.string.question_number, index + 1),
                style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold),
                color = RemoteTheme.colors.accent,
            )
        }
        Text(
            question.question,
            style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold),
            modifier = Modifier.semantics { heading() },
        )
        question.detail?.let {
            Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        question.options.forEach { option ->
            OptionRow(
                option = option,
                selected = option.label in selected,
                multiple = question.allowsMultipleSelection,
                onClick = { onOptionSelected(option.label) },
            )
        }
        val customState = stringResource(
            if (customIsExpanded) R.string.detail_state_expanded else R.string.detail_state_collapsed,
        )
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 44.dp)
                .clickable(role = Role.Button) { onCustomExpandedChange(!customIsExpanded) }
                .semantics { stateDescription = customState }
                .padding(horizontal = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(9.dp),
        ) {
            Icon(
                Icons.Default.EditNote,
                null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(18.dp),
            )
            Text(
                text = stringResource(
                    if (customAnswer.isBlank()) R.string.question_custom_add else R.string.question_custom_edit,
                ),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.weight(1f),
            )
            if (customAnswer.isNotBlank() && !customIsExpanded) {
                Text(
                    text = customAnswer,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.width(120.dp),
                )
            }
            Icon(
                imageVector = if (customIsExpanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(18.dp),
            )
        }
        if (customIsExpanded) {
            TextField(
                value = customAnswer,
                onValueChange = onCustomAnswerChange,
                modifier = Modifier.fillMaxWidth(),
                label = { Text(stringResource(R.string.question_custom_answer)) },
                minLines = 2,
                maxLines = 5,
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = RemoteTheme.colors.raisedSurface,
                    unfocusedContainerColor = RemoteTheme.colors.raisedSurface,
                    focusedIndicatorColor = Color.Transparent,
                    unfocusedIndicatorColor = Color.Transparent,
                ),
            )
        }
    }
}

@Composable
private fun OptionRow(
    option: QuestionOptionUiModel,
    selected: Boolean,
    multiple: Boolean,
    onClick: () -> Unit,
) {
    val shape = RoundedCornerShape(12.dp)
    val selectionModifier = if (multiple) {
        Modifier.toggleable(value = selected, role = Role.Checkbox) { onClick() }
    } else {
        Modifier.selectable(selected = selected, role = Role.RadioButton, onClick = onClick)
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 52.dp)
            .clip(shape)
            .background(if (selected) RemoteTheme.colors.accent.copy(alpha = 0.08f) else Color.Transparent)
            .border(
                width = 1.dp,
                color = if (selected) RemoteTheme.colors.accent.copy(alpha = 0.42f) else RemoteTheme.colors.strongHairline,
                shape = shape,
            )
            .then(selectionModifier)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(11.dp),
    ) {
        SelectionIndicator(selected = selected, multiple = multiple)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(option.label, style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Medium))
            option.description?.let {
                Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun SelectionIndicator(selected: Boolean, multiple: Boolean) {
    val shape = if (multiple) RoundedCornerShape(6.dp) else CircleShape
    Box(
        modifier = Modifier
            .size(22.dp)
            .clip(shape)
            .background(if (selected) RemoteTheme.colors.accent else Color.Transparent)
            .border(1.5.dp, if (selected) RemoteTheme.colors.accent else RemoteTheme.colors.strongHairline, shape),
        contentAlignment = Alignment.Center,
    ) {
        if (selected) Icon(Icons.Default.Check, null, tint = Color.White, modifier = Modifier.size(15.dp))
    }
}

@Composable
private fun StickyActions(content: @Composable androidx.compose.foundation.layout.RowScope.() -> Unit) {
    HorizontalDivider(color = RemoteTheme.colors.hairline)
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = RemoteDimens.pagePadding, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        content = content,
    )
}
