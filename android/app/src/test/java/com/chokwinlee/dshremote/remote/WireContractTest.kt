package com.chokwinlee.dshremote.remote

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.decodeFromJsonElement
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class WireContractTest {
    private val json = LiveHarnessRemoteClient.defaultJson()

    @Test
    fun `decodes shared host describe response`() {
        val envelope = json.decodeFromString(
            RpcResponseEnvelope.serializer(),
            remoteFixture("host-describe.response.json"),
        )
        val value = RpcResponseValidator.successfulValue(envelope, "fixture-host-describe")
        val host = json.decodeFromJsonElement(HostDescriptionWire.serializer(), value)

        assertEquals("0.1.0-rc.8", host.version)
        assertEquals(2, host.attachedSessions)
    }

    @Test
    fun `rejects mismatched rpc identifier`() {
        val envelope = json.decodeFromString(
            RpcResponseEnvelope.serializer(),
            remoteFixture("host-describe.response.json"),
        )

        assertThrows(HarnessRemoteClientException.MismatchedResponse::class.java) {
            RpcResponseValidator.successfulValue(envelope, "another-rpc")
        }
    }

    @Test
    fun `surfaces stable api failure`() {
        val envelope = json.decodeFromString(
            RpcResponseEnvelope.serializer(),
            """{"rpcId":"failed","result":{"ok":false,"error":{"code":"host-offline","message":"Harness is offline"}}}""",
        )

        val error = assertThrows(HarnessRemoteClientException.Api::class.java) {
            RpcResponseValidator.successfulValue(envelope, "failed")
        }
        assertEquals("host-offline", error.code)
        assertEquals("Harness is offline", error.message)
    }

    @Test
    fun `decodes direct projection fixture for cross platform tolerance`() {
        val envelope = json.decodeFromString(
            RpcResponseEnvelope.serializer(),
            remoteFixture("session-list.response.json"),
        )
        val value = RpcResponseValidator.successfulValue(envelope, "fixture-session-list")
        val sessions = json.decodeFromJsonElement(SessionListWire.serializer(), value)

        assertEquals("Android parity fixture", sessions.items.single().projections?.values?.get("title").stringOrNull())
    }

    @Test
    fun `ignores unknown response fields`() {
        val envelope = json.decodeFromString(
            RpcResponseEnvelope.serializer(),
            remoteFixture("host-describe.response.json").replace(
                "\"attachedSessions\": 2",
                "\"attachedSessions\": 2, \"futureCapability\": true",
            ),
        )

        assertEquals("fixture-host-describe", envelope.rpcId)
    }
}
