package dev.giann.before_i_leave

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

internal object WidgetIntentContract {
    const val ACTION_OPEN_WIDGET_DESTINATION = "dev.giann.before_i_leave.OPEN_WIDGET_DESTINATION"
    const val ACTION_SET_WIDGET_CHECKED = "dev.giann.before_i_leave.SET_WIDGET_CHECKED"
    const val EXTRA_WIDGET_ID = "dev.giann.before_i_leave.extra.WIDGET_ID"
    const val EXTRA_WIDGET_KIND = "dev.giann.before_i_leave.extra.WIDGET_KIND"
    const val EXTRA_WIDGET_BINDING_GENERATION = "dev.giann.before_i_leave.extra.WIDGET_BINDING_GENERATION"
    const val EXTRA_BLUEPRINT_ID = "dev.giann.before_i_leave.extra.BLUEPRINT_ID"
    const val EXTRA_SCHEDULE_ID = "dev.giann.before_i_leave.extra.SCHEDULE_ID"
    const val EXTRA_OUTING_ID = "dev.giann.before_i_leave.extra.OUTING_ID"
    const val EXTRA_ITEM_ID = "dev.giann.before_i_leave.extra.ITEM_ID"
    const val EXTRA_DESIRED_CHECKED = "dev.giann.before_i_leave.extra.DESIRED_CHECKED"
    const val EXTRA_BINDING_GENERATION = "dev.giann.before_i_leave.extra.BINDING_GENERATION"
    const val EXTRA_RENDER_EPOCH = "dev.giann.before_i_leave.extra.RENDER_EPOCH"
    const val EXTRA_RENDER_REVISION = "dev.giann.before_i_leave.extra.RENDER_REVISION"
    const val EXTRA_ITEM_RENDER_REVISION = "dev.giann.before_i_leave.extra.ITEM_RENDER_REVISION"

    const val TYPE_LIST = "widget_list"
    const val TYPE_OUTING = "widget_outing"
    const val TYPE_TODAY = "widget_today"
    const val TYPE_SCHEDULED_OUTING = "scheduled_widget_outing"
    const val TYPE_WIDGET_SCHEDULES = "widget_schedules"
    const val KIND_SCHEDULED_CHECKLIST = "scheduled_checklist"

