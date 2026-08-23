package com.chokwinlee.dshremote.app

import com.chokwinlee.dshremote.remote.RemoteConversationItem
import com.chokwinlee.dshremote.remote.RemoteConversationKind
import com.chokwinlee.dshremote.remote.RemoteConversationSnapshot
import com.chokwinlee.dshremote.remote.RemoteConversationState
import com.chokwinlee.dshremote.remote.RemoteDetailKind
import com.chokwinlee.dshremote.remote.RemoteGoalPhase
import com.chokwinlee.dshremote.remote.RemoteImageAttachment
import com.chokwinlee.dshremote.remote.RemoteInteraction
import com.chokwinlee.dshremote.remote.RemoteInteractionKind
import com.chokwinlee.dshremote.remote.RemoteModelDirectory
import com.chokwinlee.dshremote.remote.RemoteModelSelection
import com.chokwinlee.dshremote.remote.RemoteQueuedMessage
import com.chokwinlee.dshremote.remote.RemoteQueuedPlacement
import com.chokwinlee.dshremote.remote.RemoteSessionSummary
import com.chokwinlee.dshremote.remote.RemoteSubagentActivity
import com.chokwinlee.dshremote.remote.RemoteSubagentCatalog
import com.chokwinlee.dshremote.remote.RemoteSubagentDiagnosticReason
import com.chokwinlee.dshremote.remote.RemoteSubagentEntry
import com.chokwinlee.dshremote.remote.RemoteSubagentMode
import com.chokwinlee.dshremote.remote.RemoteToolCard
import com.chokwinlee.dshremote.remote.RemoteTrajectoryKind
import com.chokwinlee.dshremote.ui.model.ConversationActor
import com.chokwinlee.dshremote.ui.model.ConversationItemState
import com.chokwinlee.dshremote.ui.model.ConversationMessageUiModel
import com.chokwinlee.dshremote.ui.model.ConversationStatsUiModel
import com.chokwinlee.dshremote.ui.model.DetailSectionKind
import com.chokwinlee.dshremote.ui.model.DetailSectionUiModel
import com.chokwinlee.dshremote.ui.model.GoalPhaseUi
import com.chokwinlee.dshremote.ui.model.GoalUiModel
import com.chokwinlee.dshremote.ui.model.ImageAttachmentUiModel
import com.chokwinlee.dshremote.ui.model.InteractionKindUi
import com.chokwinlee.dshremote.ui.model.InteractionUiModel
import com.chokwinlee.dshremote.ui.model.ModelDirectoryUiState
import com.chokwinlee.dshremote.ui.model.ModelOptionUiModel
import com.chokwinlee.dshremote.ui.model.ModelProviderGroupUiModel
import com.chokwinlee.dshremote.ui.model.ModelSelectionUiModel
import com.chokwinlee.dshremote.ui.model.PlanUiModel
import com.chokwinlee.dshremote.ui.model.QueuePlacementUi
import com.chokwinlee.dshremote.ui.model.QueuedMessageUiModel
import com.chokwinlee.dshremote.ui.model.QuestionOptionUiModel
import com.chokwinlee.dshremote.ui.model.ReasoningEffortUiModel
import com.chokwinlee.dshremote.ui.model.SessionExecutionState
import com.chokwinlee.dshremote.ui.model.SessionUiModel
import com.chokwinlee.dshremote.ui.model.StructuredQuestionUiModel
import com.chokwinlee.dshremote.ui.model.SubagentActivityUi
import com.chokwinlee.dshremote.ui.model.SubagentCatalogUiState
import com.chokwinlee.dshremote.ui.model.SubagentModeUi
import com.chokwinlee.dshremote.ui.model.SubagentUiModel
import com.chokwinlee.dshremote.ui.model.ToolCardKind
import com.chokwinlee.dshremote.ui.model.TrajectoryKindUi
import com.chokwinlee.dshremote.ui.model.TrajectoryRecordUiModel
import java.text.DateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.roundToInt

internal object RemoteUiMapper {
    fun session(
        summary: RemoteSessionSummary,
        hasInteraction: Boolean,
        completed: Boolean,
        failed: Boolean = false,
        nowLabel: String = "Now",
        now: Long = System.currentTimeMillis(),
    ) = SessionUiModel(
        id = summary.id,
        title = summary.title,
        updatedLabel = relativeTime(summary.updatedAt, now, nowLabel),
        state = when {
            hasInteraction -> SessionExecutionState.WaitingForApproval
            summary.running -> SessionExecutionState.Running
            failed -> SessionExecutionState.Failed
            completed -> SessionExecutionState.Completed
            else -> SessionExecutionState.Idle
        },
    )

