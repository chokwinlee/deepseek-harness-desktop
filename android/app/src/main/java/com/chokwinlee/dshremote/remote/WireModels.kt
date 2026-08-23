package com.chokwinlee.dshremote.remote

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonObject

@Serializable
internal class EmptyPayload

@Serializable
internal data class SessionIdPayload(val sessionId: String)

@Serializable
internal data class SessionCreatePayload(val workspaceId: String?, val cwd: String?)

@Serializable
internal data class SessionSelectModelPayload(
    val sessionId: String,
    val provider: String,
    val model: String,
    val reasoningEffort: String?,
)

@Serializable
internal data class SessionHistoryPayload(val sessionId: String, val maxMessages: Int)

@Serializable
internal data class SessionAttachmentPayload(val sessionId: String, val attachmentId: String)

@Serializable
internal data class ScopedQueryPayload(val args: ScopedQueryArguments)

@Serializable
internal data class ScopedQueryArguments(val agentId: String, val query: String)

@Serializable
internal data class ParentSessionPayload(val parentSessionId: String)

@Serializable
internal data class SubagentAddressPayload(
    val parentSessionId: String,
    val childSessionId: String,
    val mode: String,
)

@Serializable
internal data class SubagentHistoryPayload(
    val parentSessionId: String,
    val childSessionId: String,
    val mode: String,
    val maxMessages: Int,
)

@Serializable
internal data class PromptContentPart(
    val type: String,
    val text: String? = null,
    val mediaType: String? = null,
    val data: String? = null,
    val name: String? = null,
)

@Serializable
internal data class SessionPromptPayload(
    val sessionId: String,
    val mode: String,
    val content: List<PromptContentPart>,
    val clientTimeZone: String,
)

@Serializable
internal data class SubagentPromptPayload(
    val parentSessionId: String,
    val childSessionId: String,
    val mode: String,
    val content: List<PromptContentPart>,
    val clientTimeZone: String,
)

@Serializable
internal data class PromptTextPart(val type: String, val text: String)

@Serializable
internal data class QueueActionWire(val kind: String, val content: List<PromptTextPart>? = null)

@Serializable
internal data class SessionUpdateQueuePayload(
    val sessionId: String,
    val itemId: String,
    val action: QueueActionWire,
)

@Serializable
internal data class RpcRequestEnvelope(
    val type: String,
    val rpcId: String,
    val method: String,
    val payload: JsonElement,
)

@Serializable
internal data class RpcResponseEnvelope(
    val rpcId: String,
    val result: RpcResultWire,
)

@Serializable
internal data class RpcResultWire(
    val ok: Boolean,
    val value: JsonElement? = null,
    val error: ApiErrorWire? = null,
)

internal object RpcResponseValidator {
    fun successfulValue(envelope: RpcResponseEnvelope, expectedRpcId: String): JsonElement {
        if (envelope.rpcId != expectedRpcId) throw HarnessRemoteClientException.MismatchedResponse
        if (envelope.result.ok && envelope.result.value != null) return envelope.result.value
        envelope.result.error?.let { throw HarnessRemoteClientException.Api(it.code, it.message) }
        throw HarnessRemoteClientException.InvalidResponse
    }
}

@Serializable
internal data class ApiErrorWire(val code: String, val message: String)

@Serializable
internal data class HostDescriptionWire(val version: String, val attachedSessions: Int)

@Serializable
internal data class SessionCreateWire(val sessionId: String)

@Serializable
internal data class SessionListWire(val items: List<SessionSummaryWire>)

@Serializable
internal data class WorkspaceListWire(
    val items: List<WorkspaceSummaryWire>,
    val archivedSessionIds: List<String>,
)

@Serializable
internal data class WorkspaceSummaryWire(
    val workspaceId: String,
    val path: String,
    val title: String,
    val sessionIds: List<String>,
    val createdAt: String,
    val updatedAt: String,
)

@Serializable
internal data class SessionSummaryWire(
    val sessionId: String,
    val updatedAt: Double,
    val running: Boolean,
    val blank: Boolean,
    val origin: String? = null,
    val cwd: String? = null,
    val projections: SessionProjectionsWire? = null,
)

@Serializable(with = SessionProjectionsWireSerializer::class)
internal data class SessionProjectionsWire(val values: Map<String, JsonElement>)

internal object SessionProjectionsWireSerializer : KSerializer<SessionProjectionsWire> {
    override val descriptor: SerialDescriptor = JsonObject.serializer().descriptor

    override fun deserialize(decoder: Decoder): SessionProjectionsWire {
        val jsonDecoder = decoder as? JsonDecoder
            ?: throw IllegalStateException("Session projections require JSON")
        val objectValue = jsonDecoder.decodeJsonElement() as? JsonObject
            ?: throw IllegalStateException("Session projections must be an object")
        val values = objectValue["values"] as? JsonObject ?: objectValue
        return SessionProjectionsWire(values)
    }

