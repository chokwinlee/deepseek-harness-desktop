package com.chokwinlee.dshremote.app

import com.chokwinlee.dshremote.remote.RemoteConversationItem
import com.chokwinlee.dshremote.remote.RemoteConversationKind
import com.chokwinlee.dshremote.remote.RemoteConversationSnapshot
import com.chokwinlee.dshremote.remote.RemoteConversationState
import com.chokwinlee.dshremote.remote.RemoteDetailKind
import com.chokwinlee.dshremote.remote.RemoteDetailSection
import com.chokwinlee.dshremote.remote.RemoteGoalPhase
import com.chokwinlee.dshremote.remote.RemoteGoalState
import com.chokwinlee.dshremote.remote.RemoteInteraction
import com.chokwinlee.dshremote.remote.RemoteInteractionKind
import com.chokwinlee.dshremote.remote.RemoteQuestion
import com.chokwinlee.dshremote.remote.RemoteQuestionOption
import com.chokwinlee.dshremote.remote.RemoteQueuedMessage
import com.chokwinlee.dshremote.remote.RemoteQueuedPlacement
import com.chokwinlee.dshremote.remote.RemoteSubagentActivity
import com.chokwinlee.dshremote.remote.RemoteSubagentDiagnosticReason
import com.chokwinlee.dshremote.remote.RemoteSubagentEntry
import com.chokwinlee.dshremote.remote.RemoteSubagentMode
import com.chokwinlee.dshremote.remote.RemoteTrajectoryKind
import com.chokwinlee.dshremote.remote.RemoteTrajectoryRecord
import org.junit.Assert.assertEquals
import org.junit.Test

class RemoteUiMapperTest {
    private val localize: (String) -> String = { value -> "localized:$value" }

    @Test
    fun conversationAndTrajectoryApplyProductCopyLocalization() {
        val item = RemoteConversationItem(
            id = "item",
            kind = RemoteConversationKind.STATUS,
            title = "Lifecycle",
            text = "Stopped",
            time = 1,
            state = RemoteConversationState.STOPPED,
            details = listOf(
                RemoteDetailSection("detail", "Model context", "payload", RemoteDetailKind.TEXT),
            ),
            metadata = listOf("12 tokens"),
        )
        val trajectory = RemoteTrajectoryRecord(
            id = "trajectory",
            sequence = 1,
            turn = 0,
            step = 1,
            kind = RemoteTrajectoryKind.LIFECYCLE,
            title = "Lifecycle",
            summary = "Stopped",
            time = 1,
            durationMs = null,
            state = RemoteConversationState.STOPPED,
            details = item.details,
        )
        val snapshot = RemoteConversationSnapshot(
            items = listOf(item),
            hasMore = false,
            stats = null,
            trajectory = listOf(trajectory),
            goal = RemoteGoalState(
                id = "goal",
                revision = 1,
                objective = "Prepare release",
                phase = RemoteGoalPhase.ACTIVE,
                blockedReasonCode = null,
                blockedReasonMessage = null,
                maxRounds = 3,
                roundsStarted = 1,
                createdAt = 1,
                updatedAt = 1,
            ),
        )

        val message = RemoteUiMapper.conversation(snapshot, localize).single()
        assertEquals("localized:Lifecycle", message.title)
        assertEquals("localized:Stopped", message.text)
        assertEquals("localized:Model context", message.details.single().title)
        assertEquals(listOf("localized:12 tokens"), message.metadata)

        val record = RemoteUiMapper.trajectory(snapshot, localize).single()
        assertEquals("localized:Lifecycle", record.title)
        assertEquals("localized:Stopped", record.summary)
        assertEquals(1, record.turn)
        assertEquals(2, record.step)
        assertEquals("localized:Prepare release", RemoteUiMapper.goal(snapshot, localize)?.objective)
    }

    @Test
    fun questionsAndSubagentsApplyProductCopyLocalization() {
        val interaction = RemoteInteraction(
            id = "question:1",
            rpcId = "rpc",
            sessionId = "session",
            approvalId = null,
            kind = RemoteInteractionKind.Questions(
                listOf(
                    RemoteQuestion(
                        id = "question",
                        header = "Confirmation",
                        question = "Continue?",
                        detail = "Review changes",
                        options = listOf(RemoteQuestionOption("Approve", "Continue on computer")),
                        allowsMultipleSelection = false,
                    ),
                ),
            ),
        )
        val mapped = RemoteUiMapper.interaction(interaction, localize = localize)
        assertEquals("localized:Confirmation", mapped?.title)
        assertEquals("localized:Continue?", mapped?.questions?.single()?.question)
        assertEquals("localized:Approve", mapped?.questions?.single()?.options?.single()?.label)

        val subagent = RemoteSubagentEntry(
            id = "subagent",
            mode = RemoteSubagentMode.CONTINUABLE,
            activity = RemoteSubagentActivity.INACTIVE,
            hasChildren = false,
            label = "Regression test",
            diagnosticReason = RemoteSubagentDiagnosticReason.UNAVAILABLE,
        )
        val mappedSubagent = RemoteUiMapper.subagent(
            entry = subagent,
            diagnosticName = { "localized:${it.name}" },
            localizeLabel = localize,
        )
        assertEquals("localized:Regression test", mappedSubagent.label)
        assertEquals("localized:UNAVAILABLE", mappedSubagent.diagnosticMessage)
    }

    @Test
    fun queuePreviewUsesLocalizedProductCopyAndPreservesUserText() {
        val mapped = RemoteUiMapper.queue(
            items = listOf(
                RemoteQueuedMessage("mixed", RemoteQueuedPlacement.QUEUED, "", "检查截图", 2),
                RemoteQueuedMessage("image", RemoteQueuedPlacement.QUEUED, "", null, 1),
                RemoteQueuedMessage("empty", RemoteQueuedPlacement.QUEUED, "", null, 0),
            ),
            imageCountLabel = { count -> "$count 张图片" },
            emptyLabel = "排队指令",
        )

        assertEquals(listOf("检查截图 · 2 张图片", "1 张图片", "排队指令"), mapped.map { it.preview })
    }

    @Test
    fun modelDescriptionsUseProductLocalizationWithoutChangingNames() {
        val directory = com.chokwinlee.dshremote.remote.RemoteModelDirectory(
            current = com.chokwinlee.dshremote.remote.RemoteModelSelection("provider", "model", "high"),
            routable = true,
            groups = listOf(
                com.chokwinlee.dshremote.remote.RemoteModelProviderGroup(
                    "provider",
                    "Provider",
                    listOf(
                        com.chokwinlee.dshremote.remote.RemoteModelCatalogEntry(
                            "model",
                            "Model",
                            "Fast everyday coding and analysis",
                            com.chokwinlee.dshremote.remote.RemoteModelReasoning(
                                listOf(
                                    com.chokwinlee.dshremote.remote.RemoteModelReasoningEffort(
                                        "high",
                                        "High",
                                        "Complex coding tasks",
                                    ),
                                ),
                                "high",
                            ),
                        ),
                    ),
                ),
            ),
            failures = emptyList(),
        )

        val model = RemoteUiMapper.models(directory, localizeDescription = localize)
            .groups.single().models.single()

        assertEquals("Model", model.name)
        assertEquals("localized:Fast everyday coding and analysis", model.description)
        assertEquals("High", model.reasoningEfforts.single().name)
        assertEquals("localized:Complex coding tasks", model.reasoningEfforts.single().description)
    }
}
