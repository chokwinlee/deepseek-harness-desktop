package com.chokwinlee.dshremote.ui

import android.content.ClipboardManager
import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.chokwinlee.dshremote.R
import com.chokwinlee.dshremote.ui.features.session.SessionStatusBand
import com.chokwinlee.dshremote.ui.features.trajectory.TrajectoryLedger
import com.chokwinlee.dshremote.ui.model.DetailSectionKind
import com.chokwinlee.dshremote.ui.model.DetailSectionUiModel
import com.chokwinlee.dshremote.ui.model.GoalPhaseUi
import com.chokwinlee.dshremote.ui.model.GoalUiModel
import com.chokwinlee.dshremote.ui.model.SessionExecutionState
import com.chokwinlee.dshremote.ui.model.TrajectoryKindUi
import com.chokwinlee.dshremote.ui.model.TrajectoryRecordUiModel
import com.chokwinlee.dshremote.ui.screens.AboutRemoteScreen
import com.chokwinlee.dshremote.ui.theme.DSHRemoteTheme
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class InformationDepthUiTest {
    @get:Rule
    val compose = createComposeRule()

    private val context get() = ApplicationProvider.getApplicationContext<android.content.Context>()

    @Test
    fun goalBandOpensCompleteReadOnlyDetailAtLargeText() {
        val goal = GoalUiModel(
            id = "goal",
            objective = "Ship the complete Android Remote information architecture",
            phase = GoalPhaseUi.Blocked,
            roundsStarted = 3,
            maxRounds = 6,
            revision = 9,
            blockedReason = "Waiting for physical-device approval",
        )
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, 1.8f)) {
                DSHRemoteTheme {
                    SessionStatusBand(
                        sessionState = SessionExecutionState.WaitingForApproval,
                        goal = goal,
                    )
                }
            }
        }

        compose.onNodeWithContentDescription(
            context.getString(R.string.goal_detail_open),
            substring = true,
        ).performClick()
        compose.onNodeWithText(context.getString(R.string.goal_detail_title)).assertIsDisplayed()
        compose.onNodeWithText(goal.objective).fetchSemanticsNode()
        compose.onAllNodesWithText(context.getString(R.string.goal_phase_blocked))
            .assertCountEquals(3)
        compose.onAllNodesWithText(context.resources.getQuantityString(R.plurals.goal_rounds_value, 3, 3, 6))
            .assertCountEquals(2)
        compose.onNodeWithText("9").fetchSemanticsNode()
        compose.onAllNodesWithText(goal.blockedReason!!).assertCountEquals(2)
        compose.onNodeWithContentDescription(context.getString(R.string.action_close))
            .assertHeightIsAtLeast(44.dp)
    }

    @Test
    fun trajectorySearchesFullDetailsGroupsTurnsAndCopiesCompleteRecord() {
        val records = listOf(
            TrajectoryRecordUiModel(
                id = "context",
                sequence = 1,
                kind = TrajectoryKindUi.Context,
                title = "Context loaded",
                summary = "Project rules are ready",
            ),
            TrajectoryRecordUiModel(
                id = "tool",
                sequence = 2,
                turn = 2,
                step = 1,
                kind = TrajectoryKindUi.Tool,
                title = "Tool result",
                summary = "Build completed",
                details = listOf(
                    DetailSectionUiModel(
                        id = "output",
                        title = "Output",
                        content = "secret acceptance evidence",
                        kind = DetailSectionKind.Code,
                    ),
                ),
            ),
        )
        compose.setContent {
            DSHRemoteTheme {
                Column {
                    TrajectoryLedger(records = records, onOpenAttachment = {})
                }
            }
        }

        compose.onNodeWithContentDescription(context.getString(R.string.trajectory_search_description))
            .performTextInput("secret")
        compose.onNodeWithText("Tool result").assertIsDisplayed().performClick()
        compose.onNodeWithText("secret acceptance evidence").fetchSemanticsNode()
        compose.onNodeWithText(context.getString(R.string.trajectory_copy_all)).performClick()
        compose.onNodeWithText(context.getString(R.string.trajectory_copied)).assertIsDisplayed()

        compose.runOnIdle {
            val clipboard = context.getSystemService(ClipboardManager::class.java)
            val copied = clipboard.primaryClip?.getItemAt(0)?.coerceToText(context)?.toString().orEmpty()
            assertTrue(copied.contains("secret acceptance evidence"))
            assertTrue(copied.contains("Tool result"))
        }
    }

    @Test
    fun tailscaleGuideKeepsLinksFunnelWarningAndCellularStepReadableAtLargeText() {
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, 1.6f)) {
                DSHRemoteTheme {
                    AboutRemoteScreen(
                        savedComputerCount = 1,
                        onBack = {},
                        onRemoveAllComputers = {},
                    )
                }
            }
        }

        compose.onNodeWithText(context.getString(R.string.about_tailscale_download_android))
            .performScrollTo()
            .assertIsDisplayed()
            .assertHeightIsAtLeast(44.dp)
        compose.onNodeWithText(context.getString(R.string.about_tailscale_step_5))
            .performScrollTo()
            .assertIsDisplayed()
        compose.onNodeWithText(context.getString(R.string.about_tailscale_funnel_title))
            .performScrollTo()
            .assertIsDisplayed()
    }
}
