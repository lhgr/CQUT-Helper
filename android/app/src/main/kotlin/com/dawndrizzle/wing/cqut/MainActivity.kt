package com.dawndrizzle.wing.cqut

import android.app.DownloadManager
import android.app.ActivityManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.dawndrizzle.wing.cqut.widget.TodayListWidgetProvider
import com.dawndrizzle.wing.cqut.widget.TodayAndNextWidgetProvider
import com.dawndrizzle.wing.cqut.widget.TodayCourseWidgetProvider

class MainActivity : FlutterActivity() {
  private val channelName = "cqut/downloads"
  private val widgetChannelName = "cqut/widget"
  private val powerChannelName = "cqut/power"

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "enqueueDownload" -> {
            val url = call.argument<String>("url")
            val fileName = call.argument<String>("fileName")

            if (url.isNullOrBlank() || fileName.isNullOrBlank()) {
              result.error("INVALID_ARGS", "url/fileName is required", null)
              return@setMethodCallHandler
            }

            try {
              val request = DownloadManager.Request(Uri.parse(url))
                .setTitle(fileName)
                .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                .setAllowedOverMetered(true)
                .setAllowedOverRoaming(true)
                .setDestinationInExternalPublicDir(
                  Environment.DIRECTORY_DOWNLOADS,
                  "CQUT-Helper/$fileName",
                )

              val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
              val downloadId = manager.enqueue(request)

              val downloadsDir =
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS).absolutePath
              val savePath = "$downloadsDir/CQUT-Helper/$fileName"

              val map: HashMap<String, Any> = hashMapOf(
                "downloadId" to downloadId,
                "path" to savePath,
              )
              result.success(map)
            } catch (e: Exception) {
              result.error("DOWNLOAD_FAILED", e.toString(), null)
            }
          }

          else -> result.notImplemented()
        }
      }

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, widgetChannelName)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "updateTodayWidget" -> {
            TodayListWidgetProvider.updateAll(applicationContext)
            TodayAndNextWidgetProvider.updateAll(applicationContext)
            TodayCourseWidgetProvider.updateAll(applicationContext)
            result.success(null)
          }

          else -> result.notImplemented()
        }
      }

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, powerChannelName)
      .setMethodCallHandler { call, result ->
        fun tryStart(intent: Intent): Boolean {
          return try {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
          } catch (_: Exception) {
            false
          }
        }

        when (call.method) {
          "manufacturer" -> {
            result.success("${Build.MANUFACTURER} ${Build.BRAND}".trim())
          }

          "isIgnoringBatteryOptimizations" -> {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
              result.success(null)
              return@setMethodCallHandler
            }
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            result.success(pm.isIgnoringBatteryOptimizations(packageName))
          }

          "isBackgroundRestricted" -> {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
              result.success(null)
              return@setMethodCallHandler
            }
            val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            result.success(am.isBackgroundRestricted)
          }

          "requestIgnoreBatteryOptimizations" -> {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
              result.success(false)
              return@setMethodCallHandler
            }
            val intent = Intent(
              Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
              Uri.parse("package:$packageName"),
            )
            result.success(tryStart(intent))
          }

          "openBatteryOptimizationSettings" -> {
            val ok = tryStart(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            if (ok) {
              result.success(true)
            } else {
              val fallback = Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:$packageName"),
              )
              result.success(tryStart(fallback))
            }
          }

          "openAppDetailsSettings" -> {
            val intent = Intent(
              Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
              Uri.parse("package:$packageName"),
            )
            result.success(tryStart(intent))
          }

          "openAutoStartSettings" -> {
            val intents = listOf(
              Intent().setComponent(
                ComponentName(
                  "com.miui.securitycenter",
                  "com.miui.permcenter.autostart.AutoStartManagementActivity",
                ),
              ),
              Intent().setComponent(
                ComponentName(
                  "com.huawei.systemmanager",
                  "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
                ),
              ),
              Intent().setComponent(
                ComponentName(
                  "com.huawei.systemmanager",
                  "com.huawei.systemmanager.optimize.process.ProtectActivity",
                ),
              ),
              Intent().setComponent(
                ComponentName(
                  "com.oppo.safe",
                  "com.oppo.safe.permission.startup.StartupAppListActivity",
                ),
              ),
              Intent().setComponent(
                ComponentName(
                  "com.coloros.safecenter",
                  "com.coloros.safecenter.permission.startup.StartupAppListActivity",
                ),
              ),
              Intent().setComponent(
                ComponentName(
                  "com.vivo.permissionmanager",
                  "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
                ),
              ),
              Intent().setComponent(
                ComponentName(
                  "com.samsung.android.lool",
                  "com.samsung.android.sm.ui.battery.BatteryActivity",
                ),
              ),
            )

            var ok = false
            for (i in intents) {
              if (tryStart(i)) {
                ok = true
                break
              }
            }
            if (!ok) {
              val fallback = Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:$packageName"),
              )
              ok = tryStart(fallback)
            }
            result.success(ok)
          }

          else -> result.notImplemented()
        }
      }
  }
}
