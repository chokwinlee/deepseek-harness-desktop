package com.chokwinlee.dshremote.ui

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.chokwinlee.dshremote.R
import com.chokwinlee.dshremote.ui.features.queue.QueueDock
import com.chokwinlee.dshremote.ui.model.ModelDirectoryUiState
import com.chokwinlee.dshremote.ui.model.ModelOptionUiModel
import com.chokwinlee.dshremote.ui.model.ModelProviderGroupUiModel
import com.chokwinlee.dshremote.ui.model.ModelSelectionUiModel
import com.chokwinlee.dshremote.ui.model.ProjectListUiState
import com.chokwinlee.dshremote.ui.model.ProjectUiModel
import com.chokwinlee.dshremote.ui.model.QueuePlacementUi
import com.chokwinlee.dshremote.ui.model.QueuedMessageUiModel
import com.chokwinlee.dshremote.ui.model.SessionDetailCallbacks
import com.chokwinlee.dshremote.ui.model.SessionDetailUiState
import com.chokwinlee.dshremote.ui.model.SessionExecutionState
import com.chokwinlee.dshremote.ui.model.SessionUiModel
import com.chokwinlee.dshremote.ui.screens.ProjectListScreen
import com.chokwinlee.dshremote.ui.screens.SessionDetailScreen
import com.chokwinlee.dshremote.ui.theme.DSHRemoteTheme
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class P1ParityUiTest {
    @get:Rule
    val compose = createComposeRule()

    private val context get() = ApplicationProvider.getApplicationContext<android.content.Context>()

    @Test
    fun unroutableCurrentModelCanSelectARecoveryModel() {
        val selected = AtomicReference<ModelSelectionUiModel?>()
        val selectionResult = AtomicReference<((Boolean) -> Unit)?>()
        compose.setContent {
            DSHRemoteTheme {
                SessionDetailScreen(
                    state = SessionDetailUiState(
                        session = SessionUiModel("session", "Model recovery", "now", SessionExecutionState.Idle),
                        hasLoadedOnce = true,
                        models = ModelDirectoryUiState(
                            current = ModelSelectionUiModel("provider", "Provider", "broken", "Unavailable model"),
                            routable = false,
                            groups = listOf(
                                ModelProviderGroupUiModel(
                                    id = "provider",
                                    name = "Provider",
                                    models = listOf(
                                        ModelOptionUiModel("broken", "Unavailable model"),
                                        ModelOptionUiModel("recovery", "Recovery model"),
                                    ),
                                ),
                            ),
                        ),
                    ),
                    onBack = {},
                    onRefresh = {},
                    onSendMessage = {},
                    onStopSession = {},
                    featureCallbacks = SessionDetailCallbacks(
                        onSelectModel = { selection, onResult ->
                            selected.set(selection)
                            selectionResult.set(onResult)
                        },
                    ),
                )
            }
        }

        compose.onNodeWithContentDescription(context.getString(R.string.session_more_actions)).performClick()
        compose.onNodeWithText(context.getString(R.string.model_open)).performClick()
        compose.onNodeWithText("Recovery model").performClick()
        compose.onNodeWithText(context.getString(R.string.model_use_action))
            .assertIsEnabled()
            .performClick()
        compose.onNodeWithText(context.getString(R.string.model_picker_title)).assertIsDisplayed()
        compose.runOnIdle {
            assertEquals("recovery", selected.get()?.modelId)
            selectionResult.get()?.invoke(true)
        }
        compose.onNodeWithText(context.getString(R.string.model_picker_title)).assertDoesNotExist()
        compose.onNodeWithText(context.getString(R.string.model_selection_applied_title)).assertIsDisplayed()
    }

    @Test
    fun newSessionFailureOffersProjectSpecificRetry() {
        val project = ProjectUiModel("project", "Desktop", "/workspace/desktop")
        val retried = AtomicReference<String?>()
        compose.setContent {
            DSHRemoteTheme {
                ProjectListScreen(
                    state = ProjectListUiState(
                        computerName = "Mac",
                        projects = listOf(project),
                        hasLoadedOnce = true,
                        createSessionErrorMessage = "Computer rejected the request",
                        lastCreateSessionProjectId = project.id,
                    ),
                    onBack = {},
                    onRefresh = {},
                    onCreateSession = retried::set,
                    onSessionSelected = {},
                )
            }
        }

        compose.onNodeWithContentDescription(context.getString(R.string.session_new_action)).performClick()
        compose.onNodeWithText(context.getString(R.string.session_create_failed_title)).assertIsDisplayed()
        compose.onNodeWithText(context.getString(R.string.action_retry)).performClick()
        compose.runOnIdle { assertEquals(project.id, retried.get()) }
    }

    @Test
    fun newSessionSheetKeepsProgressVisibleAndCannotClose() {
        val project = ProjectUiModel("project", "Desktop", "/workspace/desktop")
        compose.setContent {
            DSHRemoteTheme {
                ProjectListScreen(
                    state = ProjectListUiState(
                        computerName = "Mac",
                        projects = listOf(project),
                        hasLoadedOnce = true,
                        creatingSessionProjectId = project.id,
                        lastCreateSessionProjectId = project.id,
                    ),
                    onBack = {},
                    onRefresh = {},
                    onCreateSession = {},
                    onSessionSelected = {},
                )
            }
        }
        compose.onNodeWithContentDescription(context.getString(R.string.session_new_action)).performClick()
        compose.onNodeWithText(context.getString(R.string.session_creating)).assertIsDisplayed()
        compose.onNodeWithContentDescription(context.getString(R.string.action_close)).assertDoesNotExist()
    }

    @Test
    fun queuedImagesExplainWhyTextEditingIsDisabled() {
        compose.setContent {
            DSHRemoteTheme {
                QueueDock(
                    queue = listOf(
                        QueuedMessageUiModel(
                            id = "image-message",
                            placement = QueuePlacementUi.Queued,
                            preview = "Review screenshot",
                            text = "Review screenshot",
                            attachmentCount = 1,
                        ),
                    ),
                    isRunning = true,
                    onUpdate = { _, _ -> },
                )
            }
        }

        compose.onNodeWithText(context.getString(R.string.queue_title)).performClick()
        compose.onNodeWithText(context.getString(R.string.queue_image_edit_hint)).assertIsDisplayed()
        compose.onNodeWithContentDescription(context.getString(R.string.queue_edit_images_disabled))
            .assertIsNotEnabled()
    }
}
