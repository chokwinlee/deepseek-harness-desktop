package com.chokwinlee.dshremote.ui

import android.content.res.Configuration
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.android.tools.screenshot.PreviewTest
import com.chokwinlee.dshremote.ui.components.RemoteErrorState
import com.chokwinlee.dshremote.ui.components.RemoteInlineNotice
import com.chokwinlee.dshremote.ui.components.RemoteLoadingState
import com.chokwinlee.dshremote.ui.components.RemoteNoticeTone
import com.chokwinlee.dshremote.ui.features.conversation.ConversationMessageCard
import com.chokwinlee.dshremote.ui.features.trajectory.TrajectoryLedger
import com.chokwinlee.dshremote.ui.model.AddComputerUiState
import com.chokwinlee.dshremote.ui.model.ComputerListUiState
import com.chokwinlee.dshremote.ui.model.ConversationActor
import com.chokwinlee.dshremote.ui.model.ConversationItemState
import com.chokwinlee.dshremote.ui.model.ConversationMessageUiModel
import com.chokwinlee.dshremote.ui.model.DetailSectionKind
import com.chokwinlee.dshremote.ui.model.DetailSectionUiModel
import com.chokwinlee.dshremote.ui.model.GoalPhaseUi
import com.chokwinlee.dshremote.ui.model.GoalUiModel
import com.chokwinlee.dshremote.ui.model.ImageAttachmentUiModel
import com.chokwinlee.dshremote.ui.model.InteractionKindUi
import com.chokwinlee.dshremote.ui.model.InteractionUiModel
import com.chokwinlee.dshremote.ui.model.PlanUiModel
import com.chokwinlee.dshremote.ui.model.PromptImageUiModel
import com.chokwinlee.dshremote.ui.model.ProjectListUiState
import com.chokwinlee.dshremote.ui.model.ProjectUiModel
import com.chokwinlee.dshremote.ui.model.QuestionOptionUiModel
import com.chokwinlee.dshremote.ui.model.QueuePlacementUi
import com.chokwinlee.dshremote.ui.model.QueuedMessageUiModel
import com.chokwinlee.dshremote.ui.model.ReferenceCandidateKind
import com.chokwinlee.dshremote.ui.model.ReferenceCandidateUiModel
import com.chokwinlee.dshremote.ui.model.ReferenceSuggestionsUiState
import com.chokwinlee.dshremote.ui.model.SessionDetailCallbacks
import com.chokwinlee.dshremote.ui.model.SessionDetailUiState
import com.chokwinlee.dshremote.ui.model.SessionExecutionState
import com.chokwinlee.dshremote.ui.model.SessionUiModel
import com.chokwinlee.dshremote.ui.model.StructuredQuestionUiModel
import com.chokwinlee.dshremote.ui.model.ToolCardKind
import com.chokwinlee.dshremote.ui.model.TrajectoryKindUi
import com.chokwinlee.dshremote.ui.model.TrajectoryRecordUiModel
import com.chokwinlee.dshremote.ui.screens.AddComputerScreen
import com.chokwinlee.dshremote.ui.screens.ComputerListScreen
import com.chokwinlee.dshremote.ui.screens.AboutRemoteScreen
import com.chokwinlee.dshremote.ui.screens.ProjectListScreen
import com.chokwinlee.dshremote.ui.screens.SessionDetailScreen
import com.chokwinlee.dshremote.ui.theme.DSHRemoteTheme
import com.chokwinlee.dshremote.ui.theme.RemoteTheme

private const val Phone = "spec:width=393dp,height=852dp,dpi=440"
private const val NarrowPhone = "spec:width=320dp,height=720dp,dpi=420"
private const val TallPhone = "spec:width=393dp,height=1000dp,dpi=440"

