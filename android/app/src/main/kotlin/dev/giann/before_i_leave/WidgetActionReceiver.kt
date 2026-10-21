package dev.giann.before_i_leave

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.util.concurrent.Executors

/** Private receiver for immutable, per-row desired-state clicks. */
class WidgetActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != WidgetIntentContract.ACTION_SET_WIDGET_CHECKED) return
        val widgetId = intent.getIntExtra(WidgetIntentContract.EXTRA_WIDGET_ID, -1)
        val widgetKind = intent.getStringExtra(WidgetIntentContract.EXTRA_WIDGET_KIND)
        val scheduleId = intent.getStringExtra(WidgetIntentContract.EXTRA_SCHEDULE_ID)
        val generation = intent.getStringExtra(WidgetIntentContract.EXTRA_BINDING_GENERATION) ?: return
        val epoch = intent.getStringExtra(WidgetIntentContract.EXTRA_RENDER_EPOCH) ?: return
        val revision = intent.getLongExtra(WidgetIntentContract.EXTRA_RENDER_REVISION, -1L)
        val itemRevision = intent.getLongExtra(WidgetIntentContract.EXTRA_ITEM_RENDER_REVISION, -1L)
        val outingId = intent.getStringExtra(WidgetIntentContract.EXTRA_OUTING_ID) ?: return
        val itemId = intent.getStringExtra(WidgetIntentContract.EXTRA_ITEM_ID) ?: return
        val checked = intent.getBooleanExtra(WidgetIntentContract.EXTRA_DESIRED_CHECKED, false)
        if (widgetId < 0 || revision < 0L || itemRevision < 0L) return
        if ((widgetKind == WidgetIntentContract.KIND_SCHEDULED_CHECKLIST && scheduleId.isNullOrBlank()) ||
            (widgetKind != null && widgetKind != WidgetIntentContract.KIND_SCHEDULED_CHECKLIST)) return
        val pending = goAsync()
        worker.execute {
            try {
                val canonical = if (widgetKind == WidgetIntentContract.KIND_SCHEDULED_CHECKLIST && scheduleId != null) {
                    NativeStateStore.applyScheduledWidgetItemCheck(
                        context, widgetId, generation, epoch, revision, scheduleId, outingId, itemId, checked, itemRevision,
                    )
                } else if (widgetKind == null) {
                    NativeStateStore.applyWidgetItemCheck(
                        context, widgetId, generation, epoch, revision, outingId, itemId, checked, itemRevision,
                    )
                } else {
                    NativeStateStore.applyWidgetItemCheck(
                        context, widgetId, generation, epoch, revision, outingId, itemId, checked, itemRevision,
                    )
                }
                ChecklistScheduleScheduler.refresh(context)
                main.post {
                    runCatching { NativeStateChangeNotifier.notify(canonical) }
                        .onFailure { Log.w(TAG, "Could not notify the active app after a widget check.", it) }
                    runCatching { WidgetRenderService.refreshAllKinds(context.applicationContext, pending) }
                        .onFailure { error ->
                            Log.e(TAG, "Could not refresh widgets after a checklist action.", error)
                            pending.finish()
                        }
                }
            } catch (error: Exception) {
                Log.e(TAG, "Could not apply the widget checklist action.", error)
                main.post {
                    runCatching { WidgetRenderService.refreshAllKinds(context.applicationContext, pending) }
                        .onFailure { refreshError ->
                            Log.e(TAG, "Could not refresh widgets after a rejected checklist action.", refreshError)
                            pending.finish()
                        }
                }
            }
        }
    }

    companion object {
        private const val TAG = "BeforeILeaveWidget"
        private val worker = Executors.newSingleThreadExecutor { task -> Thread(task, "before-i-leave-widget-check").apply { isDaemon = true } }
        private val main = Handler(Looper.getMainLooper())
    }
}
