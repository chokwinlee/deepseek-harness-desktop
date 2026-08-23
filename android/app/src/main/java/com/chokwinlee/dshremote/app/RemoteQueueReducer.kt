package com.chokwinlee.dshremote.app

import com.chokwinlee.dshremote.remote.RemoteQueueAction
import com.chokwinlee.dshremote.remote.RemoteQueuedMessage

internal fun reduceRemoteQueue(
    items: List<RemoteQueuedMessage>,
    itemId: String,
    action: RemoteQueueAction,
): List<RemoteQueuedMessage> = when (action) {
    is RemoteQueueAction.Edit -> items.map { item ->
        if (item.id == itemId) item.copy(preview = action.text, text = action.text) else item
    }
    RemoteQueueAction.Remove,
    RemoteQueueAction.Steer,
    -> items.filterNot { it.id == itemId }
}
