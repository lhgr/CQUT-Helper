package com.dawndrizzle.wing.cqut.widget

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import java.util.Calendar
import java.util.TimeZone

internal data class WidgetRefreshRenderState(
  val logicalDate: String,
  val presentationSignature: String,
  val contentSignature: String = "",
  val renderedAtMillis: Long = 0L,
)

/** Persists the last state that was actually sent to the launcher. */
internal object WidgetRefreshRenderStateStore {
  private const val PREFS_NAME = "WidgetRefreshRenderState"
  private const val KEY_LOGICAL_DATE = "logical_date"
  private const val KEY_PRESENTATION_SIGNATURE = "presentation_signature"
  private const val KEY_CONTENT_SIGNATURE = "content_signature"
  private const val KEY_RENDERED_AT_MILLIS = "rendered_at_millis"
  private val widgetTimeZone = TimeZone.getTimeZone(TodayWidgetData.WIDGET_TIME_ZONE_ID)

  fun capture(
    context: Context,
    nowMillis: Long = System.currentTimeMillis(),
  ): WidgetRefreshRenderState {
    val manager = AppWidgetManager.getInstance(context)
    val presentationSignatures = ArrayList<String>()
    val contentSignatures = ArrayList<String>()

    appendWidgetSignatures(
      presentationSignatures,
      contentSignatures,
      "list",
      manager.getAppWidgetIds(ComponentName(context, TodayListWidgetProvider::class.java)),
    ) { appWidgetId ->
      val dayOffset = WidgetInstanceConfigStore.load(context, appWidgetId).dayOffset
      WidgetSignatures(
        presentation = TodayWidgetData.loadRefreshPresentation(context, appWidgetId).state.name,
        content = TodayWidgetData.loadVisibleCoursesFingerprint(context, intArrayOf(dayOffset)),
      )
    }
    appendWidgetSignatures(
      presentationSignatures,
      contentSignatures,
      "next",
      manager.getAppWidgetIds(ComponentName(context, TodayAndNextWidgetProvider::class.java)),
    ) { appWidgetId ->
      WidgetSignatures(
        presentation =
          TodayWidgetData
            .loadRefreshPresentation(
              context,
              appWidgetId,
              requiredDayOffsets = intArrayOf(0, 1),
            ).state.name,
        content = TodayWidgetData.loadVisibleCoursesFingerprint(context, intArrayOf(0, 1)),
      )
    }
    appendWidgetSignatures(
      presentationSignatures,
      contentSignatures,
      "course",
      manager.getAppWidgetIds(ComponentName(context, TodayCourseWidgetProvider::class.java)),
    ) { appWidgetId ->
      val dayOffset = WidgetInstanceConfigStore.load(context, appWidgetId).dayOffset
      WidgetSignatures(
        presentation = TodayWidgetData.loadRefreshPresentation(context, appWidgetId).state.name,
        content = TodayWidgetData.loadVisibleCoursesFingerprint(context, intArrayOf(dayOffset)),
      )
    }

    return WidgetRefreshRenderState(
      logicalDate = logicalDateAtMillis(nowMillis),
      presentationSignature = presentationSignatures.joinToString("|"),
      contentSignature = contentSignatures.joinToString("|"),
      renderedAtMillis = nowMillis,
    )
  }

  fun load(context: Context): WidgetRefreshRenderState? {
    val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    val logicalDate = prefs.getString(KEY_LOGICAL_DATE, null)?.takeIf { it.isNotBlank() }
      ?: return null
    val presentationSignature = prefs.getString(KEY_PRESENTATION_SIGNATURE, null)
      ?: return null
    val contentSignature = prefs.getString(KEY_CONTENT_SIGNATURE, "").orEmpty()
    val renderedAtMillis = prefs.getLong(KEY_RENDERED_AT_MILLIS, 0L)
    return WidgetRefreshRenderState(
      logicalDate = logicalDate,
      presentationSignature = presentationSignature,
      contentSignature = contentSignature,
      renderedAtMillis = renderedAtMillis,
    )
  }

  fun save(
    context: Context,
    state: WidgetRefreshRenderState,
  ) {
    context
      .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
      .edit()
      .putString(KEY_LOGICAL_DATE, state.logicalDate)
      .putString(KEY_PRESENTATION_SIGNATURE, state.presentationSignature)
      .putString(KEY_CONTENT_SIGNATURE, state.contentSignature)
      .putLong(KEY_RENDERED_AT_MILLIS, state.renderedAtMillis)
      .apply()
  }

  fun clear(context: Context) {
    context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit().clear().apply()
  }

  internal fun shouldUseFullUpdate(
    previous: WidgetRefreshRenderState?,
    current: WidgetRefreshRenderState,
  ): Boolean =
    previous == null ||
      previous.logicalDate != current.logicalDate ||
      previous.presentationSignature != current.presentationSignature

  internal fun shouldRefresh(
    previous: WidgetRefreshRenderState?,
    current: WidgetRefreshRenderState,
  ): Boolean =
    previous == null ||
      previous.logicalDate != current.logicalDate ||
      previous.presentationSignature != current.presentationSignature ||
      previous.contentSignature != current.contentSignature

  internal fun shouldCoalesce(
    previous: WidgetRefreshRenderState?,
    current: WidgetRefreshRenderState,
    windowMillis: Long,
  ): Boolean =
    previous != null &&
      !shouldRefresh(previous, current) &&
      previous.renderedAtMillis > 0L &&
      current.renderedAtMillis >= previous.renderedAtMillis &&
      current.renderedAtMillis - previous.renderedAtMillis < windowMillis

  internal fun logicalDateAtMillis(nowMillis: Long): String {
    val calendar = Calendar.getInstance(widgetTimeZone).apply {
      timeInMillis = nowMillis
    }
    val year = calendar.get(Calendar.YEAR).toString().padStart(4, '0')
    val month = (calendar.get(Calendar.MONTH) + 1).toString().padStart(2, '0')
    val day = calendar.get(Calendar.DAY_OF_MONTH).toString().padStart(2, '0')
    return "$year-$month-$day"
  }

  private data class WidgetSignatures(
    val presentation: String,
    val content: String,
  )

  private fun appendWidgetSignatures(
    presentationDestination: MutableList<String>,
    contentDestination: MutableList<String>,
    provider: String,
    appWidgetIds: IntArray,
    signatures: (Int) -> WidgetSignatures,
  ) {
    appWidgetIds
      .asSequence()
      .filter { it != AppWidgetManager.INVALID_APPWIDGET_ID }
      .distinct()
      .sorted()
      .forEach { appWidgetId ->
        val widgetSignatures = signatures(appWidgetId)
        presentationDestination.add("$provider:$appWidgetId:${widgetSignatures.presentation}")
        contentDestination.add("$provider:$appWidgetId:${widgetSignatures.content}")
      }
  }
}
