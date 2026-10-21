package dev.giann.before_i_leave

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log
import org.json.JSONObject
import java.util.Calendar
import java.util.UUID
import java.util.concurrent.Executors

/** One next-event alarm; no polling service, location, or repeating alarm. */
internal object ChecklistScheduleScheduler {
    const val WAKE = "dev.giann.before_i_leave.SCHEDULE_WAKE"
    const val OPEN = "dev.giann.before_i_leave.SCHEDULE_OPEN"
    const val SNOOZE = "dev.giann.before_i_leave.SCHEDULE_SNOOZE"
    const val SKIP = "dev.giann.before_i_leave.SCHEDULE_SKIP"
    private const val PREFS = "checklist_schedule_alarms"
    private const val LEDGER = "_scheduleReminderState"
    private const val REQUEST = 7820
    private val worker = Executors.newSingleThreadExecutor { task -> Thread(task, "ready-yet-schedules").apply { isDaemon = true } }

    fun enqueue(
        context: Context,
        pending: BroadcastReceiver.PendingResult? = null,
        after: (() -> Unit)? = null,
    ) {
        worker.execute {
            try { refresh(context.applicationContext) } finally {
                if (after == null) pending?.finish()
                else runCatching(after).onFailure { error ->
                    Log.e("ReadyYetSchedules", "Could not refresh widgets after schedule update", error)
                    pending?.finish()
                }
            }
        }
    }

    fun status(context: Context): Map<String, Any?> {
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return mapOf("precise" to (Build.VERSION.SDK_INT < 31 || alarm.canScheduleExactAlarms()),
            "error" to context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("error", null))
    }

    private data class Event(val schedule: ChecklistSchedule, val date: String, val departure: Long, val reminder: Long) {
        val id get() = schedule.occurrenceId(date)
        val deadline get() = ScheduleTimePolicy.deliveryDeadline(departure, schedule.leadMinutes)
    }

    private fun events(root: JSONObject, now: Long): List<Event> = buildList {
        val blueprintIds = ChecklistScheduleState.objects(root.optJSONArray("blueprints")).map { it.optString("id") }.toSet()
        for (schedule in ChecklistScheduleState.schedules(root).filter { it.enabled && it.blueprintId in blueprintIds }) {
            for (offset in -1..7) {
                val date = Calendar.getInstance(java.util.TimeZone.getDefault(), java.util.Locale.US).apply { timeInMillis = now; add(Calendar.DAY_OF_MONTH, offset) }
                if (ScheduleTimePolicy.isoWeekday(date) !in schedule.weekdays) continue
                val departure = schedule.departure(date)
                if (ScheduleTimePolicy.deliveryDeadline(departure, schedule.leadMinutes) < now) continue
                add(Event(schedule, ChecklistScheduleState.dateKey(date), departure,
                    ScheduleTimePolicy.reminderAt(departure, schedule.leadMinutes)))
            }
        }
    }

