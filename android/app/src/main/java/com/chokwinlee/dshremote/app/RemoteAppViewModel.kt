package com.chokwinlee.dshremote.app

import android.Manifest
import android.app.Application
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.chokwinlee.dshremote.MainActivity
import com.chokwinlee.dshremote.R
import com.chokwinlee.dshremote.platform.images.PhotoInputProcessor
import com.chokwinlee.dshremote.platform.images.PhotoPreparationError
import com.chokwinlee.dshremote.platform.images.PhotoPreparationException
import com.chokwinlee.dshremote.platform.images.PhotoPreparationLimits
import com.chokwinlee.dshremote.platform.navigation.RemoteDeepLinkResult
import com.chokwinlee.dshremote.platform.navigation.RemoteIntentHelper
import com.chokwinlee.dshremote.platform.notifications.AppForegroundTracker
import com.chokwinlee.dshremote.platform.notifications.RemoteLocalNotificationManager
import com.chokwinlee.dshremote.platform.notifications.RemoteTaskNotification
import com.chokwinlee.dshremote.platform.notifications.shouldSuppressTaskNotification
import com.chokwinlee.dshremote.platform.scanner.PairingScanController
import com.chokwinlee.dshremote.platform.scanner.PairingScanResult
import com.chokwinlee.dshremote.platform.security.EncryptedRemoteHostStorage
import com.chokwinlee.dshremote.remote.DemoHarnessRemoteClient
import com.chokwinlee.dshremote.remote.HarnessRemoteClient
import com.chokwinlee.dshremote.remote.HarnessRemoteClientException
import com.chokwinlee.dshremote.remote.LiveHarnessRemoteClient
import com.chokwinlee.dshremote.remote.RemoteConnectionDescriptor
import com.chokwinlee.dshremote.remote.RemoteConversationSnapshot
import com.chokwinlee.dshremote.remote.RemoteConversationState
import com.chokwinlee.dshremote.remote.RemoteEndpointException
import com.chokwinlee.dshremote.remote.RemoteEndpointError
import com.chokwinlee.dshremote.remote.RemoteEndpointValidator
import com.chokwinlee.dshremote.remote.RemoteFileReferenceCandidate
import com.chokwinlee.dshremote.remote.RemoteHost
import com.chokwinlee.dshremote.remote.RemoteHostRepository
import com.chokwinlee.dshremote.remote.RemoteHostTransport
import com.chokwinlee.dshremote.remote.RemoteImageAttachment
import com.chokwinlee.dshremote.remote.RemoteImageLimits
import com.chokwinlee.dshremote.remote.RemoteInteraction
import com.chokwinlee.dshremote.remote.RemoteInteractionDecision
import com.chokwinlee.dshremote.remote.RemoteLiveEvent
import com.chokwinlee.dshremote.remote.RemoteModelDirectory
import com.chokwinlee.dshremote.remote.RemoteModelSelection
import com.chokwinlee.dshremote.remote.RemotePromptImage
import com.chokwinlee.dshremote.remote.RemoteQuestionAnswer
import com.chokwinlee.dshremote.remote.RemoteQueueAction
import com.chokwinlee.dshremote.remote.RemoteQueuedMessage
import com.chokwinlee.dshremote.remote.RemoteReferenceKind
import com.chokwinlee.dshremote.remote.RemoteSessionSummary
import com.chokwinlee.dshremote.remote.RemoteSubagentActivity
import com.chokwinlee.dshremote.remote.RemoteSubagentCatalog
import com.chokwinlee.dshremote.remote.RemoteSubagentDiagnosticReason
import com.chokwinlee.dshremote.remote.RemoteSubagentEntry
import com.chokwinlee.dshremote.remote.RemoteWorkspaceSnapshot
import com.chokwinlee.dshremote.remote.RemoteWorkspaceSummary
import com.chokwinlee.dshremote.ui.model.AddComputerUiState
import com.chokwinlee.dshremote.ui.model.ComputerConnectionState
import com.chokwinlee.dshremote.ui.model.ComputerListUiState
import com.chokwinlee.dshremote.ui.model.ComputerTransport
import com.chokwinlee.dshremote.ui.model.ComputerUiModel
import com.chokwinlee.dshremote.ui.model.ImageAttachmentUiModel
import com.chokwinlee.dshremote.ui.model.InteractionDecisionUi
import com.chokwinlee.dshremote.ui.model.ModelSelectionUiModel
import com.chokwinlee.dshremote.ui.model.ProjectListUiState
import com.chokwinlee.dshremote.ui.model.ProjectUiModel
import com.chokwinlee.dshremote.ui.model.PromptDeliveryUi
import com.chokwinlee.dshremote.ui.model.PromptImageUiModel
import com.chokwinlee.dshremote.ui.model.QueueActionUi
import com.chokwinlee.dshremote.ui.model.ReferenceCandidateKind
import com.chokwinlee.dshremote.ui.model.ReferenceCandidateUiModel
import com.chokwinlee.dshremote.ui.model.ReferenceSuggestionsUiState
import com.chokwinlee.dshremote.ui.model.RemoteAppCallbacks
import com.chokwinlee.dshremote.ui.model.RemoteAppUiState
import com.chokwinlee.dshremote.ui.model.SessionDetailCallbacks
import com.chokwinlee.dshremote.ui.model.SessionDetailUiState
import com.chokwinlee.dshremote.ui.model.SessionExecutionState
import com.chokwinlee.dshremote.ui.model.SubagentConversationUiState
import java.io.File
import java.util.Locale
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.supervisorScope
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * The Android application integration boundary.
 *
 * It owns lifecycle-scoped network work and maps the platform-neutral Remote protocol into the
 * immutable Compose state. It does not run Harness, a model gateway, or a relay on the phone.
 */
class RemoteAppViewModel(application: Application) : AndroidViewModel(application) {
    private val app = application
    private val hostRepository = RemoteHostRepository(EncryptedRemoteHostStorage(application))
    private val foregroundTracker = AppForegroundTracker.install(application)
    private val notifications = RemoteLocalNotificationManager(
        context = application,
        isAppForeground = { foregroundTracker.isForeground.value },
        shouldSuppressInForeground = { update ->
            shouldSuppressTaskNotification(
                isAppForeground = foregroundTracker.isForeground.value,
                visibleSessionId = visibleSessionId,
                updateSessionId = update.sessionId,
            )
        },
    )
    private val photoProcessor = PhotoInputProcessor(application.contentResolver)
    private val attachmentCache = AttachmentFileCache(
        File(application.cacheDir, ATTACHMENT_CACHE_DIRECTORY),
    )
    /** CameraPairingScanner consumes this one-shot parser; decoded values still verify through this ViewModel. */
    val pairingScanController = PairingScanController()

    private val mutableUiState = MutableStateFlow(
        RemoteAppUiState(computers = ComputerListUiState(isLoading = true)),
    )
    val uiState: StateFlow<RemoteAppUiState> = mutableUiState.asStateFlow()

    private val systemRequestChannel = Channel<RemoteSystemRequest>(Channel.BUFFERED)
    val systemRequests = systemRequestChannel.receiveAsFlow()
    private val mutableScannerRequested = MutableStateFlow(false)
    val scannerRequested: StateFlow<Boolean> = mutableScannerRequested.asStateFlow()

    private val connectionStates = mutableMapOf<String, ComputerConnectionState>()
    private val projectBindings = mutableMapOf<String, ProjectBinding>()
    private val sessionSummaries = mutableMapOf<String, RemoteSessionSummary>()
    private val completedSessionIds = mutableSetOf<String>()
    private val failedSessionIds = mutableSetOf<String>()
    private val runningStates = mutableMapOf<String, Boolean>()
    private val interactions = linkedMapOf<String, RemoteInteraction>()
    private val attachmentStates = mutableMapOf<AttachmentStateKey, AttachmentState>()
    private val pendingImages = mutableListOf<PendingImage>()

    private var selectedHostId: String? = null
    private var activeClient: HarnessRemoteClient? = null
    private var selectedSessionId: String? = null
    private var visibleSessionId: String? = null
    private var selectedProjectName: String = ""
    private var latestConversation: RemoteConversationSnapshot? = null
    private var latestQueue: List<RemoteQueuedMessage> = emptyList()
    private var latestModels: RemoteModelDirectory? = null
    private val subagentNavigation = SubagentNavigationState()
    private var imageLimits: RemoteImageLimits? = null
    private var historyLimit = DEFAULT_HISTORY_LIMIT
    private var selectionGeneration = 0L
    private var notificationPermissionRequested = false
    private val localNetworkPermissionRecovery = LocalNetworkPermissionRecovery()
    private var liveEventsJob: Job? = null
    private var pollingJob: Job? = null
    private var referenceJob: Job? = null
    private var subagentCatalogJob: Job? = null
    private var subagentMonitorJob: Job? = null
    private var subagentActionJob: Job? = null
    private val projectRefreshMutex = Mutex()
    private val sessionRefreshMutex = Mutex()
    private val subagentRefreshMutex = Mutex()

    val callbacks: RemoteAppCallbacks = RemoteAppCallbacks(
        onRefreshComputers = ::refreshComputers,
        onComputerSelected = ::selectComputer,
        onRemoveComputer = ::removeComputer,
        onRemoveAllComputers = ::removeAllComputers,
        onScanQrCode = ::requestQrScan,
        onOpenSystemSettings = ::openSystemSettings,
        onVerifyAndSaveComputer = ::verifyAndSaveComputer,
        onTryDemo = ::tryDemo,
        onRefreshProjects = ::refreshProjects,
        onCreateSession = ::createSession,
        onSessionSelected = ::selectSession,
        onRefreshSession = ::refreshSession,
        onSendMessage = { text -> sendPrompt(text, PromptDeliveryUi.Send) },
        onStopSession = ::stopSession,
        onSessionVisibilityChanged = ::setSessionVisibility,
        sessionDetail = SessionDetailCallbacks(
            onRefresh = ::refreshSession,
            onLoadOlderHistory = ::loadOlderHistory,
            onSendPrompt = ::sendPrompt,
            onStopSession = ::stopSession,
            onPickImages = ::requestImages,
            onPasteImages = ::requestClipboardImages,
            onRemovePendingImage = ::removePendingImage,
            onSearchReferences = ::searchReferences,
            onReferenceSelected = ::selectReference,
            onUpdateQueue = ::updateQueue,
            onResolveInteraction = ::resolveInteraction,
            onLoadModels = ::loadModels,
            onSelectModel = ::selectModel,
            onOpenAttachment = ::openAttachment,
            onRefreshSubagents = ::refreshSubagents,
            onOpenSubagent = ::openSubagent,
            onOpenSubagentChildren = ::openSubagentChildren,
            onOpenSubagentAttachment = ::openSubagentAttachment,
            onNavigateBackSubagents = ::navigateBackSubagents,
            onDismissSubagents = ::dismissSubagents,
            onCloseSubagent = ::navigateBackSubagents,
            onLoadOlderSubagentHistory = ::loadOlderSubagentHistory,
            onContinueSubagent = ::continueSubagent,
            onStopSubagent = ::stopSubagent,
            onDismissError = ::dismissSessionErrors,
        ),
    )

