package com.chokwinlee.dshremote.platform.navigation

import com.chokwinlee.dshremote.remote.RemoteEndpointError
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RemoteDeepLinkParserTest {
    @Test
    fun acceptsAuthenticatedDesktopPairingLink() {
        val token = "a".repeat(64)
        val result = RemoteDeepLinkParser.parse(
            "harnessremote://connect?url=http%3A%2F%2F192.168.1.5%3A17275&token=$token&transport=lan",
        )

        assertTrue(result is RemoteDeepLinkResult.Connection)
        result as RemoteDeepLinkResult.Connection
        assertEquals("http://192.168.1.5:17275/", result.descriptor.baseUrl)
        assertEquals(token, result.descriptor.accessToken)
    }

    @Test
    fun rejectsOrdinaryWebUrlAsExportedAppDeepLink() {
        val result = RemoteDeepLinkParser.parse("https://example.com/")

        assertEquals(
            RemoteEndpointError.INVALID_URL,
            (result as RemoteDeepLinkResult.Rejected).reason,
        )
    }

    @Test
    fun rejectsUnknownCustomHost() {
        val result = RemoteDeepLinkParser.parse("dshremote://open?url=https%3A%2F%2Fexample.com")

        assertEquals(
            RemoteEndpointError.INVALID_URL,
            (result as RemoteDeepLinkResult.Rejected).reason,
        )
    }
}