    override fun serialize(encoder: Encoder, value: SessionProjectionsWire) {
        val jsonEncoder = encoder as? JsonEncoder
            ?: throw IllegalStateException("Session projections require JSON")
        jsonEncoder.encodeJsonElement(JsonObject(mapOf("values" to JsonObject(value.values))))
    }
}

@Serializable
internal data class SessionHistoryWire(
    val events: List<HistoryEntryWire>,
    val hasMore: Boolean,
    val projections: SessionProjectionsWire? = null,
)

@Serializable
internal data class SessionAttachmentWire(val attachment: ImageAttachmentWire, val data: String)

@Serializable
internal data class ImageAttachmentWire(
    val attachmentId: String,
    val mediaType: String,
    val bytes: Int,
    val width: Int,
    val height: Int,
    val name: String? = null,
)

@Serializable
internal data class FileReferenceWire(val path: String, val kind: String)

@Serializable
internal data class SessionReferenceWire(
    val mention: String,
    val sessionId: String,
    val label: String,
    val cwd: String? = null,
    val createdAt: Double,
)

@Serializable
internal data class SubagentCatalogWire(
    val entries: List<SubagentEntryWire>,
    val parentAvailable: Boolean,
)

@Serializable
internal data class SubagentEntryWire(
    val kind: String,
    val id: String,
    val mode: String? = null,
    val activity: String? = null,
    val hasChildren: Boolean? = null,
    val label: String? = null,
    val reason: String? = null,
)

@Serializable
internal data class SubagentPromptReceiptWire(val messageId: String)

@Serializable
internal data class SessionModelsWire(
    val current: ModelSelectionWire,
    val routable: Boolean,
    val groups: List<ModelProviderGroupWire>,
    val failures: List<ModelCatalogFailureWire>,
)

@Serializable
internal data class SessionSelectModelWire(val selected: ModelSelectionWire)

@Serializable
internal data class ModelSelectionWire(
    val provider: String,
    val model: String,
    val reasoningEffort: String? = null,
)

@Serializable
internal data class ModelProviderGroupWire(
    val id: String,
    val name: String,
    val models: List<ModelCatalogEntryWire>,
)

@Serializable
internal data class ModelCatalogEntryWire(
    val id: String,
    val name: String,
    val description: String? = null,
    val reasoning: ModelReasoningWire? = null,
)

@Serializable
internal data class ModelReasoningWire(
    val efforts: List<ModelReasoningEffortWire>,
    val defaultEffort: String? = null,
)

@Serializable
internal data class ModelReasoningEffortWire(
    val id: String,
    val name: String,
    val description: String? = null,
)

@Serializable
internal data class ModelCatalogFailureWire(val id: String, val name: String, val message: String)

@Serializable
internal data class HistoryEntryWire(val event: SessionEventWire, val view: JsonElement? = null)

@Serializable
internal data class SessionEventWire(
    val type: String,
    val seq: Int,
    val time: Double,
    val data: JsonElement,
    val sourceEventSeqs: List<Int>? = null,
    val surfaceOp: JsonElement? = null,
    val ignorable: Boolean? = null,
)

@Serializable
internal data class AcceptedWire(val accepted: Boolean)

@Serializable
internal data class InteractionResponseEnvelope(
    val type: String,
    val rpcId: String,
    val result: JsonElement,
)

@Serializable
internal data class InteractionReceipt(val accepted: Boolean, val reason: String? = null)

@Serializable
internal data class LiveEventEnvelope(val rpcId: String, val payload: JsonElement)

internal fun ImageAttachmentWire.toRemote(): RemoteImageAttachment {
    if (attachmentId.isBlank() || mediaType !in SUPPORTED_IMAGE_TYPES || bytes <= 0 || width <= 0 || height <= 0) {
        throw HarnessRemoteClientException.InvalidResponse
    }
    return RemoteImageAttachment(attachmentId, mediaType, bytes, width, height, name)
}

internal fun ModelSelectionWire.toRemote() = RemoteModelSelection(provider, model, reasoningEffort)

internal fun SessionModelsWire.toRemote() = RemoteModelDirectory(
    current = current.toRemote(),
    routable = routable,
    groups = groups.map { group ->
        RemoteModelProviderGroup(group.id, group.name, group.models.map { model ->
            RemoteModelCatalogEntry(
                model.id,
                model.name,
                model.description,
                model.reasoning?.let { reasoning ->
                    RemoteModelReasoning(
                        reasoning.efforts.map { RemoteModelReasoningEffort(it.id, it.name, it.description) },
                        reasoning.defaultEffort,
                    )
                },
            )
        })
    },
    failures = failures.map { RemoteModelCatalogFailure(it.id, it.name, it.message) },
)

internal val SUPPORTED_IMAGE_TYPES = setOf("image/png", "image/jpeg", "image/webp", "image/gif")