    fun conversation(
        snapshot: RemoteConversationSnapshot,
        localize: (String) -> String = { it },
    ): List<ConversationMessageUiModel> = snapshot.items.map { conversationItem(it, localize) }

    fun conversationItem(
        item: RemoteConversationItem,
        localize: (String) -> String = { it },
    ) = ConversationMessageUiModel(
        id = item.id,
        actor = when (item.kind) {
            RemoteConversationKind.USER -> ConversationActor.User
            RemoteConversationKind.ASSISTANT -> ConversationActor.Assistant
            RemoteConversationKind.TOOL -> ConversationActor.Tool
            RemoteConversationKind.CONTEXT -> ConversationActor.Context
            RemoteConversationKind.STATUS -> ConversationActor.System
        },
        text = localize(item.text),
        timestampLabel = timeLabel(item.time),
        title = item.title?.let(localize),
        state = item.state.toUi(),
        toolCard = item.toolCard?.toUi(),
        reasoning = item.reasoning,
        details = item.details.map { detail ->
            DetailSectionUiModel(
                id = detail.id,
                title = detail.title?.let(localize),
                content = detail.content,
                kind = when (detail.kind) {
                    RemoteDetailKind.TEXT -> DetailSectionKind.Text
                    RemoteDetailKind.CODE -> DetailSectionKind.Code
                    RemoteDetailKind.DIFF -> DetailSectionKind.Diff
                    RemoteDetailKind.LIST -> DetailSectionKind.List
                },
                language = detail.language,
            )
        },
        metadata = item.metadata.map(localize),
        attachments = item.attachments.map(::attachment),
        isStreaming = item.isStreaming,
    )

    fun attachment(
        attachment: RemoteImageAttachment,
        previewUri: String? = null,
        isLoading: Boolean = false,
        errorMessage: String? = null,
    ) = ImageAttachmentUiModel(
        id = attachment.attachmentId,
        name = attachment.name,
        mediaType = attachment.mediaType,
        width = attachment.width,
        height = attachment.height,
        sizeLabel = byteSize(attachment.bytes.toLong()),
        previewUri = previewUri,
        isLoading = isLoading,
        errorMessage = errorMessage,
    )

    fun queue(
        items: List<RemoteQueuedMessage>,
        updatingItemId: String? = null,
        imageCountLabel: (Int) -> String = { count -> "$count image(s)" },
        emptyLabel: String = "Queued message",
    ) = items.map { item ->
        val text = item.text?.trim().orEmpty()
        val preview = when {
            text.isNotBlank() && item.attachmentCount > 0 -> "$text · ${imageCountLabel(item.attachmentCount)}"
            text.isNotBlank() -> text
            item.attachmentCount > 0 -> imageCountLabel(item.attachmentCount)
            else -> emptyLabel
        }
        QueuedMessageUiModel(
            id = item.id,
            placement = when (item.placement) {
                RemoteQueuedPlacement.QUEUED -> QueuePlacementUi.Queued
                RemoteQueuedPlacement.STEERING -> QueuePlacementUi.Steering
                RemoteQueuedPlacement.CONTEXT -> QueuePlacementUi.Context
            },
            preview = preview,
            text = item.text,
            attachmentCount = item.attachmentCount,
            isUpdating = item.id == updatingItemId,
        )
    }

    fun interaction(
        interaction: RemoteInteraction?,
        respondingId: String? = null,
        errorMessage: String? = null,
        questionFallback: String = "Question",
        localize: (String) -> String = { it },
    ): InteractionUiModel? = interaction?.let { value ->
        when (val kind = value.kind) {
            is RemoteInteractionKind.Approval -> InteractionUiModel(
                id = value.id,
                kind = InteractionKindUi.Approval,
                title = kind.toolName,
                detail = kind.reason,
                toolName = kind.toolName,
                isResponding = value.id == respondingId,
                errorMessage = errorMessage,
            )
            is RemoteInteractionKind.Questions -> InteractionUiModel(
                id = value.id,
                kind = InteractionKindUi.Questions,
                title = localize(kind.questions.firstOrNull()?.header
                    ?: kind.questions.firstOrNull()?.question
                    ?: questionFallback),
                questions = kind.questions.map { question ->
                    StructuredQuestionUiModel(
                        id = question.id,
                        header = question.header?.let(localize),
                        question = localize(question.question),
                        detail = question.detail?.let(localize),
                        options = question.options.map { option ->
                            QuestionOptionUiModel(
                                localize(option.label),
                                option.description?.let(localize),
                            )
                        },
                        allowsMultipleSelection = question.allowsMultipleSelection,
                    )
                },
                isResponding = value.id == respondingId,
                errorMessage = errorMessage,
            )
        }
    }

