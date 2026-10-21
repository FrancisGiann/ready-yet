package dev.giann.before_i_leave

import android.content.Context
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.util.Log
import android.util.AtomicFile
import org.json.JSONException
import org.json.JSONObject
import org.json.JSONTokener
import android.os.Build
import java.io.File
import java.io.IOException
import java.util.UUID

/** Private, crash-safe JSON state shared by Flutter and the read-only widget. */
internal object NativeStateStore {
    private const val STATE_FILE = "before_i_leave_state.json"
    private const val WIDGET_FILE = "before_i_leave_widget.json"
    private const val STATE_BACKUP = "before_i_leave_state.json.bak"
    private const val WIDGET_BACKUP = "before_i_leave_widget.json.bak"
    private const val LEGACY_EPOCH = "legacy-v1"
    private const val META_REVISION = "_nativeRevision"
    private const val META_EPOCH = "_storageEpoch"
    private const val TAG = "BeforeILeaveState"
    private val lock = Any()

    fun readState(context: Context, now: Long = System.currentTimeMillis()): String? = synchronized(lock) {
        val value = readRecovering(context.filesDir, STATE_FILE, STATE_BACKUP, ::isValidStateJson) ?: return@synchronized null
        val root = parseObject(value)
        if (!root.has(META_EPOCH) || !root.has(META_REVISION)) {
            root.put(META_EPOCH, LEGACY_EPOCH)
            root.put(META_REVISION, 0)
        }
        if (ChecklistScheduleState.ensureOccurrences(root, now)) {
            return@synchronized commitCanonical(context, canonicalize(root,
                root.optString(META_EPOCH, LEGACY_EPOCH), root.optLong(META_REVISION, 0L) + 1L))
        }
        root.put("_widgetSummary", deriveSummary(root))
        root.toString()
    }

    fun writeState(
        context: Context,
        baseJson: String?,
        targetJson: String,
        checkIntents: Any?,
        lifecycleIntents: Any?,
    ): String = synchronized(lock) {
        validateStateJson(targetJson)
        val currentJson = readRecovering(context.filesDir, STATE_FILE, STATE_BACKUP, ::isValidStateJson)
        val target = parseObject(targetJson)
        val current = currentJson?.let(::parseObject)
        val base = baseJson?.let {
            validateStateJson(it)
            parseObject(it)
        }
        if (current != null && base == null) throw JSONException("Saved state changed while this app session was open; reload before saving.")
        val currentEpoch = current?.optString(META_EPOCH, LEGACY_EPOCH)?.takeIf(String::isNotBlank) ?: LEGACY_EPOCH
        val baseEpoch = base?.optString(META_EPOCH, LEGACY_EPOCH)?.takeIf(String::isNotBlank)
        if (current != null && baseEpoch != currentEpoch) {
            throw JSONException("Saved state was reset or replaced; reload before saving this older snapshot.")
        }
        // Native reminder actions and daily materialization must survive a
        // Flutter snapshot captured before those occurrences existed.
        val targetOutings = target.getJSONArray("outings")
        val baseOutings = ChecklistScheduleState.objects(base?.optJSONArray("outings")).associateBy { it.optString("id") }
        val currentOutings = ChecklistScheduleState.objects(current?.optJSONArray("outings")).associateBy { it.optString("id") }
        // The first committed daily snapshot wins concurrent creation. A later
        // unchanged queued snapshot also keeps the saved structure; explicit
        // structural edits to an occurrence already in the base remain valid.
        for (index in 0 until targetOutings.length()) {
            val id = targetOutings.getJSONObject(index).optString("id")
            val saved = currentOutings[id]
            val previous = baseOutings[id]
            if (saved != null && !saved.isNull("scheduleId") &&
                (previous == null || sameOutingSnapshot(previous, targetOutings.getJSONObject(index)))) {
                targetOutings.put(index, copyObject(saved))
            }
        }
        val targetIds = ChecklistScheduleState.objects(targetOutings).map { it.optString("id") }.toSet()
        ChecklistScheduleState.objects(current?.optJSONArray("outings"))
            .filter { !it.isNull("scheduleId") && it.optString("id") !in targetIds }
            .forEach { targetOutings.put(copyObject(it)) }
        current?.optJSONObject("_scheduleReminderState")?.let { target.put("_scheduleReminderState", copyObject(it)) }
        val intents = parseCheckIntents(checkIntents)
        val lifecycle = parseLifecycleIntents(lifecycleIntents)
        val epoch = currentEpoch.takeUnless { current == null } ?: UUID.randomUUID().toString()
        val previousRevision = current?.optLong(META_REVISION, 0L)?.coerceAtLeast(0L) ?: 0L
        val emptyState = JSONObject().put("outings", org.json.JSONArray())
        val rejected = mergeExistingState(target, current ?: emptyState, intents, lifecycle, previousRevision + 1L)
        ChecklistScheduleState.ensureOccurrences(target, System.currentTimeMillis())
        val candidate = canonicalize(target, epoch, previousRevision + 1L)
        addResponseRejections(commitCanonical(context, candidate), rejected)
    }

