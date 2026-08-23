package com.chokwinlee.dshremote.app

import com.chokwinlee.dshremote.remote.RemoteQueueAction
import com.chokwinlee.dshremote.remote.RemoteQueuedMessage
import com.chokwinlee.dshremote.remote.RemoteQueuedPlacement
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RemoteQueueReducerTest {
    private val queue = listOf(
        RemoteQueuedMessage("first", RemoteQueuedPlacement.QUEUED, "Old", "Old", 0),
        RemoteQueuedMessage("second", RemoteQueuedPlacement.QUEUED, "Next", "Next", 0),
    )

    @Test
    fun editUpdatesPreviewAndTextWithoutChangingOrder() {
        val result = reduceRemoteQueue(queue, "first", RemoteQueueAction.Edit("Updated"))
        assertEquals(listOf("first", "second"), result.map(RemoteQueuedMessage::id))
        assertEquals("Updated", result.first().preview)
        assertEquals("Updated", result.first().text)
    }

    @Test
    fun removeAndSteerImmediatelyRemoveTheHandledItem() {
        assertEquals(listOf("second"), reduceRemoteQueue(queue, "first", RemoteQueueAction.Remove).map { it.id })
        assertEquals(listOf("second"), reduceRemoteQueue(queue, "first", RemoteQueueAction.Steer).map { it.id })
        assertTrue(reduceRemoteQueue(emptyList(), "missing", RemoteQueueAction.Remove).isEmpty())
    }
}