    init {
        notifications.ensureChannel()
        viewModelScope.launch {
            hostRepository.hosts.collect { hosts -> renderHosts(hosts) }
        }
        viewModelScope.launch {
            runCatching { hostRepository.load() }
                .onFailure { error ->
                    mutableUiState.update { state ->
                        state.copy(
                            computers = state.computers.copy(
                                isLoading = false,
                                errorMessage = error.userMessage(),
                            ),
                        )
                    }
                }
            mutableUiState.update { state ->
                state.copy(computers = state.computers.copy(isLoading = false))
            }
        }
    }

    fun handleLaunchIntent(intent: Intent?) {
        when (val deepLink = RemoteIntentHelper.parseConnectionIntent(intent)) {
            is RemoteDeepLinkResult.Connection -> importConnection(deepLink.descriptor)
            is RemoteDeepLinkResult.Rejected -> showAddComputerError(endpointErrorMessage(deepLink.reason))
            null -> {
                val hostId = intent?.getStringExtra(RemoteLaunchExtras.HOST_ID) ?: return
                val sessionId = intent.getStringExtra(RemoteLaunchExtras.SESSION_ID)
                selectComputer(hostId, sessionId)
            }
        }
    }

    fun setQrScannerAvailable(available: Boolean) {
        mutableUiState.update { state ->
            state.copy(
                addComputer = state.addComputer.copy(
                    qrScannerAvailable = available,
                    showQrPlaceholder = !available,
                ),
            )
        }
    }

    fun onQrScanResult(payload: String?) {
        if (payload.isNullOrBlank()) {
            dismissQrScanner()
            return
        }
        when (val result = pairingScanController.onDecoded(payload)) {
            is PairingScanResult.Accepted -> onPairingConnectionAccepted(result.connection)
            is PairingScanResult.Rejected -> onPairingScanRejected(result.reason)
            PairingScanResult.Duplicate,
            PairingScanResult.Inactive,
            -> Unit
        }
    }

    fun onPairingConnectionAccepted(connection: RemoteConnectionDescriptor) {
        mutableScannerRequested.value = false
        importConnection(connection)
    }

    fun onPairingScanRejected(reason: RemoteEndpointError) {
        showAddComputerError(endpointErrorMessage(reason))
    }

    fun dismissQrScanner() {
        mutableScannerRequested.value = false
        pairingScanController.stop()
    }

    fun onImagesSelected(uris: List<Uri>) {
        if (uris.isEmpty()) return
        val client = activeClient ?: return
        val sessionId = selectedSessionId ?: return
        val expectedGeneration = selectionGeneration
        viewModelScope.launch {
            mutableUiState.updateSession { it.copy(isPreparingImages = true, errorMessage = null) }
            try {
                val limits = preparationLimits(imageLimits)
                val maxImages = imageLimits?.maxImagesPerMessage?.coerceAtLeast(1) ?: DEFAULT_MAX_IMAGES
                val remaining = (maxImages - pendingImages.size).coerceAtLeast(0)
                for (uri in uris.take(remaining)) {
                    val prepared = photoProcessor.prepare(
                        uri = uri,
                        limits = limits,
                        displayName = displayName(uri),
                    )
                    if (client !== activeClient || sessionId != selectedSessionId || expectedGeneration != selectionGeneration) {
                        return@launch
                    }
                    val maximumCombined = imageLimits?.maxMessageImageBytes ?: DEFAULT_MAX_MESSAGE_IMAGE_BYTES
                    if (pendingImages.sumOf { it.remote.data.size } + prepared.bytes.size > maximumCombined) {
                        throw ImageMessageLimitException()
                    }
                    pendingImages += PendingImage(
                        remote = RemotePromptImage(
                            data = prepared.bytes,
                            mediaType = prepared.mediaType,
                            name = prepared.displayName,
                            width = prepared.width,
                            height = prepared.height,
                        ),
                        previewUri = uri.toString(),
                    )
                }
                renderPendingImages()
            } catch (error: Throwable) {
                if (error is CancellationException) throw error
                mutableUiState.updateSession { it.copy(errorMessage = error.userMessage()) }
            } finally {
                mutableUiState.updateSession { it.copy(isPreparingImages = false) }
            }
        }
    }

    fun onClipboardImageUnavailable() {
        mutableUiState.updateSession { state ->
            state.copy(errorMessage = app.getString(R.string.image_error_clipboard_empty))
        }
    }

    fun onLocalNetworkPermissionResult(granted: Boolean) {
        val pending = localNetworkPermissionRecovery.pending ?: return
        if (!granted) {
            when (pending) {
                is PendingLocalNetworkAction.Verify -> mutableUiState.update { state ->
                    state.copy(
                        addComputer = state.addComputer.copy(
                            isVerifying = false,
                            needsLocalNetworkPermission = true,
                            errorMessage = app.getString(R.string.local_network_permission_denied),
                        ),
                    )
                }
                is PendingLocalNetworkAction.SelectHost -> mutableUiState.update { state ->
                    state.copy(
                        projects = state.projects.copy(
                            isLoading = false,
                            errorMessage = app.getString(R.string.local_network_permission_denied),
                            hasLoadedOnce = true,
                        ),
                    )
                }
            }
            return
        }

        when (val action = localNetworkPermissionRecovery.consumeIfGranted(true)) {
            is PendingLocalNetworkAction.Verify ->
                performVerifyAndSaveConnection(action.name, action.connection)
            is PendingLocalNetworkAction.SelectHost ->
                selectComputer(action.hostId, action.sessionId)
            null -> Unit
        }
    }

    private fun refreshComputers() {
        viewModelScope.launch {
            val hosts = hostRepository.hosts.value
            mutableUiState.update { state ->
                state.copy(computers = state.computers.copy(isRefreshing = true, errorMessage = null))
            }
            hosts.forEach { host -> connectionStates[host.id] = ComputerConnectionState.Checking }
            renderHosts(hosts)
            supervisorScope {
                hosts.map { host ->
                    async {
                        val reachable = runCatching { client(host).describe() }.isSuccess
                        host.id to if (reachable) {
                            ComputerConnectionState.Reachable
                        } else {
                            ComputerConnectionState.Unreachable
                        }
                    }
                }.forEach { deferred ->
                    val (id, state) = deferred.await()
                    connectionStates[id] = state
                }
            }
            renderHosts(hostRepository.hosts.value)
            mutableUiState.update { state ->
                state.copy(computers = state.computers.copy(isRefreshing = false))
            }
        }
    }

    private fun selectComputer(computerId: String) = selectComputer(computerId, null)

    private fun selectComputer(computerId: String, requestedSessionId: String?) {
        viewModelScope.launch {
            val host = hostRepository.hosts.value.firstOrNull { it.id == computerId } ?: return@launch
            val connection = try {
                RemoteEndpointValidator.validatedConnection(host.connection())
            } catch (error: RemoteEndpointException) {
                connectionStates[host.id] = ComputerConnectionState.Unreachable
                renderHosts(hostRepository.hosts.value)
                mutableUiState.update { state ->
                    state.copy(
                        projects = ProjectListUiState(
                            computerName = host.name,
                            errorMessage = endpointErrorMessage(error.reason),
                            hasLoadedOnce = true,
                        ),
                    )
                }
                return@launch
            }
            if (Build.VERSION.SDK_INT >= 37 &&
                RemoteEndpointValidator.requiresLocalNetworkAccess(connection) &&
                app.checkSelfPermission(Manifest.permission.ACCESS_LOCAL_NETWORK) != PackageManager.PERMISSION_GRANTED
            ) {
                localNetworkPermissionRecovery.defer(
                    PendingLocalNetworkAction.SelectHost(host.id, requestedSessionId),
                )
                mutableUiState.update { state ->
                    state.copy(projects = ProjectListUiState(computerName = host.name, isLoading = true))
                }
                systemRequestChannel.trySend(RemoteSystemRequest.RequestLocalNetworkPermission)
                return@launch
            }
            switchClient(client(host), host.id)
            connectionStates[host.id] = ComputerConnectionState.Checking
            renderHosts(hostRepository.hosts.value)
            mutableUiState.update { state ->
                state.copy(
                    projects = ProjectListUiState(computerName = host.name, isLoading = true),
                    session = SessionDetailUiState(),
                )
            }
            val generation = selectionGeneration
            try {
                activeClient?.describe()
                if (generation != selectionGeneration) return@launch
                connectionStates[host.id] = ComputerConnectionState.Reachable
                renderHosts(hostRepository.hosts.value)
                requestNotificationPermissionIfNeeded()
                startLiveMonitoring()
                refreshProjectsInternal(showLoading = true)
                if (requestedSessionId != null && requestedSessionId in sessionSummaries) {
                    selectSession(requestedSessionId)
                }
            } catch (error: Throwable) {
                if (error is CancellationException) throw error
                if (generation != selectionGeneration) return@launch
                connectionStates[host.id] = ComputerConnectionState.Unreachable
                renderHosts(hostRepository.hosts.value)
                mutableUiState.update { state ->
                    state.copy(
                        projects = state.projects.copy(
                            isLoading = false,
                            errorMessage = error.userMessage(),
                            hasLoadedOnce = true,
                        ),
                    )
                }
            }
        }
    }

    private fun removeComputer(computerId: String) {
        viewModelScope.launch {
            runCatching { hostRepository.remove(computerId) }
                .onFailure { error ->
                    mutableUiState.update { state ->
                        state.copy(computers = state.computers.copy(errorMessage = error.userMessage()))
                    }
                }
            connectionStates.remove(computerId)
            if (selectedHostId == computerId) switchClient(null, null)
        }
    }

    private fun removeAllComputers() {
        viewModelScope.launch {
            runCatching { hostRepository.clear() }
                .onSuccess {
                    connectionStates.clear()
                    switchClient(null, null)
                    mutableUiState.value = RemoteAppUiState(
                        computers = ComputerListUiState(isLoading = false),
                        addComputer = AddComputerUiState(
                            qrScannerAvailable = mutableUiState.value.addComputer.qrScannerAvailable,
                            showQrPlaceholder = mutableUiState.value.addComputer.showQrPlaceholder,
                        ),
                    )
                }
                .onFailure { error ->
                    mutableUiState.update { state ->
                        state.copy(computers = state.computers.copy(errorMessage = error.userMessage()))
                    }
                }
        }
    }

    private fun requestQrScan() {
        pairingScanController.start()
        mutableScannerRequested.value = true
        systemRequestChannel.trySend(RemoteSystemRequest.ScanPairingCode)
    }

    private fun requestClipboardImages() {
        systemRequestChannel.trySend(RemoteSystemRequest.PasteImages)
    }

    private fun openSystemSettings() {
        systemRequestChannel.trySend(RemoteSystemRequest.OpenAppSettings)
    }