    /** Durably records delivery/skip/snooze under the same state lock as checks. */
    fun updateScheduleState(context: Context, change: (JSONObject) -> Boolean): String? = synchronized(lock) {
        val root = readState(context)?.let(::parseObject) ?: return@synchronized null
        if (!change(root)) return@synchronized root.toString()
        validateStateJson(root.toString())
        commitCanonical(context, canonicalize(root, root.optString(META_EPOCH, LEGACY_EPOCH),
            root.optLong(META_REVISION, 0L) + 1L))
    }

    fun resetState(context: Context, targetJson: String): String = synchronized(lock) {
        validateStateJson(targetJson)
        val suffix = ".damaged.${System.currentTimeMillis()}.${UUID.randomUUID()}"
        archiveIfPresent(File(context.filesDir, STATE_FILE), suffix)
        archiveIfPresent(File(context.filesDir, STATE_BACKUP), suffix)
        archiveIfPresent(File(context.filesDir, WIDGET_FILE), suffix)
        archiveIfPresent(File(context.filesDir, WIDGET_BACKUP), suffix)
        val target = parseObject(targetJson)
        val candidate = canonicalize(target, UUID.randomUUID().toString(), 1L)
        commitCanonical(context, candidate)
    }

    fun widgetSnapshot(context: Context, widgetId: Int?): Map<String, Any?> = synchronized(lock) {
        val state = readState(context)
        val stateRoot = state?.let(::parseObject)
        val checklist = NativeWidgetProjection.checklists(
            state,
            widgetId?.let { WidgetInstanceConfigStore.checklistBlueprintId(context, it) },
        )
        val quick = NativeWidgetProjection.quickLists(
            state,
            widgetId?.let { WidgetInstanceConfigStore.quickListBlueprintIds(context, it) }.orEmpty(),
        )
        val checklistMap = projectionMap(checklist)["checklist"]
        val quickMap = projectionMap(quick)["quickLists"]
        val supported = Build.VERSION.SDK_INT >= 26 &&
            AppWidgetManager.getInstance(context).isRequestPinAppWidgetSupported
        mapOf(
            "pinSupported" to supported,
            "storageEpoch" to (stateRoot?.optString(META_EPOCH, LEGACY_EPOCH) ?: LEGACY_EPOCH),
            "nativeRevision" to (stateRoot?.optLong(META_REVISION, 0L) ?: 0L),
            "checklist" to checklistMap,
            "quickLists" to quickMap,
        )
    }

    /** Applies one idempotent widget check to an existing active outing only. */
    fun applyWidgetItemCheck(
        context: Context,
        widgetId: Int,
        bindingGeneration: String,
        renderEpoch: String,
        renderRevision: Long,
        outingId: String,
        itemId: String,
        checked: Boolean,
        itemRenderRevision: Long,
    ): String = applyWidgetItemCheckInternal(
        context, widgetId, bindingGeneration, renderEpoch, renderRevision,
        outingId, itemId, checked, itemRenderRevision, scheduleId = null,
    )

    fun applyScheduledWidgetItemCheck(
        context: Context,
        widgetId: Int,
        bindingGeneration: String,
        renderEpoch: String,
        renderRevision: Long,
        scheduleId: String,
        outingId: String,
        itemId: String,
        checked: Boolean,
        itemRenderRevision: Long,
    ): String = applyWidgetItemCheckInternal(
        context, widgetId, bindingGeneration, renderEpoch, renderRevision,
        outingId, itemId, checked, itemRenderRevision, scheduleId,
    )

