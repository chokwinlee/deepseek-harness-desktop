package com.chokwinlee.dshremote.remote

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LiveEventParserTest {
    private val json = LiveHarnessRemoteClient.defaultJson()

    @Test
    fun `parses shared approval fixture`() {
        val event = parseFixture("events.approval-requested.json")
        assertTrue(event is RemoteLiveEvent.Interaction)
        val interaction = (event as RemoteLiveEvent.Interaction).interaction
        assertEquals("approval:approval-1", interaction.id)
        assertEquals("exec_command", (interaction.kind as RemoteInteractionKind.Approval).toolName)
    }

    @Test
    fun `parses shared structured question fixture`() {
        val event = parseFixture("events.question-requested.json") as RemoteLiveEvent.Interaction
        val questions = (event.interaction.kind as RemoteInteractionKind.Questions).questions

        assertEquals("release-channel", questions.single().id)
        assertEquals(listOf("Internal", "Public beta"), questions.single().options.map { it.label })
    }

    @Test
    fun `parses compact shared queue fixture`() {
        val event = parseFixture("events.queue.json") as RemoteLiveEvent.QueueChanged

        assertEquals("Verify the Android build", event.items.single().text)
        assertEquals(RemoteQueuedPlacement.QUEUED, event.items.single().placement)
    }

    @Test
    fun `ignores unknown event type`() {
        val envelope = json.decodeFromString(
            LiveEventEnvelope.serializer(),
            """{"rpcId":"future","payload":{"type":"session/future","sessionId":"s1"}}""",
        )

        assertNull(LiveEventParser.parse(envelope))
    }

    @Test
    fun `queue parser does not manufacture English image or fallback copy`() {
        val envelope = json.decodeFromString(
            LiveEventEnvelope.serializer(),
            """{"rpcId":"queue","payload":{"type":"session/queue","sessionId":"s1","items":[{"id":"image","placement":"queued","content":[{"type":"image","data":"x"}]},{"id":"empty","placement":"queued","content":[]}]}}""",
        )

        val items = (LiveEventParser.parse(envelope) as RemoteLiveEvent.QueueChanged).items

        assertEquals(listOf("", ""), items.map { it.preview })
        assertEquals(listOf(1, 0), items.map { it.attachmentCount })
    }

    private fun parseFixture(name: String): RemoteLiveEvent? = LiveEventParser.parse(
        json.decodeFromString(LiveEventEnvelope.serializer(), remoteFixture(name)),
    )
}
