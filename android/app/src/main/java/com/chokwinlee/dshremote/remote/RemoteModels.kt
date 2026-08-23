package com.chokwinlee.dshremote.remote

import java.util.UUID
import kotlinx.serialization.Serializable

@Serializable
data class RemoteHost(
    val id: String,
    val name: String,
    val baseUrl: String,
    val accessToken: String?,
    val createdAt: Long,
) {
    constructor(
        name: String,
        baseUrl: String,
        accessToken: String? = null,
    ) : this(
        id = UUID.randomUUID().toString(),
        name = name,
        baseUrl = baseUrl,
        accessToken = accessToken,
        createdAt = System.currentTimeMillis(),
    )
}

enum class RemoteHostTransport {
    LOOPBACK,
    SAME_WIFI,
    UNPAIRED_LOCAL_NETWORK,
    TAILSCALE,
    HTTPS,
    CUSTOM,
}

data class RemoteHostDescription(val version: String, val attachedSessions: Int)

data class RemoteSessionSummary(
    val id: String,
    val title: String,
    val updatedAt: Long,
    val running: Boolean,
    val projectName: String?,
    val projectPath: String?,
)

data class RemoteWorkspaceSummary(
    val id: String,
    val title: String,
    val path: String,
    val sessionIds: List<String>,
    val createdAt: Long,
    val updatedAt: Long,
)

data class RemoteWorkspaceSnapshot(
    val items: List<RemoteWorkspaceSummary>,
    val archivedSessionIds: Set<String>,
)

data class RemoteConversationSnapshot(
    val items: List<RemoteConversationItem>,
    val hasMore: Boolean,
    val stats: RemoteConversationStats?,
    val trajectory: List<RemoteTrajectoryRecord> = emptyList(),
    val goal: RemoteGoalState? = null,
    val plan: RemotePlanState? = null,
    val imageLimits: RemoteImageLimits? = null,
)

data class RemoteImageLimits(
    val maxImageBytes: Int,
    val maxImagesPerMessage: Int,
    val maxMessageImageBytes: Int,
    val maxImagePixels: Int,
    val maxImageDimension: Int?,
    val mediaTypes: List<String>,
)

data class RemotePromptImage(
    val id: String = UUID.randomUUID().toString(),
    val data: ByteArray,
    val mediaType: String,
    val name: String?,
    val width: Int,
    val height: Int,
)

enum class RemoteReferenceKind { FILE, DIRECTORY }

data class RemoteFileReferenceCandidate(
    val path: String,
    val kind: RemoteReferenceKind,
) {
    val id: String get() = "${kind.name.lowercase()}:$path"
}

data class RemoteSessionReferenceCandidate(
    val mention: String,
    val sessionId: String,
    val label: String,
    val cwd: String?,
    val createdAt: Long,
) {
    val id: String get() = sessionId
}

enum class RemoteSubagentMode(val wireValue: String) {
    ONE_SHOT("one-shot"),
    CONTINUABLE("continuable"),
}

enum class RemoteSubagentActivity { RUNNING, INACTIVE }
enum class RemoteSubagentDiagnosticReason { CORRUPT, UNSUPPORTED, UNAVAILABLE }

data class RemoteSubagentEntry(
    val id: String,
    val mode: RemoteSubagentMode?,
    val activity: RemoteSubagentActivity?,
    val hasChildren: Boolean,
    val label: String?,
    val diagnosticReason: RemoteSubagentDiagnosticReason?,
) {
    val isDiagnostic: Boolean get() = diagnosticReason != null
}

data class RemoteSubagentCatalog(
    val entries: List<RemoteSubagentEntry>,
    val parentAvailable: Boolean,
)

enum class RemoteGoalPhase { ACTIVE, PAUSED, BLOCKED, COMPLETE }

data class RemoteGoalState(
    val id: String,
    val revision: Int,
    val objective: String,
    val phase: RemoteGoalPhase,
    val blockedReasonCode: String?,
    val blockedReasonMessage: String?,
    val maxRounds: Int,
    val roundsStarted: Int,
    val createdAt: Long,
    val updatedAt: Long,
)

data class RemotePlanState(val active: Boolean, val pending: Boolean) {
    val effectiveActive: Boolean get() = if (pending) !active else active
}

data class RemoteImageAttachment(
    val attachmentId: String,
    val mediaType: String,
    val bytes: Int,
    val width: Int,
    val height: Int,
    val name: String?,
) {
    val id: String get() = attachmentId
}

data class RemoteImageAttachmentPayload(
    val attachment: RemoteImageAttachment,
    val data: ByteArray,
)

data class RemoteConversationStats(
    val turns: Int,
    val steps: Int,
    val llmDurationMs: Long,
    val toolDurationMs: Long,
    val inputTokens: Int,
    val outputTokens: Int,
)

