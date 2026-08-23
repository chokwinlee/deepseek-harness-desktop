package com.chokwinlee.dshremote.remote

import java.util.Locale
import kotlin.math.max
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

internal object ConversationFolder {
    private data class ToolKey(val turn: Int, val step: Int, val callId: String)
    private data class StreamKey(val turn: Int, val step: Int)
    private data class StreamBlock(
        var type: String,
        var text: String = "",
        var attachment: RemoteImageAttachment? = null,
    )
    private data class PartialAssistant(
        val firstSequence: Int,
        val time: Long,
        val blocks: MutableMap<Int, StreamBlock> = mutableMapOf(),
    )

    fun fold(history: SessionHistoryWire): RemoteConversationSnapshot {
        val toolResults = mutableMapOf<ToolKey, HistoryEntryWire>()
        val toolCalls = mutableSetOf<ToolKey>()
        history.events.forEach { entry ->
            if (isReplacement(entry.event)) return@forEach
            val key = toolKey(entry) ?: return@forEach
            when (entry.event.type) {
                "tool/call" -> toolCalls += key
                "tool/result" -> toolResults[key] = entry
            }
        }

        val stepStarts = history.events.mapNotNull { entry ->
            if (entry.event.type != "step/start") return@mapNotNull null
            val data = entry.event.data.objectOrNull() ?: return@mapNotNull null
            val turn = data["turn"].intOrNull() ?: return@mapNotNull null
            val step = data["step"].intOrNull() ?: return@mapNotNull null
            StreamKey(turn, step) to entry.event.time.toLong()
        }.toMap()
        val turnStarts = history.events.mapNotNull { entry ->
            if (entry.event.type != "turn/start") return@mapNotNull null
            val data = entry.event.data.objectOrNull() ?: return@mapNotNull null
            val turn = data["turn"].intOrNull() ?: return@mapNotNull null
            turn to entry.event.time.toLong()
        }.toMap()

        val output = mutableListOf<RemoteConversationItem>()
        val partials = mutableMapOf<StreamKey, PartialAssistant>()

        history.events.forEach { entry ->
            val event = entry.event
            val time = event.time.toLong()
            when (event.type) {
                "user/message" -> {
                    if (isReplacement(event)) return@forEach
                    val data = event.data.objectOrNull() ?: return@forEach
                    val text = textContent(data["content"]).orEmpty()
                    val attachments = imageAttachments(data["content"])
                    if (text.isEmpty() && attachments.isEmpty()) return@forEach
                    val source = data["source"].objectOrNull()
                    val sourceKind = source?.get("kind").stringOrNull() ?: "context"
                    output += if (sourceKind == "user") {
                        RemoteConversationItem(
                            "user:${event.seq}",
                            event.seq,
                            RemoteConversationKind.USER,
                            null,
                            text,
                            time,
                            attachments = attachments,
                        )
                    } else {
                        RemoteConversationItem(
                            "context:${event.seq}",
                            event.seq,
                            RemoteConversationKind.CONTEXT,
                            contextLabel(sourceKind),
                            text.lineSequence().firstOrNull { it.isNotBlank() }?.trim() ?: "Harness context",
                            time,
                            details = listOf(
                                RemoteDetailSection("context-raw", "Model context", text, RemoteDetailKind.TEXT),
                            ),
                            attachments = attachments,
                        )
                    }
                }
                "assistant/message" -> {
                    if (isReplacement(event)) return@forEach
                    val data = event.data.objectOrNull() ?: return@forEach
                    val message = data["message"].objectOrNull() ?: return@forEach
                    val turn = data["turn"].intOrNull()
                    val step = data["step"].intOrNull()
                    if (turn != null && step != null) partials.remove(StreamKey(turn, step))
                    val text = textContent(message["content"]).orEmpty()
                    val reasoning = reasoningContent(message["content"])
                    val attachments = imageAttachments(message["content"])
                    if (text.isEmpty() && reasoning == null && attachments.isEmpty()) return@forEach
                    val interrupted = data["interrupted"].booleanOrNull() == true
                    val metadata = buildList {
                        message["source"].objectOrNull()?.let { source ->
                            listOfNotNull(source["provider"].stringOrNull(), source["model"].stringOrNull())
                                .joinToString(" · ").takeIf(String::isNotEmpty)?.let(::add)
                        }
                        data["usage"].objectOrNull()?.get("outputTokens").intOrNull()?.let { add("$it tokens") }
                        if (turn != null && step != null) {
                            stepStarts[StreamKey(turn, step)]?.let { add(durationLabel(time - it)) }
                        }
                        if (interrupted) add("Stopped")
                    }
                    output += RemoteConversationItem(
                        "assistant:${event.seq}",
                        event.seq,
                        RemoteConversationKind.ASSISTANT,
                        null,
                        text,
                        time,
                        if (interrupted) RemoteConversationState.STOPPED else RemoteConversationState.SUCCEEDED,
                        reasoning = reasoning,
                        metadata = metadata,
                        attachments = attachments,
                    )
                }
                "assistant/chunk" -> {
                    val data = event.data.objectOrNull() ?: return@forEach
                    val turn = data["turn"].intOrNull() ?: return@forEach
                    val step = data["step"].intOrNull() ?: return@forEach
                    val chunk = data["chunk"].objectOrNull() ?: return@forEach
                    val type = chunk["type"].stringOrNull() ?: return@forEach
                    val key = StreamKey(turn, step)
                    val partial = partials.getOrPut(key) { PartialAssistant(event.seq, time) }
                    updatePartial(partial, chunk, type)
                }
                "tool/call" -> {
                    val key = toolKey(entry) ?: return@forEach
                    output += toolItem(entry, toolResults[key])
                }
                "tool/result" -> {
                    if (isReplacement(event)) return@forEach
                    val key = toolKey(entry) ?: return@forEach
                    if (key !in toolCalls) output += toolItem(null, entry)
                }
                "goal/change" -> output += goalChangeItem(event)
                "plan/mode" -> output += planModeItem(event)
                "turn/end" -> turnEndItem(event)?.let(output::add)
                "llm/retry" -> {
                    val data = event.data.objectOrNull()
                    val turn = data?.get("turn").intOrNull()
                    val step = data?.get("step").intOrNull()
                    if (turn != null && step != null) partials.remove(StreamKey(turn, step))
                    val delay = data?.get("delayMs").doubleOrNull()?.toLong()
                    output += RemoteConversationItem(
                        "retry:${event.seq}",
                        event.seq,
                        RemoteConversationKind.STATUS,
                        "Model request retrying",
                        delay?.let { "Retrying in ${durationLabel(it)}" }
                            ?: "The connection or model request failed temporarily; Harness will retry.",
                        time,
                        RemoteConversationState.RUNNING,
                    )
                }
                "compaction/summary" -> {
                    val summary = textContent(event.data.objectOrNull()?.get("summary")) ?: return@forEach
                    output += RemoteConversationItem(
                        "compaction:${event.seq}",
                        event.seq,
                        RemoteConversationKind.STATUS,
                        "Context compacted",
                        "Older content was compressed into a summary.",
                        time,
                        details = listOf(
                            RemoteDetailSection("summary", "Compaction summary", summary, RemoteDetailKind.TEXT),
                        ),
                    )
                }
            }
        }

        partials.forEach { (key, partial) ->
            val ordered = partial.blocks.toSortedMap().values
            val text = ordered.filter { it.type == "text" }.joinToString("\n") { it.text }
            val reasoning = ordered.filter { it.type == "reasoning" }.joinToString("\n") { it.text }
                .trim().takeIf(String::isNotEmpty)
            val attachments = ordered.mapNotNull { it.attachment }
            if (text.isNotEmpty() || reasoning != null || attachments.isNotEmpty()) {
                output += RemoteConversationItem(
                    "assistant-stream:${key.turn}:${key.step}",
                    partial.firstSequence,
                    RemoteConversationKind.ASSISTANT,
                    null,
                    text,
                    partial.time,
                    RemoteConversationState.RUNNING,
                    reasoning = reasoning,
                    attachments = attachments,
                    isStreaming = true,
                )
            }
        }

        val sorted = output.sortedWith(compareBy<RemoteConversationItem> { it.sequence }.thenBy { it.id })
        return RemoteConversationSnapshot(
            items = sorted,
            hasMore = history.hasMore,
            stats = stats(history.projections),
            trajectory = buildTrajectory(
                entries = history.events,
                conversation = sorted,
                toolResults = toolResults,
                toolCalls = toolCalls,
                stepStarts = stepStarts,
                turnStarts = turnStarts,
            ),
            goal = goalState(history.projections?.values?.get("goal")),
            plan = planState(history.projections),
            imageLimits = imageLimits(history.projections),
        )
    }