    private fun applyWidgetItemCheckInternal(
        context: Context,
        widgetId: Int,
        bindingGeneration: String,
        renderEpoch: String,
        renderRevision: Long,
        outingId: String,
        itemId: String,
        checked: Boolean,
        itemRenderRevision: Long,
        scheduleId: String?,
    ): String = synchronized(lock) {
        val currentJson = readRecovering(context.filesDir, STATE_FILE, STATE_BACKUP, ::isValidStateJson)
            ?: throw JSONException("There is no saved outing to update.")
        val root = parseObject(currentJson)
        val canonical = canonicalize(root, root.optString(META_EPOCH, LEGACY_EPOCH), root.optLong(META_REVISION, 0L))
        val currentRevision = canonical.optLong(META_REVISION, 0L)
        if (canonical.optString(META_EPOCH, LEGACY_EPOCH) != renderEpoch || renderRevision > currentRevision) {
            return@synchronized canonical.toString()
        }
        val manager = AppWidgetManager.getInstance(context)
        if (scheduleId != null) {
            val scheduledIds = manager.getAppWidgetIds(ComponentName(context, ScheduledChecklistWidgetProvider::class.java))
            if (widgetId !in scheduledIds) return@synchronized canonical.toString()
            if (WidgetInstanceConfigStore.existingScheduledBindingGeneration(context, widgetId) != bindingGeneration) {
                return@synchronized canonical.toString()
            }
            val projectionNow = System.currentTimeMillis()
            val projectionToday = ChecklistScheduleState.dateKey(java.util.Calendar.getInstance(java.util.TimeZone.getDefault(), java.util.Locale.US).apply {
                timeInMillis = projectionNow
            })
            val projection = NativeWidgetProjection.scheduledChecklist(currentJson, projectionNow)
            if (projection.scheduleId != scheduleId || projection.checkOutingId != outingId ||
                projection.date != projectionToday) {
                return@synchronized canonical.toString()
            }
        } else {
            val checklistIds = manager.getAppWidgetIds(ComponentName(context, LeaveWidgetProvider::class.java))
            if (widgetId !in checklistIds) return@synchronized canonical.toString()
            if (WidgetInstanceConfigStore.existingBindingGeneration(context, widgetId, quickLists = false) != bindingGeneration) {
                return@synchronized canonical.toString()
            }
            val configuredBlueprintId = WidgetInstanceConfigStore.checklistBlueprintId(context, widgetId)
            val projection = NativeWidgetProjection.checklists(currentJson, configuredBlueprintId)
            if (projection.outingId != outingId) return@synchronized canonical.toString()
        }
        val outings = root.optJSONArray("outings") ?: return@synchronized canonical.toString()
        val outing = uniqueObject(outings, outingId) ?: return@synchronized canonical.toString()
        if (!isActiveOuting(outing)) return@synchronized canonical.toString()
        val items = outing.optJSONArray("items") ?: return@synchronized canonical.toString()
        val item = uniqueObject(items, itemId) ?: return@synchronized canonical.toString()
        val currentChecked = item.opt("checked") as? Boolean
            ?: throw JSONException("Saved checklist item '$itemId' has an invalid checked value.")
        val lastItemRevision = root.optJSONObject("_widgetCheckRevisions")
            ?.optJSONObject(outingId)
            ?.optLong(itemId, 0L)
            ?: 0L
        if (scheduleId != null && !ScheduledWidgetSelectionPolicy.mayApplyCheck(
                true, true, true, true, true, true,
                renderRevision, currentRevision, itemRenderRevision, lastItemRevision,
                currentChecked, checked,
            )) return@synchronized canonical.toString()
        if (!WidgetCheckMergePolicy.shouldApplyWidgetCheck(
                itemRenderRevision,
                lastItemRevision,
                currentChecked,
                checked,
            )) return@synchronized canonical.toString()
        item.put("checked", checked)
        val nextRevision = currentRevision + 1L
        val revisions = root.optJSONObject("_widgetCheckRevisions") ?: JSONObject().also { root.put("_widgetCheckRevisions", it) }
        val outingRevisions = revisions.optJSONObject(outingId) ?: JSONObject().also { revisions.put(outingId, it) }
        outingRevisions.put(itemId, nextRevision)
        val updated = canonicalize(root, canonical.optString(META_EPOCH, LEGACY_EPOCH), nextRevision)
        commitCanonical(context, updated)
    }

