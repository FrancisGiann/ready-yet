package dev.giann.before_i_leave

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

internal class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ReminderScheduler.ACTION_REMINDER) return
        val scheduledAt = ReminderScheduler.scheduledAt(intent)
        if (scheduledAt <= 0L) return
        try {
            ReminderScheduler.scheduleAfterDelivery(context, scheduledAt, System.currentTimeMillis())
        } catch (error: Exception) {
            Log.e("ReadyYetReminder", "Could not complete reminder delivery.", error)
        }
    }
}

internal class ReminderRescheduleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_DATE_CHANGED,
            "android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED" -> {
                ReminderScheduler.rescheduleIfEnabled(context,
                    force = ReminderReschedulePolicy.shouldForceForAction(intent.action))
                val pending = goAsync()
                ChecklistScheduleScheduler.enqueue(context, pending) {
                    WidgetRenderService.refreshAllKinds(context.applicationContext, pending)
                }
            }
        }
    }
}

internal object ReminderNotifications {
    fun show(context: Context) {
        if (!ReminderScheduler.canNotify(context)) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val contentIntent = PendingIntent.getActivity(
            context,
            7713,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(context, ReminderScheduler.NOTIFICATION_CHANNEL_ID)
        } else {
            Notification.Builder(context)
        }.setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("Ready Yet?")
            .setContentText("Before I Leave: take a quick look at what you need to pack today.")
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .build()
        manager.notify(ReminderScheduler.NOTIFICATION_ID, notification)
    }
}