    fun openDestination(
        context: Context,
        widgetId: Int,
        blueprintId: String?,
        outingId: String?,
        quickLists: Boolean = false,
    ): PendingIntent {
        val type = if (outingId != null) TYPE_OUTING else if (blueprintId != null) TYPE_LIST else TYPE_TODAY
        val bindingGeneration = if (widgetId >= 0) {
            WidgetInstanceConfigStore.existingBindingGeneration(context, widgetId, quickLists)
        } else null
        val payload = JSONObject().apply {
            put("type", type)
            put("blueprintId", blueprintId)
            put("outingId", outingId)
            put("widgetId", widgetId)
            put("widgetKind", if (quickLists) "quick_lists" else "checklist")
            put("bindingGeneration", bindingGeneration)
            put("source", "widget")
            if (outingId == null && blueprintId != null) {
                put("date", SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date()))
            }
            put("requestId", UUID.randomUUID().toString())
        }.toString()
        val intent = Intent(context, MainActivity::class.java).apply {
            action = ACTION_OPEN_WIDGET_DESTINATION
            data = Uri.Builder().scheme("beforeileave").authority("widget")
                .appendPath(widgetId.toString()).appendPath(type)
                .appendPath(if (quickLists) "quick_lists" else "checklist")
                .appendPath(bindingGeneration.orEmpty())
                .appendPath(blueprintId.orEmpty()).appendPath(outingId.orEmpty())
                .appendPath(JSONObject(payload).optString("requestId"))
                .build()
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(MainActivity.EXTRA_WIDGET_LAUNCH_ACTION, payload)
        }
        return PendingIntent.getActivity(
            context,
            intent.dataString.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    fun configuration(context: Context, widgetId: Int, quickLists: Boolean): PendingIntent {
        val activity = if (quickLists) QuickListsWidgetConfigActivity::class.java else ChecklistWidgetConfigActivity::class.java
        val intent = Intent(context, activity).apply {
            data = Uri.parse("beforeileave://widget-config/$widgetId")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
        }
        return PendingIntent.getActivity(
            context,
            intent.dataString.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    fun openScheduledOuting(
        context: Context,
        widgetId: Int,
        scheduleId: String,
        outingId: String,
        storageEpoch: String,
    ): PendingIntent {
        val generation = WidgetInstanceConfigStore.scheduledBindingGeneration(context, widgetId).orEmpty()
        val requestId = UUID.randomUUID().toString()
        val payload = JSONObject().apply {
            put("type", TYPE_SCHEDULED_OUTING)
            put("source", "widget")
            put("widgetId", widgetId)
            put("widgetKind", KIND_SCHEDULED_CHECKLIST)
            put("bindingGeneration", generation)
            put("scheduleId", scheduleId)
            put("outingId", outingId)
            put("storageEpoch", storageEpoch)
            put("requestId", requestId)
        }.toString()
        val intent = Intent(context, MainActivity::class.java).apply {
            action = ACTION_OPEN_WIDGET_DESTINATION
            data = scheduledWidgetUri(widgetId, TYPE_SCHEDULED_OUTING, generation, scheduleId, outingId, storageEpoch, requestId)
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(MainActivity.EXTRA_WIDGET_LAUNCH_ACTION, payload)
        }
        return PendingIntent.getActivity(
            context,
            intent.dataString.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    fun openWidgetSchedules(context: Context, widgetId: Int): PendingIntent {
        val generation = WidgetInstanceConfigStore.scheduledBindingGeneration(context, widgetId).orEmpty()
        val requestId = UUID.randomUUID().toString()
        val payload = JSONObject().apply {
            put("type", TYPE_WIDGET_SCHEDULES)
            put("source", "widget")
            put("widgetId", widgetId)
            put("widgetKind", KIND_SCHEDULED_CHECKLIST)
            put("bindingGeneration", generation)
            put("requestId", requestId)
        }.toString()
        val intent = Intent(context, MainActivity::class.java).apply {
            action = ACTION_OPEN_WIDGET_DESTINATION
            data = Uri.Builder().scheme("beforeileave").authority("widget")
                .appendPath(widgetId.toString()).appendPath(TYPE_WIDGET_SCHEDULES)
                .appendPath(KIND_SCHEDULED_CHECKLIST).appendPath(generation).appendPath(requestId)
                .build()
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(MainActivity.EXTRA_WIDGET_LAUNCH_ACTION, payload)
        }
        return PendingIntent.getActivity(
            context,
            intent.dataString.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun scheduledWidgetUri(
        widgetId: Int,
        type: String,
        generation: String,
        scheduleId: String,
        outingId: String,
        storageEpoch: String,
        requestId: String,
    ) = Uri.Builder().scheme("beforeileave").authority("widget")
        .appendPath(widgetId.toString()).appendPath(type).appendPath(KIND_SCHEDULED_CHECKLIST)
        .appendPath(generation).appendPath(scheduleId).appendPath(outingId)
        .appendPath(storageEpoch).appendPath(requestId).build()

    fun scheduledCheckedBroadcast(
        context: Context,
        widgetId: Int,
        scheduleId: String,
        outingId: String,
        itemId: String,
        checked: Boolean,
        bindingGeneration: String,
        renderEpoch: String,
        renderRevision: Long,
        itemRenderRevision: Long,
    ): PendingIntent {
        val intent = Intent(context, WidgetActionReceiver::class.java).apply {
            action = ACTION_SET_WIDGET_CHECKED
            data = Uri.Builder().scheme("beforeileave").authority("scheduled-widget-check")
                .appendPath(widgetId.toString()).appendPath(bindingGeneration).appendPath(renderEpoch)
                .appendPath(renderRevision.toString()).appendPath(itemRenderRevision.toString())
                .appendPath(scheduleId).appendPath(outingId).appendPath(itemId).appendPath(checked.toString()).build()
            putExtra(EXTRA_WIDGET_ID, widgetId)
            putExtra(EXTRA_WIDGET_KIND, KIND_SCHEDULED_CHECKLIST)
            putExtra(EXTRA_SCHEDULE_ID, scheduleId)
            putExtra(EXTRA_OUTING_ID, outingId)
            putExtra(EXTRA_ITEM_ID, itemId)
            putExtra(EXTRA_DESIRED_CHECKED, checked)
            putExtra(EXTRA_BINDING_GENERATION, bindingGeneration)
            putExtra(EXTRA_RENDER_EPOCH, renderEpoch)
            putExtra(EXTRA_RENDER_REVISION, renderRevision)
            putExtra(EXTRA_ITEM_RENDER_REVISION, itemRenderRevision)
        }
        return PendingIntent.getBroadcast(
            context,
            intent.dataString.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    fun checkedBroadcast(
        context: Context,
        widgetId: Int,
        outingId: String,
        itemId: String,
        checked: Boolean,
        bindingGeneration: String,
        renderEpoch: String,
        renderRevision: Long,
        itemRenderRevision: Long,
    ): PendingIntent {
        val intent = Intent(context, WidgetActionReceiver::class.java).apply {
            action = ACTION_SET_WIDGET_CHECKED
            data = Uri.Builder().scheme("beforeileave").authority("widget-check")
                .appendPath(widgetId.toString()).appendPath(bindingGeneration).appendPath(renderEpoch)
                .appendPath(renderRevision.toString()).appendPath(itemRenderRevision.toString())
                .appendPath(outingId).appendPath(itemId).appendPath(checked.toString()).build()
            putExtra(EXTRA_WIDGET_ID, widgetId)
            putExtra(EXTRA_OUTING_ID, outingId)
            putExtra(EXTRA_ITEM_ID, itemId)
            putExtra(EXTRA_DESIRED_CHECKED, checked)
            putExtra(EXTRA_BINDING_GENERATION, bindingGeneration)
            putExtra(EXTRA_RENDER_EPOCH, renderEpoch)
            putExtra(EXTRA_RENDER_REVISION, renderRevision)
            putExtra(EXTRA_ITEM_RENDER_REVISION, itemRenderRevision)
        }
        return PendingIntent.getBroadcast(
            context,
            intent.dataString.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    fun consume(context: Context, intent: Intent?): String? {
        val current = intent ?: return null
        if (current.action == ChecklistScheduleScheduler.OPEN) return ChecklistScheduleScheduler.consumeOpen(context, current)
        if (current.action == MainActivity.ACTION_PACK_TODAY) {
            current.action = null
            return "pack_today"
        }
        if (current.action != ACTION_OPEN_WIDGET_DESTINATION) return null
        val payload = current.getStringExtra(MainActivity.EXTRA_WIDGET_LAUNCH_ACTION)
        current.action = null
        current.removeExtra(MainActivity.EXTRA_WIDGET_LAUNCH_ACTION)
        if (payload == null || !validateWidgetLaunch(context, current, payload)) return WidgetLaunchPolicy.invalidLaunchFallback()
        val validated = JSONObject(payload)
        if (validated.optString("type") == TYPE_SCHEDULED_OUTING ||
            validated.optString("type") == TYPE_WIDGET_SCHEDULES) {
            validated.put("requestId", UUID.randomUUID().toString())
            return validated.toString()
        }
        return payload
    }

    private fun validateWidgetLaunch(context: Context, intent: Intent, encoded: String): Boolean = runCatching {
        val payload = JSONObject(encoded)
        if (payload.optString("source") != "widget") return false
        val type = payload.optString("type")
        if (type != TYPE_LIST && type != TYPE_OUTING &&
            type != TYPE_SCHEDULED_OUTING && type != TYPE_WIDGET_SCHEDULES) return false
        val widgetId = payload.optInt("widgetId", -1)
        val kind = payload.optString("widgetKind")
        val generation = payload.optString("bindingGeneration")
        val requestId = payload.optString("requestId")
        if (widgetId < 0 || generation.isBlank() || requestId.isBlank()) return false
        val scheduledKind = type == TYPE_SCHEDULED_OUTING || type == TYPE_WIDGET_SCHEDULES
        val quickLists = kind == "quick_lists"
        if (scheduledKind != (kind == KIND_SCHEDULED_CHECKLIST)) return false
        if (!scheduledKind && !quickLists && kind != "checklist") return false
        val blueprintId = payload.optString("blueprintId").takeIf(String::isNotBlank)
        val outingId = payload.optString("outingId").takeIf(String::isNotBlank)
        val scheduleId = payload.optString("scheduleId").takeIf(String::isNotBlank)
        val storageEpoch = payload.optString("storageEpoch").takeIf(String::isNotBlank)
        if (type == TYPE_LIST && (blueprintId == null || outingId != null)) return false
        if (type == TYPE_OUTING && (blueprintId == null || outingId == null)) return false
        if (type == TYPE_SCHEDULED_OUTING && (scheduleId == null || outingId == null || storageEpoch == null)) return false
        if (type == TYPE_WIDGET_SCHEDULES && (scheduleId != null || outingId != null)) return false

        val expectedProvider = when {
            scheduledKind -> ScheduledChecklistWidgetProvider::class.java
            quickLists -> QuickListsWidgetProvider::class.java
            else -> LeaveWidgetProvider::class.java
        }
        val manager = AppWidgetManager.getInstance(context)
        val info = manager.getAppWidgetInfo(widgetId)
        val providerOwned = info?.provider == ComponentName(context, expectedProvider)
        val bindingMatches = if (scheduledKind) {
            WidgetInstanceConfigStore.existingScheduledBindingGeneration(context, widgetId) == generation
        } else WidgetInstanceConfigStore.existingBindingGeneration(context, widgetId, quickLists) == generation
        if (!providerOwned || !bindingMatches) return false

        if (type == TYPE_WIDGET_SCHEDULES) {
            val expectedUri = Uri.Builder().scheme("beforeileave").authority("widget")
                .appendPath(widgetId.toString()).appendPath(type).appendPath(kind).appendPath(generation)
                .appendPath(requestId).build()
            return intent.data == expectedUri
        }

        if (type == TYPE_SCHEDULED_OUTING) {
            val expectedUri = scheduledWidgetUri(widgetId, type, generation, scheduleId!!, outingId!!, storageEpoch!!, requestId)
            if (intent.data != expectedUri) return false
            val state = NativeStateStore.readState(context) ?: return false
            val root = JSONObject(state)
            if (root.optString("_storageEpoch") != storageEpoch) return false
            val projectionNow = System.currentTimeMillis()
            val projectionToday = ChecklistScheduleState.dateKey(java.util.Calendar.getInstance(java.util.TimeZone.getDefault(), java.util.Locale.US).apply {
                timeInMillis = projectionNow
            })
            val projection = NativeWidgetProjection.scheduledChecklist(state, projectionNow)
            val exact = projection.scheduleId == scheduleId && projection.outingId == outingId &&
                projection.openOutingId == outingId && projection.date == projectionToday
            val matching = ChecklistScheduleState.objects(root.optJSONArray("outings"))
                .filter { it.optString("id") == outingId && it.optString("scheduleId") == scheduleId && it.optString("date") == projection.date }
            val matched = matching.singleOrNull() ?: return false
            val completed = !matched.isNull("completedAt")
            val skipped = !matched.isNull("dismissedAtUTC")
            return ScheduledWidgetSelectionPolicy.mayOpenOuting(
                providerOwned, bindingMatches, true, projection.date == projectionToday,
                exact && matching.size == 1, ChecklistScheduleState.active(matched), completed, skipped,
            )
        }

        val configuredChecklistId = if (quickLists) null else WidgetInstanceConfigStore.checklistBlueprintId(context, widgetId)
        val configuredQuickListIds = if (quickLists) WidgetInstanceConfigStore.quickListBlueprintIds(context, widgetId) else emptyList()
        val selected = if (quickLists) {
            blueprintId in configuredQuickListIds
        } else {
            configuredChecklistId == blueprintId || (configuredChecklistId == null && type == TYPE_OUTING)
        }
        if (!selected || blueprintId == null) return false

        val expectedUri = Uri.Builder().scheme("beforeileave").authority("widget")
            .appendPath(widgetId.toString()).appendPath(type).appendPath(kind)
            .appendPath(generation).appendPath(blueprintId).appendPath(outingId.orEmpty())
            .appendPath(requestId).build()
        if (intent.data != expectedUri) return false

        val state = NativeStateStore.readState(context) ?: return false
        val root = JSONObject(state)
        if (type == TYPE_LIST) {
            val blueprints = root.optJSONArray("blueprints") ?: return false
            val blueprintExists = (0 until blueprints.length()).any { blueprints.optJSONObject(it)?.optString("id") == blueprintId }
            return WidgetLaunchPolicy.canOpenList(providerOwned, bindingMatches, selected, blueprintExists)
        } else {
            val outings = root.optJSONArray("outings") ?: return false
            val matching = (0 until outings.length()).mapNotNull(outings::optJSONObject)
                .filter { it.optString("id") == outingId && it.optString("blueprintId") == blueprintId }
            if (matching.size != 1) return false
            val outing = matching.single()
            val active = (outing.opt("completedAt") == null || outing.opt("completedAt") == JSONObject.NULL) &&
                (outing.opt("dismissedAtUTC") == null || outing.opt("dismissedAtUTC") == JSONObject.NULL)
            val projectedOutingId = if (quickLists) {
                NativeWidgetProjection.quickLists(state, configuredQuickListIds)
                    .firstOrNull { it.blueprintId == blueprintId }
                    ?.outingId
            } else {
                NativeWidgetProjection.checklists(state, configuredChecklistId).let { projection ->
                    projection.outingId.takeIf { projection.blueprintId == blueprintId }
                }
            }
            return WidgetLaunchPolicy.canOpenOuting(
                providerOwned,
                bindingMatches,
                selected,
                active,
                projectedOutingId == outingId,
            )
        }
        false
    }.getOrDefault(false)
}

internal object NativeStateChangeNotifier {
    @Volatile
    var listener: ((String) -> Unit)? = null

    fun notify(canonicalJson: String) {
        listener?.invoke(canonicalJson)
    }
}
