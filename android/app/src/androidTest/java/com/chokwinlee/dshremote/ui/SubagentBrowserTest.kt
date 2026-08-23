package com.chokwinlee.dshremote.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertWidthIsAtLeast
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToIndex
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.chokwinlee.dshremote.R
import com.chokwinlee.dshremote.ui.features.subagents.SUBAGENT_TRANSCRIPT_TEST_TAG
import com.chokwinlee.dshremote.ui.features.subagents.SUBAGENT_COMPOSER_TEST_TAG
import com.chokwinlee.dshremote.ui.features.subagents.SubagentBrowserSheet
import com.chokwinlee.dshremote.ui.features.subagents.SubagentConversationContent
import com.chokwinlee.dshremote.ui.model.ConversationActor
import com.chokwinlee.dshremote.ui.model.ConversationMessageUiModel
import com.chokwinlee.dshremote.ui.model.SubagentActivityUi
import com.chokwinlee.dshremote.ui.model.SubagentCatalogUiState
import com.chokwinlee.dshremote.ui.model.SubagentConversationUiState
import com.chokwinlee.dshremote.ui.model.SubagentModeUi
import com.chokwinlee.dshremote.ui.model.SubagentUiModel
import com.chokwinlee.dshremote.ui.theme.DSHRemoteTheme
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SubagentBrowserTest {
    @get:Rule
    val compose = createComposeRule()

    private val context get() = ApplicationProvider.getApplicationContext<android.content.Context>()

    @Test
    fun nestedCatalogHasAccessibleBackNavigation() {
        val wentBack = AtomicBoolean(false)
        compose.setContent {
            DSHRemoteTheme {
                SubagentBrowserSheet(
                    catalog = SubagentCatalogUiState(
                        entries = listOf(subagent("grandchild")),
                        navigationDepth = 1,
                        parentLabel = "Release review",
                    ),
                    selected = null,
                    onDismiss = {},
                    onRefresh = {},
                    onOpen = {},
                    onNavigateBack = { wentBack.set(true) },
                    onOpenChildren = {},
                    onLoadOlder = {},
                    onContinue = { _, _ -> },
                    onStop = {},
                    onOpenAttachment = { _, _ -> },
                )
            }
        }

        compose.onNodeWithText(context.getString(R.string.subagent_nested_title)).assertIsDisplayed()
        compose.onNodeWithText("Release review", substring = true).assertIsDisplayed()
        compose.onNodeWithContentDescription(context.getString(R.string.action_back))
            .assertIsDisplayed()
            .assertWidthIsAtLeast(48.dp)
            .assertHeightIsAtLeast(48.dp)
            .performClick()
        compose.runOnIdle { assertTrue(wentBack.get()) }
    }

    @Test
    fun childConversationExposesNestedCatalogAsA48DpAction() {
        val openedChildren = AtomicBoolean(false)
        compose.setContent {
            DSHRemoteTheme {
                Box(Modifier.fillMaxSize()) {
                    SubagentConversationContent(
                        state = SubagentConversationUiState(
                            subagent = subagent("child", hasChildren = true),
                            messages = listOf(message(0)),
                        ),
                        onBack = {},
                        onOpenChildren = { openedChildren.set(true) },
                        onLoadOlder = {},
                        onContinue = {},
                        onStop = {},
                        onOpenAttachment = {},
                    )
                }
            }
        }

        compose.onNodeWithContentDescription(context.getString(R.string.subagent_open_children))
            .assertIsDisplayed()
            .assertWidthIsAtLeast(48.dp)
            .assertHeightIsAtLeast(48.dp)
            .performClick()
        compose.runOnIdle { assertTrue(openedChildren.get()) }
    }

    @Test
    fun updatesStayUnreadUntilTheReaderJumpsToLatest() {
        var state by mutableStateOf(
            SubagentConversationUiState(
                subagent = subagent("child"),
                messages = (0 until 24).map(::message),
            ),
        )
        compose.setContent {
            DSHRemoteTheme {
                SubagentConversationContent(
                    state = state,
                    onBack = {},
                    onOpenChildren = {},
                    onLoadOlder = {},
                    onContinue = {},
                    onStop = {},
                    onOpenAttachment = {},
                )
            }
        }
        compose.waitForIdle()
        compose.onNodeWithTag(SUBAGENT_TRANSCRIPT_TEST_TAG).performScrollToIndex(0)
        compose.runOnIdle {
            state = state.copy(messages = state.messages + message(24) + message(25))
        }

        val unread = context.resources.getQuantityString(R.plurals.subagent_new_updates, 2, 2)
        compose.onNodeWithText(unread)
            .assertIsDisplayed()
            .assertHeightIsAtLeast(48.dp)
            .performClick()
        compose.onNodeWithText(unread).assertDoesNotExist()
    }

    @Test
    fun continuableSheetKeepsSendAndStopControlsReachable() {
        var selected by mutableStateOf(
            SubagentConversationUiState(
                subagent = subagent("child"),
                messages = (0 until 30).map(::message),
            ),
        )
        val continued = AtomicReference<String?>()
        val stopped = AtomicBoolean(false)
        compose.setContent {
            DSHRemoteTheme {
                SubagentBrowserSheet(
                    catalog = SubagentCatalogUiState(),
                    selected = selected,
                    onDismiss = {},
                    onRefresh = {},
                    onOpen = {},
                    onNavigateBack = {},
                    onOpenChildren = {},
                    onLoadOlder = {},
                    onContinue = { _, text -> continued.set(text) },
                    onStop = { stopped.set(true) },
                    onOpenAttachment = { _, _ -> },
                )
            }
        }

        compose.onNodeWithTag(SUBAGENT_COMPOSER_TEST_TAG).assertIsDisplayed()
        compose.onNodeWithContentDescription(context.getString(R.string.subagent_input_label))
            .assertIsDisplayed()
            .performTextInput("Continue the review")
        compose.onNodeWithContentDescription(context.getString(R.string.subagent_continue_send))
            .assertIsDisplayed()
            .assertWidthIsAtLeast(48.dp)
            .assertHeightIsAtLeast(48.dp)
            .performClick()
        compose.runOnIdle {
            assertTrue(continued.get() == "Continue the review")
            selected = selected.copy(
                subagent = selected.subagent.copy(activity = SubagentActivityUi.Running),
                parentAvailable = false,
            )
        }
        compose.onNodeWithContentDescription(context.getString(R.string.subagent_stop))
            .assertIsDisplayed()
            .assertWidthIsAtLeast(48.dp)
            .assertHeightIsAtLeast(48.dp)
            .performClick()
        compose.runOnIdle { assertTrue(stopped.get()) }
    }

    private fun subagent(id: String, hasChildren: Boolean = false) = SubagentUiModel(
        id = id,
        label = id,
        mode = SubagentModeUi.Continuable,
        activity = SubagentActivityUi.Inactive,
        hasChildren = hasChildren,
    )

    private fun message(index: Int) = ConversationMessageUiModel(
        id = "message-$index",
        actor = ConversationActor.Assistant,
        text = "Subagent update $index with enough detail to occupy a readable transcript row.",
    )
}
