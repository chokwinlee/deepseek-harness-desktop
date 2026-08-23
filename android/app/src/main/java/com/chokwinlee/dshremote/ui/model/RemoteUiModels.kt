package com.chokwinlee.dshremote.ui.model

/** UI-only snapshots. Transport and persistence types deliberately stay outside this package. */
data class RemoteAppUiState(
    val computers: ComputerListUiState = ComputerListUiState(),
    val addComputer: AddComputerUiState = AddComputerUiState(),
    val projects: ProjectListUiState = ProjectListUiState(),
    val session: SessionDetailUiState = SessionDetailUiState(),
)

data class ComputerListUiState(
    val computers: List<ComputerUiModel> = emptyList(),
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
    val isRefreshing: Boolean = false,
)

data class ComputerUiModel(
    val id: String,
    val name: String,
    val address: String,
    val transport: ComputerTransport,
    val connectionState: ComputerConnectionState = ComputerConnectionState.Unknown,
)

enum class ComputerTransport { SameWifi, Tailscale, CustomHttps, Demo }
enum class ComputerConnectionState { Unknown, Checking, Reachable, Unreachable }

data class AddComputerUiState(
    val initialName: String = "",
    val initialAddress: String = "",
    val isVerifying: Boolean = false,
    val errorMessage: String? = null,
    val qrScannerAvailable: Boolean = true,
    /** Keep true while the host has not supplied a camera scanner implementation. */
    val showQrPlaceholder: Boolean = true,
    val needsLocalNetworkPermission: Boolean = false,
    /** Non-null after the data layer has verified and persisted a computer. */
    val savedComputerId: String? = null,
)

data class ProjectListUiState(
    val computerName: String = "",
    val projects: List<ProjectUiModel> = emptyList(),
    val isLoading: Boolean = false,
    val isRefreshing: Boolean = false,
    val isDirectoryFallback: Boolean = false,
    val errorMessage: String? = null,
    val hasLoadedOnce: Boolean = false,
    val creatingSessionProjectId: String? = null,
    val createSessionErrorMessage: String? = null,
    val lastCreateSessionProjectId: String? = null,
    val lastCreatedSessionId: String? = null,
)

data class ProjectUiModel(
    val id: String,
    val title: String,
    val path: String? = null,
    val sessions: List<SessionUiModel> = emptyList(),
    val canCreateSession: Boolean = true,
) {
    val runningCount: Int get() = sessions.count { it.state == SessionExecutionState.Running }
}

data class SessionUiModel(
    val id: String,
    val title: String,
    val updatedLabel: String,
    val state: SessionExecutionState = SessionExecutionState.Idle,
)

enum class SessionExecutionState { Idle, Running, WaitingForApproval, Completed, Failed }

/** Complete immutable snapshot consumed by the session feature. */
data class SessionDetailUiState(
    val session: SessionUiModel? = null,
    val projectName: String = "",
    val messages: List<ConversationMessageUiModel> = emptyList(),
    val isLoading: Boolean = false,
    val isLoadingOlder: Boolean = false,
    val hasMoreHistory: Boolean = false,
    val hasLoadedOnce: Boolean = false,
    val isStreaming: Boolean = false,
    val isSending: Boolean = false,
    val isCancelling: Boolean = false,
    val errorMessage: String? = null,
    val pendingImages: List<PromptImageUiModel> = emptyList(),
    val isPreparingImages: Boolean = false,
    val imageInputAvailable: Boolean = true,
    val imageLimitLabel: String? = null,
    val references: ReferenceSuggestionsUiState = ReferenceSuggestionsUiState(),
    val queue: List<QueuedMessageUiModel> = emptyList(),
    val interaction: InteractionUiModel? = null,
    val models: ModelDirectoryUiState = ModelDirectoryUiState(),
    val goal: GoalUiModel? = null,
    val plan: PlanUiModel? = null,
    val stats: ConversationStatsUiModel? = null,
    val trajectory: List<TrajectoryRecordUiModel> = emptyList(),
    val subagents: SubagentCatalogUiState = SubagentCatalogUiState(),
    val selectedSubagent: SubagentConversationUiState? = null,
)

data class ConversationMessageUiModel(
    val id: String,
    val actor: ConversationActor,
    val text: String,
    val timestampLabel: String = "",
    val title: String? = null,
    val state: ConversationItemState = ConversationItemState.Info,
    val toolCard: ToolCardKind? = null,
    val reasoning: String? = null,
    val details: List<DetailSectionUiModel> = emptyList(),
    val metadata: List<String> = emptyList(),
    val attachments: List<ImageAttachmentUiModel> = emptyList(),
    val isStreaming: Boolean = false,
)

enum class ConversationActor { User, Assistant, Tool, Context, System }
enum class ConversationItemState { Info, Running, Succeeded, Failed, Stopped }
enum class ToolCardKind { Generic, Terminal, Diff, Search, Read, Web }
enum class DetailSectionKind { Text, Code, Diff, List }