    private fun verifyAndSaveComputer(name: String, address: String) {
        val connection = try {
            RemoteEndpointValidator.connection(address)
        } catch (error: RemoteEndpointException) {
            showAddComputerError(endpointErrorMessage(error.reason))
            return
        }
        verifyAndSaveConnection(name, connection)
    }

    private fun importConnection(connection: RemoteConnectionDescriptor) {
        mutableUiState.update { state ->
            state.copy(
                addComputer = state.addComputer.copy(
                    initialAddress = connection.baseUrl,
                    errorMessage = null,
                ),
            )
        }
        verifyAndSaveConnection(null, connection)
    }

    private fun verifyAndSaveConnection(name: String?, connection: RemoteConnectionDescriptor) {
        if (Build.VERSION.SDK_INT >= 37 &&
            RemoteEndpointValidator.requiresLocalNetworkAccess(connection) &&
            app.checkSelfPermission(Manifest.permission.ACCESS_LOCAL_NETWORK) != PackageManager.PERMISSION_GRANTED
        ) {
            localNetworkPermissionRecovery.defer(PendingLocalNetworkAction.Verify(name, connection))
            mutableUiState.update { state ->
                state.copy(
                    addComputer = state.addComputer.copy(
                        isVerifying = false,
                        errorMessage = null,
                        needsLocalNetworkPermission = false,
                    ),
                )
            }
            systemRequestChannel.trySend(RemoteSystemRequest.RequestLocalNetworkPermission)
            return
        }
        performVerifyAndSaveConnection(name, connection)
    }

    private fun performVerifyAndSaveConnection(name: String?, connection: RemoteConnectionDescriptor) {
        viewModelScope.launch {
            mutableUiState.update { state ->
                state.copy(
                    addComputer = state.addComputer.copy(
                        isVerifying = true,
                        errorMessage = null,
                        needsLocalNetworkPermission = false,
                        savedComputerId = null,
                    ),
                )
            }
            try {
                val candidate = LiveHarnessRemoteClient(
                    baseUrl = connection.baseUrl,
                    displayName = name?.trim().orEmpty().ifBlank {
                        app.getString(R.string.remote_computer_fallback)
                    },
                    accessToken = connection.accessToken,
                )
                candidate.describe()
                val host = hostRepository.add(name, connection)
                connectionStates[host.id] = ComputerConnectionState.Reachable
                mutableUiState.update { state ->
                    state.copy(
                        addComputer = state.addComputer.copy(
                            initialName = host.name,
                            initialAddress = host.baseUrl,
                            isVerifying = false,
                            needsLocalNetworkPermission = false,
                            savedComputerId = host.id,
                        ),
                    )
                }
            } catch (error: Throwable) {
                if (error is CancellationException) throw error
                mutableUiState.update { state ->
                    state.copy(
                        addComputer = state.addComputer.copy(
                            isVerifying = false,
                            errorMessage = error.userMessage(),
                        ),
                    )
                }
            }
        }
    }

    private fun tryDemo() {
        viewModelScope.launch {
            switchClient(DemoHarnessRemoteClient(), DEMO_HOST_ID)
            mutableUiState.update { state ->
                state.copy(
                    projects = ProjectListUiState(
                        computerName = activeClient?.displayName?.let(::localizeRemoteGenerated).orEmpty(),
                        isLoading = true,
                    ),
                    session = SessionDetailUiState(),
                )
            }
            startLiveMonitoring()
            refreshProjectsInternal(showLoading = true)
        }
    }

    private fun refreshProjects() {
        val pendingSelection = localNetworkPermissionRecovery.pending as? PendingLocalNetworkAction.SelectHost
        if (pendingSelection != null) {
            if (Build.VERSION.SDK_INT >= 37 &&
                app.checkSelfPermission(Manifest.permission.ACCESS_LOCAL_NETWORK) == PackageManager.PERMISSION_GRANTED
            ) {
                onLocalNetworkPermissionResult(true)
            } else {
                openSystemSettings()
            }
            return
        }
        viewModelScope.launch { refreshProjectsInternal(showLoading = false) }
    }

    private suspend fun refreshProjectsInternal(showLoading: Boolean) {
        val client = activeClient ?: return
        val generation = selectionGeneration
        projectRefreshMutex.withLock {
            if (client !== activeClient || generation != selectionGeneration) return
            mutableUiState.update { state ->
                state.copy(
                    projects = state.projects.copy(
                        isLoading = showLoading && state.projects.projects.isEmpty(),
                        isRefreshing = !showLoading || state.projects.projects.isNotEmpty(),
                        errorMessage = null,
                    ),
                )
            }
            try {
                val (sessionsResult, workspacesResult) = supervisorScope {
                    val sessions = async { runCatching { client.sessions() } }
                    val workspaces = async { runCatching { client.workspaces() } }
                    sessions.await() to workspaces.await()
                }
                val sessions = sessionsResult.getOrThrow()
                if (client !== activeClient || generation != selectionGeneration) return
                observeSessionTransitions(sessions)
                val workspaces = workspacesResult.getOrNull()
                val projection = projectProjection(workspaces, sessions)
                projectBindings.clear()
                projectBindings.putAll(projection.bindings)
                sessionSummaries.clear()
                sessionSummaries.putAll(sessions.associateBy(RemoteSessionSummary::id))
                mutableUiState.update { state ->
                    state.copy(
                        projects = state.projects.copy(
                            computerName = client.displayName,
                            projects = projection.projects,
                            isLoading = false,
                            isRefreshing = false,
                            isDirectoryFallback = projection.isDirectoryFallback,
                            errorMessage = workspacesResult.exceptionOrNull()?.userMessage(),
                            hasLoadedOnce = true,
                        ),
                    )
                }
            } catch (error: Throwable) {
                if (error is CancellationException) throw error
                if (client !== activeClient || generation != selectionGeneration) return
                mutableUiState.update { state ->
                    state.copy(
                        projects = state.projects.copy(
                            isLoading = false,
                            isRefreshing = false,
                            errorMessage = error.userMessage(),
                            hasLoadedOnce = true,
                        ),
                    )
                }
            }
        }
    }

    private fun createSession(projectId: String) {
        val client = activeClient ?: return
        val binding = projectBindings[projectId] ?: return
        if (mutableUiState.value.projects.creatingSessionProjectId != null) return
        mutableUiState.update { state ->
            state.copy(
                projects = state.projects.copy(
                    creatingSessionProjectId = projectId,
                    createSessionErrorMessage = null,
                    lastCreateSessionProjectId = projectId,
                    lastCreatedSessionId = null,
                ),
            )
        }
        viewModelScope.launch {
            try {
                val sessionId = client.createSession(binding.workspaceId, binding.cwd)
                refreshProjectsInternal(showLoading = false)
                if (sessionId !in sessionSummaries) {
                    val project = mutableUiState.value.projects.projects.firstOrNull { it.id == projectId }
                    val summary = RemoteSessionSummary(
                        id = sessionId,
                        title = app.getString(R.string.session_new_default_title),
                        updatedAt = System.currentTimeMillis(),
                        running = false,
                        projectName = project?.title,
                        projectPath = binding.cwd,
                    )
                    sessionSummaries[sessionId] = summary
                    mutableUiState.update { state ->
                        state.copy(
                            projects = state.projects.copy(
                                projects = state.projects.projects.map { item ->
                                    if (item.id == projectId) {
                                        item.copy(sessions = listOf(sessionUi(summary)) + item.sessions)
                                    } else {
                                        item
                                    }
                                },
                            ),
                        )
                    }
                }
                mutableUiState.update { state ->
                    state.copy(
                        projects = state.projects.copy(
                            creatingSessionProjectId = null,
                            createSessionErrorMessage = null,
                            lastCreatedSessionId = sessionId,
                        ),
                    )
                }
                selectSession(sessionId)
            } catch (error: Throwable) {
                if (error is CancellationException) throw error
                mutableUiState.update { state ->
                    state.copy(
                        projects = state.projects.copy(
                            creatingSessionProjectId = null,
                            createSessionErrorMessage = error.userMessage(),
                            lastCreateSessionProjectId = projectId,
                        ),
                    )
                }
            }
        }
    }

    private fun selectSession(sessionId: String) {
        val summary = sessionSummaries[sessionId] ?: return
        cancelSubagentWork()
        selectedSessionId = sessionId
        selectedProjectName = projectNameFor(sessionId)
        subagentNavigation.reset(sessionId)
        latestConversation = null
        latestQueue = emptyList()
        latestModels = null
        imageLimits = null
        historyLimit = DEFAULT_HISTORY_LIMIT
        pendingImages.clear()
        mutableUiState.update { state ->
            state.copy(
                session = SessionDetailUiState(
                    session = sessionUi(summary),
                    projectName = selectedProjectName,
                    isLoading = true,
                ),
            )
        }
        refreshSession()
    }

    private fun refreshSession() {
        viewModelScope.launch { refreshSessionInternal(showLoading = true) }
    }

    private suspend fun refreshSessionInternal(showLoading: Boolean) {
        val client = activeClient ?: return
        val sessionId = selectedSessionId ?: return
        val generation = selectionGeneration
        sessionRefreshMutex.withLock {
            if (client !== activeClient || sessionId != selectedSessionId || generation != selectionGeneration) return
            mutableUiState.updateSession { state ->
                state.copy(
                    isLoading = showLoading && state.messages.isEmpty(),
                    errorMessage = null,
                )
            }
            try {
                val snapshot = client.conversation(sessionId, historyLimit)
                if (client !== activeClient || sessionId != selectedSessionId || generation != selectionGeneration) return
                latestConversation = snapshot
                imageLimits = snapshot.imageLimits
                val failed = snapshot.items.lastOrNull()?.state == RemoteConversationState.FAILED
                if (failed) failedSessionIds += sessionId else failedSessionIds -= sessionId
                val summary = sessionSummaries[sessionId]
                val streaming = summary?.running == true || snapshot.items.any {
                    it.isStreaming || it.state == RemoteConversationState.RUNNING
                }
                mutableUiState.updateSession { state ->
                    state.copy(
                        session = summary?.let(::sessionUi) ?: state.session,
                        projectName = selectedProjectName,
                        messages = mappedConversation(snapshot),
                        isLoading = false,
                        isLoadingOlder = false,
                        hasMoreHistory = snapshot.hasMore,
                        hasLoadedOnce = true,
                        isStreaming = streaming,
                        errorMessage = null,
                        imageLimitLabel = snapshot.imageLimits?.let { limits ->
                            "${limits.maxImagesPerMessage} × ${RemoteUiMapper.byteSize(limits.maxImageBytes.toLong())}"
                        },
                        queue = mappedQueue(latestQueue),
                        interaction = currentInteractionUi(),
                        goal = RemoteUiMapper.goal(snapshot, ::localizeRemoteGenerated),
                        plan = RemoteUiMapper.plan(snapshot),
                        stats = RemoteUiMapper.stats(snapshot),
                        trajectory = RemoteUiMapper.trajectory(snapshot, ::localizeRemoteGenerated),
                    )
                }
                if (latestModels == null) loadModels()
                if (subagentNavigation.rootCatalog == null) refreshSubagents()
            } catch (error: Throwable) {
                if (error is CancellationException) throw error
                if (client !== activeClient || sessionId != selectedSessionId || generation != selectionGeneration) return
                mutableUiState.updateSession { state ->
                    state.copy(
                        isLoading = false,
                        isLoadingOlder = false,
                        hasLoadedOnce = true,
                        errorMessage = error.userMessage(),
                    )
                }
            }
        }
    }

