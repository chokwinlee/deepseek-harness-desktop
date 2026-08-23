package com.chokwinlee.dshremote.remote

import java.net.InetAddress
import java.net.URI
import java.net.URLDecoder
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

enum class RemoteEndpointError {
    EMPTY,
    INVALID_URL,
    INSECURE_URL,
    UNSUPPORTED_HOST,
    EMBEDDED_CREDENTIALS,
    MISSING_PAIRING_CREDENTIAL,
}

class RemoteEndpointException(val reason: RemoteEndpointError) : IllegalArgumentException(reason.name)

data class RemoteConnectionDescriptor(
    val baseUrl: String,
    val accessToken: String?,
) {
    val importedUrl: String get() = RemoteEndpointValidator.connectionUrl(baseUrl, accessToken)
}

object RemoteEndpointValidator {
    private val connectionSchemes = setOf("harnessremote", "dshremote")
    private val tokenRegex = Regex("^[0-9a-f]{64}$")

    fun normalizedUrl(input: String): String = connection(input).baseUrl

    fun connection(input: String): RemoteConnectionDescriptor {
        val trimmed = input.trim()
        if (trimmed.isEmpty()) throw RemoteEndpointException(RemoteEndpointError.EMPTY)

        val uri = runCatching { URI(trimmed) }.getOrNull()
        if (uri != null && uri.scheme?.lowercase() in connectionSchemes) return normalizedConnection(uri)

        return RemoteConnectionDescriptor(endpointUrl(trimmed, allowLocalHttp = false).toString(), null)
    }

    /** Revalidates a descriptor loaded from storage before it can create a network client. */
    fun validatedConnection(connection: RemoteConnectionDescriptor): RemoteConnectionDescriptor {
        val token = connection.accessToken
        if (token != null && !tokenRegex.matches(token)) {
            throw RemoteEndpointException(RemoteEndpointError.INVALID_URL)
        }
        val endpoint = endpointUrl(connection.baseUrl, allowLocalHttp = token != null)
        if (endpoint.scheme == "http" && token == null) {
            throw RemoteEndpointException(RemoteEndpointError.MISSING_PAIRING_CREDENTIAL)
        }
        return RemoteConnectionDescriptor(endpoint.toString(), token)
    }

    fun connectionUrl(remoteUrl: String, accessToken: String? = null): String {
        val url = URLEncoder.encode(remoteUrl, StandardCharsets.UTF_8.name()).replace("+", "%20")
        return buildString {
            append("harnessremote://connect?url=").append(url)
            if (accessToken != null) {
                append("&token=").append(URLEncoder.encode(accessToken, StandardCharsets.UTF_8.name()))
                append("&transport=lan")
            }
        }
    }

    fun transport(connection: RemoteConnectionDescriptor): RemoteHostTransport {
        val url = connection.baseUrl.toHttpUrlOrNull() ?: return RemoteHostTransport.CUSTOM
        val host = url.host.lowercase()
        return when {
            host == "127.0.0.1" || host == "localhost" || host == "::1" -> RemoteHostTransport.LOOPBACK
            url.scheme == "http" && isLocalNetworkHost(host) -> {
                if (connection.accessToken == null) RemoteHostTransport.UNPAIRED_LOCAL_NETWORK
                else RemoteHostTransport.SAME_WIFI
            }
            url.scheme == "https" && host.endsWith(".ts.net") -> RemoteHostTransport.TAILSCALE
            url.scheme == "https" -> RemoteHostTransport.HTTPS
            else -> RemoteHostTransport.CUSTOM
        }
    }

    /** Android 17 gates direct LAN sockets behind ACCESS_LOCAL_NETWORK. */
    fun requiresLocalNetworkAccess(connection: RemoteConnectionDescriptor): Boolean {
        val url = connection.baseUrl.toHttpUrlOrNull() ?: return false
        val host = url.host.lowercase()
        if (host == "127.0.0.1" || host == "localhost" || host == "::1") return false
        if (host.endsWith(".ts.net")) return false
        return host.endsWith(".local") || isLocalNetworkHost(host)
    }

    private fun normalizedConnection(uri: URI): RemoteConnectionDescriptor {
        if (!uri.host.equals("connect", ignoreCase = true)) {
            throw RemoteEndpointException(RemoteEndpointError.INVALID_URL)
        }
        val query = parseQuery(uri.rawQuery)
        val value = query["url"] ?: throw RemoteEndpointException(RemoteEndpointError.INVALID_URL)
        val token = query["token"]
        if (token != null && !tokenRegex.matches(token)) {
            throw RemoteEndpointException(RemoteEndpointError.INVALID_URL)
        }
        return validatedConnection(RemoteConnectionDescriptor(value, token))
    }

    private fun endpointUrl(value: String, allowLocalHttp: Boolean): HttpUrl {
        val candidate = if (value.contains("://")) value else "https://$value"
        val parsed = candidate.toHttpUrlOrNull()
            ?: throw RemoteEndpointException(RemoteEndpointError.INVALID_URL)
        if (parsed.username.isNotEmpty() || parsed.password.isNotEmpty()) {
            throw RemoteEndpointException(RemoteEndpointError.EMBEDDED_CREDENTIALS)
        }
        val host = parsed.host.lowercase()
        when (parsed.scheme) {
            "https" -> Unit
            "http" -> {
                if (!isLocalNetworkHost(host)) {
                    throw RemoteEndpointException(RemoteEndpointError.UNSUPPORTED_HOST)
                }
                if (!allowLocalHttp) {
                    throw RemoteEndpointException(RemoteEndpointError.MISSING_PAIRING_CREDENTIAL)
                }
            }
            else -> throw RemoteEndpointException(RemoteEndpointError.INSECURE_URL)
        }
        return parsed.newBuilder()
            .encodedPath("/")
            .query(null)
            .fragment(null)
            .build()
    }

    internal fun isLocalNetworkHost(host: String): Boolean {
        val normalized = host.lowercase().removePrefix("[").removeSuffix("]")
        if (normalized == "localhost") {
            return true
        }
        if (normalized.contains(':')) return isPrivateIpv6Literal(normalized)
        val octets = normalized.split('.').mapNotNull(String::toIntOrNull)
        if (octets.size != 4 || octets.any { it !in 0..255 }) return false
        return octets[0] == 10 ||
            octets[0] == 127 ||
            (octets[0] == 172 && octets[1] in 16..31) ||
            (octets[0] == 192 && octets[1] == 168) ||
            (octets[0] == 169 && octets[1] == 254)
    }

    private fun isPrivateIpv6Literal(host: String): Boolean {
        val address = runCatching { InetAddress.getByName(host) }.getOrNull() ?: return false
        val bytes = address.address
        if (bytes.size != 16) return false
        val first = bytes[0].toInt() and 0xff
        return address.isLoopbackAddress ||
            address.isLinkLocalAddress ||
            address.isSiteLocalAddress ||
            first and 0xfe == 0xfc
    }

    private fun parseQuery(rawQuery: String?): Map<String, String> {
        if (rawQuery.isNullOrEmpty()) return emptyMap()
        return rawQuery.split('&').mapNotNull { pair ->
            val parts = pair.split('=', limit = 2)
            val key = decode(parts[0])
            val value = decode(parts.getOrElse(1) { "" })
            key to value
        }.toMap()
    }

    private fun decode(value: String): String =
        runCatching { URLDecoder.decode(value, StandardCharsets.UTF_8.name()) }
            .getOrElse { throw RemoteEndpointException(RemoteEndpointError.INVALID_URL) }
}
