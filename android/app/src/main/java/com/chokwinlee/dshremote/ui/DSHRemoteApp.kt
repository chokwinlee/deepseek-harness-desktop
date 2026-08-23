package com.chokwinlee.dshremote.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.chokwinlee.dshremote.R
import com.chokwinlee.dshremote.ui.model.AddComputerUiState
import com.chokwinlee.dshremote.ui.model.ComputerConnectionState
import com.chokwinlee.dshremote.ui.model.ComputerListUiState
import com.chokwinlee.dshremote.ui.model.ComputerTransport
import com.chokwinlee.dshremote.ui.model.ComputerUiModel
import com.chokwinlee.dshremote.ui.model.ConversationActor
import com.chokwinlee.dshremote.ui.model.ConversationMessageUiModel
import com.chokwinlee.dshremote.ui.model.ProjectListUiState
import com.chokwinlee.dshremote.ui.model.ProjectUiModel
import com.chokwinlee.dshremote.ui.model.RemoteAppCallbacks
import com.chokwinlee.dshremote.ui.model.RemoteAppUiState
import com.chokwinlee.dshremote.ui.model.SessionDetailUiState
import com.chokwinlee.dshremote.ui.model.SessionExecutionState
import com.chokwinlee.dshremote.ui.model.SessionUiModel
import com.chokwinlee.dshremote.ui.screens.AddComputerScreen
import com.chokwinlee.dshremote.ui.screens.AboutRemoteScreen
import com.chokwinlee.dshremote.ui.screens.ComputerListScreen
import com.chokwinlee.dshremote.ui.screens.ProjectListScreen
import com.chokwinlee.dshremote.ui.screens.SessionDetailScreen
import com.chokwinlee.dshremote.ui.theme.DSHRemoteTheme

sealed class RemoteDestination(val route: String) {
    data object Computers : RemoteDestination("computers")
    data object AddComputer : RemoteDestination("add-computer")
    data object Projects : RemoteDestination("projects")
    data object Session : RemoteDestination("session")
    data object About : RemoteDestination("about")
}

/**
 * Runnable preview/demo driver used by the scaffolded Activity.
 *
 * It intentionally contains no network client. Production integration should call the overload
 * accepting [RemoteAppUiState] and [RemoteAppCallbacks].
 */
@Composable
fun DSHRemoteApp() {
    DSHRemoteTheme {
        PreviewDrivenRemoteApp()
    }
}

/** Stateless production entry point for a real AppViewModel. */
@Composable
fun DSHRemoteApp(
    uiState: RemoteAppUiState,
    callbacks: RemoteAppCallbacks,
) {
    DSHRemoteTheme {
        RemoteAppShell(uiState = uiState, callbacks = callbacks)
    }
}

@Composable
fun RemoteAppShell(
    uiState: RemoteAppUiState,
    callbacks: RemoteAppCallbacks,
    navController: NavHostController = rememberNavController(),
) {
    LaunchedEffect(uiState.addComputer.savedComputerId) {
        val computerId = uiState.addComputer.savedComputerId ?: return@LaunchedEffect
        callbacks.onComputerSelected(computerId)
        navController.navigate(RemoteDestination.Projects.route) {
            popUpTo(RemoteDestination.AddComputer.route) { inclusive = true }
            launchSingleTop = true
        }
    }

    LaunchedEffect(
        uiState.addComputer.initialAddress,
        uiState.addComputer.isVerifying,
        uiState.addComputer.errorMessage,
    ) {
        val importedAddress = uiState.addComputer.initialAddress
        val needsPairingSurface = importedAddress.isNotBlank() &&
            uiState.addComputer.savedComputerId == null &&
            (uiState.addComputer.isVerifying || uiState.addComputer.errorMessage != null)
        if (needsPairingSurface &&
            navController.currentDestination?.route != RemoteDestination.AddComputer.route
        ) {
            navController.navigate(RemoteDestination.AddComputer.route) {
                launchSingleTop = true
            }
        }
    }

    LaunchedEffect(uiState.session.session?.id) {
        if (uiState.session.session?.id == null) return@LaunchedEffect
        if (navController.currentDestination?.route != RemoteDestination.Session.route) {
            navController.navigate(RemoteDestination.Session.route) {
                launchSingleTop = true
            }
        }
    }

    NavHost(
        navController = navController,
        startDestination = RemoteDestination.Computers.route,
    ) {
        composable(RemoteDestination.Computers.route) {
            ComputerListScreen(
                state = uiState.computers,
                onAddComputer = {
                    navController.navigate(RemoteDestination.AddComputer.route) {
                        launchSingleTop = true
                    }
                },
                onComputerSelected = { computerId ->
                    callbacks.onComputerSelected(computerId)
                    navController.navigate(RemoteDestination.Projects.route) {
                        launchSingleTop = true
                    }
                },
                onRemoveComputer = callbacks.onRemoveComputer,
                onTryDemo = {
                    callbacks.onTryDemo()
                    navController.navigate(RemoteDestination.Projects.route) {
                        launchSingleTop = true
                    }
                },
                onRefresh = callbacks.onRefreshComputers,
                onOpenAbout = {
                    navController.navigate(RemoteDestination.About.route) {
                        launchSingleTop = true
                    }
                },
            )
        }
        composable(RemoteDestination.About.route) {
            AboutRemoteScreen(
                savedComputerCount = uiState.computers.computers.size,
                onBack = { navController.popBackStack() },
                onRemoveAllComputers = callbacks.onRemoveAllComputers,
                onOpenSystemSettings = callbacks.onOpenSystemSettings,
            )
        }
        composable(RemoteDestination.AddComputer.route) {
            AddComputerScreen(
                state = uiState.addComputer,
                onBack = { navController.popBackStack() },
                onScanQrCode = callbacks.onScanQrCode,
                onVerifyAndSave = callbacks.onVerifyAndSaveComputer,
                onOpenSettings = callbacks.onOpenSystemSettings,
            )
        }
        composable(RemoteDestination.Projects.route) {
            ProjectListScreen(
                state = uiState.projects,
                onBack = { navController.popBackStack() },
                onRefresh = callbacks.onRefreshProjects,
                onCreateSession = callbacks.onCreateSession,
                onSessionSelected = { sessionId ->
                    callbacks.onSessionSelected(sessionId)
                    navController.navigate(RemoteDestination.Session.route) {
                        launchSingleTop = true
                    }
                },
            )
        }
        composable(RemoteDestination.Session.route) {
            val visibleSessionId = uiState.session.session?.id
            DisposableEffect(visibleSessionId) {
                callbacks.onSessionVisibilityChanged(visibleSessionId, true)
                onDispose {
                    callbacks.onSessionVisibilityChanged(visibleSessionId, false)
                }
            }
            SessionDetailScreen(
                state = uiState.session,
                onBack = { navController.popBackStack() },
                onRefresh = callbacks.onRefreshSession,
                onSendMessage = callbacks.onSendMessage,
                onStopSession = callbacks.onStopSession,
                featureCallbacks = callbacks.sessionDetail,
            )
        }
    }
}