    private fun buildTrajectory(
        entries: List<HistoryEntryWire>,
        conversation: List<RemoteConversationItem>,
        toolResults: Map<ToolKey, HistoryEntryWire>,
        toolCalls: Set<ToolKey>,
        stepStarts: Map<StreamKey, Long>,
        turnStarts: Map<Int, Long>,
    ): List<RemoteTrajectoryRecord> {
        val conversationBySequence = conversation.groupBy(RemoteConversationItem::sequence)
        val records = mutableListOf<RemoteTrajectoryRecord>()
        var activeTurn: Int? = null
        var activeStep: Int? = null

        entries.forEach { entry ->
            val event = entry.event
            val data = event.data.objectOrNull().orEmpty()
            val time = event.time.toLong()
            if (event.type == "turn/start") activeTurn = data["turn"].intOrNull()
            if (event.type == "step/start") activeStep = data["step"].intOrNull()

            when (event.type) {
                "user/message" -> {
                    if (isReplacement(event)) return@forEach
                    val text = textContent(data["content"]).orEmpty()
                    val attachments = imageAttachments(data["content"])
                    if (text.isEmpty() && attachments.isEmpty()) return@forEach
                    val sourceKind = data["source"].objectOrNull()?.get("kind").stringOrNull() ?: "context"
                    val isUser = sourceKind == "user"
                    val item = conversationBySequence[event.seq]?.firstOrNull {
                        it.kind == if (isUser) RemoteConversationKind.USER else RemoteConversationKind.CONTEXT
                    }
                    records += RemoteTrajectoryRecord(
                        id = "trajectory-message:${event.seq}",
                        sequence = event.seq,
                        turn = activeTurn,
                        step = activeStep,
                        kind = if (isUser) RemoteTrajectoryKind.INPUT else RemoteTrajectoryKind.CONTEXT,
                        title = if (isUser) "User input" else contextLabel(sourceKind),
                        summary = item?.text ?: firstMeaningfulLine(text, if (isUser) "User input" else "Harness context"),
                        time = time,
                        durationMs = null,
                        state = item?.state ?: RemoteConversationState.SUCCEEDED,
                        details = item?.details.orEmpty(),
                        attachments = attachments,
                    )
                }

                "request/header" -> {
                    val header = data["header"].objectOrNull()
                    val config = header?.get("config").objectOrNull()
                    val summary = listOfNotNull(
                        config?.get("provider").stringOrNull(),
                        config?.get("model").stringOrNull(),
                        config?.get("reasoningEffort").stringOrNull(),
                    ).filter(String::isNotBlank).joinToString(" · ")
                    val details = header?.get("system").stringOrNull()?.let { system ->
                        listOf(RemoteDetailSection("system", "System prompt", system.take(30_000), RemoteDetailKind.TEXT))
                    }.orEmpty()
                    records += RemoteTrajectoryRecord(
                        id = "trajectory-request:${event.seq}",
                        sequence = event.seq,
                        turn = activeTurn,
                        step = activeStep,
                        kind = RemoteTrajectoryKind.REQUEST,
                        title = "Model request",
                        summary = summary,
                        time = time,
                        durationMs = null,
                        state = RemoteConversationState.SUCCEEDED,
                        details = details,
                    )
                }

                "assistant/message" -> {
                    if (isReplacement(event)) return@forEach
                    val message = data["message"].objectOrNull() ?: return@forEach
                    val text = textContent(message["content"]).orEmpty()
                    val reasoning = reasoningContent(message["content"]).orEmpty()
                    val attachments = imageAttachments(message["content"])
                    if (text.isEmpty() && reasoning.isEmpty() && attachments.isEmpty()) return@forEach
                    val turn = data["turn"].intOrNull() ?: activeTurn
                    val step = data["step"].intOrNull() ?: activeStep
                    val item = conversationBySequence[event.seq]?.firstOrNull {
                        it.kind == RemoteConversationKind.ASSISTANT
                    }
                    val details = buildList {
                        if (reasoning.isNotEmpty()) {
                            add(RemoteDetailSection("reasoning", "Reasoning", reasoning, RemoteDetailKind.TEXT))
                        }
                        if (text.isNotEmpty()) {
                            add(RemoteDetailSection("answer", "Answer", text, RemoteDetailKind.TEXT))
                        }
                    }
                    records += RemoteTrajectoryRecord(
                        id = "trajectory-assistant:${event.seq}",
                        sequence = event.seq,
                        turn = turn,
                        step = step,
                        kind = RemoteTrajectoryKind.ASSISTANT,
                        title = if (text.isEmpty()) "Model reasoning" else "Model response",
                        summary = firstMeaningfulLine(if (text.isEmpty()) reasoning else text, "Model output"),
                        time = time,
                        durationMs = if (turn != null && step != null) {
                            stepStarts[StreamKey(turn, step)]?.let { (time - it).coerceAtLeast(0) }
                        } else null,
                        state = item?.state ?: if (data["interrupted"].booleanOrNull() == true) {
                            RemoteConversationState.STOPPED
                        } else {
                            RemoteConversationState.SUCCEEDED
                        },
                        details = details,
                        attachments = attachments,
                    )
                }

                "tool/call" -> {
                    val key = toolKey(entry) ?: return@forEach
                    val item = toolItem(entry, toolResults[key])
                    val result = toolResults[key]
                    records += RemoteTrajectoryRecord(
                        id = "trajectory-tool:${key.turn}:${key.step}:${key.callId}",
                        sequence = event.seq,
                        turn = data["turn"].intOrNull() ?: activeTurn,
                        step = data["step"].intOrNull() ?: activeStep,
                        kind = RemoteTrajectoryKind.TOOL,
                        title = item.title ?: "Tool",
                        summary = item.text,
                        time = item.time,
                        durationMs = result?.let { (it.event.time.toLong() - time).coerceAtLeast(0) },
                        state = item.state,
                        details = item.details,
                        attachments = item.attachments,
                    )
                }

                "tool/result" -> {
                    if (isReplacement(event)) return@forEach
                    val key = toolKey(entry) ?: return@forEach
                    if (key in toolCalls) return@forEach
                    val item = toolItem(null, entry)
                    records += RemoteTrajectoryRecord(
                        id = "trajectory-tool-result:${key.turn}:${key.step}:${key.callId}:${event.seq}",
                        sequence = event.seq,
                        turn = key.turn,
                        step = key.step,
                        kind = RemoteTrajectoryKind.TOOL,
                        title = item.title ?: key.callId,
                        summary = item.text,
                        time = item.time,
                        durationMs = null,
                        state = item.state,
                        details = item.details,
                        attachments = item.attachments,
                    )
                }

                "goal/change" -> {
                    val item = goalChangeItem(event)
                    records += item.toTrajectory(
                        id = "trajectory-goal:${event.seq}",
                        kind = RemoteTrajectoryKind.GOAL,
                        turn = activeTurn,
                        step = activeStep,
                    )
                }

                "plan/mode" -> {
                    val item = planModeItem(event)
                    records += item.toTrajectory(
                        id = "trajectory-plan:${event.seq}",
                        kind = RemoteTrajectoryKind.PLAN,
                        turn = activeTurn,
                        step = activeStep,
                    )
                }

                "llm/retry" -> {
                    records += RemoteTrajectoryRecord(
                        id = "trajectory-retry:${event.seq}",
                        sequence = event.seq,
                        turn = data["turn"].intOrNull() ?: activeTurn,
                        step = data["step"].intOrNull() ?: activeStep,
                        kind = RemoteTrajectoryKind.LIFECYCLE,
                        title = "Model request retrying",
                        summary = data["error"].objectOrNull()?.get("message").stringOrNull()
                            ?: "Waiting for the next request",
                        time = time,
                        durationMs = null,
                        state = RemoteConversationState.RUNNING,
                    )
                }

                "compaction/summary" -> {
                    val summary = textContent(data["summary"]) ?: return@forEach
                    records += RemoteTrajectoryRecord(
                        id = "trajectory-compaction:${event.seq}",
                        sequence = event.seq,
                        turn = activeTurn,
                        step = activeStep,
                        kind = RemoteTrajectoryKind.LIFECYCLE,
                        title = "Context compacted",
                        summary = "Older content was compressed into a summary.",
                        time = time,
                        durationMs = null,
                        state = RemoteConversationState.SUCCEEDED,
                        details = listOf(
                            RemoteDetailSection("summary", "Compaction summary", summary, RemoteDetailKind.TEXT),
                        ),
                    )
                }

                "turn/end" -> {
                    val turn = data["turn"].intOrNull() ?: activeTurn
                    val reason = data["reason"].objectOrNull()
                    val reasonKind = reason?.get("kind").stringOrNull() ?: "interrupted"
                    val status = turnEndItem(event)
                    records += RemoteTrajectoryRecord(
                        id = "trajectory-turn:${event.seq}",
                        sequence = event.seq,
                        turn = turn,
                        step = activeStep,
                        kind = RemoteTrajectoryKind.LIFECYCLE,
                        title = if (reasonKind == "completed") "Turn completed" else status?.title ?: "Turn ended",
                        summary = if (reasonKind == "completed") {
                            "Harness completed this turn"
                        } else {
                            status?.text ?: "The session ended before completion."
                        },
                        time = time,
                        durationMs = turn?.let { turnStarts[it] }?.let { (time - it).coerceAtLeast(0) },
                        state = if (reasonKind == "completed") {
                            RemoteConversationState.SUCCEEDED
                        } else {
                            status?.state ?: RemoteConversationState.STOPPED
                        },
                        details = status?.details.orEmpty(),
                    )
                }
            }

            if (event.type == "step/end") activeStep = null
            if (event.type == "turn/end") activeTurn = null
        }

        return records.sortedWith(compareBy<RemoteTrajectoryRecord> { it.sequence }.thenBy { it.id })
    }

