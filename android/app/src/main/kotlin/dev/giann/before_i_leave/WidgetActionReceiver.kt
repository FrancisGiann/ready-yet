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
        val generation = intent.getStringExtra(WidgetIntentContract.EXTRA_BINDING_GENERATION) ?: return
        val epoch = intent.getStringExtra(WidgetIntentContract.EXTRA_RENDER_EPOCH) ?: return
        val revision = intent.getLongExtra(WidgetIntentContract.EXTRA_RENDER_REVISION, -1L)
        val itemRevision = intent.getLongExtra(WidgetIntentContract.EXTRA_ITEM_RENDER_REVISION, -1L)
        val outingId = intent.getStringExtra(WidgetIntentContract.EXTRA_OUTING_ID) ?: return
        val itemId = intent.getStringExtra(WidgetIntentContract.EXTRA_ITEM_ID) ?: return
        val checked = intent.getBooleanExtra(WidgetIntentContract.EXTRA_DESIRED_CHECKED, false)
        if (widgetId < 0 || revision < 0L || itemRevision < 0L) return
        val pending = goAsync()
        worker.execute {
            try {
                val canonical = NativeStateStore.applyWidgetItemCheck(
                    context, widgetId, generation, epoch, revision, outingId, itemId, checked, itemRevision,
                )
                main.post {
                    runCatching { NativeStateChangeNotifier.notify(canonical) }
                        .onFailure { Log.w(TAG, "Could not notify the active app after a widget check.", it) }
                    runCatching { LeaveWidgetProvider.refreshAll(context) }
                    runCatching { QuickListsWidgetProvider.refreshAll(context) }
                    pending.finish()
                }
            } catch (error: Exception) {
                Log.e(TAG, "Could not apply the widget checklist action.", error)
                main.post {
                    runCatching { LeaveWidgetProvider.refreshAll(context) }
                    pending.finish()
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
