package com.chokwinlee.dshremote.platform.scanner

import com.chokwinlee.dshremote.remote.RemoteEndpointError
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CameraPairingScannerTest {
    private val validPayload =
        "harnessremote://connect?url=https%3A%2F%2Fstudio.tailnet.ts.net%2F"

    @Test
    fun validPairingPausesBeforeDeliveringAndOnlyDeliversOnce() {
        val events = mutableListOf<String>()
        val dispatcher = PairingScanResultDispatcher(
            controller = PairingScanController(),
            pauseCamera = { events += "paused" },
            onAccepted = { events += "accepted:${it.baseUrl}" },
            onRejected = { events += "rejected:$it" },
        )

        dispatcher.start()
        val first = dispatcher.dispatch(validPayload)
        val second = dispatcher.dispatch(validPayload)

        assertTrue(first is PairingScanResult.Accepted)
        assertEquals(PairingScanResult.Inactive, second)
        assertEquals(
            listOf("paused", "accepted:https://studio.tailnet.ts.net/"),
            events,
        )
    }

    @Test
    fun rejectedCodeLeavesCameraRunningForNextValidCode() {
        val events = mutableListOf<String>()
        val dispatcher = PairingScanResultDispatcher(
            controller = PairingScanController(),
            pauseCamera = { events += "paused" },
            onAccepted = { events += "accepted" },
            onRejected = { events += "rejected:$it" },
        )

        dispatcher.start()
        val rejected = dispatcher.dispatch("not a pairing code")
        val accepted = dispatcher.dispatch(validPayload)

        assertEquals(
            RemoteEndpointError.INVALID_URL,
            (rejected as PairingScanResult.Rejected).reason,
        )
        assertTrue(accepted is PairingScanResult.Accepted)
        assertEquals(
            listOf("rejected:INVALID_URL", "paused", "accepted"),
            events,
        )
    }

    @Test
    fun stopMakesLateCameraResultInactive() {
        var acceptedCount = 0
        val dispatcher = PairingScanResultDispatcher(
            controller = PairingScanController(),
            pauseCamera = {},
            onAccepted = { acceptedCount += 1 },
            onRejected = {},
        )

        dispatcher.start()
        dispatcher.stop()

        assertEquals(PairingScanResult.Inactive, dispatcher.dispatch(validPayload))
        assertEquals(0, acceptedCount)
    }
}
