package com.chokwinlee.dshremote.app

import com.chokwinlee.dshremote.remote.RemoteConversationItem
import com.chokwinlee.dshremote.remote.RemoteConversationKind
import com.chokwinlee.dshremote.remote.RemoteConversationSnapshot
import com.chokwinlee.dshremote.remote.RemoteImageAttachment
import com.chokwinlee.dshremote.remote.RemoteSubagentActivity
import com.chokwinlee.dshremote.remote.RemoteSubagentCatalog
import com.chokwinlee.dshremote.remote.RemoteSubagentEntry
import com.chokwinlee.dshremote.remote.RemoteSubagentMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SubagentNavigationStateTest {
    @Test
    fun `recursive catalogs retain the parent conversation on every back step`() {
        val navigation = SubagentNavigationState()
        val child = subagent("child", hasChildren = true)
        val grandchild = subagent("grandchild", hasChildren = true)

        navigation.reset("root-session")
        navigation.updateCatalog("root-session", catalog(child))
        assertEquals("child", navigation.select("child", 120)?.entry?.id)
        assertEquals(true, navigation.enterChildren(SubagentAddress("root-session", "child")))
        navigation.updateCatalog("child", catalog(grandchild))
        assertEquals(1, navigation.depth)
        assertEquals("child", navigation.currentCatalogAddress?.parentSessionId)

        assertEquals("grandchild", navigation.select("grandchild", 120)?.entry?.id)
        assertEquals(true, navigation.enterChildren(SubagentAddress("child", "grandchild")))
        navigation.updateCatalog("grandchild", catalog())
        assertEquals(2, navigation.depth)

        assertEquals(SubagentBackResult.ShowConversation, navigation.back())
        assertEquals("grandchild", navigation.selection?.entry?.id)
        assertEquals(1, navigation.depth)
        assertEquals(SubagentBackResult.ShowCatalog, navigation.back())
        assertNull(navigation.selection)
        assertEquals(SubagentBackResult.ShowConversation, navigation.back())
        assertEquals("child", navigation.selection?.entry?.id)
        assertEquals(0, navigation.depth)
    }

    @Test
    fun `monitor refreshes running work every second and idle work every three seconds`() {
        assertEquals(1_000L, subagentRefreshIntervalMillis(RemoteSubagentActivity.RUNNING))
        assertEquals(3_000L, subagentRefreshIntervalMillis(RemoteSubagentActivity.INACTIVE))
        assertEquals(3_000L, subagentRefreshIntervalMillis(null))
    }

    @Test
    fun `dismiss and session reset cannot leak a nested selection`() {
        val navigation = SubagentNavigationState()
        val child = subagent("child", hasChildren = true)
        navigation.reset("first-session")
        navigation.updateCatalog("first-session", catalog(child))
        navigation.select("child", 120)
        navigation.enterChildren(SubagentAddress("first-session", "child"))
        navigation.updateCatalog("child", catalog(subagent("grandchild", hasChildren = false)))
        navigation.select("grandchild", 120)

        navigation.dismiss()
        assertEquals(0, navigation.depth)
        assertNull(navigation.selection)
        assertEquals("first-session", navigation.currentCatalogAddress?.parentSessionId)

        navigation.reset("second-session")
        assertEquals("second-session", navigation.currentCatalogAddress?.parentSessionId)
        assertNull(navigation.rootCatalog)
        assertNull(navigation.selection)
    }

    @Test
    fun `child attachment lookup never falls back to a parent snapshot`() {
        val parentAttachment = attachment("shared-id", "parent.png")
        val childAttachment = attachment("shared-id", "child.png")
        val parent = snapshot(parentAttachment)
        val child = snapshot(childAttachment)
        val childWithoutAttachment = snapshot()

        assertEquals("parent.png", parent.findImageAttachment("shared-id")?.name)
        assertEquals("child.png", child.findImageAttachment("shared-id")?.name)
        assertNull(childWithoutAttachment.findImageAttachment("shared-id"))
    }

    private fun subagent(id: String, hasChildren: Boolean) = RemoteSubagentEntry(
        id = id,
        mode = RemoteSubagentMode.CONTINUABLE,
        activity = RemoteSubagentActivity.INACTIVE,
        hasChildren = hasChildren,
        label = id,
        diagnosticReason = null,
    )

    private fun catalog(vararg entries: RemoteSubagentEntry) = RemoteSubagentCatalog(
        entries = entries.toList(),
        parentAvailable = true,
    )

    private fun attachment(id: String, name: String) = RemoteImageAttachment(
        attachmentId = id,
        mediaType = "image/png",
        bytes = 16,
        width = 2,
        height = 2,
        name = name,
    )

    private fun snapshot(vararg attachments: RemoteImageAttachment) = RemoteConversationSnapshot(
        items = listOf(
            RemoteConversationItem(
                id = "message",
                kind = RemoteConversationKind.ASSISTANT,
                title = null,
                text = "result",
                time = 1,
                attachments = attachments.toList(),
            ),
        ),
        hasMore = false,
        stats = null,
    )
}