    fun readWidgetSummary(context: Context): JSONObject = synchronized(lock) {
        val embedded = runCatching {
            readRecovering(context.filesDir, STATE_FILE, STATE_BACKUP, ::isValidStateJson)
        }.getOrNull()?.let { runCatching { parseObject(it).optJSONObject("_widgetSummary") }.getOrNull() }
        if (embedded != null && isValidSummary(embedded)) return@synchronized embedded

        val summary = runCatching {
            readRecovering(context.filesDir, WIDGET_FILE, WIDGET_BACKUP, ::isValidJson)
        }.getOrNull()
        if (summary != null) {
            runCatching { JSONObject(summary) }.getOrNull()?.takeIf(::isValidSummary)?.let { return@synchronized it }
        }
        JSONObject()
    }

    private fun withWidgetSummary(json: String, summary: JSONObject): String =
        parseObject(json).put("_widgetSummary", summary).toString()

    private fun projectionMap(projection: Any): Map<String, Any?> {
        val checklist = projection as? ChecklistWidgetProjection
        if (checklist != null) {
            val total = checklist.totalCount
            val checked = checklist.checkedCount
            val state = when {
                checklist.stateMessage == "Saved lists could not be read" -> "unavailable"
                checklist.stateMessage == "This list was deleted" -> "missing"
                checklist.outingId != null -> "active"
                checklist.completedHistory -> "completed"
                checklist.canStart -> "preview"
                else -> "empty"
            }
            val subtitle = checklist.progress
            return mapOf(
                "pinSupported" to true,
                "checklist" to mapOf(
                    "title" to checklist.title,
                    "subtitle" to subtitle,
                    "blueprintId" to checklist.blueprintId,
                    "outingId" to checklist.outingId,
                    "state" to state,
                    "checked" to checked,
                    "total" to total,
                    "items" to checklist.items.map { mapOf("id" to it.id, "label" to it.label, "checked" to it.checked) },
                    "remainingItems" to (total - checked).coerceAtLeast(0),
                    "primaryLabel" to when {
                        checklist.blueprintId == null || checklist.stateMessage == "This list was deleted" -> "Choose a list"
                        checklist.outingId == null && checklist.canStart -> "Open checklist"
                        checklist.stateMessage == "Saved lists could not be read" -> "Open app"
                        else -> "Open full checklist"
                    },
                    "date" to checklist.date,
                ),
                "quickLists" to mapOf("title" to "Your lists", "lists" to emptyList<Any>()),
            )
        }
        val lists = (projection as? List<*>)?.filterIsInstance<QuickListWidgetProjection>().orEmpty()
        return mapOf(
            "pinSupported" to true,
            "checklist" to mapOf(
                "title" to "Ready Yet?", "subtitle" to "Choose a list", "state" to "empty",
                "checked" to 0, "total" to 0, "items" to emptyList<Any>(), "remainingItems" to 0, "primaryLabel" to "Open app",
            ),
            "quickLists" to mapOf(
                "title" to "Your lists",
                "lists" to lists.map { list ->
                    mapOf(
                        "id" to list.blueprintId,
                        "title" to list.title,
                        "subtitle" to list.progress,
                        "outingId" to list.outingId,
                        "checked" to list.checkedCount,
                        "total" to list.totalCount,
                        "hasActive" to list.hasActive,
                    )
                },
            ),
        )
    }

    private data class CheckKey(val outingId: String, val itemId: String)

    private data class LifecycleIntent(
        val completedAt: String?,
        val dismissedAtUTC: String?,
    )

    private fun parseCheckIntents(raw: Any?): Map<CheckKey, Boolean> {
        val values = raw as? List<*> ?: return emptyMap()
        val result = linkedMapOf<CheckKey, Boolean>()
        values.forEach { entry ->
            val item = entry as? Map<*, *> ?: return@forEach
            val outingId = item["outingId"] as? String ?: return@forEach
            val itemId = item["itemId"] as? String ?: return@forEach
            val checked = item["checked"] as? Boolean ?: return@forEach
            if (outingId.isNotBlank() && itemId.isNotBlank()) result[CheckKey(outingId, itemId)] = checked
        }
        return result
    }

