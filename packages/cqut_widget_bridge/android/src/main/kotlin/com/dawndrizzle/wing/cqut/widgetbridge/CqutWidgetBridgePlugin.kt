package com.dawndrizzle.wing.cqut.widgetbridge

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec

class CqutWidgetBridgePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
  private lateinit var applicationContext: Context
  private lateinit var channel: MethodChannel
  private lateinit var diagnosticChannel: MethodChannel
  private lateinit var courseReminderChannel: MethodChannel

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    applicationContext = binding.applicationContext
    channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
    channel.setMethodCallHandler(this)
    try { CqutDiagnostics.initialize(applicationContext) } catch (_: Exception) {}
    try { CourseAutoMode.initialize(applicationContext) } catch (error: Exception) {
      CqutDiagnostics.record(applicationContext, "error", "CourseAutoMode", "event=initialize", error)
    }
    courseReminderChannel = MethodChannel(binding.binaryMessenger, "cqut/course_reminders")
    courseReminderChannel.setMethodCallHandler { call, result ->
      try {
        when (call.method) {
          "getStatus" -> result.success(CourseAutoMode.status(applicationContext))
          "openSettings" -> result.success(CourseAutoMode.openSettings(applicationContext, call.argument<String>("kind") ?: ""))
          "replaceSchedule" -> {
            val mode = call.argument<String>("mode") ?: throw IllegalArgumentException("mode is required")
            val intervals = (call.argument<List<Map<String, Any?>>>("intervals") ?: emptyList()).map { interval ->
              CourseModeInterval(
                (interval["startMillis"] as? Number)?.toLong() ?: throw IllegalArgumentException("startMillis is required"),
                (interval["endMillis"] as? Number)?.toLong() ?: throw IllegalArgumentException("endMillis is required"),
              )
            }
            CourseAutoMode.replace(applicationContext, mode, intervals)
            result.success(null)
          }
          "cancelAndRestore" -> { CourseAutoMode.cancel(applicationContext); result.success(null) }
          else -> result.notImplemented()
        }
      } catch (error: Exception) {
        CqutDiagnostics.record(applicationContext, "error", "CourseAutoMode", "event=channel method=${call.method}", error)
        result.error("COURSE_AUTO_MODE", error.message, null)
      }
    }
    diagnosticChannel = MethodChannel(
      binding.binaryMessenger, "cqut/diagnostics", StandardMethodCodec.INSTANCE,
      binding.binaryMessenger.makeBackgroundTaskQueue(),
    )
    diagnosticChannel.setMethodCallHandler { call, result ->
      try {
        CqutDiagnostics.initialize(applicationContext)
        when (call.method) {
          "init" -> result.success(CqutDiagnostics.stats())
          "write" -> {
            val source = call.argument<String>("source") ?: "foreground"
            val event = call.argument<Map<String, Any?>>("event")
            result.success(event != null && CqutDiagnostics.persist(source, event))
          }
          "snapshot" -> result.success(CqutDiagnostics.snapshot())
          "stats" -> result.success(CqutDiagnostics.stats())
          "clear" -> result.success(CqutDiagnostics.clear())
          "prune" -> result.success(CqutDiagnostics.prune())
          "publishExport" -> result.success(CqutDiagnostics.publishExport(
            call.argument<String>("fileName") ?: throw IllegalArgumentException("fileName is required"),
            call.argument<String>("content") ?: throw IllegalArgumentException("content is required"),
          ))
          "exportStats" -> result.success(CqutDiagnostics.exportStats())
          "pruneExports" -> result.success(CqutDiagnostics.pruneExports())
          "clearExports" -> result.success(CqutDiagnostics.clearExports())
          else -> result.notImplemented()
        }
      } catch (error: Exception) { result.error("DIAGNOSTIC_IO", error.message, null) }
    }
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    if (call.method != METHOD_UPDATE_TODAY_WIDGET) {
      result.notImplemented()
      return
    }

    try {
      val themeMode = call.argument<String>("themeMode")
      val trigger = call.argument<String>("trigger")
      if (!themeMode.isNullOrBlank()) {
        val committed =
          applicationContext
            .getSharedPreferences(FLUTTER_PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putString(FLUTTER_THEME_MODE_KEY, themeMode)
            .commit()
        if (!committed) {
          Log.w(TAG, "theme mode preference commit returned false")
        }
      }

      CqutDiagnostics.withOperation("widget_bridge", call.argument<String>("operationId")) {
        dispatch(WidgetBridgeDispatchPlans.from(themeMode, trigger))
      }
      result.success(null)
    } catch (error: RuntimeException) {
      Log.e(TAG, "widget update bridge failed", error)
      result.error("WIDGET_UPDATE_FAILED", error.message, null)
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    diagnosticChannel.setMethodCallHandler(null)
    courseReminderChannel.setMethodCallHandler(null)
  }

  private fun dispatch(plan: WidgetBridgeDispatchPlan) {
    val receiver =
      ComponentName(
        applicationContext.packageName,
        WidgetBridgeDispatchPlans.AUTO_REFRESH_RECEIVER,
      )
    if (isReceiverAvailable(receiver)) {
      applicationContext.sendBroadcast(
        Intent(plan.primaryAction).setComponent(receiver).putExtra("diagnosticOperationId", CqutDiagnostics.operationId()),
      )
      return
    }

    Log.w(TAG, "central widget receiver unavailable; using provider fallback")
    for (target in plan.fallbackTargets) {
      applicationContext.sendBroadcast(
        Intent(target.action).putExtra("diagnosticOperationId", CqutDiagnostics.operationId()).setComponent(
          ComponentName(applicationContext.packageName, target.receiverClassName),
        ),
      )
    }
  }

  @Suppress("DEPRECATION")
  private fun isReceiverAvailable(componentName: ComponentName): Boolean {
    return try {
      applicationContext.packageManager.getReceiverInfo(componentName, 0).enabled
    } catch (_: PackageManager.NameNotFoundException) {
      false
    }
  }

  private companion object {
    const val TAG = "CqutWidgetBridge"
    const val CHANNEL_NAME = "cqut/widget"
    const val METHOD_UPDATE_TODAY_WIDGET = "updateTodayWidget"
    const val FLUTTER_PREFERENCES = "FlutterSharedPreferences"
    const val FLUTTER_THEME_MODE_KEY = "flutter.theme_mode"
  }
}
