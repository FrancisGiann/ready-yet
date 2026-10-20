package dev.giann.before_i_leave

import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

internal data class ChecklistSchedule(
    val id: String, val blueprintId: String, val weekdays: Set<Int>,
    val departureMinute: Int, val leadMinutes: Int, val enabled: Boolean,
) {
    fun occurrenceId(date: String) = "scheduled:$id:$date"
    fun departure(date: Calendar): Long = ScheduleTimePolicy.departureAt(
        date.get(Calendar.YEAR), date.get(Calendar.MONTH) + 1,
        date.get(Calendar.DAY_OF_MONTH), departureMinute, date.timeZone,
    )
}

/** Additive v1 schema; all mutation runs under NativeStateStore's existing lock. */
internal object ChecklistScheduleState {
    fun schedules(root: JSONObject): List<ChecklistSchedule> {
        val values = root.optJSONArray("schedules") ?: return emptyList()
        return (0 until values.length()).map { index ->
            val value = values.getJSONObject(index)
            val days = value.getJSONArray("weekdays")
            ChecklistSchedule(value.getString("id"), value.getString("blueprintId"),
                (0 until days.length()).map { days.getInt(it) }.toSet(),
                value.getInt("departureMinute"), value.getInt("leadMinutes"), value.getBoolean("enabled"))
        }
    }

    fun valid(root: JSONObject): Boolean = runCatching {
        if (root.has("schedules") && root.opt("schedules") !is JSONArray) return false
        val raw = root.optJSONArray("schedules")
        objects(raw).forEach { value ->
            if (value.opt("enabled") !is Boolean || value.opt("departureMinute") !is Int || value.opt("leadMinutes") !is Int) return false
            val days = value.optJSONArray("weekdays") ?: return false
            for (index in 0 until days.length()) if (days.opt(index) !is Int) return false
        }
        if (raw != null && objects(raw).size != raw.length()) return false
        if (root.has("_scheduleReminderState") && root.opt("_scheduleReminderState") !is JSONObject) return false
        val values = schedules(root)
        values.size <= 32 && values.map { it.id }.distinct().size == values.size && values.all {
            it.id.isNotBlank() && it.blueprintId.isNotBlank() && it.weekdays.isNotEmpty() &&
                it.weekdays.all { day -> day in 1..7 } && it.departureMinute in 0..1439 && it.leadMinutes in 0..1440
        }
    }.getOrDefault(false)

    fun dateKey(calendar: Calendar): String = String.format(Locale.US, "%04d-%02d-%02d",
        calendar.get(Calendar.YEAR), calendar.get(Calendar.MONTH) + 1, calendar.get(Calendar.DAY_OF_MONTH))

    fun utc(instant: Long): String = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }.format(Date(instant))

    fun objects(values: JSONArray?): List<JSONObject> = if (values == null) emptyList()
        else (0 until values.length()).mapNotNull(values::optJSONObject)

    fun active(outing: JSONObject): Boolean = outing.isNull("completedAt") && outing.isNull("dismissedAtUTC")

    fun ensureOccurrences(root: JSONObject, now: Long): Boolean {
        val outings = root.getJSONArray("outings")
        val ids = objects(outings).map { it.optString("id") }.toMutableSet()
        val blueprints = objects(root.optJSONArray("blueprints")).associateBy { it.optString("id") }
        val extras = objects(root.optJSONArray("extras"))
        var changed = false
        for (schedule in schedules(root).filter { it.enabled }.sortedBy { it.departureMinute }) {
            val blueprint = blueprints[schedule.blueprintId] ?: continue
            // Tomorrow is materialized only when its lead-time reminder falls
            // before midnight. Never backfill missed days or reset snapshots.
            for (offset in 0..1) {
                val date = Calendar.getInstance(java.util.TimeZone.getDefault(), java.util.Locale.US).apply { timeInMillis = now; add(Calendar.DAY_OF_MONTH, offset) }
                if (ScheduleTimePolicy.isoWeekday(date) !in schedule.weekdays) continue
                val departure = schedule.departure(date)
                if (offset == 1 && ScheduleTimePolicy.reminderAt(departure, schedule.leadMinutes) > now) continue
                val key = dateKey(date)
                val id = schedule.occurrenceId(key)
                if (!ids.add(id)) continue
                val items = JSONArray()
                objects(blueprint.optJSONArray("items")).forEach { item ->
                    items.put(JSONObject(item.toString()).put("checked", false))
                }
                extras.filter { it.optString("blueprintId") == schedule.blueprintId && it.optString("date") == key }.forEach {
                    items.put(JSONObject().put("id", "extra:${it.getString("id")}")
                        .put("label", it.getString("label")).put("iconKey", it.optString("iconKey", "spark")).put("checked", false))
                }
                outings.put(JSONObject().put("id", id).put("scheduleId", schedule.id)
                    .put("blueprintId", schedule.blueprintId).put("blueprintName", blueprint.getString("name"))
                    .put("date", key).put("startedAt", utc(now)).put("completedAt", JSONObject.NULL)
                    .put("dismissedAtUTC", JSONObject.NULL).put("items", items))
                changed = true
            }
        }
        return changed
    }
}