    private fun parseLifecycleIntents(raw: Any?): Map<String, LifecycleIntent> {
        val values = raw as? List<*> ?: return emptyMap()
        val result = linkedMapOf<String, LifecycleIntent>()
        values.forEach { entry ->
            val item = entry as? Map<*, *> ?: return@forEach
            val outingId = item["outingId"] as? String ?: return@forEach
            if (outingId.isBlank() || !item.containsKey("completedAt") || !item.containsKey("dismissedAtUTC")) return@forEach
            val completedAt = item["completedAt"] as? String
            val dismissedAt = item["dismissedAtUTC"] as? String
            if (item["completedAt"] != null && completedAt == null) return@forEach
            if (item["dismissedAtUTC"] != null && dismissedAt == null) return@forEach
            result[outingId] = LifecycleIntent(completedAt, dismissedAt)
        }
        return result
    }

    /** Checks/lifecycle have separate intent masks; only structure is compared. */
    private fun sameOutingSnapshot(left: JSONObject, right: JSONObject): Boolean {
        val fields = listOf("id", "scheduleId", "blueprintId", "blueprintName", "date", "startedAt")
        if (fields.any { left.optString(it) != right.optString(it) }) return false
        fun items(value: JSONObject) = ChecklistScheduleState.objects(value.optJSONArray("items")).map {
            listOf(it.optString("id"), it.optString("label"), it.optString("iconKey"))
        }
        return items(left) == items(right)
    }

    private fun mergeExistingState(
        target: JSONObject,
        current: JSONObject,
        checkIntents: Map<CheckKey, Boolean>,
        lifecycleIntents: Map<String, LifecycleIntent>,
        nextRevision: Long,
    ): Set<String> {
        val targetOutings = target.optJSONArray("outings") ?: return emptySet()
        val currentOutings = current.optJSONArray("outings")
        val rejectedFinishes = linkedSetOf<String>()
        val checkRevisions = copyObject(current.optJSONObject("_widgetCheckRevisions") ?: JSONObject())
        val seenOutingIds = mutableSetOf<String>()

        for (outingIndex in 0 until targetOutings.length()) {
            val targetOuting = targetOutings.optJSONObject(outingIndex) ?: continue
            val outingId = targetOuting.optString("id").takeIf(String::isNotBlank) ?: continue
            if (!seenOutingIds.add(outingId)) throw JSONException("Duplicate outing ID '$outingId'.")
            val currentOuting = uniqueObject(currentOutings, outingId)

            // Flutter owns structure. Explicit masks are the only authority for
            // changing a previously committed check or lifecycle tuple.
            if (currentOuting != null) {
                targetOuting.put("completedAt", nullableJsonValue(currentOuting, "completedAt"))
                targetOuting.put("dismissedAtUTC", nullableJsonValue(currentOuting, "dismissedAtUTC"))
            }
            lifecycleIntents[outingId]?.let { intent ->
                targetOuting.put("completedAt", intent.completedAt ?: JSONObject.NULL)
                targetOuting.put("dismissedAtUTC", intent.dismissedAtUTC ?: JSONObject.NULL)
            }

            val currentItems = objectMap(currentOuting?.optJSONArray("items"))
            val targetItems = targetOuting.optJSONArray("items")
                ?: throw JSONException("Outing '$outingId' has no checklist item array.")
            val targetIds = mutableSetOf<String>()
            val revisionsForOuting = checkRevisions.optJSONObject(outingId) ?: JSONObject().also {
                checkRevisions.put(outingId, it)
            }
            for (itemIndex in 0 until targetItems.length()) {
                val targetItem = targetItems.optJSONObject(itemIndex) ?: continue
                val itemId = targetItem.optString("id").takeIf(String::isNotBlank) ?: continue
                if (!targetIds.add(itemId)) throw JSONException("Duplicate item ID in outing '$outingId'.")
                val currentItem = currentItems[itemId]
                val targetRawChecked = targetItem.opt("checked")
                if (targetRawChecked !is Boolean) throw JSONException("Checklist item '$itemId' has an invalid checked value.")
                val targetChecked = targetRawChecked
                val currentRawChecked = currentItem?.opt("checked")
                if (currentItem != null && currentRawChecked !is Boolean) throw JSONException("Saved checklist item '$itemId' has an invalid checked value.")
                val currentChecked = currentRawChecked as? Boolean
                val explicit = checkIntents[CheckKey(outingId, itemId)]
                val merged = WidgetCheckMergePolicy.mergeAuthorizedAppCheck(
                    targetChecked,
                    currentChecked,
                    explicit,
                    currentItem != null,
                    lifecycleIntents.containsKey(outingId),
                ) ?: continue
                targetItem.put("checked", merged)
                if (WidgetCheckMergePolicy.shouldAdvanceItemRevision(
                        explicit != null,
                        lifecycleIntents.containsKey(outingId),
                        targetChecked != merged,
                        currentChecked != null && currentChecked != merged,
                    )) {
                    revisionsForOuting.put(itemId, nextRevision)
                }
            }

            val itemsNow = targetOuting.optJSONArray("items") ?: continue
            val checkedNow = (0 until itemsNow.length()).count { itemsNow.optJSONObject(it)?.optBoolean("checked", false) == true }
            val hasFinishIntent = lifecycleIntents[outingId]?.completedAt != null
            if (isCompletedOuting(targetOuting) && !WidgetCheckMergePolicy.keepCompleted(true, itemsNow.length(), checkedNow)) {
                if (hasFinishIntent) {
                    rejectedFinishes += outingId
                    targetOuting.put("dismissedAtUTC", JSONObject.NULL)
                }
                targetOuting.put("completedAt", JSONObject.NULL)
            }
        }
        target.put("_widgetCheckRevisions", checkRevisions)
        return rejectedFinishes
    }

