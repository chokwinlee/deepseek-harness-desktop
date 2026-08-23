package com.chokwinlee.dshremote.app

import com.chokwinlee.dshremote.remote.RemoteConnectionDescriptor

internal sealed interface PendingLocalNetworkAction {
    data class Verify(
        val name: String?,
        val connection: RemoteConnectionDescriptor,
    ) : PendingLocalNetworkAction

    data class SelectHost(
        val hostId: String,
        val sessionId: String?,
    ) : PendingLocalNetworkAction
}

/** Retains the user's requested LAN action across denial and a round trip through Settings. */
internal class LocalNetworkPermissionRecovery {
    var pending: PendingLocalNetworkAction? = null
        private set

    fun defer(action: PendingLocalNetworkAction) {
        pending = action
    }

    fun consumeIfGranted(granted: Boolean): PendingLocalNetworkAction? {
        if (!granted) return null
        return pending.also { pending = null }
    }

    fun clear() {
        pending = null
    }
}
