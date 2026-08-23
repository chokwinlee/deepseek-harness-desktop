package com.chokwinlee.dshremote.remote

import com.sun.net.httpserver.HttpExchange
import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener

class LiveHarnessRemoteClientTest {
    private val json = LiveHarnessRemoteClient.defaultJson()

    @Test
    fun `sends rpc envelope and bearer credential over real http`() = withServer { server ->
        server.createContext("/api/host.describe") { exchange ->
            assertEquals("Bearer ${"a".repeat(64)}", exchange.requestHeaders.getFirst("Authorization"))
            val request = json.parseToJsonElement(exchange.requestBody.bufferedReader().readText()).jsonObject
            assertEquals("client-request", request["type"]?.jsonPrimitive?.content)
            assertEquals("host.describe", request["method"]?.jsonPrimitive?.content)
            assertEquals(JsonObject(emptyMap()), request["payload"])
            val rpcId = request.getValue("rpcId").jsonPrimitive.content
            exchange.respond(
                200,
                """{"rpcId":"$rpcId","result":{"ok":true,"value":{"version":"fixture-host","attachedSessions":3}}}""",
            )
        }

        val client = LiveHarnessRemoteClient(
            "http://127.0.0.1:${server.address.port}/",
            "Test host",
            "a".repeat(64),
        )
        val description = runBlocking { client.describe() }

        assertEquals("fixture-host", description.version)
        assertEquals(3, description.attachedSessions)
    }

    @Test
    fun `rejects mismatched rpc id from real transport`() = withServer { server ->
        server.createContext("/api/host.describe") { exchange ->
            exchange.respond(
                200,
                """{"rpcId":"wrong","result":{"ok":true,"value":{"version":"fixture-host","attachedSessions":0}}}""",
            )
        }
        val client = LiveHarnessRemoteClient("http://127.0.0.1:${server.address.port}/", "Test")

        assertThrows(HarnessRemoteClientException.MismatchedResponse::class.java) {
            runBlocking { client.describe() }
        }
    }

    @Test
    fun `surfaces http status without attempting to decode body`() = withServer { server ->
        server.createContext("/api/host.describe") { exchange -> exchange.respond(401, "unauthorized") }
        val client = LiveHarnessRemoteClient("http://127.0.0.1:${server.address.port}/", "Test")

        val error = assertThrows(HarnessRemoteClientException.Server::class.java) {
            runBlocking { client.describe() }
        }
        assertEquals(401, error.statusCode)
    }

    @Test
    fun `does not follow redirect or forward bearer authorization to another origin`() {
        val source = MockWebServer()
        val target = MockWebServer()
        source.start()
        target.start()
        try {
            source.enqueue(
                MockResponse.Builder()
                    .code(307)
                    .addHeader("Location", target.url("/api/host.describe"))
                    .build(),
            )
            val token = "f".repeat(64)
            val client = LiveHarnessRemoteClient(source.url("/").toString(), "Test", token)

            val error = assertThrows(HarnessRemoteClientException.Server::class.java) {
                runBlocking { client.describe() }
            }

            assertEquals(307, error.statusCode)
            assertEquals("Bearer $token", source.takeRequest().headers["Authorization"])
            assertEquals(0, target.requestCount)
        } finally {
            source.close()
            target.close()
        }
    }

    @Test
    fun `reconnects websocket and preserves bearer authorization`() {
        val server = MockWebServer()
        val responses = listOf(
            """{"rpcId":"approval-rpc","payload":{"type":"approval/requested","sessionId":"session","approvalId":"approval","toolName":"exec_command"}}""",
            """{"rpcId":"queue-rpc","payload":{"type":"session/queue","sessionId":"session","items":[]}}""",
        )
        responses.forEachIndexed { index, payload ->
            server.enqueue(
                MockResponse.Builder()
                    .webSocketUpgrade(object : WebSocketListener() {
                        override fun onOpen(webSocket: WebSocket, response: Response) {
                            webSocket.send(payload)
                            webSocket.close(1000, "fixture-$index")
                        }
                    })
                    .build(),
            )
        }
        server.start()
        try {
            val token = "b".repeat(64)
            val client = LiveHarnessRemoteClient(server.url("/").toString(), "Test", token)
            val events = runBlocking {
                withTimeout(8_000) { client.liveEvents().take(2).toList() }
            }

            assertEquals(2, events.size)
            assertTrue(events[0] is RemoteLiveEvent.Interaction)
            assertTrue(events[1] is RemoteLiveEvent.QueueChanged)
            repeat(2) {
                val request = server.takeRequest()
                assertEquals("/api/events.mux", request.url.encodedPath)
                assertEquals("Bearer $token", request.headers["Authorization"])
            }
        } finally {
            server.close()
        }
    }

    private fun withServer(block: (HttpServer) -> Unit) {
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.start()
        try {
            block(server)
        } finally {
            server.stop(0)
        }
    }

    private fun HttpExchange.respond(status: Int, body: String) {
        val data = body.toByteArray()
        responseHeaders.add("Content-Type", "application/json")
        sendResponseHeaders(status, data.size.toLong())
        responseBody.use { it.write(data) }
    }
}