    fun models(
        directory: RemoteModelDirectory?,
        isLoading: Boolean = false,
        isSelecting: Boolean = false,
        errorMessage: String? = null,
        localizeDescription: (String) -> String = { it },
    ): ModelDirectoryUiState {
        if (directory == null) {
            return ModelDirectoryUiState(
                isLoading = isLoading,
                isSelecting = isSelecting,
                errorMessage = errorMessage,
            )
        }
        return ModelDirectoryUiState(
            current = modelSelection(directory, directory.current),
            groups = directory.groups.map { group ->
                ModelProviderGroupUiModel(
                    id = group.id,
                    name = group.name,
                    models = group.models.map { model ->
                        ModelOptionUiModel(
                            id = model.id,
                            name = model.name,
                            description = model.description?.let(localizeDescription),
                            reasoningEfforts = model.reasoning?.efforts.orEmpty().map { effort ->
                                ReasoningEffortUiModel(
                                    effort.id,
                                    effort.name,
                                    effort.description?.let(localizeDescription),
                                )
                            },
                            defaultReasoningEffortId = model.reasoning?.defaultEffort,
                        )
                    },
                )
            },
            routable = directory.routable,
            isLoading = isLoading,
            isSelecting = isSelecting,
            errorMessage = errorMessage ?: directory.failures.firstOrNull()?.message,
        )
    }

    private fun modelSelection(
        directory: RemoteModelDirectory,
        selection: RemoteModelSelection,
    ): ModelSelectionUiModel {
        val provider = directory.groups.firstOrNull { it.id == selection.provider }
        val model = provider?.models?.firstOrNull { it.id == selection.model }
        val effort = model?.reasoning?.efforts?.firstOrNull { it.id == selection.reasoningEffort }
        return ModelSelectionUiModel(
            providerId = selection.provider,
            providerName = provider?.name ?: selection.provider,
            modelId = selection.model,
            modelName = model?.name ?: selection.model,
            reasoningEffortId = selection.reasoningEffort,
            reasoningEffortName = effort?.name ?: selection.reasoningEffort,
        )
    }

    fun goal(
        snapshot: RemoteConversationSnapshot,
        localize: (String) -> String = { it },
    ): GoalUiModel? = snapshot.goal?.let { goal ->
        GoalUiModel(
            id = goal.id,
            objective = localize(goal.objective),
            phase = when (goal.phase) {
                RemoteGoalPhase.ACTIVE -> GoalPhaseUi.Active
                RemoteGoalPhase.PAUSED -> GoalPhaseUi.Paused
                RemoteGoalPhase.BLOCKED -> GoalPhaseUi.Blocked
                RemoteGoalPhase.COMPLETE -> GoalPhaseUi.Complete
            },
            roundsStarted = goal.roundsStarted,
            maxRounds = goal.maxRounds,
            revision = goal.revision,
            blockedReason = goal.blockedReasonMessage,
        )
    }

    fun plan(snapshot: RemoteConversationSnapshot): PlanUiModel? = snapshot.plan?.let { plan ->
        PlanUiModel(plan.active, plan.pending)
    }

    fun stats(snapshot: RemoteConversationSnapshot): ConversationStatsUiModel? = snapshot.stats?.let { stats ->
        ConversationStatsUiModel(
            turns = stats.turns,
            steps = stats.steps,
            durationLabel = duration(stats.llmDurationMs + stats.toolDurationMs),
            tokenLabel = "${stats.inputTokens + stats.outputTokens}",
        )
    }

    fun trajectory(snapshot: RemoteConversationSnapshot): List<TrajectoryRecordUiModel> =
        trajectory(snapshot) { it }

    fun trajectory(
        snapshot: RemoteConversationSnapshot,
        localize: (String) -> String,
    ): List<TrajectoryRecordUiModel> = snapshot.trajectory.map { record ->
            TrajectoryRecordUiModel(
                id = record.id,
                sequence = record.sequence,
                // Harness event coordinates are zero-based; labels shown to people are one-based.
                turn = record.turn?.plus(1),
                step = record.step?.plus(1),
                kind = when (record.kind) {
                    RemoteTrajectoryKind.INPUT -> TrajectoryKindUi.Input
                    RemoteTrajectoryKind.CONTEXT -> TrajectoryKindUi.Context
                    RemoteTrajectoryKind.REQUEST -> TrajectoryKindUi.Request
                    RemoteTrajectoryKind.ASSISTANT -> TrajectoryKindUi.Assistant
                    RemoteTrajectoryKind.TOOL -> TrajectoryKindUi.Tool
                    RemoteTrajectoryKind.GOAL -> TrajectoryKindUi.Goal
                    RemoteTrajectoryKind.PLAN -> TrajectoryKindUi.Plan
                    RemoteTrajectoryKind.LIFECYCLE -> TrajectoryKindUi.Lifecycle
                },
                title = localize(record.title),
                summary = localize(record.summary),
                timestampLabel = timeLabel(record.time),
                durationLabel = record.durationMs?.let(::duration),
                state = record.state.toUi(),
                details = record.details.map { detail ->
                    DetailSectionUiModel(
                        id = detail.id,
                        title = detail.title?.let(localize),
                        content = detail.content,
                        kind = when (detail.kind) {
                            RemoteDetailKind.TEXT -> DetailSectionKind.Text
                            RemoteDetailKind.CODE -> DetailSectionKind.Code
                            RemoteDetailKind.DIFF -> DetailSectionKind.Diff
                            RemoteDetailKind.LIST -> DetailSectionKind.List
                        },
                        language = detail.language,
                    )
                },
                attachments = record.attachments.map(::attachment),
            )
        }

