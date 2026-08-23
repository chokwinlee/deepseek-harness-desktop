package com.chokwinlee.dshremote.platform.scanner

import com.chokwinlee.dshremote.platform.navigation.RemoteDeepLinkParser
import com.chokwinlee.dshremote.platform.navigation.RemoteDeepLinkResult
import com.chokwinlee.dshremote.remote.RemoteConnectionDescriptor
import com.chokwinlee.dshremote.remote.RemoteEndpointError

enum class PairingScanPhase {
    IDLE,
    SCANNING,
    COMPLETED,
}

data class PairingScanState(
    val phase: PairingScanPhase = PairingScanPhase.IDLE,
    val lastError: RemoteEndpointError? = null,
)

sealed interface PairingScanResult {
    data class Accepted(val connection: RemoteConnectionDescriptor) : PairingScanResult
    data class Rejected(val reason: RemoteEndpointError) : PairingScanResult
    data object Duplicate : PairingScanResult
    data object Inactive : PairingScanResult
}

/**
 * Pure scanner gate: exactly one valid result is accepted for each scan session.
 * CameraX/ML Kit (or another camera implementation) can feed decoded strings into it.
 */
class PairingScanController(
    private val clockMillis: () -> Long = System::currentTimeMillis,
    private val duplicateWindowMillis: Long = 1_500,
    private val parser: (String?) -> RemoteDeepLinkResult = RemoteDeepLinkParser::parse,
) {
    init {
        require(duplicateWindowMillis >= 0)
    }

    var state: PairingScanState = PairingScanState()
        private set

    private var lastPayload: String? = null
    private var lastPayloadAt: Long = Long.MIN_VALUE

    @Synchronized
    fun start() {
        lastPayload = null
        lastPayloadAt = Long.MIN_VALUE
        state = PairingScanState(phase = PairingScanPhase.SCANNING)
    }

    @Synchronized
    fun stop() {
        state = PairingScanState(phase = PairingScanPhase.IDLE)
    }

    @Synchronized
    fun onDecoded(payload: String): PairingScanResult {
        if (state.phase != PairingScanPhase.SCANNING) return PairingScanResult.Inactive

        val normalized = payload.trim()
        val now = clockMillis()
        val elapsed = if (lastPayloadAt == Long.MIN_VALUE) Long.MAX_VALUE else now - lastPayloadAt
        if (normalized == lastPayload && elapsed in 0..duplicateWindowMillis) {
            return PairingScanResult.Duplicate
        }
        lastPayload = normalized
        lastPayloadAt = now

        return when (val parsed = parser(normalized)) {
            is RemoteDeepLinkResult.Connection -> {
                state = PairingScanState(phase = PairingScanPhase.COMPLETED)
                PairingScanResult.Accepted(parsed.descriptor)
            }
            is RemoteDeepLinkResult.Rejected -> {
                state = PairingScanState(
                    phase = PairingScanPhase.SCANNING,
                    lastError = parsed.reason,
                )
                PairingScanResult.Rejected(parsed.reason)
            }
        }
    }
}

/** Camera boundary implemented by the lifecycle-bound CameraX/ML Kit pairing scanner. */
interface PairingQrCamera : AutoCloseable {
    fun start(
        onDecoded: (String) -> Unit,
        onFailure: (Throwable) -> Unit,
    )

    fun stop()

    override fun close() = stop()
}