    private fun loadOlderHistory() {
        historyLimit = (historyLimit + HISTORY_PAGE_SIZE).coerceAtMost(MAX_HISTORY_LIMIT)
        mutableUiState.updateSession { it.copy(isLoadingOlder = true) }
        viewModelScope.launch { refreshSessionInternal(showLoading = false) }
    }

    private fun sendPrompt(text: String, delivery: PromptDeliveryUi) {
        val client = activeClient ?: return
        val sessionId = selectedSessionId ?: return
        val images = pendingImages.map(PendingImage::remote)
        if (text.isBlank() && images.isEmpty()) return
        viewModelScope.launch {
            mutableUiState.updateSession { it.copy(isSending = true, errorMessage = null) }
            try {
                client.send(
                    text = text,
                    images = images,
                    sessionId = sessionId,
                    steer = delivery == PromptDeliveryUi.Steer,
                )
                pendingImages.clear()
                renderPendingImages()
                refreshSessionInternal(showLoading = false)
                refreshProjectsInternal(showLoading = false)
            } catch (error: Throwable) {
                if (error is CancellationException) throw error
                mutableUiState.updateSession { it.copy(errorMessage = error.userMessage()) }
            } finally {
                mutableUiState.updateSession { it.copy(isSending = false) }
            }
        }
    }

    private fun stopSession() {
        val client = activeClient ?: return
        val sessionId = selectedSessionId ?: return
        viewModelScope.launch {
            mutableUiState.updateSession { it.copy(isCancelling = true, errorMessage = null) }
            try {
                client.cancel(sessionId)
                refreshSessionInternal(showLoading = false)
                refreshProjectsInternal(showLoading = false)
            } catch (error: Throwable) {
                if (error is CancellationException) throw error
                mutableUiState.updateSession { it.copy(errorMessage = error.userMessage()) }
            } finally {
                mutableUiState.updateSession { it.copy(isCancelling = false) }
            }
        }
    }

    private fun requestImages() {
        if (selectedSessionId != null) systemRequestChannel.trySend(RemoteSystemRequest.PickImages)
    }

    private fun removePendingImage(imageId: String) {
        pendingImages.removeAll { it.remote.id == imageId }
        renderPendingImages()
    }

    private fun searchReferences(query: String) {
        referenceJob?.cancel()
        val client = activeClient ?: return
        val sessionId = selectedSessionId ?: return
        referenceJob = viewModelScope.launch {
            delay(REFERENCE_DEBOUNCE_MILLIS)
            mutableUiState.updateSession {
                it.copy(references = it.references.copy(query = query, isLoading = true, errorMessage = null))
            }
            try {
                val (files, sessions) = supervisorScope {
                    val fileResult = async { client.fileReferences(sessionId, query) }
                    val sessionResult = async { client.sessionReferences(sessionId, query) }
                    fileResult.await() to sessionResult.await()
                }
                if (client !== activeClient || sessionId != selectedSessionId) return@launch
                val candidates = files.map { candidate -> candidate.toUi() } + sessions.map { candidate ->
                    ReferenceCandidateUiModel(
                        id = "session:${candidate.id}",
                        mention = candidate.mention,
                        label = candidate.label,
                        detail = candidate.cwd,
                        kind = ReferenceCandidateKind.Session,
                    )
                }
                mutableUiState.updateSession {
                    it.copy(references = it.references.copy(candidates = candidates, isLoading = false))
                }
            } catch (error: Throwable) {
                if (error is CancellationException) throw error
                mutableUiState.updateSession {
                    it.copy(references = it.references.copy(isLoading = false, errorMessage = error.userMessage()))
                }
            }
        }
    }

    private fun selectReference(candidate: ReferenceCandidateUiModel) {
        mutableUiState.updateSession {
            it.copy(references = ReferenceSuggestionsUiState(query = candidate.mention))
        }
    }

    private fun updateQueue(itemId: String, action: QueueActionUi) {
        val client = activeClient ?: return
        val sessionId = selectedSessionId ?: return
        val item = latestQueue.firstOrNull { it.id == itemId } ?: return
        if (action is QueueActionUi.Edit && item.attachmentCount > 0) {
            mutableUiState.updateSession {
                it.copy(errorMessage = app.getString(R.string.queue_image_edit_error))
            }
            return
        }
        val remoteAction = when (action) {
            is QueueActionUi.Edit -> RemoteQueueAction.Edit(action.text)
            QueueActionUi.Remove -> RemoteQueueAction.Remove
            QueueActionUi.Steer -> RemoteQueueAction.Steer
        }
        viewModelScope.launch {
            mutableUiState.updateSession { it.copy(queue = mappedQueue(latestQueue, itemId)) }
            try {
                client.updateQueue(sessionId, itemId, remoteAction)
                latestQueue = reduceRemoteQueue(latestQueue, itemId, remoteAction)
                mutableUiState.updateSession { it.copy(queue = mappedQueue(latestQueue)) }
                refreshSessionInternal(showLoading = false)
            } catch (error: Throwable) {
                if (error is CancellationException) throw error
                mutableUiState.updateSession { it.copy(errorMessage = error.userMessage()) }
            } finally {
                mutableUiState.updateSession { it.copy(queue = mappedQueue(latestQueue)) }
            }
        }
    }

    private fun resolveInteraction(interactionId: String, decision: InteractionDecisionUi) {
        val client = activeClient ?: return
        val interaction = interactions[interactionId] ?: return
        val remoteDecision = when (decision) {
            InteractionDecisionUi.AllowOnce -> RemoteInteractionDecision.AllowOnce
            InteractionDecisionUi.Reject -> RemoteInteractionDecision.Reject
            is InteractionDecisionUi.Answer -> RemoteInteractionDecision.Answer(
                decision.answers.map { answer ->
                    RemoteQuestionAnswer(answer.questionId, answer.selected, answer.custom)
                },
            )
            InteractionDecisionUi.CancelQuestions -> RemoteInteractionDecision.CancelQuestions
        }
        viewModelScope.launch {
            mutableUiState.updateSession {
                it.copy(
                    interaction = RemoteUiMapper.interaction(
                        interaction,
                        respondingId = interactionId,
                        questionFallback = app.getString(R.string.remote_question_fallback),
                        localize = ::localizeRemoteGenerated,
                    ),
                )
            }
            try {
                client.respond(interaction, remoteDecision)
                interactions.remove(interactionId)
                renderInteraction()
                refreshSessionInternal(showLoading = false)
                refreshProjectsInternal(showLoading = false)
            } catch (error: Throwable) {
                if (error is CancellationException) throw error
                mutableUiState.updateSession {
                    it.copy(
                        interaction = RemoteUiMapper.interaction(
                            interaction,
                            errorMessage = error.userMessage(),
                            questionFallback = app.getString(R.string.remote_question_fallback),
                            localize = ::localizeRemoteGenerated,
                        ),
                    )
                }
            }
        }
    }

    private fun loadModels() {
        val client = activeClient ?: return
        val sessionId = selectedSessionId ?: return
        viewModelScope.launch {
            mutableUiState.updateSession { it.copy(models = mappedModels(latestModels, isLoading = true)) }
            try {
                val directory = client.models(sessionId)
                if (client !== activeClient || sessionId != selectedSessionId) return@launch
                latestModels = directory
                mutableUiState.updateSession { it.copy(models = mappedModels(directory)) }
            } catch (error: Throwable) {
                if (error is CancellationException) throw error
                mutableUiState.updateSession {
                    it.copy(models = mappedModels(latestModels, errorMessage = error.userMessage()))
                }
            }
        }
    }

    private fun selectModel(
        selection: ModelSelectionUiModel,
        onResult: (Boolean) -> Unit,
    ) {
        val client = activeClient ?: run {
            onResult(false)
            return
        }
        val sessionId = selectedSessionId ?: run {
            onResult(false)
            return
        }
        viewModelScope.launch {
            mutableUiState.updateSession {
                it.copy(models = mappedModels(latestModels, isSelecting = true))
            }
            try {
                client.selectModel(
                    sessionId,
                    RemoteModelSelection(
                        provider = selection.providerId,
                        model = selection.modelId,
                        reasoningEffort = selection.reasoningEffortId,
                    ),
                )
                latestModels = client.models(sessionId)
                mutableUiState.updateSession { it.copy(models = mappedModels(latestModels)) }
                onResult(true)
            } catch (error: Throwable) {
                if (error is CancellationException) {
                    onResult(false)
                    throw error
                }
                mutableUiState.updateSession {
                    it.copy(models = mappedModels(latestModels, errorMessage = error.userMessage()))
                }
                onResult(false)
            }
        }
    }

    private fun openAttachment(attachmentId: String) {
        val client = activeClient ?: return
        val sessionId = selectedSessionId ?: return
        val metadata = latestConversation.findImageAttachment(attachmentId) ?: return
        requestAttachment(
            client = client,
            sessionId = sessionId,
            metadata = metadata,
            isCurrent = { client === activeClient && sessionId == selectedSessionId },
            render = ::renderConversationFromCache,
        )
    }

    private fun openSubagentAttachment(subagentId: String, attachmentId: String) {
        val client = activeClient ?: return
        val selection = subagentNavigation.selection
            ?.takeIf { it.entry.id == subagentId }
            ?: return
        // Deliberately search only the selected child's snapshot. A matching parent attachment id
        // must never cause a child tap to read from the root session.
        val metadata = selection.snapshot.findImageAttachment(attachmentId) ?: return
        val address = selection.address
        requestAttachment(
            client = client,
            sessionId = subagentId,
            metadata = metadata,
            isCurrent = { client === activeClient && subagentNavigation.selection?.address == address },
            render = { renderSelectedSubagent() },
        )
    }

