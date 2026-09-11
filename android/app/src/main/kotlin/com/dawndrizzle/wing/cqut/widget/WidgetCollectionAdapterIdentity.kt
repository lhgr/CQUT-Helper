package com.dawndrizzle.wing.cqut.widget

import java.util.Calendar
import java.util.TimeZone

/**
 * Builds a stable collection-adapter identity for one concrete calendar day.
 *
 * App widget hosts compare service intents without their extras. Including the
 * resolved date in the data URI prevents a host from reusing yesterday's
 * RemoteViewsFactory after the relative "today"/"tomorrow" offsets roll over.
 */
internal object WidgetCollectionAdapterIdentity {
  private val widgetTimeZone = TimeZone.getTimeZone(TodayWidgetData.WIDGET_TIME_ZONE_ID)

  fun dataUri(
    kind: String,
    appWidgetId: Int,
    dayOffset: Int,
    nowMillis: Long = WidgetRenderSnapshot.nowMillis(),
  ): String {
    val targetDate =
      Calendar.getInstance(widgetTimeZone).apply {
        timeInMillis = nowMillis
        add(Calendar.DAY_OF_YEAR, dayOffset)
      }
    val year = targetDate.get(Calendar.YEAR).toString().padStart(4, '0')
    val month = (targetDate.get(Calendar.MONTH) + 1).toString().padStart(2, '0')
    val day = targetDate.get(Calendar.DAY_OF_MONTH).toString().padStart(2, '0')
    return "cqut-helper://widget/collection/$kind/$appWidgetId/$dayOffset/$year-$month-$day"
  }
}
