package dev.giann.before_i_leave

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import java.io.IOException
internal object ReminderScheduler {
    private const val PREFS = "before_i_leave_reminders"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_HOUR = "hour"
    private const val KEY_MINUTE = "minute"
    private const val KEY_SCHEDULED_AT = "scheduled_at"
    private const val KEY_LAST_DELIVERED_AT = "last_delivered_at"
    const val NOTIFICATION_CHANNEL_ID = "daily_packing_reminder"
    const val NOTIFICATION_ID = 7711
    const val ACTION_REMINDER = "dev.giann.before_i_leave.DAILY_REMINDER"
    private const val ALARM_REQUEST_CODE = 7712
    private const val TAG = "BeforeILeaveReminder"
    private var lastInstalledAt = 0L

    fun configure(context: Context, hour: Int, minute: Int, enabled: Boolean): Map<String, Any?> {
        require(hour in 0..23 && minute in 0..59) { "Choose a valid local time." }
        val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val previous = ReminderConfiguration.snapshot(preferences)
        val granted = canNotify(context)
        val allowed = enabled && granted
        val scheduledAt = if (allowed) {
            ReminderTimeCalculator.nextTriggerAt(System.currentTimeMillis(), hour, minute)
        } else {
            null
        }
        val editor = preferences.edit()
            .putInt(KEY_HOUR, hour)
            .putInt(KEY_MINUTE, minute)
            .putBoolean(KEY_ENABLED, allowed)
        if (scheduledAt == null) editor.remove(KEY_SCHEDULED_AT)
        else editor.putLong(KEY_SCHEDULED_AT, scheduledAt)
        if (!editor.commit()) {
            val failure = IOException("Could not save reminder settings.")
            restoreAfterConfigurationFailure(context, preferences, previous, failure)
            throw failure
        }
        try {
            if (scheduledAt != null) installAlarm(context, scheduledAt)
            else cancelAlarm(context)
            return status(context, requestedButBlocked = enabled && !granted)
        } catch (failure: Exception) {
            restoreAfterConfigurationFailure(context, preferences, previous, failure)
            throw failure
        }
    }

    fun status(context: Context): Map<String, Any?> = status(context, requestedButBlocked = false)

    private fun status(context: Context, requestedButBlocked: Boolean): Map<String, Any?> {
        val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val allowed = canNotify(context)
        val storedEnabled = preferences.getBoolean(KEY_ENABLED, false)
        val storedAt = preferences.getLong(KEY_SCHEDULED_AT, 0L)
        val alarmInstalled = storedEnabled && allowed && storedAt > 0L && lastInstalledAt == storedAt
        val enabled = storedEnabled && allowed && alarmInstalled
        val hour = preferences.getInt(KEY_HOUR, 9)
        val minute = preferences.getInt(KEY_MINUTE, 0)
        val scheduledAt = storedAt.takeIf { enabled }
        val unavailableReason = if (Build.VERSION.SDK_INT >= 33) "permission_required" else "notifications_disabled"
        val status = when {
            requestedButBlocked || !allowed -> unavailableReason
            enabled -> "scheduled"
            storedEnabled -> "schedule_unavailable"
            else -> "disabled"
        }
        return mapOf(
            "enabled" to enabled,
            "scheduled" to (enabled && scheduledAt != null),
            "permissionGranted" to allowed,
            "permissionRequired" to (Build.VERSION.SDK_INT >= 33 && !allowed),
            "reason" to when {
                requestedButBlocked || !allowed -> unavailableReason
                storedEnabled && !alarmInstalled -> "schedule_unavailable"
                else -> null
            },
            "status" to status,
            "hour" to hour,
            "minute" to minute,
            "nextAlarmAt" to scheduledAt,
        )
    }

