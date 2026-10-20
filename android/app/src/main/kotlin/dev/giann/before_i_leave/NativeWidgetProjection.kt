package dev.giann.before_i_leave

import org.json.JSONObject
import org.json.JSONTokener

internal data class NativeWidgetItem(
    val id: String,
    val label: String,
    val checked: Boolean,
    val canToggle: Boolean,
)

internal data class ChecklistWidgetProjection(
    val blueprintId: String?,
    val outingId: String?,
    val title: String,
    val progress: String,
    val date: String?,
    val items: List<NativeWidgetItem>,
    val canOpenList: Boolean,
    val canStart: Boolean,
    val stateMessage: String? = null,
    val checkedCount: Int = 0,
    val totalCount: Int = items.size,
    val completedHistory: Boolean = false,
)

internal data class QuickListWidgetProjection(
    val blueprintId: String?,
    val title: String,
    val progress: String,
    val outingId: String?,
    val canOpenList: Boolean,
    val stateMessage: String? = null,
    val checkedCount: Int = 0,
    val totalCount: Int = 0,
    val hasActive: Boolean = outingId != null,
)

/** Projects the durable Flutter model into the small, read-only widget view model. */
internal object NativeWidgetProjection {
    private data class Blueprint(
        val id: String,
        val name: String,
        val items: List<BlueprintItem>,
    )

    private data class BlueprintItem(val id: String, val label: String)
    private data class Outing(
        val id: String,
        val blueprintId: String,
        val blueprintName: String,
        val date: String,
        val startedAt: String,
        val scheduleId: String?,
        val completed: Boolean,
        val dismissed: Boolean,
        val items: List<NativeWidgetItem>,
    ) {
        val active: Boolean get() = !completed && !dismissed && (scheduleId == null || date == todayKey())
    }

    private fun todayKey() = ChecklistScheduleState.dateKey(java.util.Calendar.getInstance(java.util.TimeZone.getDefault(), java.util.Locale.US))

    private fun latestActive(outings: List<Outing>): Outing? = outings.filter(Outing::active)
        .sortedWith(compareBy<Outing> { if (it.scheduleId != null) 0 else 1 }.thenByDescending { it.startedAt }).firstOrNull()

    fun checklists(stateJson: String?, configuredBlueprintId: String?): ChecklistWidgetProjection {
        val state = parseState(stateJson)
            ?: return ChecklistWidgetProjection(
                blueprintId = configuredBlueprintId,
                outingId = null,
                title = "Ready Yet?",
                progress = "Open the app to load your lists",
                date = null,
                items = emptyList(),
                canOpenList = false,
                canStart = false,
                stateMessage = "Saved lists could not be read",
            )
        val scheduled = scheduledToday(state, configuredBlueprintId)
        if (scheduled != null) return outingProjection(scheduled)
        val recentActive = latestActive(state.outings)
        if (configuredBlueprintId == null) {
            if (recentActive != null) return outingProjection(recentActive)
            return ChecklistWidgetProjection(
                blueprintId = null,
                outingId = null,
                title = "Ready Yet?",
                progress = "Choose a list in the app",
                date = null,
                items = emptyList(),
                canOpenList = false,
                canStart = false,
                stateMessage = "Open Today to start a list",
            )
        }
        val blueprint = state.blueprints.firstOrNull { it.id == configuredBlueprintId }
            ?: return ChecklistWidgetProjection(
                blueprintId = configuredBlueprintId,
                outingId = null,
                title = "List removed",
                progress = "Choose another list for this widget",
                date = null,
                items = emptyList(),
                canOpenList = false,
                canStart = false,
                stateMessage = "This list was deleted",
            )
        val outing = latestActive(state.outings.filter { it.blueprintId == blueprint.id })
        if (outing != null) return outingProjection(outing)
        val hasCompletedOuting = state.outings.any { it.blueprintId == blueprint.id && it.completed }
        val previewItems = blueprint.items.take(5).map { NativeWidgetItem(it.id, it.label, false, false) }
        val empty = blueprint.items.isEmpty()
        return ChecklistWidgetProjection(
            blueprintId = blueprint.id,
            outingId = null,
            title = blueprint.name,
            progress = if (empty) "Add items before you start" else "${blueprint.items.size} items ready to pack",
            date = null,
            items = previewItems,
            canOpenList = true,
            canStart = !empty,
            stateMessage = if (empty) "Open this list to add your first item" else null,
            totalCount = blueprint.items.size,
            completedHistory = hasCompletedOuting,
        )
    }

