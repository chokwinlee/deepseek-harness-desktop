package com.chokwinlee.dshremote.remote

import java.util.Base64
import java.util.UUID
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

class DemoHarnessRemoteClient(
    private val clock: () -> Long = System::currentTimeMillis,
) : HarnessRemoteClient {
    override val displayName: String = "Demo"
    override val isDemo: Boolean = true

    private val mutex = Mutex()
    private val reviewSessionId = "review-demo-session"
    private var selectedModel = RemoteModelSelection("deepseek-official", "deepseek-v4-flash", "high")
    private val uploadedAttachments = mutableMapOf<String, RemoteImageAttachmentPayload>()
    private val sessionStates = linkedMapOf<String, DemoSessionState>()

    init {
        val now = clock()
        val reviewItems = mutableListOf<RemoteConversationItem>()
        reviewItems += RemoteConversationItem(
            "demo-user",
            1,
            RemoteConversationKind.USER,
            null,
            "Review the login flow before release.",
            now - 180_000,
        )
        reviewItems += RemoteConversationItem(
            "demo-tool",
            2,
            RemoteConversationKind.TOOL,
            "Read project files",
            "Read four authentication files",
            now - 170_000,
            RemoteConversationState.SUCCEEDED,
            RemoteToolCard.READ,
            details = listOf(
                RemoteDetailSection(
                    "demo-files",
                    "Files",
                    "Sources/Auth/SessionStore.kt\nSources/Auth/LoginScreen.kt\nTests/AuthTest.kt\nREADME.md",
                    RemoteDetailKind.LIST,
                ),
            ),
        )
        reviewItems += RemoteConversationItem(
            "demo-assistant",
            3,
            RemoteConversationKind.ASSISTANT,
            null,
            "I found two release risks: session restoration is not covered by a regression test, and the offline error does not explain how to reconnect. I can fix both after you confirm.",
            now - 160_000,
            RemoteConversationState.SUCCEEDED,
        )
        sessionStates[reviewSessionId] = DemoSessionState(
            title = "Login flow release review",
            createdAt = now - 86_400_000,
            updatedAt = now,
            items = reviewItems,
            goal = demoGoal(now),
            stats = RemoteConversationStats(1, 2, 4_200, 320, 1_284, 436),
            plan = RemotePlanState(active = false, pending = true),
        )
    }

    override suspend fun describe() = RemoteHostDescription("Offline Demo", 1)

    override suspend fun workspaces(): RemoteWorkspaceSnapshot = mutex.withLock {
        val states = sessionStates.values
        return RemoteWorkspaceSnapshot(
            listOf(
                RemoteWorkspaceSummary(
                    "review-demo-workspace",
                    "Sample App",
                    "/Users/demo/sample-app",
                    sessionStates.keys.toList(),
                    states.minOfOrNull(DemoSessionState::createdAt) ?: clock(),
                    states.maxOfOrNull(DemoSessionState::updatedAt) ?: clock(),
                ),
            ),
            emptySet(),
        )
    }

    override suspend fun sessions(): List<RemoteSessionSummary> = mutex.withLock {
        sessionStates.map { (id, state) ->
            RemoteSessionSummary(
                id,
                state.title,
                state.updatedAt,
                state.running,
                "sample-app",
                "/Users/demo/sample-app",
            )
        }.sortedByDescending(RemoteSessionSummary::updatedAt)
    }

    override suspend fun createSession(workspaceId: String?, cwd: String?): String = mutex.withLock {
        val id = "demo-created-session-${UUID.randomUUID()}"
        val now = clock()
        sessionStates[id] = DemoSessionState(
            title = "Untitled task",
            createdAt = now,
            updatedAt = now,
        )
        id
    }

    override suspend fun conversation(sessionId: String, maxMessages: Int): RemoteConversationSnapshot = mutex.withLock {
        val state = sessionStates[sessionId]
            ?: throw HarnessRemoteClientException.Api("session-not-found", "This session was not found")
        val visible = if (maxMessages <= 0) emptyList() else state.items.takeLast(maxMessages)
        RemoteConversationSnapshot(
            visible,
            hasMore = state.items.size > visible.size,
            stats = state.stats,
            trajectory = visible.mapIndexed { index, item ->
                RemoteTrajectoryRecord(
                    "demo-trajectory-${item.id}",
                    index + 1,
                    0,
                    index,
                    when (item.kind) {
                        RemoteConversationKind.USER -> RemoteTrajectoryKind.INPUT
                        RemoteConversationKind.ASSISTANT -> RemoteTrajectoryKind.ASSISTANT
                        RemoteConversationKind.TOOL -> RemoteTrajectoryKind.TOOL
                        RemoteConversationKind.CONTEXT -> RemoteTrajectoryKind.CONTEXT
                        RemoteConversationKind.STATUS -> RemoteTrajectoryKind.LIFECYCLE
                    },
                    item.title ?: item.kind.name.lowercase().replaceFirstChar(Char::uppercase),
                    item.text,
                    item.time,
                    null,
                    item.state,
                    item.details,
                    item.attachments,
                )
            },
            goal = state.goal,
            plan = state.plan,
            imageLimits = RemoteImageLimits(
                20 * 1024 * 1024,
                4,
                40 * 1024 * 1024,
                40_000_000,
                8_192,
                SUPPORTED_IMAGE_TYPES.sorted(),
            ),
        )
    }

    override suspend fun attachment(sessionId: String, attachmentId: String): RemoteImageAttachmentPayload =
        mutex.withLock {
            uploadedAttachments[attachmentId] ?: if (attachmentId == DEMO_ATTACHMENT.attachmentId) {
                RemoteImageAttachmentPayload(DEMO_ATTACHMENT, DEMO_ATTACHMENT_DATA)
            } else {
                throw HarnessRemoteClientException.Api("attachment-not-found", "This image was not found")
            }
        }

    override suspend fun fileReferences(sessionId: String, query: String): List<RemoteFileReferenceCandidate> {
        val candidates = listOf(
            RemoteFileReferenceCandidate("Sources/Auth/LoginScreen.kt", RemoteReferenceKind.FILE),
            RemoteFileReferenceCandidate("Sources/Auth/SessionStore.kt", RemoteReferenceKind.FILE),
            RemoteFileReferenceCandidate("Tests/Auth", RemoteReferenceKind.DIRECTORY),
        )
        return candidates.filter { query.isBlank() || it.path.contains(query, ignoreCase = true) }
    }

    override suspend fun sessionReferences(sessionId: String, query: String): List<RemoteSessionReferenceCandidate> {
        val candidate = RemoteSessionReferenceCandidate(
            "@[Login error recovery](dsh-session:ZGVtby1yZWZlcmVuY2U)",
            "demo-reference",
            "Login error recovery",
            "/Users/demo/sample-app",
            clock() - 7_200_000,
        )
        return if (query.isBlank() || candidate.label.contains(query, ignoreCase = true)) listOf(candidate) else emptyList()
    }

    override suspend fun subagents(parentSessionId: String): RemoteSubagentCatalog = RemoteSubagentCatalog(
        if (parentSessionId == reviewSessionId) listOf(
            RemoteSubagentEntry(
                "demo-subagent",
                RemoteSubagentMode.CONTINUABLE,
                RemoteSubagentActivity.INACTIVE,
                false,
                "Login regression test",
                null,
            ),
        ) else emptyList(),
        parentAvailable = true,
    )

    override suspend fun subagentConversation(
        parentSessionId: String,
        child: RemoteSubagentEntry,
        maxMessages: Int,
    ): RemoteConversationSnapshot = RemoteConversationSnapshot(
        listOf(
            RemoteConversationItem(
                "demo-subagent-message",
                kind = RemoteConversationKind.ASSISTANT,
                title = null,
                text = "The existing login tests do not cover process recreation.",
                time = clock(),
                state = RemoteConversationState.SUCCEEDED,
            ),
        ),
        false,
        null,
    )

    override suspend fun promptSubagent(parentSessionId: String, child: RemoteSubagentEntry, text: String) = Unit
    override suspend fun interruptSubagent(parentSessionId: String, child: RemoteSubagentEntry) = Unit

    override suspend fun models(sessionId: String): RemoteModelDirectory = mutex.withLock {
        RemoteModelDirectory(
            selectedModel,
            true,
            listOf(
                RemoteModelProviderGroup(
                    "deepseek-official",
                    "DeepSeek",
                    listOf(
                        RemoteModelCatalogEntry(
                            "deepseek-v4-flash",
                            "DeepSeek-V4-Flash",
                            "Fast everyday coding and analysis",
                            RemoteModelReasoning(
                                listOf(
                                    RemoteModelReasoningEffort("off", "Off", "Disable deep reasoning"),
                                    RemoteModelReasoningEffort("high", "High", "Complex coding tasks"),
                                    RemoteModelReasoningEffort("max", "Max", "Use the largest reasoning budget"),
                                ),
                                "high",
                            ),
                        ),
                    ),
                ),
            ),
            emptyList(),
        )
    }

    override suspend fun selectModel(
        sessionId: String,
        selection: RemoteModelSelection,
    ): RemoteModelSelection {
        val directory = models(sessionId)
        return mutex.withLock {
        val model = directory.groups.firstOrNull { it.id == selection.provider }
            ?.models?.firstOrNull { it.id == selection.model }
            ?: throw HarnessRemoteClientException.Api("model-unavailable", "This model is unavailable")
        val effort = selection.reasoningEffort ?: model.reasoning?.defaultEffort
        if (effort != null && model.reasoning?.efforts?.none { it.id == effort } != false) {
            throw HarnessRemoteClientException.Api("model-unavailable", "This reasoning effort is unavailable")
        }
        RemoteModelSelection(selection.provider, selection.model, effort).also { selectedModel = it }
        }
    }

    override suspend fun send(text: String, images: List<RemotePromptImage>, sessionId: String, steer: Boolean) {
        val trimmed = text.trim()
        if (trimmed.isEmpty() && images.isEmpty()) return
        mutex.withLock {
            val state = sessionStates[sessionId]
                ?: throw HarnessRemoteClientException.Api("session-not-found", "This session was not found")
            val attachments = images.map { image ->
                val attachment = RemoteImageAttachment(
                    "demo-upload-${image.id}",
                    image.mediaType,
                    image.data.size,
                    image.width,
                    image.height,
                    image.name,
                )
                uploadedAttachments[attachment.attachmentId] = RemoteImageAttachmentPayload(attachment, image.data)
                attachment
            }
            state.items += RemoteConversationItem(
                UUID.randomUUID().toString(),
                state.items.size + 1,
                RemoteConversationKind.USER,
                if (steer) "Steer" else null,
                trimmed,
                clock(),
                attachments = attachments,
            )
            state.items += RemoteConversationItem(
                UUID.randomUUID().toString(),
                state.items.size + 1,
                RemoteConversationKind.ASSISTANT,
                null,
                "Received. All execution still happens on your computer.",
                clock(),
                RemoteConversationState.SUCCEEDED,
            )
            state.updatedAt = clock()
        }
    }

    override suspend fun updateQueue(sessionId: String, itemId: String, action: RemoteQueueAction) = Unit

    override suspend fun cancel(sessionId: String) {
        mutex.withLock {
            val state = sessionStates[sessionId]
                ?: throw HarnessRemoteClientException.Api("session-not-found", "This session was not found")
            state.running = false
            state.items += RemoteConversationItem(
                UUID.randomUUID().toString(),
                state.items.size + 1,
                RemoteConversationKind.STATUS,
                null,
                "You stopped the task",
                clock(),
                RemoteConversationState.STOPPED,
            )
            state.updatedAt = clock()
        }
    }

    override suspend fun respond(interaction: RemoteInteraction, decision: RemoteInteractionDecision) {
        mutex.withLock {
            val state = sessionStates[interaction.sessionId]
                ?: throw HarnessRemoteClientException.Api("session-not-found", "This session was not found")
            state.items += RemoteConversationItem(
                UUID.randomUUID().toString(),
                state.items.size + 1,
                RemoteConversationKind.STATUS,
                null,
                when (decision) {
                    RemoteInteractionDecision.AllowOnce -> "Allowed once"
                    RemoteInteractionDecision.Reject -> "Rejected"
                    is RemoteInteractionDecision.Answer -> "Answer submitted"
                    RemoteInteractionDecision.CancelQuestions -> "Question dismissed"
                },
                clock(),
                RemoteConversationState.SUCCEEDED,
            )
            state.updatedAt = clock()
        }
    }

    override fun liveEvents(): Flow<RemoteLiveEvent> = flow {
        delay(700)
        emit(
            RemoteLiveEvent.Interaction(
                RemoteInteraction(
                    "question:review-demo",
                    "review-demo",
                    reviewSessionId,
                    null,
                    RemoteInteractionKind.Questions(
                        listOf(
                            RemoteQuestion(
                                "release-choice",
                                "Confirmation",
                                "Apply the fixes before release?",
                                "1. Restore login state\n2. Improve offline guidance\n3. Add regression tests",
                                listOf(
                                    RemoteQuestionOption("Approve", "Continue on the computer"),
                                    RemoteQuestionOption("Not yet", "Keep the current result"),
                                ),
                                false,
                            ),
                        ),
                    ),
                ),
            ),
        )
    }

    private fun demoGoal(now: Long) = RemoteGoalState(
        "demo-goal",
        1,
        "Prepare the login flow for release",
        RemoteGoalPhase.ACTIVE,
        null,
        null,
        12,
        1,
        now - 180_000,
        now,
    )

    private data class DemoSessionState(
        val title: String,
        val createdAt: Long,
        var updatedAt: Long,
        var running: Boolean = false,
        val items: MutableList<RemoteConversationItem> = mutableListOf(),
        val goal: RemoteGoalState? = null,
        val stats: RemoteConversationStats? = null,
        val plan: RemotePlanState? = null,
    )

    companion object {
        private val DEMO_ATTACHMENT_DATA = Base64.getDecoder().decode(
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=",
        )
        private val DEMO_ATTACHMENT = RemoteImageAttachment(
            "demo-image",
            "image/png",
            DEMO_ATTACHMENT_DATA.size,
            1,
            1,
            "demo.png",
        )
    }
}