    private fun RemoteConversationItem.toTrajectory(
        id: String,
        kind: RemoteTrajectoryKind,
        turn: Int?,
        step: Int?,
    ) = RemoteTrajectoryRecord(
        id = id,
        sequence = sequence,
        turn = turn,
        step = step,
        kind = kind,
        title = title ?: kind.name.lowercase().replaceFirstChar(Char::uppercase),
        summary = text,
        time = time,
        durationMs = null,
        state = state,
        details = details,
        attachments = attachments,
    )

    private fun firstMeaningfulLine(value: String, fallback: String): String = value
        .lineSequence()
        .map(String::trim)
        .firstOrNull(String::isNotEmpty)
        ?.take(240)
        ?: fallback

    private fun updatePartial(partial: PartialAssistant, chunk: JsonObject, type: String) {
        val index = chunk["index"].intOrNull() ?: 0
        when (type) {
            "block-start" -> partial.blocks[index] = StreamBlock(chunk["blockType"].stringOrNull() ?: "other")
            "text-delta", "reasoning-delta" -> {
                val blockType = if (type == "text-delta") "text" else "reasoning"
                val block = partial.blocks.getOrPut(index) { StreamBlock(blockType) }
                block.type = blockType
                block.text += chunk["text"].stringOrNull().orEmpty()
            }
            "block-end" -> chunk["block"].objectOrNull()?.let { block ->
                partial.blocks[index] = StreamBlock(
                    type = block["type"].stringOrNull() ?: "other",
                    text = block["text"].stringOrNull().orEmpty(),
                    attachment = imageAttachments(block).firstOrNull(),
                )
            }
        }
    }

