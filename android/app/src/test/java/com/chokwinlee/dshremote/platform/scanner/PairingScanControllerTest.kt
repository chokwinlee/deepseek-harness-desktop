package com.chokwinlee.dshremote.platform.scanner

import com.chokwinlee.dshremote.remote.RemoteEndpointError
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PairingScanControllerTest {
    private val validPayload =
        "harnessremote://connect?url=https%3A%2F%2Fstudio.tailnet.ts.net%2F"

    @Test
    fun acceptsOnlyOneConnectionPerScanSession() {
        val controller = PairingScanController()
        controller.start()

        assertTrue(controller.onDecoded(validPayload) is PairingScanResult.Accepted)
        assertEquals(PairingScanPhase.COMPLETED, controller.state.phase)
        assertEquals(PairingScanResult.Inactive, controller.onDecoded(validPayload))
    }

    @Test
    fun invalidPayloadKeepsScannerActiveAndIsDebounced() {
        var time = 1_000L
        val controller = PairingScanController(clockMillis = { time })
        controller.start()

        val first = controller.onDecoded("not a pairing code")
        time += 200
        val second = controller.onDecoded("not a pairing code")

        assertEquals(
            RemoteEndpointError.INVALID_URL,
            (first as PairingScanResult.Rejected).reason,
        )
        assertEquals(PairingScanResult.Duplicate, second)
        assertEquals(PairingScanPhase.SCANNING, controller.state.phase)
    }

    @Test
    fun restartAllowsASecondValidScan() {
        val controller = PairingScanController()
        controller.start()
        controller.onDecoded(validPayload)
        controller.start()

        assertTrue(controller.onDecoded(validPayload) is PairingScanResult.Accepted)
    }
}