    fun quickLists(stateJson: String?, configuredBlueprintIds: List<String>): List<QuickListWidgetProjection> {
        if (configuredBlueprintIds.isEmpty()) return emptyList()
        val state = parseState(stateJson) ?: return configuredBlueprintIds.take(4).map {
            QuickListWidgetProjection(it, "Ready Yet?", "Open the app to load your lists", null, false, "Saved lists could not be read")
        }
        return configuredBlueprintIds.distinct().take(4).map { id ->
            val blueprint = state.blueprints.firstOrNull { it.id == id }
                ?: return@map QuickListWidgetProjection(id, "List removed", "Choose lists again", null, false, "This list was deleted")
            val scheduled = scheduledToday(state, id)
            if (scheduled != null && !scheduled.active) {
                val checked = scheduled.items.count(NativeWidgetItem::checked)
                return@map QuickListWidgetProjection(id, blueprint.name,
                    if (scheduled.completed) "Completed today" else "Skipped today", null, true,
                    stateMessage = if (scheduled.completed) "Completed today" else "Skipped today",
                    checkedCount = checked, totalCount = scheduled.items.size, hasActive = false)
            }
            val active = latestActive(state.outings.filter { it.blueprintId == id })
            if (active != null) {
                val checked = active.items.count(NativeWidgetItem::checked)
                QuickListWidgetProjection(
                    blueprintId = id,
                    title = blueprint.name,
                    progress = "$checked of ${active.items.size} packed",
                    outingId = active.id,
                    canOpenList = true,
                    checkedCount = checked,
                    totalCount = active.items.size,
                    hasActive = true,
                )
            } else {
                QuickListWidgetProjection(
                    blueprintId = id,
                    title = blueprint.name,
                    progress = if (blueprint.items.isEmpty()) "Add items in app" else "${blueprint.items.size} items ready",
                    outingId = null,
                    canOpenList = true,
                    stateMessage = if (blueprint.items.isEmpty()) "This list is empty" else null,
                    totalCount = blueprint.items.size,
                    hasActive = false,
                )
            }
        }
    }

    private fun outingProjection(outing: Outing): ChecklistWidgetProjection {
        val checked = outing.items.count(NativeWidgetItem::checked)
        return ChecklistWidgetProjection(
            blueprintId = outing.blueprintId,
            outingId = outing.id.takeIf { outing.active },
            title = outing.blueprintName,
            progress = if (outing.dismissed) "Skipped today" else if (outing.completed) "Completed today" else "$checked of ${outing.items.size} packed",
            date = outing.date,
            items = outing.items.take(5).map { if (outing.active) it else it.copy(canToggle = false) },
            canOpenList = true,
            canStart = false,
            checkedCount = checked,
            totalCount = outing.items.size,
            completedHistory = outing.completed,
            stateMessage = if (outing.completed) "Completed today" else if (outing.dismissed) "Skipped today" else null,
        )
    }

    private fun scheduledToday(state: State, blueprintId: String?): Outing? = state.outings
        .filter { it.scheduleId in state.enabledScheduleIds && it.date == todayKey() &&
            (blueprintId == null || it.blueprintId == blueprintId) }
        .sortedWith(compareBy<Outing> { if (it.active) 0 else 1 }.thenBy { it.startedAt }).firstOrNull()

    private data class State(val blueprints: List<Blueprint>, val outings: List<Outing>, val enabledScheduleIds: Set<String>)

    private fun parseState(source: String?): State? {
      return try {
        if (source == null) return null
        val tokener = JSONTokener(source)
        val root = tokener.nextValue() as? JSONObject ?: return null
        if (tokener.nextClean() != '\u0000' || root.optInt("version", -1) != 1) return null
        val blueprintArray = root.optJSONArray("blueprints") ?: return null
        val outingArray = root.optJSONArray("outings") ?: return null
        val blueprints = buildList {
            for (index in 0 until blueprintArray.length()) {
                val value = blueprintArray.optJSONObject(index) ?: continue
                val id = value.optString("id").takeIf(String::isNotBlank) ?: continue
                val name = value.optString("name").takeIf(String::isNotBlank) ?: continue
                val items = value.optJSONArray("items")?.let { array ->
                    buildList {
                        for (itemIndex in 0 until array.length()) {
                            val item = array.optJSONObject(itemIndex) ?: continue
                            val itemId = item.optString("id").takeIf(String::isNotBlank) ?: continue
                            val label = item.optString("label").takeIf(String::isNotBlank) ?: continue
                            add(BlueprintItem(itemId, label))
                        }
                    }
                }.orEmpty()
                add(Blueprint(id, name, items))
            }
        }
        val outings = buildList {
            for (index in 0 until outingArray.length()) {
                val value = outingArray.optJSONObject(index) ?: continue
                val id = value.optString("id").takeIf(String::isNotBlank) ?: continue
                val blueprintId = value.optString("blueprintId").takeIf(String::isNotBlank) ?: continue
                val startedAt = value.optString("startedAt").takeIf(String::isNotBlank) ?: continue
                val items = value.optJSONArray("items")?.let { array ->
                    buildList {
                        for (itemIndex in 0 until array.length()) {
                            val item = array.optJSONObject(itemIndex) ?: continue
                            val itemId = item.optString("id").takeIf(String::isNotBlank) ?: continue
                            val label = item.optString("label").takeIf(String::isNotBlank) ?: continue
                            add(NativeWidgetItem(itemId, label, item.optBoolean("checked", false), true))
                        }
                    }
                }.orEmpty()
                val completion = value.opt("completedAt")
                val dismissal = value.opt("dismissedAtUTC")
                add(Outing(
                    id = id,
                    blueprintId = blueprintId,
                    blueprintName = value.optString("blueprintName", "Ready Yet?"),
                    date = value.optString("date", ""),
                    startedAt = startedAt,
                    scheduleId = value.opt("scheduleId") as? String,
                    completed = completion != null && completion != JSONObject.NULL,
                    dismissed = dismissal != null && dismissal != JSONObject.NULL,
                    items = items,
                ))
            }
        }
        val enabled = ChecklistScheduleState.schedules(root).filter { it.enabled }.map { it.id }.toSet()
        State(blueprints, outings, enabled)
      } catch (_: Exception) {
        null
      }
    }
}
