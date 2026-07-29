package com.dawndrizzle.wing.cqut.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build

object WidgetNavigationPendingIntent {
  const val EXTRA_OPEN_TODAY = "widgetOpenToday"
  const val EXTRA_DAY_OFFSET = "widgetDayOffset"
  const val EXTRA_EVENT_NAME = "eventName"
  const val EXTRA_EVENT_ID = "eventId"

  fun create(
    context: Context,
    appWidgetId: Int,
    dayOffset: Int,
    mutableForCollection: Boolean,
  ): PendingIntent? {
    val launchIntent =
      context.packageManager.getLaunchIntentForPackage(context.packageName)
        ?: return null
    launchIntent.apply {
      putExtra(EXTRA_OPEN_TODAY, true)
      putExtra(EXTRA_DAY_OFFSET, dayOffset)
      putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
      data =
        Uri.parse(
          "cqut-helper://widget/today/$appWidgetId/$dayOffset/" +
            if (mutableForCollection) "course" else "root",
        )
    }
    val mutabilityFlag =
      if (mutableForCollection && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        PendingIntent.FLAG_MUTABLE
      } else {
        PendingIntent.FLAG_IMMUTABLE
      }
    val requestCode =
      appWidgetId * 10 + dayOffset.coerceIn(0, 7) +
        if (mutableForCollection) 100000 else 0
    return PendingIntent.getActivity(
      context,
      requestCode,
      launchIntent,
      PendingIntent.FLAG_UPDATE_CURRENT or mutabilityFlag,
    )
  }
}
