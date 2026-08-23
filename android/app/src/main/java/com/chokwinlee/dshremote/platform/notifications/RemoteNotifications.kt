package com.chokwinlee.dshremote.platform.notifications

import android.Manifest
import android.app.Activity
import android.app.Application
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import com.chokwinlee.dshremote.R
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Process-local foreground signal. It intentionally makes no promise after process death. */
class AppForegroundTracker private constructor(
    private val application: Application,
) : Application.ActivityLifecycleCallbacks, AutoCloseable {
    private val counter = ForegroundActivityCounter()
    private val mutableIsForeground = MutableStateFlow(false)
    private val closed = AtomicBoolean(false)

    val isForeground: StateFlow<Boolean> = mutableIsForeground.asStateFlow()

    init {
        application.registerActivityLifecycleCallbacks(this)
    }

    override fun onActivityStarted(activity: Activity) {
        mutableIsForeground.value = counter.activityStarted()
    }

    override fun onActivityStopped(activity: Activity) {
        mutableIsForeground.value = counter.activityStopped()
    }

    override fun close() {
        if (closed.compareAndSet(false, true)) {
            application.unregisterActivityLifecycleCallbacks(this)
            counter.reset()
            mutableIsForeground.value = false
        }
    }

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit
    override fun onActivityResumed(activity: Activity) = Unit
    override fun onActivityPaused(activity: Activity) = Unit
    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
    override fun onActivityDestroyed(activity: Activity) = Unit

    companion object {
        fun install(application: Application): AppForegroundTracker = AppForegroundTracker(application)
    }
}

internal class ForegroundActivityCounter {
    private val startedActivities = AtomicInteger(0)

    fun activityStarted(): Boolean = startedActivities.incrementAndGet() > 0

    fun activityStopped(): Boolean {
        while (true) {
            val current = startedActivities.get()
            if (current == 0) return false
            if (startedActivities.compareAndSet(current, current - 1)) return current - 1 > 0
        }
    }

    fun reset() {
        startedActivities.set(0)
    }
}

data class RemoteTaskNotification(
    val stableKey: String,
    val sessionId: String? = null,
    val title: String,
    val body: String,
    val contentIntent: PendingIntent? = null,
    val alertOnlyOnce: Boolean = true,
)

enum class NotificationPostResult {
    POSTED,
    SUPPRESSED_IN_FOREGROUND,
    PERMISSION_REQUIRED,
    NOTIFICATIONS_DISABLED,
}

/**
 * Best-effort local notifications for live work observed while this process is running.
 * There is no background polling, push service, or claim of delivery after process death.
 */
class RemoteLocalNotificationManager(
    context: Context,
    private val smallIconResourceId: Int = R.drawable.ic_notification_remote,
    private val isAppForeground: () -> Boolean = { false },
    private val shouldSuppressInForeground: (RemoteTaskNotification) -> Boolean = {
        isAppForeground()
    },
    private val channelName: String = context.getString(R.string.notification_channel_name),
    private val channelDescription: String = context.getString(R.string.notification_channel_description),
    private val publicTitle: String = context.getString(R.string.notification_public_title),
    private val publicBody: String = context.getString(R.string.notification_public_body),
) {
    private val appContext = context.applicationContext
    private val notificationManager = appContext.getSystemService(NotificationManager::class.java)

    fun ensureChannel() {
        val channel = NotificationChannel(
            TASK_CHANNEL_ID,
            channelName,
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = channelDescription
            lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            setShowBadge(true)
        }
        notificationManager.createNotificationChannel(channel)
    }

    fun postTaskUpdate(
        update: RemoteTaskNotification,
        showWhileForeground: Boolean = false,
    ): NotificationPostResult {
        if (!showWhileForeground && shouldSuppressInForeground(update)) {
            return NotificationPostResult.SUPPRESSED_IN_FOREGROUND
        }
        notificationAvailability()?.let { return it }
        ensureChannel()

        val safeTitle = update.title.trim().take(MAX_TITLE_CHARACTERS)
        val safeBody = update.body.trim().take(MAX_BODY_CHARACTERS)
        val publicVersion = Notification.Builder(appContext, TASK_CHANNEL_ID)
            .setSmallIcon(smallIconResourceId)
            .setContentTitle(publicTitle)
            .setContentText(publicBody)
            .build()
        val notification = Notification.Builder(appContext, TASK_CHANNEL_ID)
            .setSmallIcon(smallIconResourceId)
            .setContentTitle(safeTitle)
            .setContentText(safeBody)
            .setStyle(Notification.BigTextStyle().bigText(safeBody))
            .setCategory(Notification.CATEGORY_STATUS)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setPublicVersion(publicVersion)
            .setAutoCancel(true)
            .setOnlyAlertOnce(update.alertOnlyOnce)
            .setWhen(System.currentTimeMillis())
            .setShowWhen(true)
            .apply { update.contentIntent?.let(::setContentIntent) }
            .build()

        notificationManager.notify(notificationId(update.stableKey), notification)
        return NotificationPostResult.POSTED
    }

    fun cancel(stableKey: String) {
        notificationManager.cancel(notificationId(stableKey))
    }

    fun cancelAll() {
        notificationManager.cancelAll()
    }

    private fun notificationAvailability(): NotificationPostResult? {
        if (Build.VERSION.SDK_INT >= 33 &&
            appContext.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return NotificationPostResult.PERMISSION_REQUIRED
        }
        if (!notificationManager.areNotificationsEnabled()) {
            return NotificationPostResult.NOTIFICATIONS_DISABLED
        }
        return null
    }

    internal fun notificationId(stableKey: String): Int = stableNotificationId(stableKey)

    companion object {
        const val TASK_CHANNEL_ID = "remote_task_updates_v1"
        private const val MAX_TITLE_CHARACTERS = 120
        private const val MAX_BODY_CHARACTERS = 1_000

        internal fun stableNotificationId(stableKey: String): Int = stableKey.hashCode() and Int.MAX_VALUE
    }
}

internal fun shouldSuppressTaskNotification(
    isAppForeground: Boolean,
    visibleSessionId: String?,
    updateSessionId: String?,
): Boolean = isAppForeground &&
    visibleSessionId != null &&
    visibleSessionId == updateSessionId
