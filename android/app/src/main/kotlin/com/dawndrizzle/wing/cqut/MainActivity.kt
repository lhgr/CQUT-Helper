package com.dawndrizzle.wing.cqut

import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import android.os.Environment
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.dawndrizzle.wing.cqut.widget.TodayListWidgetProvider
import com.dawndrizzle.wing.cqut.widget.TodayAndNextWidgetProvider
import com.dawndrizzle.wing.cqut.widget.TodayCourseWidgetProvider

class MainActivity : FlutterActivity() {
  private val channelName = "cqut/downloads"
  private val widgetChannelName = "cqut/widget"

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
  }
}