    private fun nullableJsonValue(source: JSONObject, key: String): Any =
        if (source.has(key)) source.opt(key) ?: JSONObject.NULL else JSONObject.NULL

    private fun copyObject(source: JSONObject): JSONObject = JSONObject(source.toString())

    private fun canonicalize(
        source: JSONObject,
        epoch: String,
        revision: Long,
        summaryOverride: JSONObject? = null,
    ): JSONObject = copyObject(source).apply {
        remove("_rejectedFinishIds")
        put(META_EPOCH, epoch.ifBlank { LEGACY_EPOCH })
        put(META_REVISION, revision.coerceAtLeast(0L))
        put("_widgetSummary", summaryOverride ?: deriveSummary(this))
    }

    private fun commitCanonical(context: Context, canonical: JSONObject): String {
        val encoded = canonical.toString()
        writeRecovering(context.filesDir, STATE_FILE, STATE_BACKUP, encoded, ::isValidStateJson)
        val summary = canonical.optJSONObject("_widgetSummary") ?: deriveSummary(canonical)
        runCatching { writeRecovering(context.filesDir, WIDGET_FILE, WIDGET_BACKUP, summary.toString(), ::isValidJson) }
            .onFailure { Log.w(TAG, "Widget summary cache update failed after state commit.") }
        return encoded
    }

    private fun uniqueObject(values: org.json.JSONArray?, id: String): JSONObject? {
        if (values == null) return null
        val matches = (0 until values.length()).mapNotNull(values::optJSONObject).filter { it.optString("id") == id }
        if (matches.size > 1) throw JSONException("Duplicate stable ID '$id'.")
        return matches.singleOrNull()
    }

    private fun objectMap(values: org.json.JSONArray?): Map<String, JSONObject> {
        if (values == null) return emptyMap()
        val result = LinkedHashMap<String, JSONObject>()
        for (index in 0 until values.length()) {
            val item = values.optJSONObject(index) ?: continue
            val id = item.optString("id").takeIf(String::isNotBlank) ?: continue
            if (result.put(id, item) != null) throw JSONException("Duplicate stable item ID '$id'.")
        }
        return result
    }

    private fun isActiveOuting(outing: JSONObject): Boolean =
        !isCompletedOuting(outing) && !isDismissedOuting(outing)

    private fun isCompletedOuting(outing: JSONObject): Boolean =
        outing.opt("completedAt")?.let { it != JSONObject.NULL } == true

    private fun isDismissedOuting(outing: JSONObject): Boolean =
        outing.opt("dismissedAtUTC")?.let { it != JSONObject.NULL } == true

    private fun latestActiveOutingId(outings: org.json.JSONArray): String? =
        (0 until outings.length())
            .mapNotNull(outings::optJSONObject)
            .filter(::isActiveOuting)
            .maxByOrNull { it.optString("startedAt") }
            ?.optString("id")

