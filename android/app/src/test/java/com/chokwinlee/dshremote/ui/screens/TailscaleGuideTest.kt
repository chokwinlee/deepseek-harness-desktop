package com.chokwinlee.dshremote.ui.screens

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TailscaleGuideTest {
    @Test
    fun guideCoversInstallAdminDnsCertificatesServeAndCellularAcceptance() {
        assertEquals(5, tailscaleGuideSteps.size)

        val urls = tailscaleGuideSteps.flatMap { step -> step.links.map { it.url } }
        assertEquals(urls.size, urls.distinct().size)
        assertTrue(urls.contains("https://tailscale.com/docs/install/android"))
        assertTrue(urls.contains("https://login.tailscale.com/admin/machines"))
        assertTrue(urls.contains("https://login.tailscale.com/admin/dns"))
        assertTrue(urls.contains("https://tailscale.com/docs/how-to/set-up-https-certificates"))
        assertTrue(urls.contains("https://tailscale.com/docs/features/tailscale-serve"))
        assertTrue(tailscaleGuideSteps.last().links.isEmpty())
    }
}
