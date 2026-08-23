package com.chokwinlee.dshremote.remote

internal object LiveEventParser {
    fun parse(envelope: LiveEventEnvelope): RemoteLiveEvent? {
        val payload = envelope.payload.objectOrNull() ?: return null
        val type = payload["type"].stringOrNull() ?: return null
        val sessionId = payload["sessionId"].stringOrNull() ?: return null
        return when (type) {
            "session/event", "session/projection" -> RemoteLiveEvent.SessionChanged(sessionId)
            "session/queue" -> RemoteLiveEvent.QueueChanged(
                sessionId,
                payload["items"].arrayOrNull().orEmpty().mapNotNull(::parseQueueItem),
            )
            "approval/requested" -> {
                val approvalId = payload["approvalId"].stringOrNull() ?: return null
                val toolName = payload["toolName"].stringOrNull() ?: return null
                RemoteLiveEvent.Interaction(
                    RemoteInteraction(
                        id = "approval:$approvalId",
                        rpcId = envelope.rpcId,
                        sessionId = sessionId,
                        approvalId = approvalId,
                        kind = RemoteInteractionKind.Approval(toolName, payload["reason"].stringOrNull()),
                    ),
                )
            }
            "approval/resolved" -> payload["approvalId"].stringOrNull()?.let {
                RemoteLiveEvent.InteractionResolved("approval:$it")
            }
            "question/requested" -> {
                val questions = payload["questions"].arrayOrNull().orEmpty().mapNotNull(::parseQuestion)
                if (questions.isEmpty()) null else RemoteLiveEvent.Interaction(
                    RemoteInteraction(
                        id = "question:${envelope.rpcId}",
                        rpcId = envelope.rpcId,
                        sessionId = sessionId,
                        approvalId = null,
                        kind = RemoteInteractionKind.Questions(questions),
                    ),
                )
            }
            "question/resolved" -> payload["questionRpcId"].stringOrNull()?.let {
                RemoteLiveEvent.InteractionResolved("question:$it")
            }
            else -> null
        }
    }

    private fun parseQuestion(value: kotlinx.serialization.json.JsonElement): RemoteQuestion? {
        val objectValue = value.objectOrNull() ?: return null
        val id = objectValue["id"].stringOrNull() ?: return null
        val question = objectValue["question"].stringOrNull() ?: return null
        val options = objectValue["options"].arrayOrNull().orEmpty().mapNotNull { option ->
            val raw = option.objectOrNull() ?: return@mapNotNull null
            val label = raw["label"].stringOrNull() ?: return@mapNotNull null
            RemoteQuestionOption(label, raw["description"].stringOrNull())
        }
        return RemoteQuestion(
            id,
            objectValue["header"].stringOrNull(),
            question,
            objectValue["detail"].stringOrNull(),
            options,
            objectValue["multiSelect"].booleanOrNull() ?: false,
        )
    }

    private fun parseQueueItem(value: kotlinx.serialization.json.JsonElement): RemoteQueuedMessage? {
        val objectValue = value.objectOrNull() ?: return null
        val id = objectValue["id"].stringOrNull() ?: return null
        val placement = when (objectValue["placement"].stringOrNull()) {
            null, "queued" -> RemoteQueuedPlacement.QUEUED
            "steering" -> RemoteQueuedPlacement.STEERING
            "context" -> RemoteQueuedPlacement.CONTEXT
            else -> return null
        }
        val content = objectValue["message"].objectOrNull()?.get("content") ?: objectValue["content"]
        val text = textContent(content)
        val attachmentCount = imageCount(content)
        // Keep parser output language-neutral. Product-owned image/fallback labels are added by
        // the UI layer with Android resources; user-authored text remains verbatim.
        val preview = text?.trim().orEmpty()
        return RemoteQueuedMessage(id, placement, preview, text, attachmentCount)
    }
}
