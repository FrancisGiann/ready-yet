package dev.giann.before_i_leave

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.SizeF
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.util.concurrent.Executors

/** Interactive checklist provider. It only changes checks in an existing active outing. */
class LeaveWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, widgetIds: IntArray) {
        WidgetRenderService.refresh(context, manager, widgetIds, goAsync())
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, appWidgetId: Int, newOptions: android.os.Bundle) {
        WidgetRenderService.refresh(context, manager, intArrayOf(appWidgetId), goAsync())
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        appWidgetIds.forEach { WidgetInstanceConfigStore.remove(context, it) }
    }

    companion object {
        fun refreshAll(context: Context) = WidgetRenderService.refreshAll(context, LeaveWidgetProvider::class.java)
    }
}

/** Compact, multi-list launcher surface. Taps only open the selected list/outing. */
class QuickListsWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, widgetIds: IntArray) {
        WidgetRenderService.refresh(context, manager, widgetIds, goAsync())
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, appWidgetId: Int, newOptions: android.os.Bundle) {
        WidgetRenderService.refresh(context, manager, intArrayOf(appWidgetId), goAsync())
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        appWidgetIds.forEach { WidgetInstanceConfigStore.remove(context, it) }
    }

    companion object {
        fun refreshAll(context: Context) = WidgetRenderService.refreshAll(context, QuickListsWidgetProvider::class.java)
    }
}

/** Always follows the selected schedule occurrence for today; it has no per-instance list configuration. */
class ScheduledChecklistWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, widgetIds: IntArray) {
        val pending = goAsync()
        ChecklistScheduleScheduler.enqueue(context, pending) {
            WidgetRenderService.refresh(context.applicationContext, manager, widgetIds, pending)
        }
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, appWidgetId: Int, newOptions: android.os.Bundle) {
        WidgetRenderService.refresh(context, manager, intArrayOf(appWidgetId), goAsync())
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        appWidgetIds.forEach { WidgetInstanceConfigStore.removeScheduled(context, it) }
    }

    companion object {
        fun refreshAll(context: Context) = WidgetRenderService.refreshAll(context, ScheduledChecklistWidgetProvider::class.java)
    }
}