    private fun toolItem(call: HistoryEntryWire?, result: HistoryEntryWire?): RemoteConversationItem {
        val event = call?.event ?: result?.event ?: throw HarnessRemoteClientException.InvalidResponse
        val data = call?.event?.data.objectOrNull().orEmpty()
        val callId = data["callId"].stringOrNull() ?: result?.let(::toolResultCallId) ?: "seq-${event.seq}"
        val toolName = data["name"].stringOrNull() ?: callId
        val callView = call?.view.objectOrNull()?.get("view").objectOrNull()
        val resultView = result?.view.objectOrNull()?.get("view").objectOrNull()
        val resultBlock = result?.let(::toolResultBlock)
        val isError = resultBlock?.get("isError").booleanOrNull() == true
        val errorCode = result?.event?.data.objectOrNull()?.get("error").objectOrNull()?.get("code").stringOrNull()
        val state = when {
            result == null -> RemoteConversationState.RUNNING
            errorCode == "interrupted" -> RemoteConversationState.STOPPED
            isError -> RemoteConversationState.FAILED
            else -> RemoteConversationState.SUCCEEDED
        }
        val card = when (resultView?.get("card").stringOrNull() ?: callView?.get("card").stringOrNull()) {
            "terminal" -> RemoteToolCard.TERMINAL
            "diff" -> RemoteToolCard.DIFF
            "search" -> RemoteToolCard.SEARCH
            "read" -> RemoteToolCard.READ
            "web" -> RemoteToolCard.WEB
            else -> RemoteToolCard.GENERIC
        }
        val rawResult = textContent(resultBlock?.get("content"))
        val attachments = imageAttachments(resultBlock?.get("content"))
        val summary = resultView?.get("summary").stringOrNull()
            ?: rawResult?.lineSequence()?.firstOrNull { it.isNotBlank() }?.take(120)
            ?: when (state) {
                RemoteConversationState.RUNNING -> "Running on your computer"
                RemoteConversationState.FAILED -> "Execution failed"
                RemoteConversationState.STOPPED -> "Stopped"
                else -> "Completed"
            }
        val details = buildList {
            callView?.get("description").stringOrNull()?.let {
                add(RemoteDetailSection("description", null, it, RemoteDetailKind.TEXT))
            }
            callView?.get("rawInput")?.let {
                add(RemoteDetailSection("input", "Input", it.toString(), RemoteDetailKind.CODE))
            }
            val output = resultView?.get("output").stringOrNull() ?: rawResult
            output?.let {
                add(
                    RemoteDetailSection(
                        "result",
                        if (card == RemoteToolCard.TERMINAL) "Terminal output" else "Result",
                        it.take(30_000),
                        RemoteDetailKind.CODE,
                        if (card == RemoteToolCard.TERMINAL) "console" else null,
                    ),
                )
            }
        }
        val metadata = if (call != null && result != null) {
            listOf(durationLabel(max(0, result.event.time.toLong() - call.event.time.toLong())))
        } else emptyList()
        return RemoteConversationItem(
            id = "tool:${event.seq}:$callId",
            sequence = event.seq,
            kind = RemoteConversationKind.TOOL,
            title = resultView?.get("title").stringOrNull()
                ?: callView?.get("title").stringOrNull()
                ?: readableToolName(toolName),
            text = summary,
            time = event.time.toLong(),
            state = state,
            toolCard = card,
            toolCategory = callView?.get("kind").stringOrNull(),
            details = details,
            metadata = metadata,
            attachments = attachments,
        )
    }