@Composable
private fun PreviewDrivenRemoteApp() {
    val demoComputerName = stringResource(R.string.demo_computer_name)
    val demoProjectName = stringResource(R.string.demo_project_name)
    val demoSessionTitle = stringResource(R.string.demo_session_title)
    val demoOlderSessionTitle = stringResource(R.string.demo_older_session_title)
    val demoUserMessage = stringResource(R.string.demo_user_message)
    val demoAssistantMessage = stringResource(R.string.demo_assistant_message)
    val newSessionTitle = stringResource(R.string.session_new_default_title)
    val timeNow = stringResource(R.string.time_now)
    var uiState by remember { mutableStateOf(RemoteAppUiState()) }

    fun demoProjects(computerName: String = demoComputerName): ProjectListUiState {
        return ProjectListUiState(
            computerName = computerName,
            projects = listOf(
                ProjectUiModel(
                    id = "demo-project",
                    title = demoProjectName,
                    path = "~/Projects/deepseek-harness-desktop",
                    sessions = listOf(
                        SessionUiModel(
                            id = "demo-session",
                            title = demoSessionTitle,
                            updatedLabel = "2m",
                            state = SessionExecutionState.Running,
                        ),
                        SessionUiModel(
                            id = "demo-session-older",
                            title = demoOlderSessionTitle,
                            updatedLabel = "1d",
                            state = SessionExecutionState.Completed,
                        ),
                    ),
                ),
            ),
            hasLoadedOnce = true,
        )
    }

    val callbacks = RemoteAppCallbacks(
        onComputerSelected = { computerId ->
            val computerName = uiState.computers.computers
                .firstOrNull { it.id == computerId }
                ?.name
                ?: demoComputerName
            uiState = uiState.copy(projects = demoProjects(computerName))
        },
        onRemoveComputer = { computerId ->
            uiState = uiState.copy(
                computers = uiState.computers.copy(
                    computers = uiState.computers.computers.filterNot { it.id == computerId },
                ),
            )
        },
        onVerifyAndSaveComputer = { name, address ->
            val computer = ComputerUiModel(
                id = "preview-computer",
                name = name,
                address = address,
                transport = ComputerTransport.CustomHttps,
                connectionState = ComputerConnectionState.Reachable,
            )
            uiState = uiState.copy(
                computers = ComputerListUiState(computers = listOf(computer)),
                addComputer = AddComputerUiState(
                    initialName = name,
                    initialAddress = address,
                    savedComputerId = computer.id,
                ),
                projects = demoProjects(name),
            )
        },
        onTryDemo = {
            uiState = uiState.copy(projects = demoProjects())
        },
        onCreateSession = { projectId ->
            val projects = uiState.projects.projects.map { project ->
                if (project.id == projectId) {
                    project.copy(
                        sessions = listOf(
                            SessionUiModel(
                                id = "preview-new-session",
                                title = newSessionTitle,
                                updatedLabel = timeNow,
                            ),
                        ) + project.sessions,
                    )
                } else {
                    project
                }
            }
            uiState = uiState.copy(projects = uiState.projects.copy(projects = projects))
        },
        onSessionSelected = { sessionId ->
            val selected = uiState.projects.projects
                .flatMap { project -> project.sessions.map { project.title to it } }
                .firstOrNull { it.second.id == sessionId }
            uiState = uiState.copy(
                session = SessionDetailUiState(
                    session = selected?.second,
                    projectName = selected?.first.orEmpty(),
                    messages = listOf(
                        ConversationMessageUiModel(
                            id = "preview-message-user",
                            actor = ConversationActor.User,
                            text = demoUserMessage,
                        ),
                        ConversationMessageUiModel(
                            id = "preview-message-assistant",
                            actor = ConversationActor.Assistant,
                            text = demoAssistantMessage,
                        ),
                    ),
                ),
            )
        },
        onSendMessage = { text ->
            uiState = uiState.copy(
                session = uiState.session.copy(
                    messages = uiState.session.messages + ConversationMessageUiModel(
                        id = "preview-message-${uiState.session.messages.size}",
                        actor = ConversationActor.User,
                        text = text,
                    ),
                ),
            )
        },
    )

    RemoteAppShell(uiState = uiState, callbacks = callbacks)
}
