package com.dawndrizzle.wing.cqut

import android.app.DownloadManager
import android.app.ActivityManager
import android.content.ComponentName
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.BatteryManager
import android.os.Environment
import android.os.PowerManager
import android.provider.MediaStore
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

          "exportToDownloads" -> {
            val srcPath = call.argument<String>("srcPath")
            val fileName = call.argument<String>("fileName")
            val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"

            if (srcPath.isNullOrBlank() || fileName.isNullOrBlank()) {
              result.error("INVALID_ARGS", "srcPath/fileName is required", null)
              return@setMethodCallHandler
            }

            try {
              val src = java.io.File(srcPath)
              if (!src.exists() || !src.isFile) {
                result.error("NOT_FOUND", "source file not found", null)
                return@setMethodCallHandler
              }

              val savedPath = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                  put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                  put(MediaStore.Downloads.MIME_TYPE, mimeType)
                  put(MediaStore.Downloads.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/CQUT-Helper")
                  put(MediaStore.Downloads.IS_PENDING, 1)
                }

                val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                val uri = contentResolver.insert(collection, values)
                  ?: throw IllegalStateException("failed to create downloads item")

                contentResolver.openOutputStream(uri)?.use { out ->
                  src.inputStream().use { input ->
                    input.copyTo(out)
                  }
                } ?: throw IllegalStateException("failed to open output stream")

                values.clear()
                values.put(MediaStore.Downloads.IS_PENDING, 0)
                contentResolver.update(uri, values, null, null)

                "/Download/CQUT-Helper/$fileName"
              } else {
                val dir = java.io.File(
                  Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                  "CQUT-Helper",
                )
                if (!dir.exists()) {
                  dir.mkdirs()
                }
                val dst = java.io.File(dir, fileName)
                src.inputStream().use { input ->
                  dst.outputStream().use { out ->
                    input.copyTo(out)
                  }
                }
                dst.absolutePath
              }

              val map: HashMap<String, Any> = hashMapOf(
                "path" to savedPath,
              )
              result.success(map)
            } catch (e: Exception) {
              result.error("EXPORT_FAILED", e.toString(), null)
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

          "batteryLevel" -> {
            val intent =
              applicationContext.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            if (intent == null) {
              result.success(null)
              return@setMethodCallHandler
            }
            val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
            if (level < 0 || scale <= 0) {
              result.success(null)
              return@setMethodCallHandler
            }
            val percent = ((level.toDouble() / scale.toDouble()) * 100.0).toInt()
            result.success(percent)
          }

          "isPowerSaveMode" -> {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            result.success(pm.isPowerSaveMode)
          }

          "isUnmeteredNetwork" -> {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val network = cm.activeNetwork
            if (network == null) {
              result.success(null)
              return@setMethodCallHandler
            }
            val caps = cm.getNetworkCapabilities(network)
            if (caps == null) {
              result.success(null)
              return@setMethodCallHandler
            }
            result.success(caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED))
          }

          "isLowRamDevice" -> {
            val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            result.success(am.isLowRamDevice)
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