    private fun goalChangeItem(event: SessionEventWire): RemoteConversationItem {
        val data = event.data.objectOrNull().orEmpty()
        val operation = data["operation"].stringOrNull() ?: "edit"
        if (operation == "clear") {
            return RemoteConversationItem(
                "goal:${event.seq}", event.seq, RemoteConversationKind.STATUS,
                "Goal cleared", "This session will no longer continue the goal automatically.",
                event.time.toLong(), symbolName = "target",
            )
        }
        val goal = goalState(event.data)
        val title = when (operation) {
            "create" -> "Goal created"
            "pause" -> "Goal paused"
            "resume" -> "Goal resumed"
            "complete" -> "Goal completed"
            "block" -> "Goal needs attention"
            else -> "Goal updated"
        }
        return RemoteConversationItem(
            "goal:${event.seq}",
            event.seq,
            RemoteConversationKind.STATUS,
            title,
            goal?.blockedReasonMessage ?: goal?.objective ?: "Harness updated the current goal.",
            event.time.toLong(),
            goal?.phase?.let(::goalConversationState) ?: RemoteConversationState.INFO,
            metadata = goal?.let { listOf("${it.roundsStarted}/${it.maxRounds} rounds", "revision ${it.revision}") }.orEmpty(),
            symbolName = "target",
        )
    }