data class DetailSectionUiModel(
    val id: String,
    val title: String? = null,
    val content: String,
    val kind: DetailSectionKind = DetailSectionKind.Text,
    val language: String? = null,
)

data class ImageAttachmentUiModel(
    val id: String,
    val name: String? = null,
    val mediaType: String,
    val width: Int,
    val height: Int,
    val sizeLabel: String,
    val previewUri: String? = null,
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
)

data class PromptImageUiModel(
    val id: String,
    val name: String? = null,
    val previewUri: String? = null,
    val dimensionsLabel: String? = null,
    val sizeLabel: String? = null,
    val isPreparing: Boolean = false,
    val errorMessage: String? = null,
)

enum class ReferenceCandidateKind { File, Directory, Session }

data class ReferenceCandidateUiModel(
    val id: String,
    val mention: String,
    val label: String,
    val detail: String? = null,
    val kind: ReferenceCandidateKind,
)

data class ReferenceSuggestionsUiState(
    val query: String = "",
    val candidates: List<ReferenceCandidateUiModel> = emptyList(),
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
    val isSupported: Boolean = true,
)

enum class QueuePlacementUi { Queued, Steering, Context }

data class QueuedMessageUiModel(
    val id: String,
    val placement: QueuePlacementUi,
    val preview: String,
    val text: String? = null,
    val attachmentCount: Int = 0,
    val isUpdating: Boolean = false,
)

sealed interface QueueActionUi {
    data class Edit(val text: String) : QueueActionUi
    data object Remove : QueueActionUi
    data object Steer : QueueActionUi
}

enum class InteractionKindUi { Approval, Questions }

data class InteractionUiModel(
    val id: String,
    val kind: InteractionKindUi,
    val title: String,
    val detail: String? = null,
    val toolName: String? = null,
    val questions: List<StructuredQuestionUiModel> = emptyList(),
    val isResponding: Boolean = false,
    val errorMessage: String? = null,
)

data class StructuredQuestionUiModel(
    val id: String,
    val header: String? = null,
    val question: String,
    val detail: String? = null,
    val options: List<QuestionOptionUiModel> = emptyList(),
    val allowsMultipleSelection: Boolean = false,
)

data class QuestionOptionUiModel(val label: String, val description: String? = null)
data class QuestionAnswerUiModel(val questionId: String, val selected: List<String>, val custom: String?)

sealed interface InteractionDecisionUi {
    data object AllowOnce : InteractionDecisionUi
    data object Reject : InteractionDecisionUi
    data class Answer(val answers: List<QuestionAnswerUiModel>) : InteractionDecisionUi
    data object CancelQuestions : InteractionDecisionUi
}

data class ModelSelectionUiModel(
    val providerId: String,
    val providerName: String,
    val modelId: String,
    val modelName: String,
    val reasoningEffortId: String? = null,
    val reasoningEffortName: String? = null,
)

data class ModelDirectoryUiState(
    val current: ModelSelectionUiModel? = null,
    val groups: List<ModelProviderGroupUiModel> = emptyList(),
    val routable: Boolean = true,
    val isLoading: Boolean = false,
    val isSelecting: Boolean = false,
    val errorMessage: String? = null,
)

data class ModelProviderGroupUiModel(
    val id: String,
    val name: String,
    val models: List<ModelOptionUiModel>,
)

data class ModelOptionUiModel(
    val id: String,
    val name: String,
    val description: String? = null,
    val reasoningEfforts: List<ReasoningEffortUiModel> = emptyList(),
    val defaultReasoningEffortId: String? = null,
)

data class ReasoningEffortUiModel(val id: String, val name: String, val description: String? = null)

enum class GoalPhaseUi { Active, Paused, Blocked, Complete }

data class GoalUiModel(
    val id: String,
    val objective: String,
    val phase: GoalPhaseUi,
    val roundsStarted: Int,
    val maxRounds: Int,
    val revision: Int,
    val blockedReason: String? = null,
)

data class PlanUiModel(val active: Boolean, val pending: Boolean) {
    val effectiveActive: Boolean get() = if (pending) !active else active
}

data class ConversationStatsUiModel(
    val turns: Int,
    val steps: Int,
    val durationLabel: String,
    val tokenLabel: String,
)

enum class TrajectoryKindUi { Input, Context, Request, Assistant, Tool, Goal, Plan, Lifecycle }

data class TrajectoryRecordUiModel(
    val id: String,
    val sequence: Int,
    val turn: Int? = null,
    val step: Int? = null,
    val kind: TrajectoryKindUi,
    val title: String,
    val summary: String,
    val timestampLabel: String = "",
    val durationLabel: String? = null,
    val state: ConversationItemState = ConversationItemState.Info,
    val details: List<DetailSectionUiModel> = emptyList(),
    val attachments: List<ImageAttachmentUiModel> = emptyList(),
)

