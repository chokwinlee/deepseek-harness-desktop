package com.chokwinlee.dshremote.remote

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ConversationFolderTest {
    private val json = LiveHarnessRemoteClient.defaultJson()

    @Test
    fun `folds user assistant paired tool projection and image limits`() {
        val history = json.decodeFromString(SessionHistoryWire.serializer(), HISTORY)
        val snapshot = ConversationFolder.fold(history)

        assertEquals(listOf(RemoteConversationKind.USER, RemoteConversationKind.TOOL, RemoteConversationKind.ASSISTANT), snapshot.items.map { it.kind })
        assertEquals(RemoteConversationState.SUCCEEDED, snapshot.items[1].state)
        assertTrue(snapshot.items[1].text.contains("PASS"))
        assertEquals(3, snapshot.stats?.inputTokens)
        assertEquals(7, snapshot.stats?.outputTokens)
        assertEquals("goal-1", snapshot.goal?.id)
        assertTrue(snapshot.plan?.effectiveActive == true)
        assertEquals(4, snapshot.imageLimits?.maxImagesPerMessage)
        assertFalse(snapshot.hasMore)
    }

    @Test
    fun `keeps unfinished assistant chunks as streaming item`() {
        val history = json.decodeFromString(SessionHistoryWire.serializer(), STREAMING_HISTORY)
        val item = ConversationFolder.fold(history).items.single()

        assertEquals("Hello Android", item.text)
        assertEquals("thinking", item.reasoning)
        assertTrue(item.isStreaming)
        assertEquals(RemoteConversationState.RUNNING, item.state)
    }

    @Test
    fun `suppresses replacement surface events`() {
        val history = json.decodeFromString(SessionHistoryWire.serializer(), REPLACEMENT_HISTORY)

        assertTrue(ConversationFolder.fold(history).items.isEmpty())
    }

    @Test
    fun `builds request assistant lifecycle and compaction trajectory with timing`() {
        val history = json.decodeFromString(SessionHistoryWire.serializer(), TRAJECTORY_HISTORY)
        val trajectory = ConversationFolder.fold(history).trajectory

        assertEquals(
            listOf(
                RemoteTrajectoryKind.INPUT,
                RemoteTrajectoryKind.REQUEST,
                RemoteTrajectoryKind.ASSISTANT,
                RemoteTrajectoryKind.LIFECYCLE,
                RemoteTrajectoryKind.LIFECYCLE,
            ),
            trajectory.map { it.kind },
        )
        assertEquals("deepseek · chat · high", trajectory[1].summary)
        assertEquals(200L, trajectory[2].durationMs)
        assertEquals(400L, trajectory[3].durationMs)
        assertEquals("Compaction summary", trajectory[4].details.single().title)
    }

    companion object {
        private val HISTORY = """
            {
              "events": [
                {"event":{"type":"user/message","seq":1,"time":1000,"data":{"content":[{"type":"text","text":"Run tests"}],"source":{"kind":"user"}}}},
                {"event":{"type":"tool/call","seq":2,"time":1100,"data":{"turn":0,"step":0,"callId":"call-1","name":"exec_command"}},"view":{"view":{"title":"Run unit tests","card":"terminal"}}},
                {"event":{"type":"tool/result","seq":3,"time":1300,"data":{"turn":0,"step":0,"message":{"source":{"callId":"call-1"},"content":[{"type":"tool-result","toolCallId":"call-1","isError":false,"content":[{"type":"text","text":"PASS"}]}]}}}},
                {"event":{"type":"assistant/message","seq":4,"time":1400,"data":{"turn":0,"step":0,"message":{"content":[{"type":"text","text":"All tests pass."}]}}}}
              ],
              "hasMore": false,
              "projections": {
                "values": {
                  "sessionStats":{"turns":1,"steps":1,"llmMs":200,"toolMs":200},
                  "tokenUsage":{"uncachedInputTokens":2,"cacheReadTokens":1,"outputTokens":7},
                  "goal":{"goal":{"id":"goal-1","revision":1,"objective":"Ship Android","phase":"active","maxGoalRounds":8},"roundsStarted":1,"createdAt":1000,"updatedAt":1400},
                  "plan":{"active":false,"pending":true},
                  "imageLimits":{"maxImageBytes":1024,"maxImagesPerMessage":4,"maxMessageImageBytes":4096,"maxImagePixels":1000000,"maxImageDimension":2048,"mediaTypes":["image/png"]}
                }
              }
            }
        """.trimIndent()

        private val STREAMING_HISTORY = """
            {
              "events": [
                {"event":{"type":"assistant/chunk","seq":1,"time":1000,"data":{"turn":1,"step":2,"chunk":{"type":"block-start","index":0,"blockType":"text"}}}},
                {"event":{"type":"assistant/chunk","seq":2,"time":1010,"data":{"turn":1,"step":2,"chunk":{"type":"text-delta","index":0,"text":"Hello "}}}},
                {"event":{"type":"assistant/chunk","seq":3,"time":1020,"data":{"turn":1,"step":2,"chunk":{"type":"text-delta","index":0,"text":"Android"}}}},
                {"event":{"type":"assistant/chunk","seq":4,"time":1030,"data":{"turn":1,"step":2,"chunk":{"type":"reasoning-delta","index":1,"text":"thinking"}}}}
              ],
              "hasMore": false
            }
        """.trimIndent()

        private val REPLACEMENT_HISTORY = """
            {
              "events": [
                {"event":{"type":"user/message","seq":1,"time":1000,"data":{"content":[{"type":"text","text":"hidden replacement"}],"source":{"kind":"user"}},"surfaceOp":{"op":"replace"}}}
              ],
              "hasMore": false
            }
        """.trimIndent()

        private val TRAJECTORY_HISTORY = """
            {
              "events": [
                {"event":{"type":"turn/start","seq":0,"time":900,"data":{"turn":0}}},
                {"event":{"type":"user/message","seq":1,"time":1000,"data":{"content":[{"type":"text","text":"Continue"}],"source":{"kind":"user"}}}},
                {"event":{"type":"step/start","seq":2,"time":1050,"data":{"turn":0,"step":0}}},
                {"event":{"type":"request/header","seq":3,"time":1060,"data":{"header":{"config":{"provider":"deepseek","model":"chat","reasoningEffort":"high"},"system":"Stay concise"}}}},
                {"event":{"type":"assistant/message","seq":4,"time":1250,"data":{"turn":0,"step":0,"message":{"content":[{"type":"reasoning","text":"Check state"},{"type":"text","text":"Done"}]}}}},
                {"event":{"type":"turn/end","seq":5,"time":1300,"data":{"turn":0,"reason":{"kind":"completed"}}}},
                {"event":{"type":"compaction/summary","seq":6,"time":1400,"data":{"summary":[{"type":"text","text":"Earlier context"}]}}}
              ],
              "hasMore": false
            }
        """.trimIndent()
    }
}
