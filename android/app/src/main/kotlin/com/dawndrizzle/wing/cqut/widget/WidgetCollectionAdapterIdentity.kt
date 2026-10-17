package com.dawndrizzle.wing.cqut.widget

import java.util.Calendar
import java.util.TimeZone

/**
 * Builds a stable collection-adapter identity for one concrete visible data set.
 *
 * App widget hosts compare service intents without their extras. Including the
 * resolved date prevents a host from reusing yesterday's RemoteViewsFactory.
 * Including the visible-content fingerprint also replaces a factory when a
 * course starts or synchronized schedule data changes. Some launchers ignore
 * notifyAppWidgetViewDataChanged() for only a subset of widget instances.
 * The theme signature replaces cached rows when their colors change.
 */
internal object WidgetCollectionAdapterIdentity {
  private val widgetTimeZone = TimeZone.getTimeZone(TodayWidgetData.WIDGET_TIME_ZONE_ID)

  fun dataUri(
    kind: String,
    appWidgetId: Int,
    dayOffset: Int,
    themeSignature: String,
    nowMillis: Long = WidgetRenderSnapshot.nowMillis(),
    contentFingerprint: String = "",
  ): String {
    val targetDate =
      Calendar.getInstance(widgetTimeZone).apply {
        timeInMillis = nowMillis
        add(Calendar.DAY_OF_YEAR, dayOffset)
      }
    val year = targetDate.get(Calendar.YEAR).toString().padStart(4, '0')
    val month = (targetDate.get(Calendar.MONTH) + 1).toString().padStart(2, '0')
    val day = targetDate.get(Calendar.DAY_OF_MONTH).toString().padStart(2, '0')
    val contentVersion = contentFingerprint.ifBlank { "empty" }
    val themeVersion = themeSignature.replace('|', '-')
    return "cqut-helper://widget/collection/$kind/$appWidgetId/$dayOffset/" +
      "$themeVersion/$contentVersion/$year-$month-$day"
  }
}
