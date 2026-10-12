package dev.giann.before_i_leave

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Typeface
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.TextView
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executors

internal data class WidgetBlueprintOption(val id: String, val name: String)

enum class WidgetConfigurationKind {
    CHECKLIST,
    QUICK_LISTS,
}

/** Native per-instance picker; selections are stable blueprint IDs, never list positions. */
abstract class BaseWidgetConfigurationActivity : Activity() {
    protected abstract val kind: WidgetConfigurationKind
    private val mainHandler = Handler(Looper.getMainLooper())

    private fun providerClass() = when (kind) {
        WidgetConfigurationKind.CHECKLIST -> LeaveWidgetProvider::class.java
        WidgetConfigurationKind.QUICK_LISTS -> QuickListsWidgetProvider::class.java
    }

    private fun ownsWidget(widgetId: Int): Boolean {
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) return false
        val info = AppWidgetManager.getInstance(this).getAppWidgetInfo(widgetId) ?: return false
        return info.provider == ComponentName(this, providerClass())
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(RESULT_CANCELED)
        val widgetId = intent?.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
            ?: AppWidgetManager.INVALID_APPWIDGET_ID
        if (!ownsWidget(widgetId)) {
            finish()
            return
        }
        showLoading()
        storageExecutor.execute {
            val options = runCatching { NativeStateStore.readState(this) }
                .getOrNull()
                ?.let(::parseBlueprintOptions)
                .orEmpty()
            mainHandler.post { showOptions(widgetId, options) }
        }
    }

    private fun showLoading() {
        val root = column()
        root.addView(text(getString(R.string.app_name), 22, true))
        root.addView(text(getString(R.string.app_tagline), 14, false))
        root.addView(text(getString(R.string.widget_config_loading), 15, false))
        setContentView(scroll(root))
    }

    private fun showOptions(widgetId: Int, options: List<WidgetBlueprintOption>) {
        val root = column()
        root.addView(text(getString(R.string.app_name), 15, true))
        root.addView(text(getString(R.string.app_tagline), 12, false))
        root.addView(text(
            if (kind == WidgetConfigurationKind.CHECKLIST) getString(R.string.widget_checklist_config_title)
            else getString(R.string.widget_quick_lists_config_title),
            26,
            true,
        ))
        root.addView(text(
            if (kind == WidgetConfigurationKind.CHECKLIST) getString(R.string.widget_checklist_config_hint)
            else getString(R.string.widget_quick_lists_config_hint),
            15,
            false,
        ))

        if (options.isEmpty()) {
            root.addView(text(getString(R.string.widget_config_no_lists), 16, false))
            root.addView(button(getString(R.string.widget_config_open_app)) {
                startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                finish()
            })
            setContentView(scroll(root))
            return
        }

        val savedChecklistId = WidgetInstanceConfigStore.checklistBlueprintId(this, widgetId)
        val savedQuickListIds = WidgetInstanceConfigStore.quickListBlueprintIds(this, widgetId).toSet()
        val selected = if (kind == WidgetConfigurationKind.CHECKLIST) {
            RadioGroup(this).apply {
                orientation = RadioGroup.VERTICAL
                options.forEachIndexed { index, option ->
                    addView(RadioButton(this@BaseWidgetConfigurationActivity).apply {
                        id = View.generateViewId()
                        text = option.name
                        tag = option.id
                        minHeight = dp(52)
                        gravity = Gravity.CENTER_VERTICAL
                        if (option.id == savedChecklistId || (savedChecklistId == null && index == 0)) isChecked = true
                    })
                }
            }
        } else {
            val group = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
            options.forEachIndexed { index, option ->
                group.addView(CheckBox(this).apply {
                    id = View.generateViewId()
                    text = option.name
                    tag = option.id
                    minHeight = dp(52)
                    gravity = Gravity.CENTER_VERTICAL
                    if (savedQuickListIds.isNotEmpty()) {
                        isChecked = option.id in savedQuickListIds
                    } else if (index < WidgetInstanceConfigStore.MAX_QUICK_LISTS) {
                        isChecked = true
                    }
                    setOnCheckedChangeListener { _, checked ->
                        if (checked && group.childCount { (it as CheckBox).isChecked } > WidgetInstanceConfigStore.MAX_QUICK_LISTS) {
                            isChecked = false
                        }
                    }
                })
            }
            group
        }
        root.addView(selected)
        lateinit var save: Button
        save = button(getString(R.string.widget_config_save)) {
            if (!ownsWidget(widgetId)) {
                finish()
                return@button
            }
            val selectedIds = when (kind) {
                WidgetConfigurationKind.CHECKLIST -> {
                    val selectedId = (selected as RadioGroup).checkedRadioButtonId
                    listOfNotNull(selected.findViewById<RadioButton>(selectedId)?.tag as? String)
                }
                WidgetConfigurationKind.QUICK_LISTS -> (0 until (selected as LinearLayout).childCount)
                    .mapNotNull { selected.getChildAt(it) as? CheckBox }
                    .filter(CheckBox::isChecked)
                    .mapNotNull { it.tag as? String }
            }
            save.isEnabled = false
            storageExecutor.execute {
                val currentIds = runCatching { NativeStateStore.readState(this) }
                    .getOrNull()
                    ?.let(::parseBlueprintOptions)
                    ?.map(WidgetBlueprintOption::id)
                    ?.toSet()
                    .orEmpty()
                val selectionsStillExist = selectedIds.isNotEmpty() && selectedIds.all { it in currentIds }
                val saved = if (ownsWidget(widgetId) && selectionsStillExist) {
                    when (kind) {
                        WidgetConfigurationKind.CHECKLIST -> WidgetInstanceConfigStore.setChecklistBlueprintId(this, widgetId, selectedIds.singleOrNull() ?: return@execute)
                        WidgetConfigurationKind.QUICK_LISTS -> WidgetInstanceConfigStore.setQuickListBlueprintIds(this, widgetId, selectedIds)
                    }
                } else false
                mainHandler.post {
                    if (!saved) {
                        save.isEnabled = true
                        root.addView(text(getString(R.string.widget_config_save_failed), 14, false))
                        return@post
                    }
                    sendBroadcast(Intent(AppWidgetManager.ACTION_APPWIDGET_UPDATE).apply {
                        component = ComponentName(this@BaseWidgetConfigurationActivity, providerClass())
                        putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, intArrayOf(widgetId))
                    })
                    setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId))
                    finish()
                }
            }
        }
        root.addView(save)
        setContentView(scroll(root))
    }

    private fun parseBlueprintOptions(json: String): List<WidgetBlueprintOption> = try {
        val state = JSONObject(json)
        val blueprints = state.optJSONArray("blueprints") ?: return emptyList()
        buildList {
            for (index in 0 until blueprints.length()) {
                val blueprint = blueprints.optJSONObject(index) ?: continue
                val id = blueprint.optString("id").trim()
                val name = blueprint.optString("name").trim()
                if (id.isNotEmpty() && name.isNotEmpty()) add(WidgetBlueprintOption(id, name))
            }
        }
    } catch (_: Exception) {
        emptyList()
    }

    private fun column() = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(24), dp(24), dp(24), dp(24))
    }

    private fun scroll(content: View) = ScrollView(this).apply {
        isFillViewport = true
        addView(content)
    }

    private fun text(value: String, size: Int, bold: Boolean) = TextView(this).apply {
        text = value
        textSize = size.toFloat()
        if (bold) setTypeface(typeface, Typeface.BOLD)
        setPadding(0, dp(8), 0, dp(8))
    }

    private fun button(label: String, action: () -> Unit) = Button(this).apply {
        text = label
        minHeight = dp(52)
        setOnClickListener { action() }
    }

    private fun LinearLayout.childCount(predicate: (View) -> Boolean): Int =
        (0 until childCount).count { predicate(getChildAt(it)) }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    companion object {
        private val storageExecutor = Executors.newSingleThreadExecutor { task ->
            Thread(task, "before-i-leave-widget-config").apply { isDaemon = true }
        }
    }
}

class ChecklistWidgetConfigActivity : BaseWidgetConfigurationActivity() {
    override val kind = WidgetConfigurationKind.CHECKLIST
}

class QuickListsWidgetConfigActivity : BaseWidgetConfigurationActivity() {
    override val kind = WidgetConfigurationKind.QUICK_LISTS
}
