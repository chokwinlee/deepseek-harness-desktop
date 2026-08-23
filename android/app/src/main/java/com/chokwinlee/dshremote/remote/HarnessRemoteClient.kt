package com.chokwinlee.dshremote.remote

import kotlinx.coroutines.flow.Flow

interface HarnessRemoteClient {
    val displayName: String
    val isDemo: Boolean

    suspend fun describe(): RemoteHostDescription
    suspend fun workspaces(): RemoteWorkspaceSnapshot
    suspend fun sessions(): List<RemoteSessionSummary>
    suspend fun createSession(workspaceId: String?, cwd: String?): String
    suspend fun conversation(sessionId: String, maxMessages: Int): RemoteConversationSnapshot
    suspend fun attachment(sessionId: String, attachmentId: String): RemoteImageAttachmentPayload
    suspend fun fileReferences(sessionId: String, query: String): List<RemoteFileReferenceCandidate>
    suspend fun sessionReferences(sessionId: String, query: String): List<RemoteSessionReferenceCandidate>
    suspend fun subagents(parentSessionId: String): RemoteSubagentCatalog
    suspend fun subagentConversation(
        parentSessionId: String,
        child: RemoteSubagentEntry,
        maxMessages: Int,
    ): RemoteConversationSnapshot
    suspend fun promptSubagent(parentSessionId: String, child: RemoteSubagentEntry, text: String)
    suspend fun interruptSubagent(parentSessionId: String, child: RemoteSubagentEntry)
    suspend fun models(sessionId: String): RemoteModelDirectory
    suspend fun selectModel(sessionId: String, selection: RemoteModelSelection): RemoteModelSelection
    suspend fun send(text: String, images: List<RemotePromptImage>, sessionId: String, steer: Boolean)
    suspend fun updateQueue(sessionId: String, itemId: String, action: RemoteQueueAction)
    suspend fun cancel(sessionId: String)
    suspend fun respond(interaction: RemoteInteraction, decision: RemoteInteractionDecision)
    fun liveEvents(): Flow<RemoteLiveEvent>
}

sealed class HarnessRemoteClientException(message: String) : Exception(message) {
    data object InvalidResponse : HarnessRemoteClientException("The computer returned invalid Harness data")
    data object MismatchedResponse : HarnessRemoteClientException("The response RPC id did not match the request")
    data class Server(val statusCode: Int) : HarnessRemoteClientException(
        when (statusCode) {
            401 -> "The LAN pairing credential expired; scan the Desktop QR code again"
            413 -> "The image or message exceeds the remote transfer limit"
            else -> "The computer returned HTTP $statusCode"
        },
    )
    data class Api(val code: String, override val message: String) : HarnessRemoteClientException(message)
    data object UnsupportedDecision : HarnessRemoteClientException("This interaction does not support that decision")
}