    private fun deriveSummary(root: JSONObject): JSONObject {
        val outings = root.optJSONArray("outings") ?: return emptySummary()
        val today = ChecklistScheduleState.dateKey(java.util.Calendar.getInstance(java.util.TimeZone.getDefault(), java.util.Locale.US))
        val all = (0 until outings.length()).mapNotNull(outings::optJSONObject)
            .filter { it.isNull("scheduleId") || it.optString("date") == today }
        val active = all.filter(::isActiveOuting).maxByOrNull { it.optString("startedAt") }
        val summaryOuting = active ?: all.filterNot(::isDismissedOuting).maxByOrNull { it.optString("startedAt") }
            ?: return emptySummary()
        val items = summaryOuting.optJSONArray("items")
        val total = items?.length() ?: 0
        val checked = if (items == null) 0 else (0 until total).count { items.optJSONObject(it)?.optBoolean("checked", false) == true }
        return JSONObject().apply {
            put("title", summaryOuting.optString("blueprintName", "Ready Yet?"))
            put("checked", checked)
            put("total", total)
            put("completed", isCompletedOuting(summaryOuting))
        }
    }

    private fun emptySummary() = JSONObject().apply {
        put("title", "Ready Yet?")
        put("checked", 0)
        put("total", 0)
        put("completed", false)
    }

    private fun isValidSummary(value: JSONObject): Boolean =
        value.opt("title") is String &&
            value.opt("checked") is Number &&
            value.opt("total") is Number &&
            value.opt("completed") is Boolean

    private fun addResponseRejections(json: String, rejected: Set<String>): String {
        if (rejected.isEmpty()) return json
        return parseObject(json).put("_rejectedFinishIds", org.json.JSONArray(rejected)).toString()
    }

    private fun readRecovering(
        directory: File,
        primaryName: String,
        backupName: String,
        isValid: (String) -> Boolean,
    ): String? {
        val primary = File(directory, primaryName)
        val backup = File(directory, backupName)
        if (!primary.exists() && !backup.exists()) return null
        val primaryContents = if (primary.exists()) runCatching { primary.readText(Charsets.UTF_8) }.getOrNull() else null
        val backupContents = if (backup.exists()) runCatching { backup.readText(Charsets.UTF_8) }.getOrNull() else null
        val primaryValid = primaryContents != null && isValid(primaryContents)
        val backupValid = backupContents != null && isValid(backupContents)
        if (backupValid) return backupContents
        if (primaryValid) return primaryContents
        throw JSONException("Saved data is damaged and no valid backup is available; the original files were preserved.")
    }

    private fun writeRecovering(
        directory: File,
        name: String,
        backupName: String,
        contents: String,
        isValid: (String) -> Boolean,
    ) {
        readRecovering(directory, name, backupName, isValid)
        val primary = File(directory, name)
        val backup = File(directory, backupName)
        val primaryValid = primary.exists() && runCatching { primary.readText(Charsets.UTF_8) }.getOrNull()?.let(isValid) == true
        val backupValid = backup.exists() && runCatching { backup.readText(Charsets.UTF_8) }.getOrNull()?.let(isValid) == true
        val archiveSuffix = ".damaged.${System.currentTimeMillis()}.${UUID.randomUUID()}"
        if (primary.exists() && !primaryValid && backupValid) archiveIfPresent(primary, archiveSuffix)
        if (backup.exists() && !backupValid && primaryValid) archiveIfPresent(backup, archiveSuffix)
        val atomic = AtomicFile(File(directory, name))
        val output = atomic.startWrite()
        try {
            output.write(contents.toByteArray(Charsets.UTF_8))
            atomic.finishWrite(output)
        } catch (error: Throwable) {
            atomic.failWrite(output)
            throw error
        }
    }

    private fun writeAtomically(file: File, contents: String) {
        val atomic = AtomicFile(file)
        val output = atomic.startWrite()
        try {
            output.write(contents.toByteArray(Charsets.UTF_8))
            atomic.finishWrite(output)
        } catch (error: Throwable) {
            atomic.failWrite(output)
            throw error
        }
    }

    private fun archiveIfPresent(file: File, suffix: String) {
        if (!file.exists()) return
        val archive = File(file.parentFile, file.name + suffix)
        if (!file.renameTo(archive)) throw IOException("Could not preserve damaged file ${file.name} before reset.")
    }

    private fun validateStateJson(value: String) {
        if (!isValidStateJson(value)) throw JSONException("The saved state has an unsupported version or invalid top-level structure.")
    }

    private fun isValidJson(value: String): Boolean = try {
        parseObject(value)
        true
    } catch (_: Exception) {
        false
    }

