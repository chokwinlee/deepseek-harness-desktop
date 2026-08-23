package com.chokwinlee.dshremote.app

import com.chokwinlee.dshremote.R
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ControlledApiErrorTest {
    @Test
    fun productOwnedApiCodesUseLocalizedResources() {
        assertEquals(R.string.remote_error_attachment_not_found, controlledApiErrorString("attachment-not-found"))
        assertEquals(R.string.remote_error_interaction_rejected, controlledApiErrorString("interaction-rejected"))
        assertEquals(R.string.remote_error_model_unavailable, controlledApiErrorString("model-unavailable"))
        assertEquals(R.string.remote_error_session_not_found, controlledApiErrorString("session-not-found"))
        assertEquals(R.string.remote_error_subagent_not_resumable, controlledApiErrorString("subagent-not-resumable"))
    }

    @Test
    fun unknownHostApiCodesRemainAvailableForVerbatimServerCopy() {
        assertNull(controlledApiErrorString("future-server-error"))
    }
}
