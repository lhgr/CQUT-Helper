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
  const val EXTRA_DATE = "widgetDate"
  const val EXTRA_EVENT_NAME = "eventName"
  const val EXTRA_EVENT_ID = "eventId"
  const val EXTRA_ITEM_KIND = "itemKind"
  const val EXTRA_EXAM_KEY = "examKey"

  internal fun navigationExtras(
    dayOffset: Int,
    date: String,
    mutableForCollection: Boolean = false,
    eventName: String? = null,
    eventId: String? = null,
    itemKind: String = "course",
    examKey: String? = null,
  ): Map<String, Any> = buildMap {
    put(EXTRA_OPEN_TODAY, true)
    put(EXTRA_DAY_OFFSET, dayOffset)
    // Collection rows own their date. A freshly rebound template must not
    // redirect a row that the launcher is still showing from the previous day.
    if (!mutableForCollection) put(EXTRA_DATE, date)
    eventName?.let { put(EXTRA_EVENT_NAME, it) }
    eventId?.let { put(EXTRA_EVENT_ID, it) }
    if (!mutableForCollection) put(EXTRA_ITEM_KIND, itemKind)
    examKey?.let { put(EXTRA_EXAM_KEY, it) }
  }

  internal fun dataUri(
    appWidgetId: Int,
    dayOffset: Int,
    date: String,
    target: String,
  ): String = "cqut-helper://widget/today/$appWidgetId/$dayOffset/$date/$target"

  internal fun Intent.putNavigationExtras(extras: Map<String, Any>) {
    extras.forEach { (key, value) ->
      when (value) {
        is Boolean -> putExtra(key, value)
        is Int -> putExtra(key, value)
        is String -> putExtra(key, value)
      }
    }
  }

  fun create(
    context: Context,
    appWidgetId: Int,
    dayOffset: Int,
    mutableForCollection: Boolean,
    date: String = TodayWidgetData.dateForDayOffset(dayOffset),
  ): PendingIntent? {
    val launchIntent =
      context.packageManager.getLaunchIntentForPackage(context.packageName)
        ?: return null
    launchIntent.apply {
      putNavigationExtras(navigationExtras(dayOffset, date, mutableForCollection))
      putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
      data =
        Uri.parse(
          dataUri(appWidgetId, dayOffset, date, if (mutableForCollection) "course" else "root"),
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

  fun createForCourse(
    context: Context,
    appWidgetId: Int,
    dayOffset: Int,
    eventName: String,
    eventId: String?,
    date: String = TodayWidgetData.dateForDayOffset(dayOffset),
    itemKind: String = "course",
    examKey: String? = null,
  ): PendingIntent? {
    val launchIntent =
      context.packageManager.getLaunchIntentForPackage(context.packageName)
        ?: return null
    launchIntent.apply {
      putNavigationExtras(navigationExtras(dayOffset, date, eventName = eventName, eventId = eventId,
        itemKind = itemKind, examKey = examKey))
      putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
      data = Uri.parse(dataUri(appWidgetId, dayOffset, date, "tiny-course"))
    }
    return PendingIntent.getActivity(
      context,
      appWidgetId * 10 + 200000,
      launchIntent,
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
  }
}