    private fun planModeItem(event: SessionEventWire): RemoteConversationItem {
        val active = event.data.objectOrNull()?.get("active").booleanOrNull() == true
        return RemoteConversationItem(
            "plan:${event.seq}",
            event.seq,
            RemoteConversationKind.STATUS,
            if (active) "Plan mode enabled" else "Plan mode disabled",
            if (active) "Harness will prepare a plan before asking to execute it."
            else "Harness returned to normal execution mode.",
            event.time.toLong(),
            if (active) RemoteConversationState.RUNNING else RemoteConversationState.INFO,
            symbolName = "map",
        )
    }

    private fun turnEndItem(event: SessionEventWire): RemoteConversationItem? {
        val reason = event.data.objectOrNull()?.get("reason").objectOrNull() ?: return null
        return when (reason["kind"].stringOrNull()) {
            "completed" -> null
            "error" -> statusItem(event, "Turn failed", reason["error"].objectOrNull()?.get("message").stringOrNull() ?: "The model returned an error.", RemoteConversationState.FAILED)
            "max-tokens" -> statusItem(event, "Output limit reached", "The model reached the output token limit.", RemoteConversationState.FAILED)
            "aborted" -> statusItem(event, "Turn stopped", "Execution was cancelled; existing output is retained.", RemoteConversationState.STOPPED)
            "blocked" -> statusItem(event, "Turn blocked", "Harness cannot continue this step.", RemoteConversationState.FAILED)
            else -> statusItem(event, "Turn interrupted", "The session ended before completion.", RemoteConversationState.STOPPED)
        }
    }

