package com.chokwinlee.dshremote.remote

import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DemoHarnessRemoteClientTest {
    @Test
    fun `demo works without a host or model call`() = runTest {
        val client = DemoHarnessRemoteClient { 1_800_000_000_000 }

        assertTrue(client.isDemo)
        assertEquals("Offline Demo", client.describe().version)
        assertTrue(client.sessions().isNotEmpty())
        assertTrue(client.conversation("review-demo-session", 100).items.isNotEmpty())
        assertTrue(client.liveEvents().first() is RemoteLiveEvent.Interaction)
    }

    @Test
    fun `demo accepts a prompt and returns a local reply`() = runTest {
        val client = DemoHarnessRemoteClient { 1_800_000_000_000 }
        val before = client.conversation("review-demo-session", 100).items.size

        client.send("Continue", emptyList(), "review-demo-session", false)
        val after = client.conversation("review-demo-session", 100).items

        assertEquals(before + 2, after.size)
        assertFalse(after.last().isStreaming)
        assertEquals(RemoteConversationKind.ASSISTANT, after.last().kind)
    }

    @Test
    fun `new demo session owns independent empty history and goal`() = runTest {
        val client = DemoHarnessRemoteClient { 1_800_000_000_000 }
        val reviewBefore = client.conversation("review-demo-session", 100)

        val created = client.createSession("review-demo-workspace", "/Users/demo/sample-app")
        val createdBefore = client.conversation(created, 100)

        assertTrue(createdBefore.items.isEmpty())
        assertEquals(null, createdBefore.goal)
        assertTrue(client.workspaces().items.single().sessionIds.contains(created))
        assertTrue(client.sessions().any { it.id == created })

        client.send("Start a separate review", emptyList(), created, false)

        assertEquals(2, client.conversation(created, 100).items.size)
        assertEquals(reviewBefore.items, client.conversation("review-demo-session", 100).items)
        assertEquals(reviewBefore.goal, client.conversation("review-demo-session", 100).goal)
    }
}
