package dev.giann.before_i_leave

import android.Manifest
import android.content.pm.PackageManager
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.os.Bundle
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var nativeChannel: MethodChannel? = null
    private var notificationPermissionResult: MethodChannel.Result? = null
    private var pendingLaunchAction: String? = null
    private val storageExecutor = Executors.newSingleThreadExecutor { task ->
        Thread(task, "before-i-leave-storage").apply { isDaemon = true }
    }
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        nativeChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "readState" -> readStateAsync(result)
                    "appVersion" -> runCatching { installedAppVersion() }.fold(result::success) {
                        result.error("app_version_unavailable", it.message, null)
                    }
                    "writeState" -> writeStateAsync(call.arguments, result, reset = false)
                    "resetState" -> writeStateAsync(call.arguments, result, reset = true)
                    "widgetSnapshot" -> {
                        val args = call.arguments as? Map<*, *>
                        val widgetId = (args?.get("widgetId") as? Number)?.toInt()
                        storageExecutor.execute {
                            val snapshot = runCatching { NativeStateStore.widgetSnapshot(this, widgetId) }
                            mainHandler.post { snapshot.fold(result::success, { result.error("widget_snapshot_failed", it.message, null) }) }
                        }
                    }
                    "requestPinWidget" -> result.success(requestPinWidget((call.arguments as? Map<*, *>)?.get("kind") as? String))
                    "reminderStatus" -> result.success(ReminderScheduler.status(this))
                    "scheduleReminder" -> {
                        val args = call.arguments as? Map<*, *>
                        val hour = (args?.get("hour") as? Number)?.toInt()
                        val minute = (args?.get("minute") as? Number)?.toInt()
                        val enabled = args?.get("enabled") as? Boolean
                        if (hour == null || minute == null || enabled == null) {
                            result.error("invalid_reminder", "Expected hour, minute, and enabled values.", null)
                        } else {
                            runCatching {
                                ReminderScheduler.configure(this, hour, minute, enabled)
                            }.fold(result::success) {
                                result.error("invalid_reminder", it.message, null)
                            }
                        }
                    }
                    "openNotificationSettings" -> {
                        runCatching {
                            val settings = if (Build.VERSION.SDK_INT >= 26) android.content.Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                .putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, packageName)
                            else android.content.Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                android.net.Uri.parse("package:$packageName"))
                            startActivity(settings)
                            true
                        }.fold(result::success) { result.success(false) }
                    }
                    "openPreciseReminderSettings" -> {
                        if (Build.VERSION.SDK_INT >= 31) {
                            runCatching { startActivity(android.content.Intent(android.provider.Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                                android.net.Uri.parse("package:$packageName"))); true }
                                .fold(result::success) { result.success(false) }
                        } else result.success(false)
                    }
                    "requestNotifications" -> requestNotificationPermission(result)
                    "getLaunchAction" -> consumeLaunchAction(result)
                    else -> result.notImplemented()
                }
            }
        }
        NativeStateChangeNotifier.listener = { canonical ->
            mainHandler.post { nativeChannel?.invokeMethod("externalStateChanged", canonical) }
        }
        pendingLaunchAction?.let { action ->
            pendingLaunchAction = null
            nativeChannel?.invokeMethod("launchAction", action)
        }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        ReminderScheduler.rescheduleIfEnabled(this)
    }

    override fun onResume() {
        super.onResume()
        ReminderScheduler.rescheduleIfEnabled(this)
        ChecklistScheduleScheduler.enqueue(this)
        LeaveWidgetProvider.refreshAll(this)
        QuickListsWidgetProvider.refreshAll(this)
        ScheduledChecklistWidgetProvider.refreshAll(this)
    }

    override fun onDestroy() {
        storageExecutor.shutdown()
        NativeStateChangeNotifier.listener = null
        super.onDestroy()
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        storageExecutor.execute {
            val action = runCatching { WidgetIntentContract.consume(this, intent) }.getOrNull()
            mainHandler.post { notifyLaunchAction(action) }
        }
    }

    private fun consumeLaunchAction(result: MethodChannel.Result) {
        storageExecutor.execute {
            val action = runCatching { WidgetIntentContract.consume(this, intent) }
            mainHandler.post {
                action.fold(result::success, { result.error("widget_launch_failed", it.message, null) })
            }
        }
    }

    private fun notifyLaunchAction(action: String?) {
        if (action == null) return
        val channel = nativeChannel
        if (channel == null) pendingLaunchAction = action else channel.invokeMethod("launchAction", action)
    }

    private fun readStateAsync(result: MethodChannel.Result) {
        storageExecutor.execute {
            val state = runCatching { NativeStateStore.readState(this) }
            ChecklistScheduleScheduler.refresh(this)
            runCatching { LeaveWidgetProvider.refreshAll(this) }
            runCatching { QuickListsWidgetProvider.refreshAll(this) }
            runCatching { ScheduledChecklistWidgetProvider.refreshAll(this) }
            mainHandler.post {
                state.fold(
                    result::success,
                    { result.error("state_read_failed", it.message, null) },
                )
            }
        }
    }

    private fun writeStateAsync(arguments: Any?, result: MethodChannel.Result, reset: Boolean) {
        val args = arguments as? Map<*, *>
        val targetJson = (if (reset) args?.get("targetJson") else args?.get("targetJson")) as? String
        if (targetJson == null) {
            result.error("invalid_state", "Expected a JSON string in 'targetJson'.", null)
            return
        }
        storageExecutor.execute {
            val write = runCatching {
                if (reset) NativeStateStore.resetState(this, targetJson)
                else NativeStateStore.writeState(
                    this,
                    args?.get("baseJson") as? String,
                    targetJson,
                    args?.get("checkIntents"),
                    args?.get("lifecycleIntents"),
                )
            }
            if (write.isSuccess) ChecklistScheduleScheduler.refresh(this)
            mainHandler.post {
                write.fold(
                    { canonical ->
                        // The canonical state is durable already; widget refresh failures
                        // must never turn a successful state transaction into an app error.
                        runCatching { LeaveWidgetProvider.refreshAll(this) }
                        runCatching { QuickListsWidgetProvider.refreshAll(this) }
                        runCatching { ScheduledChecklistWidgetProvider.refreshAll(this) }
                        result.success(canonical)
                    },
                    { result.error(if (reset) "state_reset_failed" else "state_write_failed", it.message, null) },
                )
            }
        }
    }

    private fun requestPinWidget(kind: String?): Boolean {
        if (Build.VERSION.SDK_INT < 26) return false
        val provider = when (kind) {
            "quick_lists" -> QuickListsWidgetProvider::class.java
            "scheduled" -> ScheduledChecklistWidgetProvider::class.java
            else -> LeaveWidgetProvider::class.java
        }
        val manager = AppWidgetManager.getInstance(this)
        if (!manager.isRequestPinAppWidgetSupported) return false
        return runCatching { manager.requestPinAppWidget(ComponentName(this, provider), Bundle(), null) }.getOrDefault(false)
    }

    private fun installedAppVersion(): Map<String, String> {
        val packageInfo = packageManager.getPackageInfo(packageName, 0)
        @Suppress("DEPRECATION")
        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo.longVersionCode
        } else {
            packageInfo.versionCode.toLong()
        }
        return mapOf(
            "versionName" to packageInfo.versionName.orEmpty(),
            "buildNumber" to versionCode.toString(),
        )
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (ReminderScheduler.canNotify(this)) {
            result.success(true)
            return
        }
        if (Build.VERSION.SDK_INT < 33) {
            result.success(false)
            return
        }
        if (notificationPermissionResult != null) {
            result.error("permission_request_in_progress", "A notification permission request is already open.", null)
            return
        }
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            result.success(ReminderScheduler.canNotify(this))
            return
        }
        notificationPermissionResult = result
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS)
    }

    @Deprecated("Deprecated in Android API; retained for broad device compatibility.")
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_NOTIFICATIONS) {
            val pending = notificationPermissionResult
            notificationPermissionResult = null
            pending?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED && ReminderScheduler.canNotify(this))
        }
    }

    companion object {
        const val CHANNEL = "dev.giann.before_i_leave/native"
        const val ACTION_PACK_TODAY = "dev.giann.before_i_leave.PACK_TODAY"
        const val EXTRA_WIDGET_LAUNCH_ACTION = "dev.giann.before_i_leave.extra.WIDGET_LAUNCH_ACTION"
        private const val REQUEST_NOTIFICATIONS = 49021
    }
}