    private fun isValidStateJson(value: String): Boolean {
        return try {
        val json = parseObject(value)
        if (!ChecklistScheduleState.valid(json)) return false
        val rawSettings = json.opt("settings")
        if (json.opt("version") !is Number || json.optInt("version", -1) != 1) return false
        if (rawSettings != null && rawSettings != JSONObject.NULL && rawSettings !is JSONObject) return false
        val requests = json.opt("widgetLaunchRequests")
        if (requests != null && requests != JSONObject.NULL) {
            if (requests !is JSONObject) return false
            val keys = requests.keys()
            while (keys.hasNext()) if (requests.opt(keys.next()) !is String) return false
        }
        if (json.has(META_EPOCH) && (json.opt(META_EPOCH) !is String || json.optString(META_EPOCH).isBlank())) return false
        if (json.has(META_REVISION) && ((json.opt(META_REVISION) !is Number) || json.optLong(META_REVISION, -1L) < 0L)) return false
        if (json.has("_widgetCheckRevisions") && json.opt("_widgetCheckRevisions") !is JSONObject) return false
        json.optJSONObject("_widgetCheckRevisions")?.let { revisions ->
            val outingKeys = revisions.keys()
            while (outingKeys.hasNext()) {
                val itemRevisions = revisions.opt(outingKeys.next()) as? JSONObject ?: return false
                val itemKeys = itemRevisions.keys()
                while (itemKeys.hasNext()) {
                    val revision = itemRevisions.opt(itemKeys.next()) as? Number ?: return false
                    if (revision.toLong() < 0L) return false
                }
            }
        }
        val blueprints = json.optJSONArray("blueprints") ?: return false
        val extras = json.optJSONArray("extras") ?: return false
        val outings = json.optJSONArray("outings") ?: return false
        val blueprintIds = mutableSetOf<String>()
        for (index in 0 until blueprints.length()) {
            val blueprint = blueprints.optJSONObject(index) ?: return false
            val id = nonblank(blueprint, "id") ?: return false
            if (!blueprintIds.add(id) || nonblank(blueprint, "name") == null) return false
            val items = blueprint.optJSONArray("items") ?: return false
            val ids = mutableSetOf<String>()
            for (itemIndex in 0 until items.length()) {
                val item = items.optJSONObject(itemIndex) ?: return false
                val itemId = nonblank(item, "id") ?: return false
                if (!ids.add(itemId) || nonblank(item, "label") == null) return false
            }
        }
        val extraIds = mutableSetOf<String>()
        for (index in 0 until extras.length()) {
            val extra = extras.optJSONObject(index) ?: return false
            val id = nonblank(extra, "id") ?: return false
            if (!extraIds.add(id) || nonblank(extra, "blueprintId") == null ||
                nonblank(extra, "date") == null || nonblank(extra, "label") == null) return false
        }
        val outingIds = mutableSetOf<String>()
        for (index in 0 until outings.length()) {
            val outing = outings.optJSONObject(index) ?: return false
            val id = nonblank(outing, "id") ?: return false
            if (!outingIds.add(id) || nonblank(outing, "blueprintId") == null ||
                nonblank(outing, "blueprintName") == null || nonblank(outing, "date") == null ||
                nonblank(outing, "startedAt") == null) return false
            for (field in listOf("completedAt", "dismissedAtUTC")) {
                if (outing.has(field) && outing.opt(field) != JSONObject.NULL && outing.opt(field) !is String) return false
            }
            val items = outing.optJSONArray("items") ?: return false
            val itemIds = mutableSetOf<String>()
            for (itemIndex in 0 until items.length()) {
                val item = items.optJSONObject(itemIndex) ?: return false
                val itemId = nonblank(item, "id") ?: return false
                if (!itemIds.add(itemId) || nonblank(item, "label") == null || item.opt("checked") !is Boolean) return false
            }
        }
        true
    } catch (_: Exception) {
        false
    }
    }

    private fun nonblank(objectValue: JSONObject, key: String): String? =
        (objectValue.opt(key) as? String)?.takeIf(String::isNotBlank)

    private fun parseObject(value: String): JSONObject {
        val tokener = JSONTokener(value)
        val root = tokener.nextValue()
        if (root !is JSONObject || tokener.nextClean() != '\u0000') {
            throw JSONException("Expected one complete JSON object.")
        }
        return root
    }
}
