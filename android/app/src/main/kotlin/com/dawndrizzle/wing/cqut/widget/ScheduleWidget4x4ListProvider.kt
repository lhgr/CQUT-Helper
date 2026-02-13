package com.dawndrizzle.wing.cqut.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import com.dawndrizzle.wing.cqut.MainActivity
import com.dawndrizzle.wing.cqut.R

class ScheduleWidget4x4ListProvider : AppWidgetProvider() {

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
        val views = RemoteViews(context.packageName, R.layout.schedule_widget_4x4_list)
        val data = ScheduleDataHelper.loadCachedSchedule(context)
        val todayName = ScheduleDataHelper.todayWeekDayName()
        val barDrawables = intArrayOf(
            R.drawable.widget_bar_blue,
            R.drawable.widget_bar_blue,
            R.drawable.widget_bar_green,
            R.drawable.widget_bar_teal
        )

        if (data != null) {
            views.setTextViewText(R.id.widget_4x4_list_header_left, "今天 / $todayName")
            views.setTextViewText(R.id.widget_4x4_list_week, "第${data.weekNum ?: "?"}周")
            val today = ScheduleDataHelper.todayEvents(data)
            for (i in 0 until 4) {
                val event = today.getOrNull(i)
                setListRow(views, event, i + 1, barDrawables.getOrElse(i) { R.drawable.widget_bar_blue })
            }
            val rest = (today.size - 4).coerceAtLeast(0)
            views.setTextViewText(
                R.id.widget_4x4_list_footer,
                if (rest > 0) "其他${rest}节课程・・・" else ""
            )
        } else {
            views.setTextViewText(R.id.widget_4x4_list_header_left, "今天 / $todayName")
            views.setTextViewText(R.id.widget_4x4_list_week, "")
            for (i in 1..4) setListRow(views, null, i, R.drawable.widget_bar_blue)
            views.setTextViewText(R.id.widget_4x4_list_footer, "请先打开应用同步课表")
        }

        val pending = PendingIntent.getActivity(
            context, 0,
            Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(android.R.id.background, pending)
        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    private fun setListRow(views: RemoteViews, event: EventItem?, row: Int, barDrawableRes: Int) {
        val (timeStartId, timeEndId, barId, titleId, detailId) = when (row) {
            1 -> RowIds(R.id.widget_4x4_list_time1_start, R.id.widget_4x4_list_time1_end, R.id.widget_4x4_list_bar1, R.id.widget_4x4_list_title1, R.id.widget_4x4_list_detail1)
            2 -> RowIds(R.id.widget_4x4_list_time2_start, R.id.widget_4x4_list_time2_end, R.id.widget_4x4_list_bar2, R.id.widget_4x4_list_title2, R.id.widget_4x4_list_detail2)
            3 -> RowIds(R.id.widget_4x4_list_time3_start, R.id.widget_4x4_list_time3_end, R.id.widget_4x4_list_bar3, R.id.widget_4x4_list_title3, R.id.widget_4x4_list_detail3)
            else -> RowIds(R.id.widget_4x4_list_time4_start, R.id.widget_4x4_list_time4_end, R.id.widget_4x4_list_bar4, R.id.widget_4x4_list_title4, R.id.widget_4x4_list_detail4)
        }
        views.setInt(barId, "setBackgroundResource", barDrawableRes)
        if (event != null) {
            val range = ScheduleDataHelper.formatTimeRange(event)
            val parts = range.split("-", limit = 2)
            views.setTextViewText(timeStartId, parts.getOrNull(0)?.trim() ?: "")
            views.setTextViewText(timeEndId, parts.getOrNull(1)?.trim() ?: "")
            views.setTextViewText(titleId, event.eventName ?: "")
            views.setTextViewText(detailId, buildDetail(event))
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

    private data class RowIds(val timeStart: Int, val timeEnd: Int, val bar: Int, val title: Int, val detail: Int)
}