data class RemoteModelSelection(
    val provider: String,
    val model: String,
    val reasoningEffort: String?,
)

data class RemoteModelReasoningEffort(
    val id: String,
    val name: String,
    val description: String?,
)

data class RemoteModelReasoning(
    val efforts: List<RemoteModelReasoningEffort>,
    val defaultEffort: String?,
)

data class RemoteModelCatalogEntry(
    val id: String,
    val name: String,
    val description: String?,
    val reasoning: RemoteModelReasoning?,
)

data class RemoteModelProviderGroup(
    val id: String,
    val name: String,
    val models: List<RemoteModelCatalogEntry>,
)

data class RemoteModelCatalogFailure(
    val id: String,
    val name: String,
    val message: String,
)

data class RemoteModelDirectory(
    val current: RemoteModelSelection,
    val routable: Boolean,
    val groups: List<RemoteModelProviderGroup>,
    val failures: List<RemoteModelCatalogFailure>,
)

enum class RemoteDetailKind { TEXT, CODE, DIFF, LIST }

data class RemoteDetailSection(
    val id: String,
    val title: String?,
    val content: String,
    val kind: RemoteDetailKind,
    val language: String? = null,
)

enum class RemoteConversationKind { USER, ASSISTANT, TOOL, CONTEXT, STATUS }
enum class RemoteConversationState { INFO, RUNNING, SUCCEEDED, FAILED, STOPPED }
enum class RemoteToolCard { GENERIC, TERMINAL, DIFF, SEARCH, READ, WEB }

data class RemoteConversationItem(
    val id: String,
    val sequence: Int = 0,
    val kind: RemoteConversationKind,
    val title: String?,
    val text: String,
    val time: Long,
    val state: RemoteConversationState = RemoteConversationState.INFO,
    val toolCard: RemoteToolCard? = null,
    val toolCategory: String? = null,
    val reasoning: String? = null,
    val details: List<RemoteDetailSection> = emptyList(),
    val metadata: List<String> = emptyList(),
    val attachments: List<RemoteImageAttachment> = emptyList(),
    val symbolName: String? = null,
    val isStreaming: Boolean = false,
)

enum class RemoteQueuedPlacement { QUEUED, STEERING, CONTEXT }

data class RemoteQueuedMessage(
    val id: String,
    val placement: RemoteQueuedPlacement,
    val preview: String,
    val text: String?,
    val attachmentCount: Int = 0,
)

enum class RemoteTrajectoryKind { INPUT, CONTEXT, REQUEST, ASSISTANT, TOOL, GOAL, PLAN, LIFECYCLE }

data class RemoteTrajectoryRecord(
    val id: String,
    val sequence: Int,
    val turn: Int?,
    val step: Int?,
    val kind: RemoteTrajectoryKind,
    val title: String,
    val summary: String,
    val time: Long,
    val durationMs: Long?,
    val state: RemoteConversationState,
    val details: List<RemoteDetailSection> = emptyList(),
    val attachments: List<RemoteImageAttachment> = emptyList(),
)

sealed interface RemoteQueueAction {
    data class Edit(val text: String) : RemoteQueueAction
    data object Remove : RemoteQueueAction
    data object Steer : RemoteQueueAction
}

data class RemoteQuestionOption(val label: String, val description: String?)

data class RemoteQuestion(
    val id: String,
    val header: String?,
    val question: String,
    val detail: String?,
    val options: List<RemoteQuestionOption>,
    val allowsMultipleSelection: Boolean,
)

sealed interface RemoteInteractionKind {
    data class Approval(val toolName: String, val reason: String?) : RemoteInteractionKind
    data class Questions(val questions: List<RemoteQuestion>) : RemoteInteractionKind
}

data class RemoteInteraction(
    val id: String,
    val rpcId: String,
    val sessionId: String,
    val approvalId: String?,
    val kind: RemoteInteractionKind,
)

data class RemoteQuestionAnswer(
    val questionId: String,
    val selected: List<String>,
    val custom: String?,
)

sealed interface RemoteInteractionDecision {
    data object AllowOnce : RemoteInteractionDecision
    data object Reject : RemoteInteractionDecision
    data class Answer(val answers: List<RemoteQuestionAnswer>) : RemoteInteractionDecision
    data object CancelQuestions : RemoteInteractionDecision
}

sealed interface RemoteLiveEvent {
    data class SessionChanged(val sessionId: String) : RemoteLiveEvent
    data class QueueChanged(val sessionId: String, val items: List<RemoteQueuedMessage>) : RemoteLiveEvent
    data class Interaction(val interaction: RemoteInteraction) : RemoteLiveEvent
    data class InteractionResolved(val id: String) : RemoteLiveEvent
}