    fun canNotify(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return false
        if (Build.VERSION.SDK_INT >= 24) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            createNotificationChannel(context, manager)
            if (!manager.areNotificationsEnabled()) return false
            if (Build.VERSION.SDK_INT >= 26 && manager.getNotificationChannel(NOTIFICATION_CHANNEL_ID)?.importance == NotificationManager.IMPORTANCE_NONE) {
                return false
            }
        }
        return true
    }

    fun rescheduleIfEnabled(context: Context, force: Boolean = false) {
        try {
            rescheduleIfEnabledOrThrow(context, force)
        } catch (error: Exception) {
            lastInstalledAt = 0L
            Log.e(TAG, "Could not restore the scheduled reminder.", error)
        }
    }

    private fun rescheduleIfEnabledOrThrow(context: Context, force: Boolean) {
        val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!preferences.getBoolean(KEY_ENABLED, false)) return
        if (!canNotify(context)) {
            preferences.edit().putBoolean(KEY_ENABLED, false).remove(KEY_SCHEDULED_AT).apply()
            cancel(context)
            return
        }
        val scheduledAt = preferences.getLong(KEY_SCHEDULED_AT, 0L)
        val now = System.currentTimeMillis()
        if (ReminderReschedulePolicy.shouldReuseStoredAlarm(scheduledAt, now, force)) {
            // Reinstall the same immutable PendingIntent as well: Android clears
            // alarms on force-stop, while this preference survives the stop.
            installAt(context, scheduledAt)
            return
        }
        scheduleNext(context)
    }

    fun scheduleAfterDelivery(context: Context, expectedAt: Long, now: Long) {
        val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!preferences.getBoolean(KEY_ENABLED, false)) return
        if (preferences.getLong(KEY_SCHEDULED_AT, 0L) != expectedAt) return

        val fresh = ReminderTimeCalculator.isFreshDelivery(expectedAt, now)
        val duplicate = preferences.getLong(KEY_LAST_DELIVERED_AT, 0L) == expectedAt
        if (fresh && !duplicate && canNotify(context)) {
            if (preferences.edit().putLong(KEY_LAST_DELIVERED_AT, expectedAt).commit()) {
                runCatching { ReminderNotifications.show(context) }
                    .onFailure { Log.e(TAG, "Could not show the reminder notification.", it) }
            } else {
                Log.e(TAG, "Could not record reminder delivery; skipping this notification.")
            }
        } else if (!canNotify(context)) {
            preferences.edit().putBoolean(KEY_ENABLED, false).remove(KEY_SCHEDULED_AT).apply()
            cancel(context)
            return
        }
        scheduleNext(context)
    }

    private fun scheduleNext(context: Context) {
        val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!preferences.getBoolean(KEY_ENABLED, false)) return
        val hour = preferences.getInt(KEY_HOUR, 9)
        val minute = preferences.getInt(KEY_MINUTE, 0)
        val nextAt = ReminderTimeCalculator.nextTriggerAt(System.currentTimeMillis(), hour, minute)
        installAt(context, nextAt, forceInstall = true)
    }

    private fun installAt(context: Context, scheduledAt: Long, forceInstall: Boolean = false) {
        if (!forceInstall && lastInstalledAt == scheduledAt) return
        lastInstalledAt = 0L
        val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!preferences.edit().putLong(KEY_SCHEDULED_AT, scheduledAt).commit()) {
            throw IOException("Could not save the scheduled reminder time.")
        }
        installAlarm(context, scheduledAt)
    }

    private fun installAlarm(context: Context, scheduledAt: Long) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val operation = pendingIntent(context, scheduledAt)
        alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, scheduledAt, operation)
        lastInstalledAt = scheduledAt
    }

    private fun cancel(context: Context) {
        cancelAlarm(context)
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(KEY_SCHEDULED_AT).apply()
    }

    private fun cancelAlarm(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.cancel(pendingIntent(context, 0L))
        lastInstalledAt = 0L
    }

    private fun restoreAfterConfigurationFailure(
        context: Context,
        preferences: android.content.SharedPreferences,
        previous: ReminderConfiguration,
        originalFailure: Exception,
    ) {
        val restored = previous.restore(preferences).commit()
        if (!restored) {
            originalFailure.addSuppressed(IOException("Could not restore the previous reminder settings."))
            Log.e(TAG, "Could not restore the previous reminder settings.", originalFailure)
        }

        lastInstalledAt = 0L
        try {
            if (previous.enabled && canNotify(context)) {
                val now = System.currentTimeMillis()
                val restoreAt = if (ReminderReschedulePolicy.shouldReuseStoredAlarm(previous.scheduledAt, now, false)) {
                    previous.scheduledAt
                } else {
                    ReminderTimeCalculator.nextTriggerAt(now, previous.hour, previous.minute)
                }
                installAt(context, restoreAt, forceInstall = true)
            } else {
                cancelAlarm(context)
            }
        } catch (rollbackFailure: Exception) {
            lastInstalledAt = 0L
            originalFailure.addSuppressed(rollbackFailure)
            Log.e(TAG, "Could not restore the previous reminder alarm.", rollbackFailure)
        }
    }

    private data class ReminderConfiguration(
        val enabled: Boolean,
        val hour: Int,
        val minute: Int,
        val scheduledAt: Long,
        private val hasEnabled: Boolean,
        private val hasHour: Boolean,
        private val hasMinute: Boolean,
        private val hasScheduledAt: Boolean,
    ) {
        fun restore(preferences: android.content.SharedPreferences): android.content.SharedPreferences.Editor {
            val editor = preferences.edit()
            if (hasEnabled) editor.putBoolean(KEY_ENABLED, enabled) else editor.remove(KEY_ENABLED)
            if (hasHour) editor.putInt(KEY_HOUR, hour) else editor.remove(KEY_HOUR)
            if (hasMinute) editor.putInt(KEY_MINUTE, minute) else editor.remove(KEY_MINUTE)
            if (hasScheduledAt) editor.putLong(KEY_SCHEDULED_AT, scheduledAt) else editor.remove(KEY_SCHEDULED_AT)
            return editor
        }

        companion object {
            fun snapshot(preferences: android.content.SharedPreferences) = ReminderConfiguration(
                enabled = preferences.getBoolean(KEY_ENABLED, false),
                hour = preferences.getInt(KEY_HOUR, 9),
                minute = preferences.getInt(KEY_MINUTE, 0),
                scheduledAt = preferences.getLong(KEY_SCHEDULED_AT, 0L),
                hasEnabled = preferences.contains(KEY_ENABLED),
                hasHour = preferences.contains(KEY_HOUR),
                hasMinute = preferences.contains(KEY_MINUTE),
                hasScheduledAt = preferences.contains(KEY_SCHEDULED_AT),
            )
        }
    }

    fun scheduledAt(intent: Intent): Long = intent.getLongExtra(KEY_SCHEDULED_AT, 0L)

    fun alarmIntent(context: Context, scheduledAt: Long): Intent =
        Intent(context, ReminderReceiver::class.java).apply {
            action = ACTION_REMINDER
            putExtra(KEY_SCHEDULED_AT, scheduledAt)
        }

    private fun pendingIntent(context: Context, scheduledAt: Long): PendingIntent = PendingIntent.getBroadcast(
        context,
        ALARM_REQUEST_CODE,
        alarmIntent(context, scheduledAt),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun createNotificationChannel(context: Context, manager: NotificationManager) {
        if (Build.VERSION.SDK_INT >= 26 && manager.getNotificationChannel(NOTIFICATION_CHANNEL_ID) == null) {
            manager.createNotificationChannel(
                NotificationChannel(
                    NOTIFICATION_CHANNEL_ID,
                    "Packing reminders",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply { description = "A gentle reminder to check your outing list." },
            )
        }
    }
}
