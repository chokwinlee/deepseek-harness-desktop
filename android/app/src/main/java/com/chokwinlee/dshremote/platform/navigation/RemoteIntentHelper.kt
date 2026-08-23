package com.chokwinlee.dshremote.platform.navigation

import android.content.Context
import android.content.Intent
import androidx.core.net.toUri
import com.chokwinlee.dshremote.remote.RemoteConnectionDescriptor
import com.chokwinlee.dshremote.remote.RemoteEndpointError
import com.chokwinlee.dshremote.remote.RemoteEndpointException
import com.chokwinlee.dshremote.remote.RemoteEndpointValidator
import java.net.URI

sealed interface RemoteDeepLinkResult {
    data class Connection(val descriptor: RemoteConnectionDescriptor) : RemoteDeepLinkResult
    data class Rejected(val reason: RemoteEndpointError) : RemoteDeepLinkResult
}

/** Strict parsing for exported VIEW intents. Ordinary HTTPS URLs are not app deep links. */
object RemoteDeepLinkParser {
    private val allowedSchemes = setOf("harnessremote", "dshremote")

    fun parse(rawValue: String?): RemoteDeepLinkResult {
        val value = rawValue?.trim().orEmpty()
        if (value.isEmpty()) return RemoteDeepLinkResult.Rejected(RemoteEndpointError.EMPTY)
        if (value.length > MAX_DEEP_LINK_CHARACTERS) {
            return RemoteDeepLinkResult.Rejected(RemoteEndpointError.INVALID_URL)
        }
        val uri = runCatching { URI(value) }.getOrNull()
            ?: return RemoteDeepLinkResult.Rejected(RemoteEndpointError.INVALID_URL)
        if (uri.scheme?.lowercase() !in allowedSchemes || !uri.host.equals("connect", ignoreCase = true)) {
            return RemoteDeepLinkResult.Rejected(RemoteEndpointError.INVALID_URL)
        }
        return try {
            RemoteDeepLinkResult.Connection(RemoteEndpointValidator.connection(value))
        } catch (error: RemoteEndpointException) {
            RemoteDeepLinkResult.Rejected(error.reason)
        } catch (_: IllegalArgumentException) {
            RemoteDeepLinkResult.Rejected(RemoteEndpointError.INVALID_URL)
        }
    }

    private const val MAX_DEEP_LINK_CHARACTERS = 8_192
}

object RemoteIntentHelper {
    fun parseConnectionIntent(intent: Intent?): RemoteDeepLinkResult? {
        if (intent?.action != Intent.ACTION_VIEW) return null
        return RemoteDeepLinkParser.parse(intent.dataString)
    }

    /** Creates an app-scoped pairing intent without duplicating the bearer token in extras. */
    fun connectionIntent(context: Context, connection: RemoteConnectionDescriptor): Intent = Intent(
        Intent.ACTION_VIEW,
        connection.importedUrl.toUri(),
    )
        .setPackage(context.packageName)
        .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
}
