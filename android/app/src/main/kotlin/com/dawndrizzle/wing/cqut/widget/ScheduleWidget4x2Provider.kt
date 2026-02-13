package com.dawndrizzle.wing.cqut.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import com.dawndrizzle.wing.cqut.MainActivity
import com.dawndrizzle.wing.cqut.R

class ScheduleWidget4x2Provider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    private fun updateWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int
    ) {
        val views = RemoteViews(context.packageName, R.layout.schedule_widget_4x2)
        val data = ScheduleDataHelper.loadCachedSchedule(context)
        val todayName = ScheduleDataHelper.todayWeekDayName()

        if (data != null) {
            views.setTextViewText(R.id.widget_4x2_header_left, "今天 / $todayName")
            views.setTextViewText(R.id.widget_4x2_week, "第${data.weekNum ?: "?"}周")
            val today = ScheduleDataHelper.todayEvents(data)
            val (first, second) = today.getOrNull(0) to today.getOrNull(1)
            setCourseRow(views, first, 1)
            setCourseRow(views, second, 2)
            val rest = (today.size - 2).coerceAtLeast(0)
            views.setTextViewText(
                R.id.widget_4x2_footer,
                if (rest > 0) "其他${rest}节课程・・・" else ""
            )
        } else {
            views.setTextViewText(R.id.widget_4x2_header_left, "今天 / $todayName")
            views.setTextViewText(R.id.widget_4x2_week, "")
            setCourseRow(views, null, 1)
            setCourseRow(views, null, 2)
            views.setTextViewText(R.id.widget_4x2_footer, "请先打开应用同步课表")
        }

        val pending = PendingIntent.getActivity(
            context, 0,
            Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(android.R.id.background, pending)
        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    private fun setCourseRow(views: RemoteViews, event: EventItem?, row: Int) {
        val (timeStartId, timeEndId, titleId, detailId) = when (row) {
            1 -> Quad(R.id.widget_4x2_time1_start, R.id.widget_4x2_time1_end, R.id.widget_4x2_title1, R.id.widget_4x2_detail1)
            else -> Quad(R.id.widget_4x2_time2_start, R.id.widget_4x2_time2_end, R.id.widget_4x2_title2, R.id.widget_4x2_detail2)
        }
        if (event != null) {
            val range = ScheduleDataHelper.formatTimeRange(event)
            val parts = range.split("-", limit = 2)
            views.setTextViewText(timeStartId, parts.getOrNull(0)?.trim() ?: "")
            views.setTextViewText(timeEndId, parts.getOrNull(1)?.trim() ?: "")
            views.setTextViewText(titleId, event.eventName ?: "")
            val detail = buildDetail(event)
            views.setTextViewText(detailId, detail)
        } else {
            views.setTextViewText(timeStartId, "")
            views.setTextViewText(timeEndId, "")
            views.setTextViewText(titleId, "")
            views.setTextViewText(detailId, "")
        }
    }

    private fun buildDetail(e: EventItem): String {
        val parts = mutableListOf<String>()
        e.sessionStart?.takeIf { s -> s.isNotEmpty() }?.let { s -> parts.add("第${s}节") }
        e.sessionLast?.takeIf { s -> s.isNotEmpty() && s != e.sessionStart }?.let { s -> parts.add("-${s}节") }
        e.address?.takeIf { a -> a.isNotEmpty() }?.let { a -> parts.add(a) }
        e.memberName?.takeIf { m -> m.isNotEmpty() }?.let { m -> parts.add(m) }
        return parts.joinToString(" | ")
    }

    private data class Quad(val a: Int, val b: Int, val c: Int, val d: Int)
}