    private fun requestAttachment(
        client: HarnessRemoteClient,
        sessionId: String,
        metadata: RemoteImageAttachment,
        isCurrent: () -> Boolean,
        render: () -> Unit,
    ) {
        val hostId = selectedHostId.orEmpty()
        val stateKey = attachmentStateKey(sessionId, metadata.attachmentId)
        attachmentStates[stateKey] = AttachmentState(metadata, isLoading = true)
        render()
        viewModelScope.launch {
            try {
                val cacheKey = "$hostId:$sessionId:${metadata.attachmentId}"
                val cached = withContext(Dispatchers.IO) {
                    attachmentCache.get(cacheKey, metadata.mediaType, metadata.bytes.toLong())
                }
                val attachment: RemoteImageAttachment
                val file = if (cached != null) {
                    attachment = metadata
                    cached
                } else {
                    val payload = client.attachment(sessionId, metadata.attachmentId)
                    attachment = payload.attachment
                    withContext(Dispatchers.IO) {
                        attachmentCache.put(cacheKey, payload.attachment.mediaType, payload.data)
                    }
                }
                if (!isCurrent()) return@launch
                val uri = FileProvider.getUriForFile(app, "${app.packageName}.files", file)
                attachmentStates[stateKey] = AttachmentState(attachment, previewUri = uri.toString())
                render()
            } catch (error: Throwable) {
                if (error is CancellationException) throw error
                if (!isCurrent()) return@launch
                attachmentStates[stateKey] = AttachmentState(metadata, errorMessage = error.userMessage())
                render()
            }
        }
    }

    private fun refreshSubagents() {
        val client = activeClient ?: return
        val sessionId = selectedSessionId ?: return
        val catalogAddress = subagentNavigation.currentCatalogAddress ?: return
        subagentCatalogJob?.cancel()
        subagentCatalogJob = viewModelScope.launch {
            renderSubagentCatalog(isLoading = true)
            try {
                val catalog = client.subagents(catalogAddress.parentSessionId)
                if (client !== activeClient || sessionId != selectedSessionId ||
                    catalogAddress != subagentNavigation.currentCatalogAddress
                ) return@launch
                subagentNavigation.updateCatalog(catalogAddress.parentSessionId, catalog)
                renderSubagentCatalog()
            } catch (error: Throwable) {
                if (error is CancellationException) throw error
                if (client !== activeClient || sessionId != selectedSessionId ||
                    catalogAddress != subagentNavigation.currentCatalogAddress
                ) return@launch
                renderSubagentCatalog(errorMessage = error.userMessage())
            }
        }
    }

    private fun openSubagent(subagentId: String) {
        activeClient ?: return
        selectedSessionId ?: return
        val selection = subagentNavigation.select(subagentId, DEFAULT_SUBAGENT_HISTORY_LIMIT) ?: return
        if (selection.entry.isDiagnostic) return
        renderSelectedSubagent()
        startSubagentMonitor()
    }

    private fun openSubagentChildren(subagentId: String) {
        val selection = subagentNavigation.selection
            ?.takeIf { it.entry.id == subagentId && it.entry.hasChildren }
            ?: return
        cancelSubagentWork()
        if (!subagentNavigation.enterChildren(selection.address)) return
        mutableUiState.updateSession { it.copy(selectedSubagent = null) }
        renderSubagentCatalog(isLoading = true)
        refreshSubagents()
    }

    private fun navigateBackSubagents() {
        cancelSubagentWork()
        when (subagentNavigation.back()) {
            SubagentBackResult.ShowCatalog -> {
                mutableUiState.updateSession { it.copy(selectedSubagent = null) }
                renderSubagentCatalog()
            }
            SubagentBackResult.ShowConversation -> {
                renderSubagentCatalog()
                renderSelectedSubagent()
                startSubagentMonitor()
            }
            SubagentBackResult.AtRoot -> Unit
        }
    }

    private fun dismissSubagents() {
        cancelSubagentWork()
        subagentNavigation.dismiss()
        mutableUiState.updateSession {
            it.copy(
                subagents = currentSubagentCatalogUi(),
                selectedSubagent = null,
            )
        }
    }

    private fun loadOlderSubagentHistory(subagentId: String) {
        val client = activeClient ?: return
        selectedSessionId ?: return
        val address = subagentNavigation.selection?.address?.takeIf { it.childSessionId == subagentId } ?: return
        subagentNavigation.updateSelection(address) { selection ->
            selection.copy(
                historyLimit = (selection.historyLimit + HISTORY_PAGE_SIZE).coerceAtMost(MAX_HISTORY_LIMIT),
                isLoadingOlder = true,
                errorMessage = null,
            )
        }
        renderSelectedSubagent()
        subagentActionJob?.cancel()
        subagentActionJob = viewModelScope.launch {
            refreshSelectedSubagent(client, address)
        }
    }

    private fun startSubagentMonitor() {
        val client = activeClient ?: return
        val sessionId = selectedSessionId ?: return
        val address = subagentNavigation.selection?.address ?: return
        subagentMonitorJob?.cancel()
        subagentMonitorJob = viewModelScope.launch {
            while (currentCoroutineContext().isActive && client === activeClient &&
                sessionId == selectedSessionId && address == subagentNavigation.selection?.address
            ) {
                refreshSelectedSubagent(client, address)
                val activity = subagentNavigation.selection?.entry?.activity
                delay(subagentRefreshIntervalMillis(activity))
            }
        }
    }

    private suspend fun refreshSelectedSubagent(
        client: HarnessRemoteClient,
        address: SubagentAddress,
    ) {
        subagentRefreshMutex.withLock {
            val selection = subagentNavigation.selection?.takeIf { it.address == address } ?: return
            try {
                val catalog = try {
                    client.subagents(address.parentSessionId)
                } catch (error: CancellationException) {
                    throw error
                } catch (_: Throwable) {
                    null
                }
                val currentEntry = catalog?.entries?.firstOrNull { it.id == address.childSessionId }
                    ?.takeUnless { it.isDiagnostic }
                    ?: selection.entry
                val snapshot = client.subagentConversation(
                    address.parentSessionId,
                    currentEntry,
                    selection.historyLimit,
                )
                if (client !== activeClient || address != subagentNavigation.selection?.address) return
                if (catalog != null) subagentNavigation.updateCatalog(address.parentSessionId, catalog)
                subagentNavigation.updateSelection(address) { latest ->
                    latest.copy(
                        entry = currentEntry,
                        snapshot = snapshot,
                        parentAvailable = catalog?.parentAvailable ?: latest.parentAvailable,
                        isLoading = false,
                        isLoadingOlder = false,
                        errorMessage = null,
                    )
                }
                renderSubagentCatalog()
                renderSelectedSubagent()
            } catch (error: Throwable) {
                if (error is CancellationException) throw error
                if (client !== activeClient || address != subagentNavigation.selection?.address) return
                subagentNavigation.updateSelection(address) { latest ->
                    latest.copy(
                        isLoading = false,
                        isLoadingOlder = false,
                        errorMessage = error.userMessage(),
                    )
                }
                renderSelectedSubagent()
            }
        }
    }

    private fun continueSubagent(subagentId: String, text: String) {
        val client = activeClient ?: return
        selectedSessionId ?: return
        val selection = subagentNavigation.selection
            ?.takeIf { it.entry.id == subagentId && it.parentAvailable && !it.isSending && !it.isStopping }
            ?: return
        val value = text.trim()
        if (value.isEmpty()) return
        val address = selection.address
        subagentNavigation.updateSelection(address) { it.copy(isSending = true, errorMessage = null) }
        renderSelectedSubagent()
        subagentActionJob?.cancel()
        subagentActionJob = viewModelScope.launch {
            try {
                client.promptSubagent(address.parentSessionId, selection.entry, value)
                subagentNavigation.updateSelection(address) { latest ->
                    latest.copy(entry = latest.entry.copy(activity = RemoteSubagentActivity.RUNNING))
                }
                refreshSelectedSubagent(client, address)
            } catch (error: Throwable) {
                if (error is CancellationException) throw error
                subagentNavigation.updateSelection(address) { latest ->
                    latest.copy(errorMessage = error.userMessage())
                }
            } finally {
                subagentNavigation.updateSelection(address) { latest ->
                    latest.copy(isSending = false)
                }
                renderSelectedSubagent()
            }
        }
    }

    private fun stopSubagent(subagentId: String) {
        val client = activeClient ?: return
        selectedSessionId ?: return
        val selection = subagentNavigation.selection
            ?.takeIf {
                it.entry.id == subagentId &&
                    it.entry.activity == RemoteSubagentActivity.RUNNING &&
                    !it.isStopping && !it.isSending
            }
            ?: return
        val address = selection.address
        subagentNavigation.updateSelection(address) { it.copy(isStopping = true, errorMessage = null) }
        renderSelectedSubagent()
        subagentActionJob?.cancel()
        subagentActionJob = viewModelScope.launch {
            try {
                client.interruptSubagent(address.parentSessionId, selection.entry)
                refreshSelectedSubagent(client, address)
            } catch (error: Throwable) {
                if (error is CancellationException) throw error
                subagentNavigation.updateSelection(address) { latest ->
                    latest.copy(errorMessage = error.userMessage())
                }
            } finally {
                subagentNavigation.updateSelection(address) { latest -> latest.copy(isStopping = false) }
                renderSelectedSubagent()
            }
        }
    }

    private fun dismissSessionErrors() {
        subagentNavigation.selection?.address?.let { address ->
            subagentNavigation.updateSelection(address) { it.copy(errorMessage = null) }
        }
        mutableUiState.updateSession { state ->
            state.copy(
                errorMessage = null,
                references = state.references.copy(errorMessage = null),
                models = state.models.copy(errorMessage = null),
                subagents = state.subagents.copy(errorMessage = null),
                interaction = state.interaction?.copy(errorMessage = null),
                selectedSubagent = state.selectedSubagent?.copy(errorMessage = null),
            )
        }
    }

    private fun switchClient(client: HarnessRemoteClient?, hostId: String?) {
        selectionGeneration += 1
        liveEventsJob?.cancel()
        pollingJob?.cancel()
        referenceJob?.cancel()
        cancelSubagentWork()
        activeClient = client
        selectedHostId = hostId
        selectedSessionId = null
        selectedProjectName = ""
        subagentNavigation.reset(null)
        latestConversation = null
        latestQueue = emptyList()
        latestModels = null
        imageLimits = null
        projectBindings.clear()
        sessionSummaries.clear()
        interactions.clear()
        pendingImages.clear()
        localNetworkPermissionRecovery.clear()
    }

    private fun startLiveMonitoring() {
        val client = activeClient ?: return
        val generation = selectionGeneration
        liveEventsJob?.cancel()
        liveEventsJob = viewModelScope.launch {
            client.liveEvents().collect { event ->
                if (client !== activeClient || generation != selectionGeneration) return@collect
                handleLiveEvent(client, event)
            }
        }
        pollingJob?.cancel()
        pollingJob = viewModelScope.launch {
            foregroundTracker.isForeground.collectLatest { foreground ->
                if (!foreground) return@collectLatest
                while (currentCoroutineContext().isActive && client === activeClient) {
                    delay(FOREGROUND_POLL_MILLIS)
                    refreshProjectsInternal(showLoading = false)
                    if (selectedSessionId != null) refreshSessionInternal(showLoading = false)
                }
            }
        }
    }