    fun subagents(
        catalog: RemoteSubagentCatalog?,
        isLoading: Boolean = false,
        errorMessage: String? = null,
        diagnosticName: (RemoteSubagentDiagnosticReason) -> String = { it.displayName() },
        localizeLabel: (String) -> String = { it },
    ) = SubagentCatalogUiState(
        entries = catalog?.entries.orEmpty().map { subagent(it, diagnosticName, localizeLabel) },
        parentAvailable = catalog?.parentAvailable ?: true,
        isLoading = isLoading,
        errorMessage = errorMessage,
    )

    fun subagent(
        entry: RemoteSubagentEntry,
        diagnosticName: (RemoteSubagentDiagnosticReason) -> String = { it.displayName() },
        localizeLabel: (String) -> String = { it },
    ) = SubagentUiModel(
        id = entry.id,
        label = entry.label?.let(localizeLabel) ?: entry.diagnosticReason?.let(diagnosticName).orEmpty(),
        mode = when (entry.mode) {
            RemoteSubagentMode.ONE_SHOT -> SubagentModeUi.OneShot
            RemoteSubagentMode.CONTINUABLE -> SubagentModeUi.Continuable
            null -> SubagentModeUi.Unknown
        },
        activity = when (entry.activity) {
            RemoteSubagentActivity.RUNNING -> SubagentActivityUi.Running
            RemoteSubagentActivity.INACTIVE -> SubagentActivityUi.Inactive
            null -> SubagentActivityUi.Unavailable
        },
        hasChildren = entry.hasChildren,
        diagnosticMessage = entry.diagnosticReason?.let(diagnosticName),
    )

    private fun RemoteSubagentDiagnosticReason.displayName(): String =
        name.lowercase().replaceFirstChar(Char::uppercase)

    private fun RemoteConversationState.toUi() = when (this) {
        RemoteConversationState.INFO -> ConversationItemState.Info
        RemoteConversationState.RUNNING -> ConversationItemState.Running
        RemoteConversationState.SUCCEEDED -> ConversationItemState.Succeeded
        RemoteConversationState.FAILED -> ConversationItemState.Failed
        RemoteConversationState.STOPPED -> ConversationItemState.Stopped
    }

    private fun RemoteToolCard.toUi() = when (this) {
        RemoteToolCard.GENERIC -> ToolCardKind.Generic
        RemoteToolCard.TERMINAL -> ToolCardKind.Terminal
        RemoteToolCard.DIFF -> ToolCardKind.Diff
        RemoteToolCard.SEARCH -> ToolCardKind.Search
        RemoteToolCard.READ -> ToolCardKind.Read
        RemoteToolCard.WEB -> ToolCardKind.Web
    }

    fun timeLabel(time: Long): String = DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(time))

    fun relativeTime(time: Long, now: Long = System.currentTimeMillis(), nowLabel: String = "Now"): String {
        val elapsed = (now - time).coerceAtLeast(0)
        return when {
            elapsed < 60_000 -> nowLabel
            elapsed < 3_600_000 -> "${elapsed / 60_000}m"
            elapsed < 86_400_000 -> "${elapsed / 3_600_000}h"
            else -> "${elapsed / 86_400_000}d"
        }
    }

    fun byteSize(bytes: Long): String = when {
        bytes < 1_024 -> "$bytes B"
        bytes < 1_048_576 -> "${(bytes / 1_024.0).roundToInt()} KB"
        else -> String.format(Locale.ROOT, "%.1f MB", bytes / 1_048_576.0)
    }

    private fun duration(milliseconds: Long): String = when {
        milliseconds < 1_000 -> "${milliseconds}ms"
        milliseconds < 60_000 -> String.format(Locale.ROOT, "%.1fs", milliseconds / 1_000.0)
        else -> String.format(Locale.ROOT, "%.1fm", milliseconds / 60_000.0)
    }
}