    private fun statusItem(
        event: SessionEventWire,
        title: String,
        text: String,
        state: RemoteConversationState,
    ) = RemoteConversationItem(
        "turn-end:${event.seq}", event.seq, RemoteConversationKind.STATUS,
        title, text, event.time.toLong(), state,
    )

    private fun stats(projections: SessionProjectionsWire?): RemoteConversationStats? {
        val values = projections?.values ?: return null
        val session = values["sessionStats"].objectOrNull() ?: return null
        val usage = values["tokenUsage"].objectOrNull()
        return RemoteConversationStats(
            session["turns"].intOrNull() ?: 0,
            session["steps"].intOrNull() ?: 0,
            session["llmMs"].doubleOrNull()?.toLong() ?: 0,
            session["toolMs"].doubleOrNull()?.toLong() ?: 0,
            (usage?.get("uncachedInputTokens").intOrNull() ?: 0) +
                (usage?.get("cacheReadTokens").intOrNull() ?: 0),
            usage?.get("outputTokens").intOrNull() ?: 0,
        )
    }

    private fun goalState(value: JsonElement?): RemoteGoalState? {
        val projection = value.objectOrNull() ?: return null
        val goal = projection["goal"].objectOrNull() ?: return null
        val id = goal["id"].stringOrNull()?.takeIf(String::isNotBlank) ?: return null
        val revision = goal["revision"].intOrNull()?.takeIf { it > 0 } ?: return null
        val objective = goal["objective"].stringOrNull()?.trim()?.takeIf(String::isNotEmpty) ?: return null
        val phase = runCatching { RemoteGoalPhase.valueOf(goal["phase"].stringOrNull().orEmpty().uppercase()) }.getOrNull()
            ?: return null
        val maxRounds = goal["maxGoalRounds"].intOrNull()?.takeIf { it > 0 } ?: return null
        val roundsStarted = projection["roundsStarted"].intOrNull()?.takeIf { it >= 0 } ?: return null
        val createdAt = projection["createdAt"].doubleOrNull()?.toLong() ?: return null
        val updatedAt = projection["updatedAt"].doubleOrNull()?.toLong() ?: return null
        val blockedReason = goal["blockedReason"].objectOrNull()
        return RemoteGoalState(
            id,
            revision,
            objective,
            phase,
            blockedReason?.get("code").stringOrNull(),
            blockedReason?.get("message").stringOrNull(),
            maxRounds,
            roundsStarted,
            createdAt,
            updatedAt,
        )
    }

