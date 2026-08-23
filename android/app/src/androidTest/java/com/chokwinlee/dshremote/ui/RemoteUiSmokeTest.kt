package com.chokwinlee.dshremote.ui

import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertWidthIsAtLeast
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasStateDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.chokwinlee.dshremote.R
import com.chokwinlee.dshremote.ui.model.AddComputerUiState
import com.chokwinlee.dshremote.ui.model.ComputerListUiState
import com.chokwinlee.dshremote.ui.model.ConversationActor
import com.chokwinlee.dshremote.ui.model.ConversationMessageUiModel
import com.chokwinlee.dshremote.ui.model.GoalPhaseUi
import com.chokwinlee.dshremote.ui.model.GoalUiModel
import com.chokwinlee.dshremote.ui.model.InteractionKindUi
import com.chokwinlee.dshremote.ui.model.InteractionUiModel
import com.chokwinlee.dshremote.ui.model.ModelDirectoryUiState
import com.chokwinlee.dshremote.ui.model.ModelOptionUiModel
import com.chokwinlee.dshremote.ui.model.ModelProviderGroupUiModel
import com.chokwinlee.dshremote.ui.model.ModelSelectionUiModel
import com.chokwinlee.dshremote.ui.model.PlanUiModel
import com.chokwinlee.dshremote.ui.model.PromptImageUiModel
import com.chokwinlee.dshremote.ui.model.ProjectListUiState
import com.chokwinlee.dshremote.ui.model.ProjectUiModel
import com.chokwinlee.dshremote.ui.model.QueuePlacementUi
import com.chokwinlee.dshremote.ui.model.QueuedMessageUiModel
import com.chokwinlee.dshremote.ui.model.QuestionOptionUiModel
import com.chokwinlee.dshremote.ui.model.ReferenceCandidateKind
import com.chokwinlee.dshremote.ui.model.ReferenceCandidateUiModel
import com.chokwinlee.dshremote.ui.model.ReferenceSuggestionsUiState
import com.chokwinlee.dshremote.ui.model.SessionDetailCallbacks
import com.chokwinlee.dshremote.ui.model.SessionDetailUiState
import com.chokwinlee.dshremote.ui.model.SessionExecutionState
import com.chokwinlee.dshremote.ui.model.SessionUiModel
import com.chokwinlee.dshremote.ui.model.StructuredQuestionUiModel
import com.chokwinlee.dshremote.ui.model.TrajectoryKindUi
import com.chokwinlee.dshremote.ui.model.TrajectoryRecordUiModel
import com.chokwinlee.dshremote.ui.screens.AddComputerScreen
import com.chokwinlee.dshremote.ui.screens.AboutRemoteScreen
import com.chokwinlee.dshremote.ui.screens.ComputerListScreen
import com.chokwinlee.dshremote.ui.screens.ProjectListScreen
import com.chokwinlee.dshremote.ui.screens.SessionDetailScreen
import com.chokwinlee.dshremote.ui.theme.DSHRemoteTheme
import java.util.concurrent.atomic.AtomicBoolean
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class RemoteUiSmokeTest {
    @get:Rule
    val compose = createComposeRule()

    private val context get() = ApplicationProvider.getApplicationContext<android.content.Context>()

    @Test
    fun freshInstallExplainsPairingAndOffersDemo() {
        val addInvoked = AtomicBoolean(false)
        val demoInvoked = AtomicBoolean(false)
        compose.setContent {
            DSHRemoteTheme {
                ComputerListScreen(
                    state = ComputerListUiState(),
                    onAddComputer = { addInvoked.set(true) },
                    onComputerSelected = {},
                    onRemoveComputer = {},
                    onTryDemo = { demoInvoked.set(true) },
                    onRefresh = {},
                    onOpenAbout = {},
                )
            }
        }

        compose.onNodeWithText(context.getString(R.string.onboarding_title)).assertIsDisplayed()
        compose.onNodeWithText(context.getString(R.string.onboarding_primary_action))
            .assertIsDisplayed()
            .assertHeightIsAtLeast(44.dp)
            .performClick()
        compose.onNodeWithText(context.getString(R.string.onboarding_demo_action))
            .assertIsDisplayed()
            .performClick()
        compose.runOnIdle {
            assertTrue(addInvoked.get())
            assertTrue(demoInvoked.get())
        }
    }

    @Test
    fun addComputerKeepsQrPrimaryAndHttpsRecoverable() {
        val scanInvoked = AtomicBoolean(false)
        val settingsInvoked = AtomicBoolean(false)
        compose.setContent {
            DSHRemoteTheme {
                AddComputerScreen(
                    state = AddComputerUiState(
                        errorMessage = "Connection refused",
                        needsLocalNetworkPermission = true,
                    ),
                    onBack = {},
                    onScanQrCode = { scanInvoked.set(true) },
                    onVerifyAndSave = { _, _ -> },
                    onOpenSettings = { settingsInvoked.set(true) },
                )
            }
        }

        compose.onNodeWithText(context.getString(R.string.pairing_scan_title))
            .assertIsDisplayed()
            .performClick()
        compose.onNodeWithText("Connection refused").assertIsDisplayed()
        compose.onNodeWithText(context.getString(R.string.action_open_settings)).performClick()
        compose.runOnIdle {
            assertTrue(scanInvoked.get())
            assertTrue(settingsInvoked.get())
        }
    }

    @Test
    fun aboutExplainsBoundariesAndConfirmsLocalDataRemoval() {
        val removed = AtomicBoolean(false)
        compose.setContent {
            DSHRemoteTheme {
                AboutRemoteScreen(
                    savedComputerCount = 2,
                    onBack = {},
                    onRemoveAllComputers = { removed.set(true) },
                )
            }
        }

        compose.onNodeWithText(context.getString(R.string.about_local_first_title)).assertIsDisplayed()
        compose.onNodeWithText(context.getString(R.string.about_tailscale_title)).assertIsDisplayed()
        compose.onNodeWithText(context.getString(R.string.about_remove_all_action))
            .performScrollTo()
            .assertIsDisplayed()
            .performClick()
        compose.onNodeWithText(context.getString(R.string.about_remove_all_confirm)).performClick()
        compose.runOnIdle { assertTrue(removed.get()) }
    }

    @Test
    fun projectsExposeRunningSessionAndNewSessionAction() {
        val session = SessionUiModel(
            id = "session-1",
            title = "Android acceptance",
            updatedLabel = "now",
            state = SessionExecutionState.Running,
        )
        compose.setContent {
            DSHRemoteTheme {
                ProjectListScreen(
                    state = ProjectListUiState(
                        computerName = "Development Mac",
                        projects = listOf(
                            ProjectUiModel(
                                id = "project-1",
                                title = "DSH Remote",
                                path = "/workspace/dsh",
                                sessions = listOf(session),
                            ),
                        ),
                        hasLoadedOnce = true,
                    ),
                    onBack = {},
                    onRefresh = {},
                    onCreateSession = {},
                    onSessionSelected = {},
                )
            }
        }

        compose.onNodeWithText("DSH Remote").assertIsDisplayed()
        compose.onNodeWithText("Android acceptance").assertIsDisplayed()
        compose.onNodeWithContentDescription(context.getString(R.string.session_new_action))
            .assertIsDisplayed()
            .assertHeightIsAtLeast(44.dp)
    }

    @Test
    fun sessionExposesApprovalQueueModelsAndTrajectory() {
        val session = SessionUiModel(
            id = "session-advanced",
            title = "Full Remote control",
            updatedLabel = "now",
            state = SessionExecutionState.WaitingForApproval,
        )
        val state = SessionDetailUiState(
            session = session,
            projectName = "DSH Remote",
            messages = listOf(
                ConversationMessageUiModel(
                    id = "assistant-1",
                    actor = ConversationActor.Assistant,
                    text = "The Android build is ready for review.",
                ),
            ),
            hasLoadedOnce = true,
            queue = listOf(
                QueuedMessageUiModel(
                    id = "queue-1",
                    placement = QueuePlacementUi.Queued,
                    preview = "Run the device acceptance suite",
                ),
            ),
            interaction = InteractionUiModel(
                id = "approval-1",
                kind = InteractionKindUi.Approval,
                title = "Approval required",
                detail = "Run reviewed command",
                toolName = "exec_command",
            ),
            models = ModelDirectoryUiState(
                current = ModelSelectionUiModel("deepseek", "DeepSeek", "chat", "Chat"),
                groups = listOf(
                    ModelProviderGroupUiModel(
                        id = "deepseek",
                        name = "DeepSeek",
                        models = listOf(ModelOptionUiModel(id = "chat", name = "Chat")),
                    ),
                ),
            ),
            goal = GoalUiModel(
                id = "goal-1",
                objective = "Ship Android Remote",
                phase = GoalPhaseUi.Active,
                roundsStarted = 1,
                maxRounds = 3,
                revision = 1,
            ),
            plan = PlanUiModel(active = true, pending = false),
            trajectory = listOf(
                TrajectoryRecordUiModel(
                    id = "trajectory-1",
                    sequence = 1,
                    kind = TrajectoryKindUi.Tool,
                    title = "Android build",
                    summary = "assembleDebug completed",
                ),
            ),
        )
        compose.setContent {
            DSHRemoteTheme {
                SessionDetailScreen(
                    state = state,
                    onBack = {},
                    onRefresh = {},
                    onSendMessage = {},
                    onStopSession = {},
                    featureCallbacks = SessionDetailCallbacks(),
                )
            }
        }

        compose.onNodeWithText("Approval required").assertIsDisplayed()
        compose.onNodeWithText(
            context.resources.getQuantityString(R.plurals.queue_count, 1, 1),
        ).performClick()
        compose.onNodeWithText("Run the device acceptance suite").assertIsDisplayed()
        compose.onNodeWithText("Ship Android Remote").assertIsDisplayed()
        compose.onNodeWithContentDescription(context.getString(R.string.session_more_actions))
            .assertIsDisplayed()
            .performClick()
        compose.onNodeWithText(context.getString(R.string.model_open)).performClick()
        compose.onNodeWithText("DeepSeek").assertIsDisplayed()
        compose.onNodeWithText(context.getString(R.string.action_cancel)).performClick()
        compose.onNodeWithText(context.getString(R.string.trajectory_tab)).performClick()
        compose.onNodeWithText("Android build").assertIsDisplayed()
    }

    @Test
    fun composerAndDisclosuresExposeStableLabelsAndFortyEightDpTargets() {
        val state = SessionDetailUiState(
            session = SessionUiModel(
                id = "session-accessibility",
                title = "Accessibility",
                updatedLabel = "now",
                state = SessionExecutionState.Running,
            ),
            messages = listOf(
                ConversationMessageUiModel(
                    id = "reasoning",
                    actor = ConversationActor.Assistant,
                    text = "Ready",
                    reasoning = "Checked the current state.",
                ),
            ),
            hasLoadedOnce = true,
            pendingImages = listOf(PromptImageUiModel(id = "image", name = "screen.png")),
            references = ReferenceSuggestionsUiState(
                candidates = listOf(
                    ReferenceCandidateUiModel(
                        id = "readme",
                        mention = "README.md",
                        label = "README.md",
                        kind = ReferenceCandidateKind.File,
                    ),
                ),
            ),
        )
        compose.setContent {
            DSHRemoteTheme {
                SessionDetailScreen(
                    state = state,
                    onBack = {},
                    onRefresh = {},
                    onSendMessage = {},
                    onStopSession = {},
                    featureCallbacks = SessionDetailCallbacks(),
                )
            }
        }

        compose.onNodeWithContentDescription(context.getString(R.string.composer_input_label)).assertIsDisplayed()
        compose.onNodeWithContentDescription(context.getString(R.string.composer_delivery_options))
            .assertHeightIsAtLeast(48.dp)
            .assertWidthIsAtLeast(48.dp)
        compose.onNodeWithContentDescription(context.getString(R.string.attachment_remove))
            .assertHeightIsAtLeast(48.dp)
            .assertWidthIsAtLeast(48.dp)
        compose.onNode(
                hasText(context.getString(R.string.reasoning_title)) and
                hasClickAction() and
                hasStateDescription(context.getString(R.string.detail_state_collapsed)),
        ).assertHeightIsAtLeast(48.dp)
        compose.onNode(hasSetTextAction()).performTextInput("@")
        compose.onNodeWithContentDescription(context.getString(R.string.action_close))
            .assertHeightIsAtLeast(48.dp)
            .assertWidthIsAtLeast(48.dp)
    }

    @Test
    fun structuredQuestionsKeepTranscriptAndActionsVisibleAtLargeText() {
        val questions = List(3) { index ->
            StructuredQuestionUiModel(
                id = "question-$index",
                header = "Question ${index + 1}",
                question = "Choose the safest option for this long structured question.",
                options = List(4) { option ->
                    QuestionOptionUiModel("Option ${option + 1}", "A detailed explanation for this option")
                },
            )
        }
        val state = SessionDetailUiState(
            session = SessionUiModel(
                id = "session-questions",
                title = "Structured questions",
                updatedLabel = "now",
                state = SessionExecutionState.WaitingForApproval,
            ),
            messages = listOf(
                ConversationMessageUiModel(
                    id = "anchor",
                    actor = ConversationActor.Assistant,
                    text = "Transcript anchor",
                ),
            ),
            hasLoadedOnce = true,
            interaction = InteractionUiModel(
                id = "questions",
                kind = InteractionKindUi.Questions,
                title = "Review choices",
                questions = questions,
            ),
        )
        compose.setContent {
            val currentDensity = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(currentDensity.density, fontScale = 1.8f)) {
                DSHRemoteTheme {
                    SessionDetailScreen(
                        state = state,
                        onBack = {},
                        onRefresh = {},
                        onSendMessage = {},
                        onStopSession = {},
                        featureCallbacks = SessionDetailCallbacks(),
                    )
                }
            }
        }

        compose.onNodeWithText("Transcript anchor").assertIsDisplayed()
        compose.onNodeWithText(context.getString(R.string.action_cancel)).assertIsDisplayed()
        compose.onNodeWithText(context.getString(R.string.question_submit)).assertIsDisplayed()
    }

    @Test
    fun longQueueScrollsWithHistoryInsteadOfCrushingTranscript() {
        val state = SessionDetailUiState(
            session = SessionUiModel("session-queue", "Queue", "now", SessionExecutionState.Running),
            messages = listOf(
                ConversationMessageUiModel("anchor", ConversationActor.Assistant, "Latest transcript item"),
            ),
            hasLoadedOnce = true,
            queue = List(12) { index ->
                QueuedMessageUiModel("queue-$index", QueuePlacementUi.Queued, "Queued instruction $index")
            },
        )
        compose.setContent {
            DSHRemoteTheme {
                SessionDetailScreen(
                    state = state,
                    onBack = {},
                    onRefresh = {},
                    onSendMessage = {},
                    onStopSession = {},
                    featureCallbacks = SessionDetailCallbacks(),
                )
            }
        }

        compose.waitForIdle()
        compose.onNodeWithText("Latest transcript item").assertIsDisplayed()
    }
}