    private suspend fun handleLiveEvent(client: HarnessRemoteClient, event: RemoteLiveEvent) {
        when (event) {
            is RemoteLiveEvent.SessionChanged -> {
                val wasRunning = runningStates[event.sessionId] == true
                refreshProjectsInternal(showLoading = false)
                if (event.sessionId == selectedSessionId) refreshSessionInternal(showLoading = false)
                if (wasRunning && runningStates[event.sessionId] == false) {
                    sessionSummaries[event.sessionId]?.let { summary ->
                        postTaskNotification(summary, app.getString(R.string.session_state_completed))
                    }
                }
            }
            is RemoteLiveEvent.QueueChanged -> {
                if (event.sessionId == selectedSessionId) {
                    latestQueue = event.items
                    mutableUiState.updateSession { it.copy(queue = mappedQueue(event.items)) }
                }
            }
            is RemoteLiveEvent.Interaction -> {
                interactions[event.interaction.id] = event.interaction
                renderInteraction()
                renderProjectSessionStates()
                if (!client.isDemo) {
                    sessionSummaries[event.interaction.sessionId]?.let { summary ->
                        postTaskNotification(summary, app.getString(R.string.session_state_waiting))
                    }
                }
            }
            is RemoteLiveEvent.InteractionResolved -> {
                interactions.remove(event.id)
                renderInteraction()
                renderProjectSessionStates()
            }
        }
    }

    private fun observeSessionTransitions(sessions: List<RemoteSessionSummary>) {
        sessions.forEach { summary ->
            val previous = runningStates.put(summary.id, summary.running)
            if (previous == true && !summary.running) completedSessionIds += summary.id
            if (summary.running) completedSessionIds -= summary.id
        }
        runningStates.keys.retainAll(sessions.mapTo(mutableSetOf()) { it.id })
    }

    private fun projectProjection(
        workspaces: RemoteWorkspaceSnapshot?,
        sessions: List<RemoteSessionSummary>,
    ): ProjectProjection {
        val visibleSessions = sessions.filterNot { it.id in workspaces?.archivedSessionIds.orEmpty() }
        if (workspaces == null || (workspaces.items.isEmpty() && visibleSessions.isNotEmpty())) {
            return directoryProjection(visibleSessions)
        }
        val byId = visibleSessions.associateBy(RemoteSessionSummary::id)
        val assigned = mutableSetOf<String>()
        val projects = mutableListOf<ProjectUiModel>()
        val bindings = mutableMapOf<String, ProjectBinding>()
        workspaces.items.forEach { workspace ->
            val projectSessions = workspace.sessionIds.mapNotNull { id -> byId[id] }
                .sortedByDescending(RemoteSessionSummary::updatedAt)
            assigned += projectSessions.map(RemoteSessionSummary::id)
            projects += project(workspace, projectSessions)
            bindings[workspace.id] = ProjectBinding(workspace.id, workspace.path)
        }
        val unassigned = visibleSessions.filterNot { it.id in assigned }
        if (unassigned.isNotEmpty()) {
            val fallback = directoryProjection(unassigned)
            projects += fallback.projects
            bindings += fallback.bindings
        }
        return ProjectProjection(projects, bindings, isDirectoryFallback = false)
    }

    private fun directoryProjection(sessions: List<RemoteSessionSummary>): ProjectProjection {
        val grouped = sessions.groupBy { it.projectPath?.trim()?.takeIf(String::isNotEmpty) ?: "" }
        val bindings = mutableMapOf<String, ProjectBinding>()
        val projects = grouped.map { (path, projectSessions) ->
            val id = "directory:${path.ifBlank { "unassigned" }}"
            val title = projectSessions.firstNotNullOfOrNull { it.projectName?.takeIf(String::isNotBlank) }
                ?: path.substringAfterLast('/').takeIf(String::isNotBlank)
                ?: activeClient?.displayName
                ?: app.getString(R.string.remote_computer_fallback)
            bindings[id] = ProjectBinding(null, path.takeIf(String::isNotBlank))
            ProjectUiModel(
                id = id,
                title = localizeRemoteGenerated(title),
                path = path.takeIf(String::isNotBlank),
                sessions = projectSessions.sortedByDescending(RemoteSessionSummary::updatedAt).map(::sessionUi),
                canCreateSession = path.isNotBlank(),
            )
        }.sortedBy { it.title.lowercase() }
        return ProjectProjection(projects, bindings, isDirectoryFallback = true)
    }

    private fun project(workspace: RemoteWorkspaceSummary, sessions: List<RemoteSessionSummary>) = ProjectUiModel(
        id = workspace.id,
        title = localizeRemoteGenerated(workspace.title),
        path = workspace.path,
        sessions = sessions.map(::sessionUi),
        canCreateSession = true,
    )

    private fun sessionUi(summary: RemoteSessionSummary) = RemoteUiMapper.session(
        summary = summary.copy(title = localizeRemoteGenerated(summary.title)),
        hasInteraction = interactions.values.any { it.sessionId == summary.id },
        completed = summary.id in completedSessionIds,
        failed = summary.id in failedSessionIds,
        nowLabel = app.getString(R.string.time_now),
    )

    private fun projectNameFor(sessionId: String): String = mutableUiState.value.projects.projects
        .firstOrNull { project -> project.sessions.any { it.id == sessionId } }
        ?.title
        .orEmpty()

    private fun renderHosts(hosts: List<RemoteHost>) {
        val computers = hosts.map { host ->
            ComputerUiModel(
                id = host.id,
                name = host.name,
                address = host.baseUrl,
                transport = when (RemoteEndpointValidator.transport(host.connection())) {
                    RemoteHostTransport.SAME_WIFI -> ComputerTransport.SameWifi
                    RemoteHostTransport.TAILSCALE -> ComputerTransport.Tailscale
                    else -> ComputerTransport.CustomHttps
                },
                connectionState = connectionStates[host.id] ?: ComputerConnectionState.Unknown,
            )
        }
        mutableUiState.update { state ->
            state.copy(computers = state.computers.copy(computers = computers, isLoading = false))
        }
    }

    private fun renderProjectSessionStates() {
        mutableUiState.update { state ->
            state.copy(
                projects = state.projects.copy(
                    projects = state.projects.projects.map { project ->
                        project.copy(
                            sessions = project.sessions.map { session ->
                                sessionSummaries[session.id]?.let(::sessionUi) ?: session
                            },
                        )
                    },
                ),
                session = state.session.copy(
                    session = selectedSessionId?.let(sessionSummaries::get)?.let(::sessionUi) ?: state.session.session,
                ),
            )
        }
    }

    private fun renderPendingImages() {
        val models = pendingImages.map { pending ->
            PromptImageUiModel(
                id = pending.remote.id,
                name = pending.remote.name,
                previewUri = pending.previewUri,
                dimensionsLabel = "${pending.remote.width} × ${pending.remote.height}",
                sizeLabel = RemoteUiMapper.byteSize(pending.remote.data.size.toLong()),
            )
        }
        mutableUiState.updateSession { it.copy(pendingImages = models) }
    }

    private fun mappedQueue(
        items: List<RemoteQueuedMessage>,
        updatingItemId: String? = null,
    ) = RemoteUiMapper.queue(
        items = items,
        updatingItemId = updatingItemId,
        imageCountLabel = { count ->
            app.resources.getQuantityString(R.plurals.queue_images, count, count)
        },
        emptyLabel = app.getString(R.string.queue_message_fallback),
    )

    private fun mappedModels(
        directory: RemoteModelDirectory?,
        isLoading: Boolean = false,
        isSelecting: Boolean = false,
        errorMessage: String? = null,
    ) = RemoteUiMapper.models(
        directory = directory,
        isLoading = isLoading,
        isSelecting = isSelecting,
        errorMessage = errorMessage,
        localizeDescription = ::localizeRemoteGenerated,
    )

    private fun renderInteraction() {
        mutableUiState.updateSession { it.copy(interaction = currentInteractionUi()) }
    }

    private fun currentInteractionUi() = RemoteUiMapper.interaction(
        interactions.values.firstOrNull { it.sessionId == selectedSessionId },
        questionFallback = app.getString(R.string.remote_question_fallback),
        localize = ::localizeRemoteGenerated,
    )

    private fun renderConversationFromCache() {
        val snapshot = latestConversation ?: return
        mutableUiState.updateSession { it.copy(messages = mappedConversation(snapshot)) }
    }

    private fun renderSubagentCatalog(isLoading: Boolean = false, errorMessage: String? = null) {
        mutableUiState.updateSession {
            it.copy(subagents = currentSubagentCatalogUi(isLoading, errorMessage))
        }
    }

    private fun currentSubagentCatalogUi(
        isLoading: Boolean = false,
        errorMessage: String? = null,
    ) = RemoteUiMapper.subagents(
        subagentNavigation.currentCatalog,
        isLoading = isLoading,
        errorMessage = errorMessage,
        diagnosticName = ::subagentDiagnosticName,
        localizeLabel = ::localizeRemoteGenerated,
    ).copy(
        navigationDepth = subagentNavigation.depth,
        parentLabel = subagentNavigation.currentOwner?.entry?.let { entry ->
            entry.label?.let(::localizeRemoteGenerated) ?: entry.id
        },
    )

    private fun renderSelectedSubagent() {
        val selection = subagentNavigation.selection
        mutableUiState.updateSession { state ->
            state.copy(
                selectedSubagent = selection?.let { selected ->
                    SubagentConversationUiState(
                        subagent = RemoteUiMapper.subagent(
                            selected.entry,
                            ::subagentDiagnosticName,
                            ::localizeRemoteGenerated,
                        ),
                        messages = selected.snapshot?.let { snapshot ->
                            mappedConversation(snapshot, selected.entry.id)
                        }.orEmpty(),
                        hasMoreHistory = selected.snapshot?.hasMore == true,
                        isLoading = selected.isLoading,
                        isLoadingOlder = selected.isLoadingOlder,
                        isSending = selected.isSending,
                        isStopping = selected.isStopping,
                        errorMessage = selected.errorMessage,
                        parentAvailable = selected.parentAvailable,
                    )
                },
            )
        }
    }

    private fun cancelSubagentWork() {
        subagentCatalogJob?.cancel()
        subagentCatalogJob = null
        subagentMonitorJob?.cancel()
        subagentMonitorJob = null
        subagentActionJob?.cancel()
        subagentActionJob = null
    }

    private fun mappedConversation(
        snapshot: RemoteConversationSnapshot,
        sessionId: String = selectedSessionId.orEmpty(),
    ) =
        RemoteUiMapper.conversation(snapshot, ::localizeRemoteGenerated).map { message ->
            message.copy(
                attachments = message.attachments.map { attachment ->
                    attachmentStates[attachmentStateKey(sessionId, attachment.id)]?.toUi() ?: attachment
                },
            )
        }

    private fun attachmentStateKey(sessionId: String, attachmentId: String) = AttachmentStateKey(
        hostId = selectedHostId.orEmpty(),
        sessionId = sessionId,
        attachmentId = attachmentId,
    )