    private fun planState(projections: SessionProjectionsWire?): RemotePlanState? {
        val value = projections?.values?.get("plan").objectOrNull() ?: return null
        val active = value["active"].booleanOrNull() ?: return null
        val pending = value["pending"].booleanOrNull() ?: return null
        return RemotePlanState(active, pending)
    }

    private fun imageLimits(projections: SessionProjectionsWire?): RemoteImageLimits? {
        val value = projections?.values?.get("imageLimits").objectOrNull() ?: return null
        val maxImageBytes = value["maxImageBytes"].intOrNull()?.takeIf { it > 0 } ?: return null
        val maxImages = value["maxImagesPerMessage"].intOrNull()?.takeIf { it > 0 } ?: return null
        val maxMessageBytes = value["maxMessageImageBytes"].intOrNull()?.takeIf { it > 0 } ?: return null
        val maxPixels = value["maxImagePixels"].intOrNull()?.takeIf { it > 0 } ?: return null
        val mediaTypes = value["mediaTypes"].arrayOrNull().orEmpty().mapNotNull { it.stringOrNull() }
        if (mediaTypes.isEmpty()) return null
        return RemoteImageLimits(
            maxImageBytes,
            maxImages,
            maxMessageBytes,
            maxPixels,
            value["maxImageDimension"].intOrNull()?.takeIf { it > 0 },
            mediaTypes,
        )
    }

    private fun toolKey(entry: HistoryEntryWire): ToolKey? {
        val data = entry.event.data.objectOrNull() ?: return null
        val turn = data["turn"].intOrNull() ?: return null
        val step = data["step"].intOrNull() ?: return null
        val callId = if (entry.event.type == "tool/call") data["callId"].stringOrNull() else toolResultCallId(entry)
        return callId?.takeIf(String::isNotEmpty)?.let { ToolKey(turn, step, it) }
    }

    private fun toolResultBlock(entry: HistoryEntryWire): JsonObject? =
        entry.event.data.objectOrNull()?.get("message").objectOrNull()?.get("content").arrayOrNull()
            ?.firstOrNull { it.objectOrNull()?.get("type").stringOrNull() == "tool-result" }
            .objectOrNull()

    private fun toolResultCallId(entry: HistoryEntryWire): String? =
        entry.event.data.objectOrNull()?.get("message").objectOrNull()?.get("source").objectOrNull()
            ?.get("callId").stringOrNull() ?: toolResultBlock(entry)?.get("toolCallId").stringOrNull()

    private fun isReplacement(event: SessionEventWire): Boolean =
        event.surfaceOp.objectOrNull()?.get("op").stringOrNull() == "replace"

    private fun contextLabel(sourceKind: String): String = when (sourceKind) {
        "agent-instructions" -> "Project instructions"
        "plugin" -> "Plugin context"
        "skill-catalog" -> "Available capabilities"
        "skill-invocation" -> "Skill context"
        "session-reference" -> "Referenced session"
        "goal" -> "Goal continuation"
        else -> "System context"
    }

    private fun readableToolName(value: String): String = value
        .replace('_', ' ')
        .replace('-', ' ')
        .replaceFirstChar { if (it.isLowerCase()) it.titlecase() else it.toString() }

    private fun durationLabel(milliseconds: Long): String = when {
        milliseconds < 1_000 -> "${milliseconds}ms"
        milliseconds < 60_000 -> String.format(Locale.ROOT, "%.1fs", milliseconds / 1_000.0)
        else -> String.format(Locale.ROOT, "%.1fmin", milliseconds / 60_000.0)
    }

    private fun goalConversationState(phase: RemoteGoalPhase): RemoteConversationState = when (phase) {
        RemoteGoalPhase.ACTIVE -> RemoteConversationState.RUNNING
        RemoteGoalPhase.PAUSED, RemoteGoalPhase.BLOCKED -> RemoteConversationState.STOPPED
        RemoteGoalPhase.COMPLETE -> RemoteConversationState.SUCCEEDED
    }
}
