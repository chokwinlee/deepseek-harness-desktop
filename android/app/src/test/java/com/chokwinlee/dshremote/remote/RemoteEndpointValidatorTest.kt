package com.chokwinlee.dshremote.remote

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RemoteEndpointValidatorTest {
    @Test
    fun `normalizes trusted https endpoint to its origin`() {
        val result = RemoteEndpointValidator.connection("Example.TS.NET:8443/path?secret=value#fragment")

        assertEquals("https://example.ts.net:8443/", result.baseUrl)
        assertNull(result.accessToken)
        assertEquals(RemoteHostTransport.TAILSCALE, RemoteEndpointValidator.transport(result))
    }

    @Test
    fun `rejects manually entered cleartext private endpoint`() {
        val error = assertThrows(RemoteEndpointException::class.java) {
            RemoteEndpointValidator.connection("http://192.168.1.8:17373")
        }

        assertEquals(RemoteEndpointError.MISSING_PAIRING_CREDENTIAL, error.reason)
    }

    @Test
    fun `accepts private http only from credentialed pairing deep link`() {
        val token = "a".repeat(64)
        val imported = RemoteEndpointValidator.connectionUrl("http://192.168.1.8:17373/ignored?q=1", token)
        val result = RemoteEndpointValidator.connection(imported)

        assertEquals("http://192.168.1.8:17373/", result.baseUrl)
        assertEquals(token, result.accessToken)
        assertEquals(RemoteHostTransport.SAME_WIFI, RemoteEndpointValidator.transport(result))
    }

    @Test
    fun `rejects malformed pairing token`() {
        val error = assertThrows(RemoteEndpointException::class.java) {
            RemoteEndpointValidator.connection(
                "harnessremote://connect?url=http%3A%2F%2F192.168.1.8%3A17373&token=not-a-token",
            )
        }

        assertEquals(RemoteEndpointError.INVALID_URL, error.reason)
    }

    @Test
    fun `rejects credentials embedded in endpoint`() {
        val error = assertThrows(RemoteEndpointException::class.java) {
            RemoteEndpointValidator.connection("https://user:password@example.com")
        }

        assertEquals(RemoteEndpointError.EMBEDDED_CREDENTIALS, error.reason)
    }

    @Test
    fun `rejects public cleartext address`() {
        val error = assertThrows(RemoteEndpointException::class.java) {
            RemoteEndpointValidator.connection("http://example.com")
        }

        assertEquals(RemoteEndpointError.UNSUPPORTED_HOST, error.reason)
    }

    @Test
    fun `rejects credentialed cleartext dotless hostname because DNS may leave the LAN`() {
        val token = "b".repeat(64)
        val error = assertThrows(RemoteEndpointException::class.java) {
            RemoteEndpointValidator.connection(
                RemoteEndpointValidator.connectionUrl("http://desktop:17373", token),
            )
        }

        assertEquals(RemoteEndpointError.UNSUPPORTED_HOST, error.reason)
    }

    @Test
    fun `revalidates stored descriptors before reuse`() {
        val error = assertThrows(RemoteEndpointException::class.java) {
            RemoteEndpointValidator.validatedConnection(
                RemoteConnectionDescriptor("http://example.com:17373/", "d".repeat(64)),
            )
        }

        assertEquals(RemoteEndpointError.UNSUPPORTED_HOST, error.reason)
    }

    @Test
    fun `accepts explicit private IPv6 literals with a pairing credential`() {
        val token = "e".repeat(64)
        val uniqueLocal = RemoteEndpointValidator.connection(
            RemoteEndpointValidator.connectionUrl("http://[fd12:3456::8]:17373", token),
        )
        val linkLocal = RemoteEndpointValidator.connection(
            RemoteEndpointValidator.connectionUrl("http://[fe80::8]:17373", token),
        )

        assertEquals(RemoteHostTransport.SAME_WIFI, RemoteEndpointValidator.transport(uniqueLocal))
        assertEquals(RemoteHostTransport.SAME_WIFI, RemoteEndpointValidator.transport(linkLocal))
    }

    @Test
    fun `rejects credentialed cleartext mDNS name until its resolved addresses can be verified`() {
        val token = "f".repeat(64)
        val error = assertThrows(RemoteEndpointException::class.java) {
            RemoteEndpointValidator.connection(
                RemoteEndpointValidator.connectionUrl("http://desktop.local:17373", token),
            )
        }

        assertEquals(RemoteEndpointError.UNSUPPORTED_HOST, error.reason)
    }

    @Test
    fun `identifies direct LAN endpoints without treating tailnet or loopback as LAN permission`() {
        val token = "c".repeat(64)
        val lan = RemoteEndpointValidator.connection(
            RemoteEndpointValidator.connectionUrl("http://192.168.50.4:17373", token),
        )
        val localHttps = RemoteEndpointValidator.connection("https://desktop.local:8443")
        val tailnet = RemoteEndpointValidator.connection("https://desktop.example.ts.net:8443")
        val loopback = RemoteConnectionDescriptor("http://127.0.0.1:17373/", token)

        assertTrue(RemoteEndpointValidator.requiresLocalNetworkAccess(lan))
        assertTrue(RemoteEndpointValidator.requiresLocalNetworkAccess(localHttps))
        assertFalse(RemoteEndpointValidator.requiresLocalNetworkAccess(tailnet))
        assertFalse(RemoteEndpointValidator.requiresLocalNetworkAccess(loopback))
    }
}