    private fun requestNotificationPermissionIfNeeded() {
        if (activeClient?.isDemo != false || notificationPermissionRequested || Build.VERSION.SDK_INT < 33) return
        if (app.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) return
        notificationPermissionRequested = true
        systemRequestChannel.trySend(RemoteSystemRequest.RequestNotificationPermission)
    }

    private fun postTaskNotification(summary: RemoteSessionSummary, body: String) {
        val hostId = selectedHostId ?: return
        val intent = Intent(app, MainActivity::class.java)
            .putExtra(RemoteLaunchExtras.HOST_ID, hostId)
            .putExtra(RemoteLaunchExtras.SESSION_ID, summary.id)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val pendingIntent = PendingIntent.getActivity(
            app,
            (hostId + summary.id).hashCode() and Int.MAX_VALUE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        notifications.postTaskUpdate(
            RemoteTaskNotification(
                stableKey = "session:${summary.id}",
                sessionId = summary.id,
                title = summary.title,
                body = body,
                contentIntent = pendingIntent,
            ),
        )
    }

    private fun setSessionVisibility(sessionId: String?, visible: Boolean) {
        if (visible) {
            visibleSessionId = sessionId
        } else if (visibleSessionId == sessionId) {
            visibleSessionId = null
        }
    }

    private fun preparationLimits(limits: RemoteImageLimits?): PhotoPreparationLimits {
        val types = limits?.mediaTypes.orEmpty()
            .map { it.lowercase(Locale.ROOT) }
            .filter { it == "image/jpeg" || it == "image/png" }
            .toSet()
            .ifEmpty { setOf("image/jpeg", "image/png") }
        return PhotoPreparationLimits(
            maxOutputBytes = (limits?.maxImageBytes ?: DEFAULT_MAX_IMAGE_BYTES)
                .coerceAtMost(PhotoPreparationLimits.HARD_MAX_OUTPUT_BYTES),
            maxPixels = (limits?.maxImagePixels ?: PhotoPreparationLimits.HARD_MAX_DECODE_PIXELS)
                .coerceAtMost(PhotoPreparationLimits.HARD_MAX_DECODE_PIXELS),
            maxDimension = (limits?.maxImageDimension ?: PhotoPreparationLimits.HARD_MAX_DECODE_DIMENSION)
                .coerceAtMost(PhotoPreparationLimits.HARD_MAX_DECODE_DIMENSION),
            allowedMediaTypes = types,
        )
    }

    private fun displayName(uri: Uri): String? = runCatching {
        app.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (!cursor.moveToFirst()) return@use null
            cursor.getString(0)?.take(MAX_DISPLAY_NAME_CHARACTERS)
        }
    }.getOrNull()

    private fun showAddComputerError(
        message: String = app.getString(R.string.state_connection_failed),
    ) {
        mutableUiState.update { state ->
            state.copy(
                addComputer = state.addComputer.copy(
                    isVerifying = false,
                    errorMessage = message,
                ),
            )
        }
    }

    private fun client(host: RemoteHost): HarnessRemoteClient {
        val connection = RemoteEndpointValidator.validatedConnection(host.connection())
        return LiveHarnessRemoteClient(
            baseUrl = connection.baseUrl,
            displayName = host.name,
            accessToken = connection.accessToken,
        )
    }

    private fun RemoteHost.connection() = RemoteConnectionDescriptor(baseUrl, accessToken)

    private fun RemoteFileReferenceCandidate.toUi() = ReferenceCandidateUiModel(
        id = id,
        mention = "@$path",
        label = path.substringAfterLast('/').ifBlank { path },
        detail = path,
        kind = when (kind) {
            RemoteReferenceKind.FILE -> ReferenceCandidateKind.File
            RemoteReferenceKind.DIRECTORY -> ReferenceCandidateKind.Directory
        },
    )

    private fun Throwable.userMessage(): String = when (this) {
        is AttachmentCacheLimitException -> app.getString(R.string.attachment_error_cache_limit)
        is ImageMessageLimitException -> app.getString(R.string.image_error_message_limit)
        is PhotoPreparationException -> when (reason) {
            PhotoPreparationError.UNREADABLE_INPUT -> app.getString(R.string.image_error_unreadable)
            PhotoPreparationError.INPUT_TOO_LARGE,
            PhotoPreparationError.OUTPUT_TOO_LARGE,
            -> app.getString(R.string.image_error_too_large)
            PhotoPreparationError.INVALID_IMAGE,
            PhotoPreparationError.SOURCE_DIMENSIONS_UNSAFE,
            -> app.getString(R.string.image_error_invalid)
            PhotoPreparationError.UNSUPPORTED_OUTPUT_TYPE ->
                app.getString(R.string.image_error_unsupported)
        }
        HarnessRemoteClientException.InvalidResponse ->
            app.getString(R.string.remote_error_invalid_response)
        HarnessRemoteClientException.MismatchedResponse ->
            app.getString(R.string.remote_error_mismatched_response)
        is HarnessRemoteClientException.Server -> when (statusCode) {
            401 -> app.getString(R.string.remote_error_pairing_expired)
            413 -> app.getString(R.string.remote_error_too_large)
            else -> app.getString(R.string.remote_error_http, statusCode)
        }
        HarnessRemoteClientException.UnsupportedDecision ->
            app.getString(R.string.remote_error_unsupported_decision)
        is HarnessRemoteClientException.Api -> controlledApiErrorString(code)?.let { app.getString(it) }
            ?: message.takeIf { it.isNotBlank() }
            ?: app.getString(R.string.state_connection_failed)
        is HarnessRemoteClientException -> message?.takeIf { it.isNotBlank() }
            ?: app.getString(R.string.state_connection_failed)
        else -> app.getString(R.string.state_connection_failed)
    }

    private fun subagentDiagnosticName(reason: RemoteSubagentDiagnosticReason): String = when (reason) {
        RemoteSubagentDiagnosticReason.CORRUPT -> app.getString(R.string.remote_subagent_corrupt)
        RemoteSubagentDiagnosticReason.UNSUPPORTED -> app.getString(R.string.remote_subagent_unsupported)
        RemoteSubagentDiagnosticReason.UNAVAILABLE -> app.getString(R.string.remote_subagent_unavailable)
    }

    private fun endpointErrorMessage(reason: RemoteEndpointError): String = when (reason) {
        RemoteEndpointError.EMPTY -> app.getString(R.string.endpoint_error_empty)
        RemoteEndpointError.INVALID_URL -> app.getString(R.string.endpoint_error_invalid)
        RemoteEndpointError.INSECURE_URL -> app.getString(R.string.endpoint_error_insecure)
        RemoteEndpointError.UNSUPPORTED_HOST -> app.getString(R.string.endpoint_error_unsupported_host)
        RemoteEndpointError.EMBEDDED_CREDENTIALS -> app.getString(R.string.endpoint_error_credentials)
        RemoteEndpointError.MISSING_PAIRING_CREDENTIAL -> app.getString(R.string.endpoint_error_pairing_required)
    }

    private fun localizeRemoteGenerated(value: String): String {
        val tokenCount = value.removeSuffix(" tokens").toIntOrNull()
        if (tokenCount != null && value.endsWith(" tokens")) {
            return app.resources.getQuantityString(
                R.plurals.remote_token_count,
                tokenCount,
                tokenCount,
            )
        }
        GOAL_ROUNDS_PATTERN.matchEntire(value)?.let { match ->
            val roundsStarted = match.groupValues[1].toInt()
            return app.resources.getQuantityString(
                R.plurals.remote_goal_rounds,
                roundsStarted,
                roundsStarted,
                match.groupValues[2].toInt(),
            )
        }
        REVISION_PATTERN.matchEntire(value)?.let { match ->
            return app.getString(R.string.remote_revision, match.groupValues[1].toInt())
        }
        if (value.startsWith("Retrying in ")) {
            return app.getString(R.string.remote_retrying_in, value.removePrefix("Retrying in "))
        }
        return when (value) {
        "Untitled task" -> app.getString(R.string.remote_untitled_task)
        "Computer" -> app.getString(R.string.remote_computer_fallback)
        "Question" -> app.getString(R.string.remote_question_fallback)
        "Harness context" -> app.getString(R.string.remote_context_harness)
        "Model context" -> app.getString(R.string.remote_context_model)
        "Project instructions" -> app.getString(R.string.remote_context_project)
        "Plugin context" -> app.getString(R.string.remote_context_plugin)
        "Available capabilities" -> app.getString(R.string.remote_context_capabilities)
        "Skill context" -> app.getString(R.string.remote_context_skill)
        "Referenced session" -> app.getString(R.string.remote_context_session)
        "Goal continuation" -> app.getString(R.string.remote_context_goal)
        "System context" -> app.getString(R.string.remote_context_system)
        "User input" -> app.getString(R.string.remote_trajectory_user)
        "Model response" -> app.getString(R.string.remote_trajectory_model)
        "Tool" -> app.getString(R.string.remote_trajectory_tool)
        "Lifecycle" -> app.getString(R.string.remote_trajectory_lifecycle)
        "Stopped" -> app.getString(R.string.remote_metadata_stopped)
        "System prompt" -> app.getString(R.string.remote_system_prompt)
        "Model request" -> app.getString(R.string.remote_model_request)
        "Reasoning" -> app.getString(R.string.remote_reasoning)
        "Answer" -> app.getString(R.string.remote_answer)
        "Model reasoning" -> app.getString(R.string.remote_model_reasoning)
        "Model output" -> app.getString(R.string.remote_model_output)
        "Running on your computer" -> app.getString(R.string.remote_tool_running)
        "Execution failed" -> app.getString(R.string.remote_execution_failed)
        "Completed" -> app.getString(R.string.remote_completed)
        "Input" -> app.getString(R.string.remote_input)
        "Terminal output" -> app.getString(R.string.remote_terminal_output)
        "Result" -> app.getString(R.string.remote_result)
        "Goal cleared" -> app.getString(R.string.remote_goal_cleared)
        "This session will no longer continue the goal automatically." ->
            app.getString(R.string.remote_goal_cleared_message)
        "Goal created" -> app.getString(R.string.remote_goal_created)
        "Goal paused" -> app.getString(R.string.remote_goal_paused)
        "Goal resumed" -> app.getString(R.string.remote_goal_resumed)
        "Goal completed" -> app.getString(R.string.remote_goal_completed)
        "Goal needs attention" -> app.getString(R.string.remote_goal_attention)
        "Goal updated" -> app.getString(R.string.remote_goal_updated)
        "Harness updated the current goal." -> app.getString(R.string.remote_goal_updated_message)
        "Plan mode enabled" -> app.getString(R.string.remote_plan_enabled)
        "Plan mode disabled" -> app.getString(R.string.remote_plan_disabled)
        "Harness will prepare a plan before asking to execute it." ->
            app.getString(R.string.remote_plan_enabled_message)
        "Harness returned to normal execution mode." -> app.getString(R.string.remote_plan_disabled_message)
        "Model request retrying" -> app.getString(R.string.remote_model_retrying)
        "Waiting for the next request" -> app.getString(R.string.remote_waiting_request)
        "The connection or model request failed temporarily; Harness will retry." ->
            app.getString(R.string.remote_retry_message)
        "Context compacted" -> app.getString(R.string.remote_context_compacted)
        "Older content was compressed into a summary." ->
            app.getString(R.string.remote_context_compacted_message)
        "Compaction summary" -> app.getString(R.string.remote_compaction_summary)
        "Turn completed" -> app.getString(R.string.remote_turn_completed)
        "Turn ended" -> app.getString(R.string.remote_turn_ended)
        "Harness completed this turn" -> app.getString(R.string.remote_turn_completed_message)
        "Turn failed" -> app.getString(R.string.remote_turn_failed)
        "The model returned an error." -> app.getString(R.string.remote_model_error)
        "Output limit reached" -> app.getString(R.string.remote_output_limit)
        "The model reached the output token limit." -> app.getString(R.string.remote_output_limit_message)
        "Turn stopped" -> app.getString(R.string.remote_turn_stopped)
        "Execution was cancelled; existing output is retained." ->
            app.getString(R.string.remote_turn_stopped_message)
        "Turn blocked" -> app.getString(R.string.remote_turn_blocked)
        "Harness cannot continue this step." -> app.getString(R.string.remote_turn_blocked_message)
        "Turn interrupted" -> app.getString(R.string.remote_turn_interrupted)
        "The session ended before completion." -> app.getString(R.string.remote_turn_interrupted_message)
        "Demo" -> app.getString(R.string.demo_host_name)
        "Offline Demo" -> app.getString(R.string.demo_host_description)
        "Sample App" -> app.getString(R.string.demo_workspace_title)
        "Login flow release review" -> app.getString(R.string.demo_session_review_title)
        "Review the login flow before release." -> app.getString(R.string.demo_review_prompt)
        "Read project files" -> app.getString(R.string.demo_tool_read_title)
        "Read four authentication files" -> app.getString(R.string.demo_tool_read_summary)
        "Files" -> app.getString(R.string.demo_tool_files_title)
        "I found two release risks: session restoration is not covered by a regression test, and the offline error does not explain how to reconnect. I can fix both after you confirm." ->
            app.getString(R.string.demo_review_result)
        "Login regression test" -> app.getString(R.string.demo_subagent_label)
        "The existing login tests do not cover process recreation." -> app.getString(R.string.demo_subagent_result)
        "Fast everyday coding and analysis" -> app.getString(R.string.demo_model_description)
        "Disable deep reasoning" -> app.getString(R.string.demo_reasoning_off_description)
        "Complex coding tasks" -> app.getString(R.string.demo_reasoning_high_description)
        "Use the largest reasoning budget" -> app.getString(R.string.demo_reasoning_max_description)
        "Received. All execution still happens on your computer." -> app.getString(R.string.demo_received)
        "You stopped the task" -> app.getString(R.string.demo_task_stopped)
        "Allowed once" -> app.getString(R.string.demo_allowed_once)
        "Rejected" -> app.getString(R.string.demo_rejected)
        "Answer submitted" -> app.getString(R.string.demo_answer_submitted)
        "Question dismissed" -> app.getString(R.string.demo_question_dismissed)
        "Confirmation" -> app.getString(R.string.demo_confirmation)
        "Apply the fixes before release?" -> app.getString(R.string.demo_apply_fixes_question)
        "1. Restore login state\n2. Improve offline guidance\n3. Add regression tests" ->
            app.getString(R.string.demo_apply_fixes_detail)
        "Approve" -> app.getString(R.string.demo_approve_option)
        "Continue on the computer" -> app.getString(R.string.demo_approve_description)
        "Not yet" -> app.getString(R.string.demo_not_yet_option)
        "Keep the current result" -> app.getString(R.string.demo_not_yet_description)
        "Prepare the login flow for release" -> app.getString(R.string.demo_goal_objective)
            else -> value
        }
    }

