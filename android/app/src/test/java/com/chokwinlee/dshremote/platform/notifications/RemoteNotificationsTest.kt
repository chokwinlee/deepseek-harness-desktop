package com.chokwinlee.dshremote.platform.notifications

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RemoteNotificationsTest {
    @Test
    fun foregroundCounterHandlesOverlappingActivities() {
        val counter = ForegroundActivityCounter()

        assertTrue(counter.activityStarted())
        assertTrue(counter.activityStarted())
        assertTrue(counter.activityStopped())
        assertFalse(counter.activityStopped())
        assertFalse(counter.activityStopped())
    }

    @Test
    fun notificationIdsAreStableAndNonNegative() {
        val first = RemoteLocalNotificationManager.stableNotificationId("session-123")
        val second = RemoteLocalNotificationManager.stableNotificationId("session-123")

        assertEquals(first, second)
        assertTrue(first >= 0)
    }

    @Test
    fun foregroundSuppressionOnlyAppliesToTheVisibleSession() {
        assertTrue(shouldSuppressTaskNotification(true, "session-1", "session-1"))
        assertFalse(shouldSuppressTaskNotification(true, "session-1", "session-2"))
        assertFalse(shouldSuppressTaskNotification(true, null, "session-1"))
        assertFalse(shouldSuppressTaskNotification(false, "session-1", "session-1"))
    }
}
