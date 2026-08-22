package com.dawndrizzle.wing.cqut.widgetbridge

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class CqutWidgetBridgePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
  private lateinit var applicationContext: Context
  private lateinit var channel: MethodChannel

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    applicationContext = binding.applicationContext
    channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
    channel.setMethodCallHandler(this)
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

      dispatch(WidgetBridgeDispatchPlans.from(themeMode, trigger))
      result.success(null)
    } catch (error: RuntimeException) {
      Log.e(TAG, "widget update bridge failed", error)
      result.error("WIDGET_UPDATE_FAILED", error.message, null)
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }

  private fun dispatch(plan: WidgetBridgeDispatchPlan) {
    val receiver =
      ComponentName(
        applicationContext.packageName,
        WidgetBridgeDispatchPlans.AUTO_REFRESH_RECEIVER,
      )
    if (isReceiverAvailable(receiver)) {
      applicationContext.sendBroadcast(
        Intent(plan.primaryAction).setComponent(receiver),
      )
      return
    }

    Log.w(TAG, "central widget receiver unavailable; using provider fallback")
    for (target in plan.fallbackTargets) {
      applicationContext.sendBroadcast(
        Intent(target.action).setComponent(
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