    private inline fun MutableStateFlow<RemoteAppUiState>.updateSession(
        transform: (SessionDetailUiState) -> SessionDetailUiState,
    ) = update { state -> state.copy(session = transform(state.session)) }

    override fun onCleared() {
        cancelSubagentWork()
        foregroundTracker.close()
        systemRequestChannel.close()
    }

    private data class ProjectBinding(val workspaceId: String?, val cwd: String?)

    private data class ProjectProjection(
        val projects: List<ProjectUiModel>,
        val bindings: Map<String, ProjectBinding>,
        val isDirectoryFallback: Boolean,
    )

    private data class PendingImage(val remote: RemotePromptImage, val previewUri: String?)

    private data class AttachmentState(
        val attachment: RemoteImageAttachment,
        val previewUri: String? = null,
        val isLoading: Boolean = false,
        val errorMessage: String? = null,
    ) {
        fun toUi(): ImageAttachmentUiModel = RemoteUiMapper.attachment(
            attachment,
            previewUri,
            isLoading,
            errorMessage,
        )
    }

    private companion object {
        const val DEMO_HOST_ID = "offline-demo"
        const val DEFAULT_HISTORY_LIMIT = 200
        const val DEFAULT_SUBAGENT_HISTORY_LIMIT = 120
        const val HISTORY_PAGE_SIZE = 200
        const val MAX_HISTORY_LIMIT = 2_000
        const val FOREGROUND_POLL_MILLIS = 5_000L
        const val REFERENCE_DEBOUNCE_MILLIS = 180L
        const val DEFAULT_MAX_IMAGES = 4
        const val DEFAULT_MAX_IMAGE_BYTES = 20 * 1024 * 1024
        const val DEFAULT_MAX_MESSAGE_IMAGE_BYTES = 40 * 1024 * 1024
        const val MAX_DISPLAY_NAME_CHARACTERS = 160
        const val ATTACHMENT_CACHE_DIRECTORY = "remote-attachments"
        val GOAL_ROUNDS_PATTERN = Regex("(\\d+)/(\\d+) rounds")
        val REVISION_PATTERN = Regex("revision (\\d+)")
    }
}

private data class AttachmentStateKey(
    val hostId: String,
    val sessionId: String,
    val attachmentId: String,
)

/** Product-owned API failures have stable localized copy; unknown host errors stay verbatim. */
internal fun controlledApiErrorString(code: String): Int? = when (code) {
    "attachment-not-found" -> R.string.remote_error_attachment_not_found
    "interaction-rejected" -> R.string.remote_error_interaction_rejected
    "model-unavailable" -> R.string.remote_error_model_unavailable
    "session-not-found" -> R.string.remote_error_session_not_found
    "subagent-not-resumable" -> R.string.remote_error_subagent_not_resumable
    else -> null
}

internal data class SubagentAddress(
    val parentSessionId: String,
    val childSessionId: String,
)

internal data class SubagentCatalogAddress(
    val parentSessionId: String,
    val depth: Int,
)

internal data class SubagentSelection(
    val parentSessionId: String,
    val entry: RemoteSubagentEntry,
    val parentAvailable: Boolean,
    val historyLimit: Int,
    val snapshot: RemoteConversationSnapshot? = null,
    val isLoading: Boolean = true,
    val isLoadingOlder: Boolean = false,
    val isSending: Boolean = false,
    val isStopping: Boolean = false,
    val errorMessage: String? = null,
) {
    val address: SubagentAddress get() = SubagentAddress(parentSessionId, entry.id)
}

internal enum class SubagentBackResult { ShowCatalog, ShowConversation, AtRoot }

/**
 * Address-aware navigation state for the recursive subagent tree.
 *
 * Each nested level retains the conversation that opened it. Returning from a nested catalog can
 * therefore restore that exact parent conversation without confusing its parent session address
 * with the root session currently shown by the app.
 */
internal class SubagentNavigationState {
    private data class CatalogLevel(
        val parentSessionId: String,
        val owner: SubagentSelection,
        var catalog: RemoteSubagentCatalog? = null,
    )

    private var rootSessionId: String? = null
    var rootCatalog: RemoteSubagentCatalog? = null
        private set
    private val nestedLevels = mutableListOf<CatalogLevel>()
    var selection: SubagentSelection? = null
        private set

    val depth: Int get() = nestedLevels.size
    val currentCatalog: RemoteSubagentCatalog?
        get() = nestedLevels.lastOrNull()?.catalog ?: rootCatalog
    val currentOwner: SubagentSelection?
        get() = nestedLevels.lastOrNull()?.owner
    val currentCatalogAddress: SubagentCatalogAddress?
        get() = (nestedLevels.lastOrNull()?.parentSessionId ?: rootSessionId)?.let {
            SubagentCatalogAddress(it, depth)
        }

    fun reset(sessionId: String?) {
        rootSessionId = sessionId
        rootCatalog = null
        nestedLevels.clear()
        selection = null
    }

    fun dismiss() {
        nestedLevels.clear()
        selection = null
    }

    fun updateCatalog(parentSessionId: String, catalog: RemoteSubagentCatalog) {
        if (parentSessionId == rootSessionId) {
            rootCatalog = catalog
            return
        }
        nestedLevels.lastOrNull { it.parentSessionId == parentSessionId }?.catalog = catalog
    }

    fun select(subagentId: String, historyLimit: Int): SubagentSelection? {
        val parentSessionId = currentCatalogAddress?.parentSessionId ?: return null
        val catalog = currentCatalog ?: return null
        val entry = catalog.entries.firstOrNull { it.id == subagentId && !it.isDiagnostic } ?: return null
        return SubagentSelection(
            parentSessionId = parentSessionId,
            entry = entry,
            parentAvailable = catalog.parentAvailable,
            historyLimit = historyLimit,
        ).also { selection = it }
    }

    fun enterChildren(address: SubagentAddress): Boolean {
        val selected = selection?.takeIf { it.address == address && it.entry.hasChildren } ?: return false
        nestedLevels += CatalogLevel(
            parentSessionId = selected.entry.id,
            owner = selected,
        )
        selection = null
        return true
    }

    fun back(): SubagentBackResult {
        if (selection != null) {
            selection = null
            return SubagentBackResult.ShowCatalog
        }
        if (nestedLevels.isNotEmpty()) {
            selection = nestedLevels.removeAt(nestedLevels.lastIndex).owner
            return SubagentBackResult.ShowConversation
        }
        return SubagentBackResult.AtRoot
    }

    fun updateSelection(
        address: SubagentAddress,
        transform: (SubagentSelection) -> SubagentSelection,
    ) {
        selection = selection?.takeIf { it.address == address }?.let(transform) ?: selection
    }
}

internal fun subagentRefreshIntervalMillis(
    activity: RemoteSubagentActivity?,
): Long = if (activity == RemoteSubagentActivity.RUNNING) 1_000L else 3_000L

internal fun RemoteConversationSnapshot?.findImageAttachment(
    attachmentId: String,
): RemoteImageAttachment? = this?.items
    ?.asSequence()
    ?.flatMap { it.attachments.asSequence() }
    ?.firstOrNull { it.attachmentId == attachmentId }

private class ImageMessageLimitException : IllegalArgumentException()
