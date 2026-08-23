package com.chokwinlee.dshremote.app

/** Requests that need an Activity-owned launcher rather than a ViewModel-owned Context. */
sealed interface RemoteSystemRequest {
    data object ScanPairingCode : RemoteSystemRequest
    data object PickImages : RemoteSystemRequest
    data object PasteImages : RemoteSystemRequest
    data object RequestNotificationPermission : RemoteSystemRequest
    data object RequestLocalNetworkPermission : RemoteSystemRequest
    data object OpenAppSettings : RemoteSystemRequest
    data class OpenAttachment(val uri: String, val mediaType: String) : RemoteSystemRequest
}

object RemoteLaunchExtras {
    const val HOST_ID = "com.chokwinlee.dshremote.extra.HOST_ID"
    const val SESSION_ID = "com.chokwinlee.dshremote.extra.SESSION_ID"
}