@PreviewTest
@Preview(name = "Home EN", device = Phone, showBackground = true)
@Composable
fun HomeEnglishScreenshot() {
    DSHRemoteTheme {
        ComputerListScreen(
            state = ComputerListUiState(),
            onAddComputer = {},
            onComputerSelected = {},
            onRemoveComputer = {},
            onTryDemo = {},
            onRefresh = {},
            onOpenAbout = {},
        )
    }
}

@PreviewTest
@Preview(
    name = "Home ZH dark",
    device = Phone,
    locale = "zh-rCN",
    uiMode = Configuration.UI_MODE_NIGHT_YES,
    showBackground = true,
)
@Composable
fun HomeChineseDarkScreenshot() {
    HomeEnglishScreenshot()
}

@PreviewTest
@Preview(
    name = "Home accessibility",
    device = Phone,
    fontScale = 1.4f,
    showBackground = true,
)
@Composable
fun HomeAccessibilityScreenshot() {
    HomeEnglishScreenshot()
}

@PreviewTest
@Preview(name = "Projects EN", device = Phone, showBackground = true)
@Composable
fun ProjectsEnglishScreenshot() {
    DSHRemoteTheme {
        ProjectListScreen(
            state = ProjectListUiState(
                computerName = "Development Mac",
                projects = listOf(
                    ProjectUiModel(
                        id = "project",
                        title = "deepseek-harness-desktop",
                        path = "/Users/demo/deepseek-harness-desktop",
                        sessions = listOf(
                            SessionUiModel(
                                id = "running",
                                title = "Build Android Remote",
                                updatedLabel = "now",
                                state = SessionExecutionState.Running,
                            ),
                            SessionUiModel(
                                id = "waiting",
                                title = "Review mobile security",
                                updatedLabel = "8m",
                                state = SessionExecutionState.WaitingForApproval,
                            ),
                            SessionUiModel(
                                id = "complete",
                                title = "Complete bilingual copy",
                                updatedLabel = "1h",
                                state = SessionExecutionState.Completed,
                            ),
                        ),
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

@PreviewTest
@Preview(name = "Conversation EN", device = Phone, showBackground = true)
@Composable
fun ConversationEnglishScreenshot() {
    DSHRemoteTheme {
        SessionDetailScreen(
            state = advancedSessionState(),
            onBack = {},
            onRefresh = {},
            onSendMessage = {},
            onStopSession = {},
            featureCallbacks = SessionDetailCallbacks(),
        )
    }
}

@PreviewTest
@Preview(
    name = "Conversation ZH dark",
    device = Phone,
    locale = "zh-rCN",
    uiMode = Configuration.UI_MODE_NIGHT_YES,
    showBackground = true,
)
@Composable
fun ConversationChineseDarkScreenshot() {
    DSHRemoteTheme {
        SessionDetailScreen(
            state = advancedSessionState(chinese = true),
            onBack = {},
            onRefresh = {},
            onSendMessage = {},
            onStopSession = {},
            featureCallbacks = SessionDetailCallbacks(),
        )
    }
}

@PreviewTest
@Preview(
    name = "Questions accessibility",
    device = Phone,
    fontScale = 1.8f,
    showBackground = true,
)
@Composable
fun QuestionsAccessibilityScreenshot() {
    val questions = List(3) { index ->
        StructuredQuestionUiModel(
            id = "question-$index",
            header = "Question ${index + 1}",
            question = "Choose the safest option for this long structured question.",
            options = List(4) { option ->
                QuestionOptionUiModel(
                    label = "Option ${option + 1}",
                    description = "A detailed explanation for this option",
                )
            },
        )
    }
    DSHRemoteTheme {
        SessionDetailScreen(
            state = advancedSessionState().copy(
                queue = emptyList(),
                interaction = InteractionUiModel(
                    id = "questions",
                    kind = InteractionKindUi.Questions,
                    title = "Review choices",
                    questions = questions,
                ),
            ),
            onBack = {},
            onRefresh = {},
            onSendMessage = {},
            onStopSession = {},
            featureCallbacks = SessionDetailCallbacks(),
        )
    }
}

@PreviewTest
@Preview(name = "About ZH", device = Phone, locale = "zh-rCN", showBackground = true)
@Composable
fun AboutChineseScreenshot() {
    DSHRemoteTheme {
        AboutRemoteScreen(
            savedComputerCount = 2,
            onBack = {},
            onRemoveAllComputers = {},
        )
    }
}

@PreviewTest
@Preview(
    name = "Conversation narrow large type",
    device = NarrowPhone,
    fontScale = 1.6f,
    showBackground = true,
)
@Composable
fun ConversationNarrowLargeTypeScreenshot() {
    DSHRemoteTheme {
        SessionDetailScreen(
            state = narrowLargeTypeSessionState(),
            onBack = {},
            onRefresh = {},
            onSendMessage = {},
            onStopSession = {},
            featureCallbacks = SessionDetailCallbacks(),
        )
    }
}

@PreviewTest
@Preview(name = "Interaction and queue stress", device = TallPhone, showBackground = true)
@Composable
fun InteractionAndQueueStressScreenshot() {
    DSHRemoteTheme {
        SessionDetailScreen(
            state = interactionAndQueueState(),
            onBack = {},
            onRefresh = {},
            onSendMessage = {},
            onStopSession = {},
            featureCallbacks = SessionDetailCallbacks(),
        )
    }
}

@PreviewTest
@Preview(name = "Activity trajectory stress", device = Phone, showBackground = true)
@Composable
fun ActivityTrajectoryStressScreenshot() {
    DSHRemoteTheme {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(RemoteTheme.colors.canvas)
                .padding(16.dp),
        ) {
            TrajectoryLedger(
                records = trajectoryStressRecords(),
                onOpenAttachment = {},
            )
        }
    }
}

@PreviewTest
@Preview(name = "Tool reasoning code diff", device = Phone, showBackground = true)
@Composable
fun ToolReasoningCodeDiffScreenshot() {
    DSHRemoteTheme {
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .background(RemoteTheme.colors.canvas),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            item {
                ConversationMessageCard(
                    message = structuredToolMessage(),
                    onOpenAttachment = {},
                )
            }
        }
    }
}

@PreviewTest
@Preview(name = "Images and reference input", device = Phone, showBackground = true)
@Composable
fun ImagesAndReferenceInputScreenshot() {
    DSHRemoteTheme {
        SessionDetailScreen(
            state = imageAndReferenceState(),
            onBack = {},
            onRefresh = {},
            onSendMessage = {},
            onStopSession = {},
            featureCallbacks = SessionDetailCallbacks(),
        )
    }
}

@PreviewTest
@Preview(name = "Loading error stale states", device = TallPhone, showBackground = true)
@Composable
fun LoadingErrorStaleStatesScreenshot() {
    DSHRemoteTheme {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(RemoteTheme.colors.canvas)
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            RemoteLoadingState(
                title = "Loading conversation",
                message = "Reading project rules, history, and the latest execution state.",
            )
            RemoteErrorState(
                message = "The computer did not respond. Check Desktop and try again.",
                onRetry = {},
            )
            RemoteInlineNotice(
                title = "Showing saved results",
                message = "The live connection was interrupted; the transcript below may be stale.",
                tone = RemoteNoticeTone.Warning,
                actionText = "Retry",
                onAction = {},
            )
        }
    }
}

@PreviewTest
@Preview(
    name = "Add computer scanner fallback",
    device = Phone,
    locale = "zh-rCN",
    showBackground = true,
)
@Composable
fun AddComputerScannerFallbackScreenshot() {
    DSHRemoteTheme {
        AddComputerScreen(
            state = AddComputerUiState(
                initialName = "开发用 MacBook Pro",
                initialAddress = "https://development-mac.example-tailnet.ts.net",
                errorMessage = "相机权限不可用，请使用私有 HTTPS 地址完成连接。",
                qrScannerAvailable = false,
                needsLocalNetworkPermission = true,
            ),
            onBack = {},
            onScanQrCode = {},
            onOpenSettings = {},
            onVerifyAndSave = { _, _ -> },
        )
    }
}

private fun advancedSessionState(chinese: Boolean = false) = SessionDetailUiState(
    session = SessionUiModel(
        id = "session",
        title = if (chinese) "Android Remote 验收" else "Android Remote acceptance",
        updatedLabel = "now",
        state = SessionExecutionState.WaitingForApproval,
    ),
    projectName = "deepseek-harness-desktop",
    messages = listOf(
        ConversationMessageUiModel(
            id = "user",
            actor = ConversationActor.User,
            text = if (chinese) {
                "执行 Android 验收，并把运行环境留在我的电脑上。"
            } else {
                "Run the Android acceptance checks and keep execution on my computer."
            },
            timestampLabel = "11:42",
        ),
        ConversationMessageUiModel(
            id = "assistant",
            actor = ConversationActor.Assistant,
            text = if (chinese) {
                "协议测试、双语资源、lint 和 APK 构建已经就绪。"
            } else {
                "The protocol tests, bilingual resources, lint, and APK build are ready."
            },
            timestampLabel = "11:43",
        ),
    ),
    hasLoadedOnce = true,
    queue = listOf(
        QueuedMessageUiModel(
            id = "queue",
            placement = QueuePlacementUi.Queued,
            preview = if (chinese) "生成最终 Android 截图" else "Capture final Android screenshots",
        ),
    ),
    interaction = InteractionUiModel(
        id = "approval",
        kind = InteractionKindUi.Approval,
        title = "exec_command",
        detail = if (chinese) "执行经过检查的 Android 构建命令" else "Run the reviewed Android build command",
        toolName = "exec_command",
    ),
    goal = GoalUiModel(
        id = "goal",
        objective = if (chinese) "交付 Android Remote" else "Ship Android Remote",
        phase = GoalPhaseUi.Active,
        roundsStarted = 2,
        maxRounds = 4,
        revision = 3,
    ),
    plan = PlanUiModel(active = true, pending = false),
    trajectory = listOf(
        TrajectoryRecordUiModel(
            id = "record",
            sequence = 1,
            kind = TrajectoryKindUi.Tool,
            title = if (chinese) "Android 构建" else "Android build",
            summary = if (chinese) "lint、测试和构建均已通过" else "lint, tests, and assemble passed",
        ),
    ),
)

private fun narrowLargeTypeSessionState() = SessionDetailUiState(
    session = SessionUiModel(
        id = "narrow-session",
        title = "Finish Android Remote visual and accessibility acceptance",
        updatedLabel = "now",
        state = SessionExecutionState.Running,
    ),
    projectName = "deepseek-harness-desktop / android companion",
    hasLoadedOnce = true,
    messages = listOf(
        ConversationMessageUiModel(
            id = "narrow-user",
            actor = ConversationActor.User,
            text = "Please verify the entire phone flow at large text sizes without hiding the current computer, project, session, or execution state.",
            timestampLabel = "11:58",
        ),
        ConversationMessageUiModel(
            id = "narrow-assistant",
            actor = ConversationActor.Assistant,
            text = "The layout keeps semantic controls reachable, wraps long labels, and leaves code and execution on the connected computer.",
            reasoning = "Check the narrowest supported viewport first, then increase the system font scale and confirm that controls reflow instead of clipping.",
            metadata = listOf("2 turns", "local-first"),
            timestampLabel = "11:59",
        ),
    ),
)

private fun interactionAndQueueState() = SessionDetailUiState(
    session = SessionUiModel(
        id = "interaction-session",
        title = "Release readiness review",
        updatedLabel = "now",
        state = SessionExecutionState.Running,
    ),
    projectName = "deepseek-harness-desktop",
    hasLoadedOnce = true,
    interaction = InteractionUiModel(
        id = "structured-questions",
        kind = InteractionKindUi.Questions,
        title = "Two decisions are required before continuing",
        detail = "Harness is paused. Your answers remain attached to this session on the computer.",
        questions = listOf(
            StructuredQuestionUiModel(
                id = "distribution",
                header = "Distribution",
                question = "Which release path should be used when the public store listing is not ready yet?",
                detail = "Choose the path that keeps installation instructions understandable for external testers.",
                options = listOf(
                    QuestionOptionUiModel(
                        label = "Closed testing",
                        description = "Invite a controlled group and validate updates before wider access.",
                    ),
                    QuestionOptionUiModel(
                        label = "Internal only",
                        description = "Fastest, but restricted to members of the developer team.",
                    ),
                    QuestionOptionUiModel(
                        label = "Wait for production",
                        description = "No pre-release feedback until the store review is complete.",
                    ),
                ),
            ),
        ),
    ),
    queue = listOf(
        QueuedMessageUiModel(
            id = "queue-one",
            placement = QueuePlacementUi.Queued,
            preview = "After the current build finishes, capture narrow-screen screenshots in both light and dark appearance and report every clipped control.",
            text = "After the current build finishes, capture narrow-screen screenshots in both appearances.",
            attachmentCount = 2,
        ),
        QueuedMessageUiModel(
            id = "queue-two",
            placement = QueuePlacementUi.Steering,
            preview = "Prioritize a readable recovery path if the computer disconnects while a question is waiting for an answer.",
        ),
    ),
)

private fun trajectoryStressRecords() = listOf(
    TrajectoryRecordUiModel(
        id = "trajectory-input",
        sequence = 1,
        turn = 1,
        kind = TrajectoryKindUi.Input,
        title = "Acceptance request received",
        summary = "Verify the Android companion across layout extremes and all durable session states.",
        timestampLabel = "12:01",
    ),
    TrajectoryRecordUiModel(
        id = "trajectory-context",
        sequence = 2,
        turn = 1,
        step = 1,
        kind = TrajectoryKindUi.Context,
        title = "Project context loaded",
        summary = "PRODUCT.md, DESIGN.md, Android UI models, and screenshot-test conventions were read.",
        timestampLabel = "12:01",
        durationLabel = "180 ms",
        state = ConversationItemState.Succeeded,
    ),
    TrajectoryRecordUiModel(
        id = "trajectory-plan",
        sequence = 3,
        turn = 1,
        step = 2,
        kind = TrajectoryKindUi.Plan,
        title = "Visual matrix reduced to seven scenarios",
        summary = "Combined related edge cases so visual confidence increases without producing an unmaintainable snapshot set.",
        timestampLabel = "12:02",
    ),
    TrajectoryRecordUiModel(
        id = "trajectory-tool",
        sequence = 4,
        turn = 1,
        step = 3,
        kind = TrajectoryKindUi.Tool,
        title = "Compile screenshot previews",
        summary = "Kotlin compilation is running against the debug screenshot-test source set.",
        timestampLabel = "12:03",
        durationLabel = "4.8 s",
        state = ConversationItemState.Running,
        details = listOf(
            DetailSectionUiModel(
                id = "trajectory-command",
                title = "Command",
                content = "./gradlew :app:compileDebugScreenshotTestKotlin",
                kind = DetailSectionKind.Code,
                language = "shell",
            ),
        ),
    ),
    TrajectoryRecordUiModel(
        id = "trajectory-goal",
        sequence = 5,
        turn = 1,
        step = 4,
        kind = TrajectoryKindUi.Goal,
        title = "Visual acceptance remains active",
        summary = "Reference images stay unchanged until the new coverage is reviewed intentionally.",
        timestampLabel = "12:03",
    ),
    TrajectoryRecordUiModel(
        id = "trajectory-lifecycle",
        sequence = 6,
        turn = 1,
        kind = TrajectoryKindUi.Lifecycle,
        title = "Screenshot source ready",
        summary = "Seven high-value preview states are available for explicit reference-image approval.",
        timestampLabel = "12:04",
        state = ConversationItemState.Succeeded,
    ),
)

private fun structuredToolMessage() = ConversationMessageUiModel(
    id = "structured-tool",
    actor = ConversationActor.Tool,
    title = "apply_patch · RemoteConversation.kt",
    text = "The first patch attempt exposed a conflicting block and preserved the original file for recovery.",
    state = ConversationItemState.Failed,
    toolCard = ToolCardKind.Diff,
    reasoning = "Keep the failed tool expanded so the user can understand what happened, inspect the proposed change, and choose a safe retry.",
    details = listOf(
        DetailSectionUiModel(
            id = "tool-code",
            title = "Kotlin source",
            content = "fun sendPrompt(text: String) {\n    require(text.isNotBlank())\n    remoteClient.send(text.trim())\n}",
            kind = DetailSectionKind.Code,
            language = "kotlin",
        ),
        DetailSectionUiModel(
            id = "tool-diff",
            title = "Proposed diff",
            content = "@@ -42,3 +42,5 @@\n-remoteClient.send(text)\n+require(text.isNotBlank())\n+remoteClient.send(text.trim())",
            kind = DetailSectionKind.Diff,
            language = "diff",
        ),
    ),
    metadata = listOf("exit 1", "retryable", "2.4 s"),
)

private fun imageAndReferenceState() = SessionDetailUiState(
    session = SessionUiModel(
        id = "media-session",
        title = "Review screenshots and references",
        updatedLabel = "now",
        state = SessionExecutionState.Idle,
    ),
    projectName = "deepseek-harness-desktop",
    hasLoadedOnce = true,
    messages = listOf(
        ConversationMessageUiModel(
            id = "media-message",
            actor = ConversationActor.Assistant,
            text = "The original message keeps its image delivery states and file references together.",
            attachments = listOf(
                ImageAttachmentUiModel(
                    id = "image-ready",
                    name = "remote-home-dark.png",
                    mediaType = "image/png",
                    width = 1179,
                    height = 2556,
                    sizeLabel = "428 KB",
                ),
                ImageAttachmentUiModel(
                    id = "image-loading",
                    name = "conversation-large-type.png",
                    mediaType = "image/png",
                    width = 960,
                    height = 2160,
                    sizeLabel = "processing",
                    isLoading = true,
                ),
                ImageAttachmentUiModel(
                    id = "image-failed",
                    name = "missing-reference.png",
                    mediaType = "image/png",
                    width = 0,
                    height = 0,
                    sizeLabel = "0 KB",
                    errorMessage = "Preview could not be loaded",
                ),
            ),
        ),
    ),
    pendingImages = listOf(
        PromptImageUiModel(
            id = "pending-ready",
            name = "scanner-fallback.png",
            dimensionsLabel = "1179 × 2556",
            sizeLabel = "390 KB",
        ),
        PromptImageUiModel(
            id = "pending-processing",
            name = "activity-detail.png",
            isPreparing = true,
        ),
    ),
    imageLimitLabel = "2 / 5",
    references = ReferenceSuggestionsUiState(
        query = "Remote",
        candidates = listOf(
            ReferenceCandidateUiModel(
                id = "reference-file",
                mention = "@android/README.md",
                label = "android/README.md",
                detail = "Android installation and architecture",
                kind = ReferenceCandidateKind.File,
            ),
            ReferenceCandidateUiModel(
                id = "reference-session",
                mention = "@session:visual-acceptance",
                label = "Visual acceptance",
                detail = "Current project session",
                kind = ReferenceCandidateKind.Session,
            ),
        ),
    ),
)