internal object WidgetRenderService {
    private data class RenderState(
        val state: JSONObject?,
        val checklist: ChecklistWidgetProjection,
        val quick: List<QuickListWidgetProjection>,
        val scheduled: ScheduledChecklistProjection,
    )
    private val worker = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "before-i-leave-widget-render").apply { isDaemon = true }
    }
    private val main = Handler(Looper.getMainLooper())

    fun refreshAll(context: Context, provider: Class<out AppWidgetProvider>) {
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(ComponentName(context, provider))
        refresh(context.applicationContext, manager, ids, null)
    }

    /** Refresh every installed widget in one worker pass and finish one receiver lifetime afterward. */
    fun refreshAllKinds(context: Context, pending: BroadcastReceiver.PendingResult?) {
        val manager = AppWidgetManager.getInstance(context)
        val providers = listOf(
            LeaveWidgetProvider::class.java,
            QuickListsWidgetProvider::class.java,
            ScheduledChecklistWidgetProvider::class.java,
        )
        val ids = providers.flatMap { provider ->
            manager.getAppWidgetIds(ComponentName(context, provider)).asIterable()
        }.distinct().toIntArray()
        refresh(context.applicationContext, manager, ids, pending)
    }

    fun refresh(context: Context, manager: AppWidgetManager, ids: IntArray, pending: BroadcastReceiver.PendingResult?) {
        if (ids.isEmpty()) {
            pending?.finish()
            return
        }
        worker.execute {
            try {
                val states = ids.associateWith { id ->
                    val providerName = manager.getAppWidgetInfo(id)?.provider?.className.orEmpty()
                    when {
                        providerName.endsWith("QuickListsWidgetProvider") -> WidgetInstanceConfigStore.bindingGeneration(context, id, quickLists = true)
                        providerName.endsWith("ScheduledChecklistWidgetProvider") -> WidgetInstanceConfigStore.scheduledBindingGeneration(context, id)
                        else -> WidgetInstanceConfigStore.bindingGeneration(context, id, quickLists = false)
                    }
                    runCatching { NativeStateStore.readState(context) }.getOrNull()
                        ?.let { json ->
                            val root = runCatching { JSONObject(json) }.getOrNull()
                            val check = NativeWidgetProjection.checklists(json, WidgetInstanceConfigStore.checklistBlueprintId(context, id))
                            val quick = NativeWidgetProjection.quickLists(json, WidgetInstanceConfigStore.quickListBlueprintIds(context, id))
                            val scheduled = NativeWidgetProjection.scheduledChecklist(json)
                            RenderState(root, check, quick, scheduled)
                        }
                }
                main.post {
                    try {
                        ids.forEach { id ->
                            val state = states[id]
                            if (state != null) {
                                val providerName = manager.getAppWidgetInfo(id)?.provider?.className.orEmpty()
                                when {
                                    providerName.endsWith("QuickListsWidgetProvider") -> renderQuick(context, manager, id, state.quick)
                                    providerName.endsWith("ScheduledChecklistWidgetProvider") -> renderScheduled(context, manager, id, state.state, state.scheduled)
                                    else -> renderChecklist(context, manager, id, state.state, state.checklist)
                                }
                            } else {
                                renderUnavailable(context, manager, id)
                            }
                        }
                    } finally {
                        pending?.finish()
                    }
                }
            } catch (error: Exception) {
                android.util.Log.e("ReadyYetWidgetRender", "Could not prepare widget views", error)
                pending?.finish()
            }
        }
    }

    private fun renderChecklist(context: Context, manager: AppWidgetManager, widgetId: Int, state: JSONObject?, projection: ChecklistWidgetProjection) {
        updateSizedViews(context, manager, widgetId) { size ->
            checklistViews(context, widgetId, state, projection, size)
        }
    }

    private fun renderScheduled(
        context: Context,
        manager: AppWidgetManager,
        widgetId: Int,
        state: JSONObject?,
        projection: ScheduledChecklistProjection,
    ) {
        if (state == null) {
            renderUnavailable(context, manager, widgetId)
            return
        }
        updateSizedViews(context, manager, widgetId) { size ->
            checklistViews(context, widgetId, state, projection.checklist, size, projection)
        }
    }

    private fun checklistViews(
        context: Context,
        widgetId: Int,
        state: JSONObject?,
        projection: ChecklistWidgetProjection,
        size: WidgetSize,
        scheduled: ScheduledChecklistProjection? = null,
    ): RemoteViews {
        val epoch = state?.optString("_storageEpoch", "legacy-v1") ?: "legacy-v1"
        val revision = state?.optLong("_nativeRevision", 0L) ?: 0L
        val generation = if (scheduled != null) WidgetInstanceConfigStore.scheduledBindingGeneration(context, widgetId).orEmpty()
            else WidgetInstanceConfigStore.bindingGeneration(context, widgetId, quickLists = false).orEmpty()
        val tiny = WidgetResizePolicy.usesTwoByTwoLayout(size.widthDp, size.heightDp)
        val compact = WidgetResizePolicy.checklistUsesCompactLayout(size.widthDp, size.heightDp, size.fontScale)
        val maxRows = WidgetResizePolicy.checklistRows(size.widthDp, size.heightDp, size.fontScale)
        val layout = when {
            tiny -> R.layout.before_i_leave_widget_2x2
            compact -> R.layout.before_i_leave_widget_compact
            else -> R.layout.before_i_leave_widget
        }
        val rowIds = intArrayOf(R.id.widget_item_1, R.id.widget_item_2, R.id.widget_item_3, R.id.widget_item_4, R.id.widget_item_5)
        val indicatorIds = intArrayOf(R.id.widget_item_indicator_1, R.id.widget_item_indicator_2, R.id.widget_item_indicator_3, R.id.widget_item_indicator_4, R.id.widget_item_indicator_5)
        val labelIds = intArrayOf(R.id.widget_item_label_1, R.id.widget_item_label_2, R.id.widget_item_label_3, R.id.widget_item_label_4, R.id.widget_item_label_5)
        val views = RemoteViews(context.packageName, layout).apply {
            if (compact) {
                setViewVisibility(R.id.widget_brand_tagline, View.GONE)
                setViewVisibility(R.id.widget_progress_bar, View.GONE)
                setViewVisibility(R.id.widget_item_rows, if (maxRows > 0) View.VISIBLE else View.GONE)
                if (maxRows == 0) setViewVisibility(R.id.widget_title_row, View.GONE)
            }
            setTextViewText(R.id.widget_title, projection.title)
            val compactProgress = when {
                projection.stateMessage == "Completed today" || projection.stateMessage == "Skipped today" -> projection.progress
                projection.totalCount <= 0 -> projection.progress
                projection.outingId != null -> "${projection.checkedCount}/${projection.totalCount}"
                else -> "${projection.totalCount} ready"
            }
            setTextViewText(R.id.widget_progress, if (compact) compactProgress else projection.progress)
            setContentDescription(R.id.widget_title, projection.title)
            setContentDescription(R.id.widget_progress, projection.progress)
            val total = projection.totalCount.coerceAtLeast(0)
            val checked = projection.checkedCount.coerceIn(0, total)
            setViewVisibility(R.id.widget_progress_bar, if (total > 0 && !compact) View.VISIBLE else View.GONE)
            setProgressBar(R.id.widget_progress_bar, 100, if (total > 0) checked * 100 / total else 0, false)
            rowIds.forEachIndexed { index, rowId ->
                val item = projection.items.getOrNull(index).takeIf { index < maxRows }
                if (item == null) {
                    setViewVisibility(rowId, View.GONE)
                } else {
                    val oldItemRevision = state?.optJSONObject("_widgetCheckRevisions")
                        ?.optJSONObject(projection.outingId.orEmpty())?.optLong(item.id, 0L) ?: 0L
                    setViewVisibility(rowId, View.VISIBLE)
                    setImageViewResource(
                        indicatorIds[index],
                        if (item.checked) R.drawable.widget_check_checked else R.drawable.widget_check_unchecked,
                    )
                    setTextViewText(labelIds[index], item.label)
                    setContentDescription(rowId, if (item.checked) "${item.label}, packed" else "${item.label}, not packed")
                    val scheduledCheckOutingId = scheduled?.checkOutingId
                    if (scheduledCheckOutingId != null && item.canToggle) {
                        setOnClickPendingIntent(rowId, WidgetIntentContract.scheduledCheckedBroadcast(
                            context, widgetId, scheduled.scheduleId.orEmpty(), scheduledCheckOutingId, item.id, !item.checked,
                            generation, epoch, revision, oldItemRevision,
                        ))
                    } else if (scheduled != null && scheduled.openOutingId != null && scheduled.scheduleId != null) {
                        setOnClickPendingIntent(rowId, WidgetIntentContract.openScheduledOuting(
                            context, widgetId, scheduled.scheduleId, scheduled.openOutingId, epoch,
                        ))
                    } else if (scheduled != null) {
                        setOnClickPendingIntent(rowId, WidgetIntentContract.openWidgetSchedules(context, widgetId))
                    } else if (projection.outingId != null && item.canToggle) {
                        setOnClickPendingIntent(rowId, WidgetIntentContract.checkedBroadcast(
                            context, widgetId, projection.outingId, item.id, !item.checked,
                            generation, epoch, revision, oldItemRevision,
                        ))
                    } else setOnClickPendingIntent(rowId, WidgetIntentContract.openDestination(context, widgetId, projection.blueprintId, null))
                }
            }
            val shownItems = minOf(projection.items.size, maxRows)
            val overflow = (projection.totalCount - shownItems).coerceAtLeast(0)
            val configure = scheduled == null && (projection.blueprintId == null || projection.stateMessage == "This list was deleted")
            val action = when {
                scheduled != null -> when (scheduled.state) {
                    "completed" -> "Review completed checklist"
                    "skipped" -> "View schedules"
                    "no_schedules" -> "Set up schedules"
                    "no_today" -> "View schedules"
                    "unavailable" -> "Open app"
                    else -> "Open scheduled checklist"
                }
                configure -> "Choose a list"
                projection.outingId == null && projection.canStart -> "Open checklist"
                projection.stateMessage == "Saved lists could not be read" -> "Open app"
                compact && maxRows == 0 -> "Open ${projection.title}"
                else -> "Open full checklist"
            }
            val actionTarget = if (tiny) R.id.widget_action_container else R.id.widget_action
            if (tiny) {
                setInt(actionTarget, "setMinimumHeight", dp(context, WidgetResizePolicy.twoByTwoChecklistFooterHeightDp(size.fontScale)))
                setTextViewText(R.id.widget_action, when {
                    configure -> "Choose a list"
                    !projection.canOpenList -> "Open Ready Yet?"
                    else -> "Open ${projection.title}"
                })
                val status = when {
                    projection.stateMessage == "Completed today" || projection.stateMessage == "Skipped today" -> projection.progress
                    configure -> "Ready Yet?"
                    projection.totalCount == 0 -> "Add items in app"
                    projection.outingId != null -> "$compactProgress packed"
                    else -> "$compactProgress to pack"
                }
                setTextViewText(R.id.widget_small_progress, if (overflow > 0 && shownItems > 0) "$status · +$overflow" else status)
                setViewVisibility(R.id.widget_title_row, View.GONE)
            } else {
                setTextViewText(R.id.widget_action, if (overflow > 0 && maxRows > 0) "$action · +$overflow more" else action)
            }
            val destination = when {
                scheduled != null && scheduled.openOutingId != null && scheduled.scheduleId != null ->
                    WidgetIntentContract.openScheduledOuting(context, widgetId, scheduled.scheduleId, scheduled.openOutingId, epoch)
                scheduled != null -> WidgetIntentContract.openWidgetSchedules(context, widgetId)
                configure -> WidgetIntentContract.configuration(context, widgetId, quickLists = false)
                else -> WidgetIntentContract.openDestination(context, widgetId, projection.blueprintId, projection.outingId)
            }
            val openDescription = when {
                configure -> "Choose a checklist for this widget"
                compact && maxRows == 0 -> "${projection.title}. ${projection.progress}. Open it in Ready Yet?"
                else -> "Open ${projection.title} in Ready Yet?"
            }
            setContentDescription(actionTarget, "${projection.title}. ${projection.progress}. $openDescription" + if (overflow > 0) ". $overflow more items in app." else "")
            setContentDescription(R.id.widget_root, openDescription)
            setOnClickPendingIntent(actionTarget, destination)
            setOnClickPendingIntent(R.id.widget_root, destination)
        }
        if (scheduled == null) return views
        val openText = when (scheduled.state) {
            "completed" -> "Review completed"
            "skipped", "no_today" -> "View schedules"
            "no_schedules" -> "Set up schedules"
            "unavailable" -> "Open app"
            else -> "Open checklist"
        }
        val packedCount = if (projection.totalCount > 0) "${projection.checkedCount}/${projection.totalCount}" else ""
        val packedLabel = if (packedCount.isNotBlank()) "$packedCount packed" else ""
        val primaryStatus = listOf(if (tiny) packedCount else packedLabel, scheduled.dueLabel)
            .filter(String::isNotBlank).joinToString(" · ")
        val tinyStatus = when (scheduled.state) {
            "no_today" -> scheduled.upcomingLabel.ifBlank { "View schedules" }
            "no_schedules" -> "Set up in app"
            else -> primaryStatus
        }
        views.setTextViewText(R.id.widget_progress, primaryStatus)
        views.setContentDescription(R.id.widget_progress, listOf(projection.progress, primaryStatus, scheduled.upcomingLabel)
            .filter(String::isNotBlank).joinToString(". "))
        val actionText = if (scheduled.upcomingLabel.isBlank()) openText else "$openText · ${scheduled.upcomingLabel}"
        views.setTextViewText(R.id.widget_action, if (!tiny && compact && maxRows == 0) {
            listOf(primaryStatus, scheduled.upcomingLabel).filter(String::isNotBlank).joinToString(" · ")
        } else actionText)
        views.setContentDescription(R.id.widget_root, listOf(projection.title, projection.progress, primaryStatus, scheduled.upcomingLabel, openText)
            .filter(String::isNotBlank).joinToString(". "))
        views.setContentDescription(if (tiny) R.id.widget_action_container else R.id.widget_action,
            listOf(projection.title, projection.progress, primaryStatus, scheduled.upcomingLabel, openText)
                .filter(String::isNotBlank).joinToString(". "))
        if (tiny) {
            val tinyActionText = when (scheduled.state) {
                "active", "empty", "completed", "skipped" -> projection.title
                "no_today" -> "Nothing today"
                "no_schedules" -> "No schedules yet"
                else -> openText
            }
            views.setTextViewText(R.id.widget_action, tinyActionText)
            views.setTextViewText(R.id.widget_small_progress, tinyStatus)
        }
        return views
    }

    private fun renderQuick(context: Context, manager: AppWidgetManager, widgetId: Int, projections: List<QuickListWidgetProjection>) {
        updateSizedViews(context, manager, widgetId) { size -> quickViews(context, widgetId, projections, size) }
    }

    private fun quickViews(
        context: Context,
        widgetId: Int,
        projections: List<QuickListWidgetProjection>,
        size: WidgetSize,
    ): RemoteViews {
        val tiny = WidgetResizePolicy.usesTwoByTwoLayout(size.widthDp, size.heightDp)
        val compact = WidgetResizePolicy.quickListsUsesCompactLayout(size.widthDp, size.heightDp, size.fontScale)
        val layout = when {
            tiny -> R.layout.quick_lists_widget_2x2
            compact -> R.layout.quick_lists_widget_compact
            else -> R.layout.quick_lists_widget
        }
        val ids = intArrayOf(R.id.quick_list_1, R.id.quick_list_2, R.id.quick_list_3, R.id.quick_list_4)
        val titleIds = intArrayOf(R.id.quick_list_title_1, R.id.quick_list_title_2, R.id.quick_list_title_3, R.id.quick_list_title_4)
        val statusIds = intArrayOf(R.id.quick_list_status_1, R.id.quick_list_status_2, R.id.quick_list_status_3, R.id.quick_list_status_4)
        val badgeIds = intArrayOf(R.id.quick_list_badge_1, R.id.quick_list_badge_2, R.id.quick_list_badge_3, R.id.quick_list_badge_4)
        val rowBudget = WidgetResizePolicy.quickListRows(size.widthDp, size.heightDp, size.fontScale)
        val visibleLists = projections.take(minOf(ids.size, rowBudget))
        return RemoteViews(context.packageName, layout).apply {
            if (compact) {
                setViewVisibility(R.id.quick_widget_tagline, View.GONE)
                setViewVisibility(R.id.quick_list_rows, if (rowBudget > 0) View.VISIBLE else View.GONE)
                if (!tiny && size.fontScale >= 2.5f) {
                    setViewPadding(R.id.quick_widget_root, dp(context, 8), dp(context, 2), dp(context, 8), dp(context, 2))
                    setTextViewTextSize(R.id.quick_widget_title, TypedValue.COMPLEX_UNIT_SP, 9f)
                }
            }
            ids.forEachIndexed { index, rowId ->
                val list = visibleLists.getOrNull(index)
                if (list == null) setViewVisibility(rowId, View.GONE)
                else {
                    setViewVisibility(rowId, View.VISIBLE)
                    setTextViewText(titleIds[index], list.title)
                    val compactStatus = when {
                        list.stateMessage == "Completed today" || list.stateMessage == "Skipped today" -> list.progress
                        tiny && list.hasActive && list.totalCount > 0 -> "${list.checkedCount}/${list.totalCount} packed"
                        list.hasActive && list.totalCount > 0 -> "${list.checkedCount} packed"
                        list.totalCount > 0 -> "${list.totalCount} ready"
                        else -> "Add items"
                    }
                    setTextViewText(statusIds[index], if (compact) compactStatus else list.progress)
                    val total = list.totalCount.coerceAtLeast(0)
                    val checked = list.checkedCount.coerceIn(0, total)
                    val badge = when {
                        list.stateMessage == "Completed today" -> "DONE"
                        list.stateMessage == "Skipped today" -> "SKIP"
                        list.hasActive && total > 0 -> "$checked/$total"
                        total > 0 -> "READY"
                        else -> "EMPTY"
                    }
                    setTextViewText(badgeIds[index], badge)
                    val accessibleProgress = when {
                        list.stateMessage == "Completed today" || list.stateMessage == "Skipped today" -> list.progress
                        list.hasActive && total > 0 -> "$checked of $total packed"
                        total > 0 -> "$total items ready to pack"
                        else -> "List is empty"
                    }
                    setContentDescription(rowId, "${list.title}. $accessibleProgress")
                    setContentDescription(statusIds[index], list.progress)
                    val action = if (list.canOpenList) {
                        WidgetIntentContract.openDestination(context, widgetId, list.blueprintId, list.outingId, quickLists = true)
                    } else WidgetIntentContract.configuration(context, widgetId, quickLists = true)
                    setOnClickPendingIntent(rowId, action)
                }
            }
            setViewVisibility(R.id.quick_widget_action, View.VISIBLE)
            setOnClickPendingIntent(R.id.quick_widget_action, WidgetIntentContract.configuration(context, widgetId, quickLists = true))
            val overflow = (projections.size - visibleLists.size).coerceAtLeast(0)
            val action = when {
                tiny && projections.isEmpty() -> "Choose lists"
                tiny && overflow > 0 -> "Lists · +$overflow"
                tiny -> "Manage lists"
                overflow > 0 && rowBudget > 0 -> "Manage quick lists · +$overflow more"
                else -> "Manage quick lists"
            }
            if (tiny) setInt(R.id.quick_widget_action, "setMinimumHeight", dp(context, WidgetResizePolicy.twoByTwoQuickFooterHeightDp(size.fontScale)))
            setTextViewText(R.id.quick_widget_action, action)
            setContentDescription(R.id.quick_widget_action, "Manage quick lists. $overflow more lists available in configuration.")
            setOnClickPendingIntent(
                R.id.quick_widget_root,
                visibleLists.firstOrNull()?.let { WidgetIntentContract.openDestination(context, widgetId, it.blueprintId, it.outingId, quickLists = true) }
                    ?: WidgetIntentContract.openDestination(context, widgetId, null, null, quickLists = true),
            )
            setContentDescription(
                R.id.quick_widget_root,
                visibleLists.firstOrNull()?.takeIf { it.canOpenList }?.let { "Open ${it.title} in Ready Yet?" }
                    ?: "Open Today in Ready Yet?",
            )
        }
    }

    @Suppress("DEPRECATION")
    private fun updateSizedViews(context: Context, manager: AppWidgetManager, widgetId: Int, render: (WidgetSize) -> RemoteViews) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val sizes = manager.getAppWidgetOptions(widgetId)
                .getParcelableArrayList<SizeF>(AppWidgetManager.OPTION_APPWIDGET_SIZES)
                .orEmpty().filter { it.width.isFinite() && it.height.isFinite() && it.width > 0 && it.height > 0 }
                .distinct().take(16)
            if (sizes.isNotEmpty()) {
                manager.updateAppWidget(widgetId, RemoteViews(sizes.associateWith { size ->
                    render(WidgetSize(size.width.toInt(), size.height.toInt(), context.resources.configuration.fontScale))
                }))
                return
            }
        }
        val sizes = widgetSizes(context, manager, widgetId)
        manager.updateAppWidget(widgetId, RemoteViews(render(sizes.landscape), render(sizes.portrait)))
    }

    private data class WidgetSize(val widthDp: Int, val heightDp: Int, val fontScale: Float)
    private data class WidgetSizes(val landscape: WidgetSize, val portrait: WidgetSize)

    private fun widgetSizes(context: Context, manager: AppWidgetManager, widgetId: Int): WidgetSizes {
        val options = manager.getAppWidgetOptions(widgetId)
        val info = manager.getAppWidgetInfo(widgetId)
        val density = context.resources.displayMetrics.density
        val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
        val maxWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 0)
        val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
        val maxHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)
        val fallbackWidth = info?.let { WidgetResizePolicy.pixelsToDpFloor(it.minWidth, density) } ?: 0
        val fallbackHeight = info?.let { WidgetResizePolicy.pixelsToDpFloor(it.minHeight, density) } ?: 0
        val fontScale = context.resources.configuration.fontScale

        fun sizeFor(orientation: Int) = WidgetSize(
            WidgetResizePolicy.availableWidthDp(minWidth, maxWidth, orientation).takeIf { it > 0 } ?: fallbackWidth,
            WidgetResizePolicy.availableHeightDp(minHeight, maxHeight, orientation).takeIf { it > 0 } ?: fallbackHeight,
            fontScale,
        )

        return WidgetSizes(
            landscape = sizeFor(WidgetResizePolicy.ORIENTATION_LANDSCAPE),
            portrait = sizeFor(WidgetResizePolicy.ORIENTATION_PORTRAIT),
        )
    }

    private fun dp(context: Context, value: Int): Int = (value * context.resources.displayMetrics.density).toInt()

    private fun renderUnavailable(context: Context, manager: AppWidgetManager, widgetId: Int) {
        val providerName = manager.getAppWidgetInfo(widgetId)?.provider?.className.orEmpty()
        val quick = providerName.endsWith("QuickListsWidgetProvider")
        val scheduled = providerName.endsWith("ScheduledChecklistWidgetProvider")
        updateSizedViews(context, manager, widgetId) { size ->
            if (quick) unavailableQuickViews(context, widgetId, size)
            else if (scheduled) unavailableScheduledViews(context, widgetId, size)
            else unavailableChecklistViews(context, widgetId, size)
        }
    }

    private fun unavailableScheduledViews(context: Context, widgetId: Int, size: WidgetSize): RemoteViews {
        val tiny = WidgetResizePolicy.usesTwoByTwoLayout(size.widthDp, size.heightDp)
        val layout = if (tiny) R.layout.before_i_leave_widget_2x2 else R.layout.before_i_leave_widget_compact
        val destination = WidgetIntentContract.openWidgetSchedules(context, widgetId)
        return RemoteViews(context.packageName, layout).apply {
            setViewVisibility(R.id.widget_brand_tagline, View.GONE)
            setTextViewText(R.id.widget_title, "Scheduled checklists")
            setTextViewText(R.id.widget_progress, "Open the app to load schedules")
            setViewVisibility(R.id.widget_progress_bar, View.GONE)
            setViewVisibility(R.id.widget_title_row, View.GONE)
            setViewVisibility(R.id.widget_item_rows, View.GONE)
            setTextViewText(R.id.widget_action, if (tiny) "Open schedules" else "Open scheduled checklists")
            setOnClickPendingIntent(R.id.widget_root, destination)
            val target = if (tiny) R.id.widget_action_container else R.id.widget_action
            if (tiny) {
                setInt(target, "setMinimumHeight", dp(context, WidgetResizePolicy.twoByTwoChecklistFooterHeightDp(size.fontScale)))
                setTextViewText(R.id.widget_small_progress, "Load schedules")
            }
            setOnClickPendingIntent(target, destination)
            setContentDescription(target, "Open Ready Yet? schedules to load the saved scheduled checklist.")
            setContentDescription(R.id.widget_root, "Scheduled checklists are unavailable. Open schedules in Ready Yet?.")
        }
    }

    private fun unavailableQuickViews(context: Context, widgetId: Int, size: WidgetSize): RemoteViews {
        val tiny = WidgetResizePolicy.usesTwoByTwoLayout(size.widthDp, size.heightDp)
        val compact = WidgetResizePolicy.quickListsUsesCompactLayout(size.widthDp, size.heightDp, size.fontScale)
        val layout = when {
            tiny -> R.layout.quick_lists_widget_2x2
            compact -> R.layout.quick_lists_widget_compact
            else -> R.layout.quick_lists_widget
        }
        val rowCount = WidgetResizePolicy.quickListRows(size.widthDp, size.heightDp, size.fontScale)
        return RemoteViews(context.packageName, layout).apply {
            setTextViewText(R.id.quick_widget_title, "Ready Yet?")
            if (compact) {
                setViewVisibility(R.id.quick_widget_tagline, View.GONE)
                setViewVisibility(R.id.quick_list_rows, if (rowCount > 0) View.VISIBLE else View.GONE)
                if (!tiny && size.fontScale >= 2.5f) {
                    setViewPadding(R.id.quick_widget_root, dp(context, 8), dp(context, 2), dp(context, 8), dp(context, 2))
                    setTextViewTextSize(R.id.quick_widget_title, TypedValue.COMPLEX_UNIT_SP, 9f)
                }
            }
            if (rowCount > 0) {
                setTextViewText(R.id.quick_list_title_1, "Your lists")
                setTextViewText(R.id.quick_list_status_1, "Open app to load them")
                setTextViewText(R.id.quick_list_badge_1, "OPEN")
                setContentDescription(R.id.quick_list_1, "Saved lists unavailable. Open Ready Yet? to load them.")
                setViewVisibility(R.id.quick_list_1, View.VISIBLE)
                setOnClickPendingIntent(R.id.quick_list_1, WidgetIntentContract.openDestination(context, widgetId, null, null, quickLists = true))
            } else setViewVisibility(R.id.quick_list_1, View.GONE)
            setViewVisibility(R.id.quick_widget_action, View.VISIBLE)
            setTextViewText(R.id.quick_widget_action, if (tiny) "Open app" else "Open Ready Yet?")
            if (tiny) setInt(R.id.quick_widget_action, "setMinimumHeight", dp(context, WidgetResizePolicy.twoByTwoQuickFooterHeightDp(size.fontScale)))
            setOnClickPendingIntent(R.id.quick_widget_action, WidgetIntentContract.openDestination(context, widgetId, null, null, quickLists = true))
            setContentDescription(R.id.quick_widget_root, "Ready Yet? Saved lists are unavailable. Open the app to load them.")
        }
    }

    private fun unavailableChecklistViews(context: Context, widgetId: Int, size: WidgetSize): RemoteViews {
        val tiny = WidgetResizePolicy.usesTwoByTwoLayout(size.widthDp, size.heightDp)
        val layout = if (tiny) R.layout.before_i_leave_widget_2x2 else R.layout.before_i_leave_widget_compact
        return RemoteViews(context.packageName, layout).apply {
            setViewVisibility(R.id.widget_brand_tagline, View.GONE)
            setTextViewText(R.id.widget_title, "Ready Yet?")
            setTextViewText(R.id.widget_progress, "Open the app to load your lists")
            setViewVisibility(R.id.widget_progress_bar, View.GONE)
            setViewVisibility(R.id.widget_title_row, View.GONE)
            setViewVisibility(R.id.widget_item_rows, View.GONE)
            setTextViewText(R.id.widget_action, "Open Ready Yet?")
            setOnClickPendingIntent(R.id.widget_root, WidgetIntentContract.openDestination(context, widgetId, null, null, quickLists = true))
            val target = if (tiny) R.id.widget_action_container else R.id.widget_action
            if (tiny) {
                setInt(target, "setMinimumHeight", dp(context, WidgetResizePolicy.twoByTwoChecklistFooterHeightDp(size.fontScale)))
                setTextViewText(R.id.widget_small_progress, "Load saved lists")
            }
            setOnClickPendingIntent(target, WidgetIntentContract.openDestination(context, widgetId, null, null, quickLists = true))
            setContentDescription(target, "Open Ready Yet? to load saved lists.")
            setContentDescription(R.id.widget_root, "Ready Yet? Saved lists are unavailable. Open the app to load them.")
        }
    }
}
