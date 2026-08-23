package com.chokwinlee.dshremote.remote

import java.io.IOException
import java.time.Instant
import java.time.ZoneId
import java.util.Base64
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.channelFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import okhttp3.Call
import okhttp3.Callback
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString

class LiveHarnessRemoteClient(
    baseUrl: String,
    override val displayName: String,
    private val accessToken: String? = null,
    httpClient: OkHttpClient = defaultHttpClient(),
    private val json: Json = defaultJson(),
) : HarnessRemoteClient {
    private val baseHttpUrl = baseUrl.toHttpUrl()
    private val httpClient = httpClient.newBuilder()
        .followRedirects(false)
        .followSslRedirects(false)
        .build()
    override val isDemo: Boolean = false

    override suspend fun describe(): RemoteHostDescription {
        val response: HostDescriptionWire = rpc("host.describe", EmptyPayload())
        if (response.version.isBlank()) throw HarnessRemoteClientException.InvalidResponse
        return RemoteHostDescription(response.version, response.attachedSessions)
    }

    override suspend fun workspaces(): RemoteWorkspaceSnapshot {
        val response: WorkspaceListWire = rpc("workspace.list", EmptyPayload())
        return RemoteWorkspaceSnapshot(
            items = response.items.map { item ->
                RemoteWorkspaceSummary(
                    item.workspaceId,
                    item.title,
                    item.path,
                    item.sessionIds,
                    parseIsoInstant(item.createdAt),
                    parseIsoInstant(item.updatedAt),
                )
            },
            archivedSessionIds = response.archivedSessionIds.toSet(),
        )
    }

    override suspend fun sessions(): List<RemoteSessionSummary> {
        val response: SessionListWire = rpc("session.list", EmptyPayload())
        return response.items
            .filter { it.origin != "subagent" && (!it.blank || hasVisibleCollaborationState(it.projections)) }
            .map { item ->
                val title = item.projections?.values?.get("title").stringOrNull()?.trim()?.takeIf(String::isNotEmpty)
                val goalTitle = item.projections?.values?.get("goal").objectOrNull()
                    ?.get("goal").objectOrNull()?.get("objective").stringOrNull()?.trim()?.takeIf(String::isNotEmpty)
                val projectPath = item.cwd?.trim()?.takeIf(String::isNotEmpty)
                val projectName = projectPath?.split('/', '\\')?.lastOrNull()?.takeIf(String::isNotEmpty)
                RemoteSessionSummary(
                    item.sessionId,
                    title ?: goalTitle ?: projectName ?: "Untitled task",
                    item.updatedAt.toLong(),
                    item.running,
                    projectName,
                    projectPath,
                )
            }
    }

    override suspend fun createSession(workspaceId: String?, cwd: String?): String =
        rpc<SessionCreatePayload, SessionCreateWire>("session.create", SessionCreatePayload(workspaceId, cwd)).sessionId

    override suspend fun conversation(sessionId: String, maxMessages: Int): RemoteConversationSnapshot =
        ConversationFolder.fold(rpc("session.history", SessionHistoryPayload(sessionId, maxMessages)))

    override suspend fun attachment(sessionId: String, attachmentId: String): RemoteImageAttachmentPayload {
        val response: SessionAttachmentWire = rpc(
            "session.attachment",
            SessionAttachmentPayload(sessionId, attachmentId),
        )
        val attachment = response.attachment.toRemote()
        if (response.data.length > MAX_WIRE_BYTES) throw HarnessRemoteClientException.Server(413)
        val data = runCatching { Base64.getDecoder().decode(response.data) }.getOrNull()
            ?: throw HarnessRemoteClientException.InvalidResponse
        if (attachment.attachmentId != attachmentId || data.size != attachment.bytes) {
            throw HarnessRemoteClientException.InvalidResponse
        }
        return RemoteImageAttachmentPayload(attachment, data)
    }

    override suspend fun fileReferences(sessionId: String, query: String): List<RemoteFileReferenceCandidate> {
        val response: List<FileReferenceWire> = rpc(
            "fileReferences/list",
            ScopedQueryPayload(ScopedQueryArguments(sessionId, query)),
        )
        return response.map { wire ->
            val kind = when (wire.kind) {
                "file" -> RemoteReferenceKind.FILE
                "directory" -> RemoteReferenceKind.DIRECTORY
                else -> throw HarnessRemoteClientException.InvalidResponse
            }
            if (wire.path.isBlank()) throw HarnessRemoteClientException.InvalidResponse
            RemoteFileReferenceCandidate(wire.path, kind)
        }
    }

    override suspend fun sessionReferences(sessionId: String, query: String): List<RemoteSessionReferenceCandidate> {
        val response: List<SessionReferenceWire> = rpc(
            "sessionReferenceResolver/candidates",
            ScopedQueryPayload(ScopedQueryArguments(sessionId, query)),
        )
        return response.map { wire ->
            if (wire.mention.isBlank() || wire.sessionId.isBlank() || wire.label.isBlank()) {
                throw HarnessRemoteClientException.InvalidResponse
            }
            RemoteSessionReferenceCandidate(
                wire.mention,
                wire.sessionId,
                wire.label,
                wire.cwd,
                wire.createdAt.toLong(),
            )
        }
    }

    override suspend fun subagents(parentSessionId: String): RemoteSubagentCatalog {
        val response: SubagentCatalogWire = rpc("subagent.list", ParentSessionPayload(parentSessionId))
        return RemoteSubagentCatalog(response.entries.map(::mapSubagent), response.parentAvailable)
    }

    override suspend fun subagentConversation(
        parentSessionId: String,
        child: RemoteSubagentEntry,
        maxMessages: Int,
    ): RemoteConversationSnapshot {
        val mode = child.mode ?: throw HarnessRemoteClientException.InvalidResponse
        if (child.isDiagnostic) throw HarnessRemoteClientException.InvalidResponse
        return ConversationFolder.fold(
            rpc(
                "subagent.history",
                SubagentHistoryPayload(parentSessionId, child.id, mode.wireValue, maxMessages),
            ),
        )
    }

    override suspend fun promptSubagent(parentSessionId: String, child: RemoteSubagentEntry, text: String) {
        if (child.mode != RemoteSubagentMode.CONTINUABLE) {
            throw HarnessRemoteClientException.Api("subagent-not-resumable", "This subagent cannot be resumed")
        }
        val value = text.trim()
        if (value.isEmpty()) return
        rpc<SubagentPromptPayload, SubagentPromptReceiptWire>(
            "subagent.prompt",
            SubagentPromptPayload(
                parentSessionId,
                child.id,
                RemoteSubagentMode.CONTINUABLE.wireValue,
                listOf(PromptContentPart(type = "text", text = value)),
                ZoneId.systemDefault().id,
            ),
        )
    }

    override suspend fun interruptSubagent(parentSessionId: String, child: RemoteSubagentEntry) {
        if (child.mode != RemoteSubagentMode.CONTINUABLE) {
            throw HarnessRemoteClientException.Api("subagent-not-resumable", "This subagent cannot be interrupted")
        }
        rpc<SubagentAddressPayload, AcceptedWire>(
            "subagent.interrupt",
            SubagentAddressPayload(parentSessionId, child.id, RemoteSubagentMode.CONTINUABLE.wireValue),
        )
    }

    override suspend fun models(sessionId: String): RemoteModelDirectory =
        rpc<SessionIdPayload, SessionModelsWire>("session.models", SessionIdPayload(sessionId)).toRemote()

    override suspend fun selectModel(
        sessionId: String,
        selection: RemoteModelSelection,
    ): RemoteModelSelection = rpc<SessionSelectModelPayload, SessionSelectModelWire>(
        "session.selectModel",
        SessionSelectModelPayload(sessionId, selection.provider, selection.model, selection.reasoningEffort),
    ).selected.toRemote()

    override suspend fun send(text: String, images: List<RemotePromptImage>, sessionId: String, steer: Boolean) {
        val value = text.trim()
        if (value.isEmpty() && images.isEmpty()) return
        val content = buildList {
            if (value.isNotEmpty()) add(PromptContentPart(type = "text", text = value))
            images.forEach { image ->
                add(
                    PromptContentPart(
                        type = "image",
                        mediaType = image.mediaType,
                        data = Base64.getEncoder().encodeToString(image.data),
                        name = image.name,
                    ),
                )
            }
        }
        rpc<SessionPromptPayload, AcceptedWire>(
            "session.prompt",
            SessionPromptPayload(sessionId, if (steer) "steer" else "queue", content, ZoneId.systemDefault().id),
        )
    }

    override suspend fun updateQueue(sessionId: String, itemId: String, action: RemoteQueueAction) {
        val wire = when (action) {
            is RemoteQueueAction.Edit -> QueueActionWire(
                "edit",
                listOf(PromptTextPart("text", action.text)),
            )
            RemoteQueueAction.Remove -> QueueActionWire("remove")
            RemoteQueueAction.Steer -> QueueActionWire("steer")
        }
        rpc<SessionUpdateQueuePayload, AcceptedWire>(
            "session.updateQueue",
            SessionUpdateQueuePayload(sessionId, itemId, wire),
        )
    }

    override suspend fun cancel(sessionId: String) {
        rpc<SessionIdPayload, AcceptedWire>("session.cancel", SessionIdPayload(sessionId))
    }

    override suspend fun respond(interaction: RemoteInteraction, decision: RemoteInteractionDecision) {
        val result = interactionResult(interaction, decision)
        val envelope = InteractionResponseEnvelope("client-response", interaction.rpcId, result)
        val request = authorizedRequest(endpoint("api/respond"))
            .post(jsonRequestBody(json.encodeToString(envelope)))
            .build()
        val receipt = execute(request).use { response ->
            if (response.code != 200) throw HarnessRemoteClientException.Server(response.code)
            val body = boundedResponseText(response)
            runCatching { json.decodeFromString(InteractionReceipt.serializer(), body) }
                .getOrElse { throw HarnessRemoteClientException.InvalidResponse }
        }
        if (!receipt.accepted) {
            throw HarnessRemoteClientException.Api(
                "interaction-rejected",
                receipt.reason ?: "The computer rejected this response",
            )
        }
    }

    override fun liveEvents(): Flow<RemoteLiveEvent> = channelFlow {
        while (currentCoroutineContext().isActive) {
            val disconnected = CompletableDeferred<Unit>()
            val request = authorizedRequest(webSocketEndpoint("api/events.mux")).build()
            val socket = httpClient.newWebSocket(request, object : WebSocketListener() {
                override fun onMessage(webSocket: WebSocket, text: String) = receive(text)

                override fun onMessage(webSocket: WebSocket, bytes: ByteString) = receive(bytes.utf8())

                private fun receive(value: String) {
                    if (value.length > MAX_WIRE_BYTES) return
                    val event = runCatching {
                        val envelope = json.decodeFromString(LiveEventEnvelope.serializer(), value)
                        LiveEventParser.parse(envelope)
                    }.getOrNull()
                    if (event != null) trySend(event)
                }

                override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                    webSocket.close(code, reason)
                }

                override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                    disconnected.complete(Unit)
                }

                override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                    disconnected.complete(Unit)
                }
            })
            try {
                disconnected.await()
            } finally {
                socket.cancel()
            }
            if (currentCoroutineContext().isActive) delay(1_500)
        }
    }

    private suspend inline fun <reified P, reified V> rpc(method: String, payload: P): V {
        val rpcId = UUID.randomUUID().toString().lowercase()
        val envelope = RpcRequestEnvelope(
            "client-request",
            rpcId,
            method,
            json.encodeToJsonElement(payload),
        )
        val request = authorizedRequest(endpoint("api/$method"))
            .post(jsonRequestBody(json.encodeToString(envelope)))
            .build()
        return execute(request).use { response ->
            if (response.code != 200) throw HarnessRemoteClientException.Server(response.code)
            val body = boundedResponseText(response)
            val decoded = runCatching { json.decodeFromString(RpcResponseEnvelope.serializer(), body) }
                .getOrElse { throw HarnessRemoteClientException.InvalidResponse }
            val value = RpcResponseValidator.successfulValue(decoded, rpcId)
            return@use runCatching { json.decodeFromJsonElement<V>(value) }
                .getOrElse { throw HarnessRemoteClientException.InvalidResponse }
        }
    }

    private suspend fun execute(request: Request): Response = suspendCancellableCoroutine { continuation ->
        val call = httpClient.newCall(request)
        continuation.invokeOnCancellation { call.cancel() }
        call.enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                if (continuation.isActive) continuation.resumeWithException(e)
            }

            override fun onResponse(call: Call, response: Response) {
                if (continuation.isActive) continuation.resumeWith(Result.success(response)) else response.close()
            }
        })
    }

    private fun boundedResponseText(response: Response): String {
        val body = response.body
        val declaredLength = body.contentLength()
        if (declaredLength > MAX_WIRE_BYTES) throw HarnessRemoteClientException.Server(413)
        val source = body.source()
        source.request(MAX_WIRE_BYTES + 1L)
        if (source.buffer.size > MAX_WIRE_BYTES) throw HarnessRemoteClientException.Server(413)
        return source.readUtf8()
    }

    private fun jsonRequestBody(value: String): RequestBody {
        if (value.toByteArray(Charsets.UTF_8).size > MAX_WIRE_BYTES) {
            throw HarnessRemoteClientException.Server(413)
        }
        return value.toRequestBody(JSON_MEDIA_TYPE)
    }

    private fun endpoint(path: String): HttpUrl = baseHttpUrl.newBuilder().encodedPath("/$path").build()

    private fun webSocketEndpoint(path: String): String {
        val httpUrl = endpoint(path).toString()
        return if (baseHttpUrl.isHttps) httpUrl.replaceFirst("https://", "wss://")
        else httpUrl.replaceFirst("http://", "ws://")
    }

    private fun authorizedRequest(url: HttpUrl): Request.Builder = Request.Builder()
        .url(url)
        .header("Accept", "application/json")
        .apply { accessToken?.let { header("Authorization", "Bearer $it") } }

    private fun authorizedRequest(url: String): Request.Builder = Request.Builder()
        .url(url)
        .header("Accept", "application/json")
        .apply { accessToken?.let { header("Authorization", "Bearer $it") } }

    private fun interactionResult(
        interaction: RemoteInteraction,
        decision: RemoteInteractionDecision,
    ): JsonElement = when {
        interaction.kind is RemoteInteractionKind.Approval &&
            (decision == RemoteInteractionDecision.AllowOnce || decision == RemoteInteractionDecision.Reject) -> {
            val approvalId = interaction.approvalId ?: throw HarnessRemoteClientException.UnsupportedDecision
            buildJsonObject {
                put("ok", true)
                putJsonObject("value") {
                    put("sessionId", interaction.sessionId)
                    put("approvalId", approvalId)
                    put("outcome", if (decision == RemoteInteractionDecision.AllowOnce) "allowed-once" else "rejected")
                }
            }
        }
        interaction.kind is RemoteInteractionKind.Questions && decision is RemoteInteractionDecision.Answer ->
            buildJsonObject {
                put("ok", true)
                putJsonObject("value") {
                    put("sessionId", interaction.sessionId)
                    putJsonObject("answer") {
                        putJsonArray("answers") {
                            decision.answers.forEach { answer ->
                                add(buildJsonObject {
                                    put("id", answer.questionId)
                                    put("selected", JsonArray(answer.selected.map(::JsonPrimitive)))
                                    answer.custom?.takeIf(String::isNotEmpty)?.let { put("custom", it) }
                                })
                            }
                        }
                    }
                }
            }
        interaction.kind is RemoteInteractionKind.Questions && decision == RemoteInteractionDecision.CancelQuestions ->
            buildJsonObject {
                put("ok", false)
                putJsonObject("error") {
                    put("code", "cancelled")
                    put("message", "the user closed this question request")
                    put("details", JsonObject(emptyMap()))
                }
            }
        else -> throw HarnessRemoteClientException.UnsupportedDecision
    }

    private fun mapSubagent(wire: SubagentEntryWire): RemoteSubagentEntry {
        if (wire.id.isBlank()) throw HarnessRemoteClientException.InvalidResponse
        if (wire.kind == "diagnostic") {
            val reason = runCatching { RemoteSubagentDiagnosticReason.valueOf(wire.reason.orEmpty().uppercase()) }
                .getOrElse { throw HarnessRemoteClientException.InvalidResponse }
            return RemoteSubagentEntry(wire.id, null, null, false, null, reason)
        }
        val mode = RemoteSubagentMode.entries.firstOrNull { it.wireValue == wire.mode }
            ?: throw HarnessRemoteClientException.InvalidResponse
        val activity = runCatching { RemoteSubagentActivity.valueOf(wire.activity.orEmpty().uppercase()) }
            .getOrElse { throw HarnessRemoteClientException.InvalidResponse }
        val hasChildren = wire.hasChildren ?: throw HarnessRemoteClientException.InvalidResponse
        if (mode == RemoteSubagentMode.CONTINUABLE && wire.label.isNullOrBlank()) {
            throw HarnessRemoteClientException.InvalidResponse
        }
        return RemoteSubagentEntry(wire.id, mode, activity, hasChildren, wire.label, null)
    }

    private fun hasVisibleCollaborationState(projections: SessionProjectionsWire?): Boolean {
        if (projections?.values?.get("goal").objectOrNull() != null) return true
        val plan = projections?.values?.get("plan").objectOrNull()
        return plan?.get("active").booleanOrNull() == true || plan?.get("pending").booleanOrNull() == true
    }

    private fun parseIsoInstant(value: String): Long = runCatching { Instant.parse(value).toEpochMilli() }
        .getOrElse { throw HarnessRemoteClientException.InvalidResponse }

    companion object {
        private val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
        private const val MAX_WIRE_BYTES = 136L * 1024L * 1024L

        fun defaultJson(): Json = Json {
            ignoreUnknownKeys = true
            explicitNulls = false
        }

        fun defaultHttpClient(): OkHttpClient = OkHttpClient.Builder()
            .followRedirects(false)
            .followSslRedirects(false)
            .connectTimeout(20, TimeUnit.SECONDS)
            .readTimeout(20, TimeUnit.SECONDS)
            .writeTimeout(20, TimeUnit.SECONDS)
            .build()
    }
}