enum class SubagentModeUi { OneShot, Continuable, Unknown }
enum class SubagentActivityUi { Running, Inactive, Unavailable }

data class SubagentUiModel(
    val id: String,
    val label: String,
    val mode: SubagentModeUi = SubagentModeUi.Unknown,
    val activity: SubagentActivityUi = SubagentActivityUi.Inactive,
    val hasChildren: Boolean = false,
    val diagnosticMessage: String? = null,
)

data class SubagentCatalogUiState(
    val entries: List<SubagentUiModel> = emptyList(),
    val parentAvailable: Boolean = true,
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
    /** Zero is the selected session's catalog. Each nested child catalog increments the depth. */
    val navigationDepth: Int = 0,
    /** User-authored label of the child whose nested catalog is currently visible. */
    val parentLabel: String? = null,
)

data class SubagentConversationUiState(
    val subagent: SubagentUiModel,
    val messages: List<ConversationMessageUiModel> = emptyList(),
    val hasMoreHistory: Boolean = false,
    val isLoading: Boolean = false,
    val isLoadingOlder: Boolean = false,
    val isSending: Boolean = false,
    val isStopping: Boolean = false,
    val errorMessage: String? = null,
    val parentAvailable: Boolean = true,
)

enum class PromptDeliveryUi { Send, Queue, Steer }

/** Session callbacks remain grouped so feature composables stay stateless and previewable. */
data class SessionDetailCallbacks(
    val onRefresh: () -> Unit = {},
    val onLoadOlderHistory: () -> Unit = {},
    val onSendPrompt: (text: String, delivery: PromptDeliveryUi) -> Unit = { _, _ -> },
    val onStopSession: () -> Unit = {},
    val onPickImages: () -> Unit = {},
    val onPasteImages: () -> Unit = {},
    val onRemovePendingImage: (imageId: String) -> Unit = {},
    val onSearchReferences: (query: String) -> Unit = {},
    val onReferenceSelected: (candidate: ReferenceCandidateUiModel) -> Unit = {},
    val onUpdateQueue: (itemId: String, action: QueueActionUi) -> Unit = { _, _ -> },
    val onResolveInteraction: (interactionId: String, decision: InteractionDecisionUi) -> Unit = { _, _ -> },
    val onLoadModels: () -> Unit = {},
    /** Reports completion so the picker closes only after an asynchronous host update succeeds. */
    val onSelectModel: (selection: ModelSelectionUiModel, onResult: (Boolean) -> Unit) -> Unit = { _, _ -> },
    val onOpenAttachment: (attachmentId: String) -> Unit = {},
    val onRefreshSubagents: () -> Unit = {},
    val onOpenSubagent: (subagentId: String) -> Unit = {},
    val onOpenSubagentChildren: (subagentId: String) -> Unit = {},
    val onOpenSubagentAttachment: (subagentId: String, attachmentId: String) -> Unit = { _, _ -> },
    val onNavigateBackSubagents: () -> Unit = {},
    val onDismissSubagents: () -> Unit = {},
    /** Legacy detail-close callback retained for preview/source compatibility. */
    val onCloseSubagent: () -> Unit = {},
    val onLoadOlderSubagentHistory: (subagentId: String) -> Unit = {},
    val onContinueSubagent: (subagentId: String, text: String) -> Unit = { _, _ -> },
    val onStopSubagent: (subagentId: String) -> Unit = {},
    val onDismissError: () -> Unit = {},
)

data class RemoteAppCallbacks(
    val onRefreshComputers: () -> Unit = {},
    val onComputerSelected: (computerId: String) -> Unit = {},
    val onRemoveComputer: (computerId: String) -> Unit = {},
    val onRemoveAllComputers: () -> Unit = {},
    val onScanQrCode: () -> Unit = {},
    val onOpenSystemSettings: () -> Unit = {},
    val onVerifyAndSaveComputer: (name: String, address: String) -> Unit = { _, _ -> },
    val onTryDemo: () -> Unit = {},
    val onRefreshProjects: () -> Unit = {},
    val onCreateSession: (projectId: String) -> Unit = {},
    val onSessionSelected: (sessionId: String) -> Unit = {},
    /** Legacy callbacks keep the existing shell source-compatible during host migration. */
    val onRefreshSession: () -> Unit = {},
    val onSendMessage: (text: String) -> Unit = {},
    val onStopSession: () -> Unit = {},
    val onSessionVisibilityChanged: (sessionId: String?, visible: Boolean) -> Unit = { _, _ -> },
    /** Full-fidelity session contract used by the production host. */
    val sessionDetail: SessionDetailCallbacks = SessionDetailCallbacks(),
)
