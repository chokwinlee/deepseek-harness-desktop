package com.chokwinlee.dshremote.app

import com.chokwinlee.dshremote.remote.RemoteConnectionDescriptor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LocalNetworkPermissionRecoveryTest {
    @Test
    fun `denial retains verification and later grant consumes it`() {
        val recovery = LocalNetworkPermissionRecovery()
        val action = PendingLocalNetworkAction.Verify(
            "Desktop",
            RemoteConnectionDescriptor("http://192.168.1.9:17373/", "a".repeat(64)),
        )
        recovery.defer(action)

        assertNull(recovery.consumeIfGranted(false))
        assertEquals(action, recovery.pending)
        assertEquals(action, recovery.consumeIfGranted(true))
        assertNull(recovery.pending)
    }

    @Test
    fun `new host selection replaces stale pending action`() {
        val recovery = LocalNetworkPermissionRecovery()
        recovery.defer(PendingLocalNetworkAction.SelectHost("old", null))
        val latest = PendingLocalNetworkAction.SelectHost("latest", "session")

        recovery.defer(latest)

        assertEquals(latest, recovery.consumeIfGranted(true))
    }
}