    @Synchronized fun refresh(context: Context) {
        try { refreshOrThrow(context) } catch (error: Exception) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString("error", "Reminder scheduling is unavailable. Open the app to try again.").apply()
            Log.e("ReadyYetSchedules", "Could not restore schedule reminders", error)
        }
    }

    private fun refreshOrThrow(context: Context) {
        val now = System.currentTimeMillis()
        // Materialization and due-event selection share one clock sample.
        val state = NativeStateStore.readState(context, now)?.let(::JSONObject) ?: return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val allowed = ReminderScheduler.canNotify(context)
        val candidates = events(state, now)
        val outings = ChecklistScheduleState.objects(state.optJSONArray("outings")).associateBy { it.optString("id") }
        val eligibleIds = candidates.filter { event ->
            val outing = outings[event.id]
            outing == null || incomplete(outing)
        }.map { it.id }.toSet()
        // Completion, skip, pause, deletion and departure expiry remove an
        // already visible reminder as well as its future delivery.
        manager.activeNotifications.filter { it.tag?.startsWith("scheduled:") == true && (!allowed || it.tag !in eligibleIds) }
            .forEach { manager.cancel(it.tag, it.id) }

        var next = Calendar.getInstance(java.util.TimeZone.getDefault(), java.util.Locale.US).apply {
            timeInMillis = now; add(Calendar.DAY_OF_MONTH, 1)
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }.timeInMillis
        val needsAlarm = candidates.isNotEmpty()
        // Scheduled checklist metadata changes at each local departure even
        // when notifications are blocked. Reuse this single next-event alarm;
        // it is not a countdown or polling loop.
        candidates.filter { it.departure > now }.minByOrNull { it.departure }?.let { event ->
            next = minOf(next, event.departure)
        }
        if (allowed) for (event in candidates) {
            val outing = outings[event.id]
            if (outing != null && !incomplete(outing)) continue
            next = minOf(next, event.deadline + 1000L)
            val ledger = state.optJSONObject(LEDGER)?.optJSONObject(event.id)
            val snoozeAt = ledger?.optLong("snoozeAt", 0L) ?: 0L
            if (ledger?.optBoolean("delivered", false) == true && snoozeAt == 0L) continue
            val trigger = if (snoozeAt > 0L) snoozeAt else event.reminder
            if (trigger > event.departure) continue
            if (now >= trigger) {
                if (outing != null) deliver(context, event, now)
                // A tomorrow pre-midnight occurrence is created atomically by
                // readState before it can be delivered.
            } else next = minOf(next, trigger)
        }
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!needsAlarm) {
            alarm.cancel(wakeOperation(context, ""))
            preferences.edit().remove("token").remove("error").apply()
            return
        }
        // Extras carry a generation; queued alarms from old configurations
        // cannot deliver a second notification after an edit or reboot.
        val token = UUID.randomUUID().toString()
        check(preferences.edit().putString("token", token).putLong("at", next).remove("error").commit())
        val operation = wakeOperation(context, token)
        if (Build.VERSION.SDK_INT < 31 || alarm.canScheduleExactAlarms()) {
            try { alarm.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, operation) }
            catch (_: SecurityException) { alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, operation) }
        } else alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, operation)
    }

    private fun incomplete(outing: JSONObject): Boolean {
        val items = ChecklistScheduleState.objects(outing.optJSONArray("items"))
        return ChecklistScheduleState.active(outing) && items.any { !it.optBoolean("checked") }
    }

    private fun deliver(context: Context, event: Event, now: Long) {
        var delivered: Pair<JSONObject, JSONObject>? = null
        val canonical = NativeStateStore.updateScheduleState(context) { latest ->
            if (ChecklistScheduleState.schedules(latest).none { it == event.schedule }) return@updateScheduleState false
            val outing = ChecklistScheduleState.objects(latest.optJSONArray("outings")).firstOrNull { it.optString("id") == event.id }
                ?: return@updateScheduleState false
            val total = outing.getJSONArray("items").length()
            val checked = ChecklistScheduleState.objects(outing.getJSONArray("items")).count { it.optBoolean("checked") }
            val all = latest.optJSONObject(LEDGER) ?: JSONObject().also { latest.put(LEDGER, it) }
            val record = all.optJSONObject(event.id) ?: JSONObject().also { all.put(event.id, it) }
            val snoozeAt = record.optLong("snoozeAt", 0L)
            if (record.optBoolean("delivered", false) && snoozeAt == 0L) return@updateScheduleState false
            if (!ScheduleTimePolicy.mayRemind(now, if (snoozeAt > 0) snoozeAt else event.reminder,
                    event.deadline, ChecklistScheduleState.active(outing), total, checked)) return@updateScheduleState false
            record.put("delivered", true).put("snoozeAt", 0L).put("token", UUID.randomUUID().toString()).remove("actedToken")
            delivered = JSONObject(latest.toString()) to JSONObject(outing.toString())
            true
        }
        if (canonical == null) return
        delivered?.let { (root, _) ->
            // Recheck under the state lock so a concurrent completion, pause or
            // reset cannot commit between eligibility and notification posting.
            NativeStateStore.updateScheduleState(context) { latest ->
                val token = root.getJSONObject(LEDGER).getJSONObject(event.id).getString("token")
                if (latest.optString("_storageEpoch") != root.optString("_storageEpoch") ||
                    latest.optJSONObject(LEDGER)?.optJSONObject(event.id)?.optString("token") != token ||
                    ChecklistScheduleState.schedules(latest).none { it == event.schedule }) return@updateScheduleState false
                val outing = ChecklistScheduleState.objects(latest.optJSONArray("outings")).firstOrNull { it.optString("id") == event.id }
                    ?: return@updateScheduleState false
                if (incomplete(outing) && System.currentTimeMillis() <= event.deadline) {
                    runCatching { show(context, latest, outing, event) }
                        .onFailure { Log.e("ReadyYetSchedules", "Could not display a schedule reminder", it) }
                }
                false
            }
        }
    }

    private fun show(context: Context, root: JSONObject, outing: JSONObject, event: Event) {
        if (!ReminderScheduler.canNotify(context)) return
        val token = root.getJSONObject(LEDGER).getJSONObject(event.id).getString("token")
        val epoch = root.getString("_storageEpoch")
        fun intent(action: String) = Intent(context, if (action == OPEN) MainActivity::class.java else ChecklistScheduleReceiver::class.java).apply {
            this.action = action
            data = Uri.Builder().scheme("readyyet").authority("schedule").appendPath(event.id).appendPath(action).appendPath(token).build()
            putExtra("outingId", event.id); putExtra("epoch", epoch); putExtra("token", token)
        }
        fun action(action: String): PendingIntent = if (action == OPEN) PendingIntent.getActivity(context, 0,
            intent(action).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            else PendingIntent.getBroadcast(context, 0, intent(action), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val items = ChecklistScheduleState.objects(outing.optJSONArray("items"))
        val remaining = items.count { !it.optBoolean("checked") }
        val time = String.format(java.util.Locale.getDefault(), "%02d:%02d", event.schedule.departureMinute / 60, event.schedule.departureMinute % 60)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, ReminderScheduler.NOTIFICATION_CHANNEL_ID) else Notification.Builder(context)
        val notification = builder.setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("${outing.getString("blueprintName")} · Leave at $time")
            .setContentText("$remaining of ${items.size} still to pack")
            .setContentIntent(action(OPEN)).setAutoCancel(true)
            .addAction(Notification.Action.Builder(R.drawable.ic_notification, "Open checklist", action(OPEN)).build())
            .apply {
                if (ScheduleTimePolicy.snoozeUntil(System.currentTimeMillis(), event.departure) > 0L)
                    addAction(Notification.Action.Builder(R.drawable.ic_notification, "Snooze 5 min", action(SNOOZE)).build())
            }
            .addAction(Notification.Action.Builder(R.drawable.ic_notification, "Skip today", action(SKIP)).build())
            .build()
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(event.id, REQUEST, notification)
    }

    fun handle(context: Context, intent: Intent) {
        if (intent.action == WAKE) {
            if (intent.getStringExtra("token") != context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("token", null)) return
        } else if (intent.action == SNOOZE || intent.action == SKIP) {
            val now = System.currentTimeMillis()
            val id = intent.getStringExtra("outingId") ?: return
            val token = intent.getStringExtra("token") ?: return
            var acted = false
            var tooClose = false
            val canonical = NativeStateStore.updateScheduleState(context) { root ->
                val event = events(root, now).firstOrNull { it.id == id } ?: return@updateScheduleState false
                val outing = ChecklistScheduleState.objects(root.optJSONArray("outings")).firstOrNull { it.optString("id") == id }
                    ?: return@updateScheduleState false
                val record = root.optJSONObject(LEDGER)?.optJSONObject(id) ?: return@updateScheduleState false
                if (!ScheduleActionPolicy.mayHandle(intent.getStringExtra("epoch"), root.optString("_storageEpoch"),
                        token, record.optString("token"), record.optString("actedToken"), incomplete(outing))) return@updateScheduleState false
                if (intent.action == SNOOZE && ScheduleTimePolicy.snoozeUntil(now, event.departure) == 0L) {
                    tooClose = true
                    return@updateScheduleState false
                }
                record.put("actedToken", token)
                if (intent.action == SKIP) {
                    outing.put("dismissedAtUTC", ChecklistScheduleState.utc(now))
                    record.put("snoozeAt", 0L)
                } else record.put("snoozeAt", ScheduleTimePolicy.snoozeUntil(now, event.departure))
                acted = true
                true
            }
            if (tooClose) android.os.Handler(android.os.Looper.getMainLooper()).post {
                android.widget.Toast.makeText(context, "Departure is close. Open your checklist to get ready.", android.widget.Toast.LENGTH_LONG).show()
            }
            if (!acted) return
            if (canonical != null) NativeStateChangeNotifier.notify(canonical)
            (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(id, REQUEST)
        } else return
        refresh(context)
    }

    fun consumeOpen(context: Context, intent: Intent): String? {
        if (intent.action != OPEN) return null
        intent.action = null
        val root = NativeStateStore.readState(context)?.let(::JSONObject) ?: return "widget_today"
        val id = intent.getStringExtra("outingId") ?: return "widget_today"
        if (root.optString("_storageEpoch") != intent.getStringExtra("epoch")) return "widget_today"
        val outing = ChecklistScheduleState.objects(root.optJSONArray("outings")).firstOrNull { it.optString("id") == id }
            ?: return "widget_today"
        val schedule = ChecklistScheduleState.schedules(root).firstOrNull { it.id == outing.optString("scheduleId") && it.enabled }
            ?: return "widget_today"
        if (!ChecklistScheduleState.active(outing) || id != schedule.occurrenceId(outing.optString("date"))) return "widget_today"
        val today = ChecklistScheduleState.dateKey(Calendar.getInstance(java.util.TimeZone.getDefault(), java.util.Locale.US))
        if (outing.optString("date") != today && events(root, System.currentTimeMillis()).none {
                it.id == id && it.reminder <= System.currentTimeMillis()
            }) return "widget_today"
        return JSONObject().put("type", "schedule_outing").put("outingId", id)
            .put("scheduleId", schedule.id).put("requestId", UUID.randomUUID().toString()).toString()
    }

    private fun wakeOperation(context: Context, token: String): PendingIntent = PendingIntent.getBroadcast(context, REQUEST,
        Intent(context, ChecklistScheduleReceiver::class.java).setAction(WAKE).putExtra("token", token),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    fun dispatch(context: Context, intent: Intent, pending: BroadcastReceiver.PendingResult) {
        worker.execute { try { handle(context.applicationContext, intent) } catch (error: Exception) {
            Log.e("ReadyYetSchedules", "Could not process schedule action", error)
        } finally {
            runCatching { WidgetRenderService.refreshAllKinds(context.applicationContext, pending) }
                .onFailure { error ->
                    Log.e("ReadyYetSchedules", "Could not refresh widgets after schedule action", error)
                    pending.finish()
                }
        } }
    }
}

internal class ChecklistScheduleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) = ChecklistScheduleScheduler.dispatch(context, intent, goAsync())
}
