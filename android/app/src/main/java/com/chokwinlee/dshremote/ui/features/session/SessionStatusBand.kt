package com.chokwinlee.dshremote.ui.features.session

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.chokwinlee.dshremote.R
import com.chokwinlee.dshremote.ui.components.RemoteCloseButton
import com.chokwinlee.dshremote.ui.components.RemoteInlineNotice
import com.chokwinlee.dshremote.ui.components.RemoteNoticeTone
import com.chokwinlee.dshremote.ui.components.RemoteSectionHeader
import com.chokwinlee.dshremote.ui.components.RemoteSurface
import com.chokwinlee.dshremote.ui.model.GoalPhaseUi
import com.chokwinlee.dshremote.ui.model.GoalUiModel
import com.chokwinlee.dshremote.ui.model.SessionExecutionState
import com.chokwinlee.dshremote.ui.theme.RemoteDimens
import com.chokwinlee.dshremote.ui.theme.RemoteTheme

/** One quiet status band. Goal details stay read-only and open in place. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SessionStatusBand(
    sessionState: SessionExecutionState,
    goal: GoalUiModel?,
    modifier: Modifier = Modifier,
) {
    var showsGoalDetails by remember(goal?.id, goal?.revision) { mutableStateOf(false) }
    val statusColor = sessionStateColor(sessionState)
    val goalDescription = goal?.let {
        pluralStringResource(
            R.plurals.goal_accessibility_value,
            it.roundsStarted,
            goalPhaseLabel(it.phase),
            it.blockedReason ?: it.objective,
            it.roundsStarted,
            it.maxRounds,
        )
    }
    val openDetailsLabel = stringResource(R.string.goal_detail_open)
    val rowModifier = modifier
        .fillMaxWidth()
        .heightIn(min = 44.dp)
        .background(RemoteTheme.colors.surface)
        .then(
            if (goal != null) {
                Modifier.clickable(role = Role.Button) { showsGoalDetails = true }
            } else {
                Modifier
            },
        )
        .padding(horizontal = RemoteDimens.pagePadding, vertical = 7.dp)
        .semantics(mergeDescendants = true) {
            liveRegion = LiveRegionMode.Polite
            if (goal != null) {
                role = Role.Button
                contentDescription = listOfNotNull(openDetailsLabel, goalDescription).joinToString(". ")
            }
        }

    Row(
        modifier = rowModifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(Modifier.size(7.dp).clip(CircleShape).background(statusColor))
        Text(
            text = stringResource(sessionStateLabel(sessionState)),
            style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold),
            color = statusColor,
        )
        goal?.let { currentGoal ->
            Box(
                Modifier
                    .size(3.dp)
                    .clip(CircleShape)
                    .background(RemoteTheme.colors.strongHairline),
            )
            Icon(
                imageVector = Icons.Default.Flag,
                contentDescription = null,
                tint = goalPhaseColor(currentGoal.phase),
                modifier = Modifier.size(16.dp),
            )
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(1.dp),
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Text(
                        text = goalPhaseLabel(currentGoal.phase),
                        style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.SemiBold),
                        color = goalPhaseColor(currentGoal.phase),
                    )
                    Text(
                        text = pluralStringResource(
                            R.plurals.goal_rounds_value,
                            currentGoal.roundsStarted,
                            currentGoal.roundsStarted,
                            currentGoal.maxRounds,
                        ),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Text(
                    text = currentGoal.blockedReason ?: currentGoal.objective,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            Icon(
                imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(17.dp),
            )
        }
    }
    HorizontalDivider(color = RemoteTheme.colors.hairline)

    if (showsGoalDetails && goal != null) {
        GoalDetailSheet(goal = goal, onDismiss = { showsGoalDetails = false })
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun GoalDetailSheet(
    goal: GoalUiModel,
    onDismiss: () -> Unit,
) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = RemoteTheme.colors.canvas,
        dragHandle = null,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(horizontal = RemoteDimens.pagePadding, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = stringResource(R.string.goal_detail_title),
                        style = MaterialTheme.typography.titleMedium,
                    )
                    Text(
                        text = goalPhaseLabel(goal.phase),
                        style = MaterialTheme.typography.labelMedium,
                        color = goalPhaseColor(goal.phase),
                    )
                }
                RemoteCloseButton(onClick = onDismiss)
            }

            Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                RemoteSectionHeader(title = stringResource(R.string.goal_detail_objective))
                SelectionContainer {
                    Text(text = goal.objective, style = MaterialTheme.typography.bodyMedium)
                }
            }

            RemoteSurface(modifier = Modifier.fillMaxWidth()) {
                Column {
                    GoalDetailRow(
                        label = stringResource(R.string.goal_detail_phase),
                        value = goalPhaseLabel(goal.phase),
                    )
                    HorizontalDivider(color = RemoteTheme.colors.hairline)
                    GoalDetailRow(
                        label = stringResource(R.string.goal_detail_rounds),
                        value = pluralStringResource(
                            R.plurals.goal_rounds_value,
                            goal.roundsStarted,
                            goal.roundsStarted,
                            goal.maxRounds,
                        ),
                    )
                    HorizontalDivider(color = RemoteTheme.colors.hairline)
                    GoalDetailRow(
                        label = stringResource(R.string.goal_detail_revision),
                        value = goal.revision.toString(),
                    )
                }
            }

            if (!goal.blockedReason.isNullOrBlank()) {
                RemoteInlineNotice(
                    title = stringResource(R.string.goal_detail_blocked_reason),
                    message = goal.blockedReason,
                    tone = RemoteNoticeTone.Warning,
                )
            }
        }
    }
}

@Composable
private fun GoalDetailRow(label: String, value: String) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        SelectionContainer {
            Text(text = value, style = MaterialTheme.typography.bodyMedium)
        }
    }
}

@Composable
private fun goalPhaseLabel(phase: GoalPhaseUi): String = stringResource(
    when (phase) {
        GoalPhaseUi.Active -> R.string.goal_phase_active
        GoalPhaseUi.Paused -> R.string.goal_phase_paused
        GoalPhaseUi.Blocked -> R.string.goal_phase_blocked
        GoalPhaseUi.Complete -> R.string.goal_phase_complete
    },
)

@Composable
private fun goalPhaseColor(phase: GoalPhaseUi): Color = when (phase) {
    GoalPhaseUi.Active -> RemoteTheme.colors.accent
    GoalPhaseUi.Paused, GoalPhaseUi.Blocked -> RemoteTheme.colors.warning
    GoalPhaseUi.Complete -> RemoteTheme.colors.success
}

@Composable
private fun sessionStateColor(state: SessionExecutionState): Color = when (state) {
    SessionExecutionState.Idle -> MaterialTheme.colorScheme.onSurfaceVariant
    SessionExecutionState.Running -> RemoteTheme.colors.accent
    SessionExecutionState.WaitingForApproval -> RemoteTheme.colors.warning
    SessionExecutionState.Completed -> RemoteTheme.colors.success
    SessionExecutionState.Failed -> RemoteTheme.colors.danger
}

private fun sessionStateLabel(state: SessionExecutionState): Int = when (state) {
    SessionExecutionState.Idle -> R.string.session_state_idle
    SessionExecutionState.Running -> R.string.session_state_running
    SessionExecutionState.WaitingForApproval -> R.string.session_state_waiting
    SessionExecutionState.Completed -> R.string.session_state_completed
    SessionExecutionState.Failed -> R.string.session_state_failed
}
