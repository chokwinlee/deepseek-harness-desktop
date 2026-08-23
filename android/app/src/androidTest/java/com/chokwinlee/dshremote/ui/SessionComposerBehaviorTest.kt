package com.chokwinlee.dshremote.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToIndex
import androidx.compose.ui.test.performTextInput
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.chokwinlee.dshremote.R
import com.chokwinlee.dshremote.ui.features.composer.COMPOSER_ERROR_TEST_TAG
import com.chokwinlee.dshremote.ui.model.ConversationActor
import com.chokwinlee.dshremote.ui.model.ConversationMessageUiModel
import com.chokwinlee.dshremote.ui.model.SessionDetailCallbacks
import com.chokwinlee.dshremote.ui.model.SessionDetailUiState
import com.chokwinlee.dshremote.ui.model.SessionExecutionState
import com.chokwinlee.dshremote.ui.model.SessionUiModel
import com.chokwinlee.dshremote.ui.screens.SESSION_HISTORY_TEST_TAG
import com.chokwinlee.dshremote.ui.screens.SessionDetailScreen
import com.chokwinlee.dshremote.ui.theme.DSHRemoteTheme
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SessionComposerBehaviorTest {
    @get:Rule
    val compose = createComposeRule()

    private val context get() = ApplicationProvider.getApplicationContext<android.content.Context>()

    @Test
    fun inputFailureStaysVisibleAtTheComposerAndIsAnnounced() {
        compose.setContent {
            DSHRemoteTheme {
                SessionDetailScreen(
                    state = state().copy(errorMessage = "Clipboard image unavailable"),
                    onBack = {},
                    onRefresh = {},
                    onSendMessage = {},
                    onStopSession = {},
                )
            }
        }

        compose.onNodeWithTag(COMPOSER_ERROR_TEST_TAG)
            .assertIsDisplayed()
            .assert(
                SemanticsMatcher.expectValue(
                    SemanticsProperties.LiveRegion,
                    LiveRegionMode.Assertive,
                ),
            )
    }

    @Test
    fun sendingFromOlderHistoryFollowsTheNewMessage() {
        var state by mutableStateOf(state())
        compose.setContent {
            DSHRemoteTheme {
                SessionDetailScreen(
                    state = state,
                    onBack = {},
                    onRefresh = {},
                    onSendMessage = {},
                    onStopSession = {},
                    featureCallbacks = SessionDetailCallbacks(
                        onSendPrompt = { text, _ ->
                            state = state.copy(
                                messages = state.messages +
                                    ConversationMessageUiModel("sent", ConversationActor.User, text) +
                                    ConversationMessageUiModel("fresh", ConversationActor.Assistant, "Fresh response"),
                            )
                        },
                    ),
                )
            }
        }
        compose.waitForIdle()
        compose.onNodeWithTag(SESSION_HISTORY_TEST_TAG).performScrollToIndex(0)
        compose.onNodeWithContentDescription(context.getString(R.string.composer_input_label))
            .performTextInput("Review the image")
        compose.onNodeWithContentDescription(context.getString(R.string.conversation_send)).performClick()

        compose.onNodeWithText("Fresh response").assertIsDisplayed()
    }

    private fun state() = SessionDetailUiState(
        session = SessionUiModel("session", "Release review", "now", SessionExecutionState.Idle),
        messages = (0 until 30).map { index ->
            ConversationMessageUiModel(
                id = "message-$index",
                actor = ConversationActor.Assistant,
                text = "Earlier update $index with enough content to keep the history scrollable.",
            )
        },
        hasLoadedOnce = true,
    )
}
