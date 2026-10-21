package dev.giann.before_i_leave

import android.content.Context
import org.json.JSONArray
import java.util.UUID

/** Stable blueprint selection for each home-screen widget instance. */
internal object WidgetInstanceConfigStore {
    private const val PREFS = "before_i_leave_widget_instances"
    private const val CHECKLIST_PREFIX = "checklist."
    private const val QUICK_LISTS_PREFIX = "quick_lists."
    private const val CHECKLIST_GENERATION_PREFIX = "checklist_generation."
    private const val QUICK_LISTS_GENERATION_PREFIX = "quick_lists_generation."
    private const val SCHEDULED_GENERATION_PREFIX = "scheduled_generation."
    const val MAX_QUICK_LISTS = 4

    fun checklistBlueprintId(context: Context, widgetId: Int): String? =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(CHECKLIST_PREFIX + widgetId, null)

    fun quickListBlueprintIds(context: Context, widgetId: Int): List<String> {
        val encoded = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(QUICK_LISTS_PREFIX + widgetId, null) ?: return emptyList()
        return runCatching { JSONArray(encoded) }
            .getOrNull()
            ?.let { array -> (0 until array.length()).mapNotNull { array.optString(it).takeIf(String::isNotBlank) } }
            .orEmpty()
            .distinct()
            .take(MAX_QUICK_LISTS)
    }

    fun bindingGeneration(context: Context, widgetId: Int, quickLists: Boolean): String? {
        val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val key = (if (quickLists) QUICK_LISTS_GENERATION_PREFIX else CHECKLIST_GENERATION_PREFIX) + widgetId
        preferences.getString(key, null)?.let { return it }
        val generation = UUID.randomUUID().toString()
        return generation.takeIf { preferences.edit().putString(key, it).commit() }
    }

    fun existingBindingGeneration(context: Context, widgetId: Int, quickLists: Boolean): String? {
        val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val key = (if (quickLists) QUICK_LISTS_GENERATION_PREFIX else CHECKLIST_GENERATION_PREFIX) + widgetId
        return preferences.getString(key, null)
    }

    fun scheduledBindingGeneration(context: Context, widgetId: Int): String? {
        val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val key = SCHEDULED_GENERATION_PREFIX + widgetId
        preferences.getString(key, null)?.let { return it }
        val generation = UUID.randomUUID().toString()
        return generation.takeIf { preferences.edit().putString(key, it).commit() }
    }

    fun existingScheduledBindingGeneration(context: Context, widgetId: Int): String? =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(SCHEDULED_GENERATION_PREFIX + widgetId, null)

    fun setChecklistBlueprintId(context: Context, widgetId: Int, blueprintId: String): Boolean {
        val generation = UUID.randomUUID().toString()
        return commitConfiguration(context, mapOf(
            CHECKLIST_PREFIX + widgetId to blueprintId,
            CHECKLIST_GENERATION_PREFIX + widgetId to generation,
        ))
    }

    fun setQuickListBlueprintIds(context: Context, widgetId: Int, blueprintIds: Collection<String>): Boolean {
        val normalized = blueprintIds.asSequence().filter(String::isNotBlank).distinct().take(MAX_QUICK_LISTS).toList()
        if (normalized.isEmpty()) return false
        val encoded = JSONArray(normalized.toList()).toString()
        val generation = UUID.randomUUID().toString()
        return commitConfiguration(context, mapOf(
            QUICK_LISTS_PREFIX + widgetId to encoded,
            QUICK_LISTS_GENERATION_PREFIX + widgetId to generation,
        ))
    }

    private fun commitConfiguration(context: Context, updates: Map<String, String>): Boolean {
        val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val previous = updates.keys.associateWith { key -> preferences.getString(key, null) }
        val editor = preferences.edit()
        updates.forEach { (key, value) -> editor.putString(key, value) }
        if (editor.commit()) return true
        val rollback = preferences.edit()
        previous.forEach { (key, value) -> if (value == null) rollback.remove(key) else rollback.putString(key, value) }
        if (!rollback.commit()) android.util.Log.e("BeforeILeaveWidget", "Could not roll back a failed widget configuration save.")
        return false
    }

    fun remove(context: Context, widgetId: Int) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .remove(CHECKLIST_PREFIX + widgetId)
            .remove(QUICK_LISTS_PREFIX + widgetId)
            .remove(CHECKLIST_GENERATION_PREFIX + widgetId)
            .remove(QUICK_LISTS_GENERATION_PREFIX + widgetId)
            .remove(SCHEDULED_GENERATION_PREFIX + widgetId)
            .apply()
    }

    fun removeScheduled(context: Context, widgetId: Int) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().remove(SCHEDULED_GENERATION_PREFIX + widgetId).apply()
    }
}
