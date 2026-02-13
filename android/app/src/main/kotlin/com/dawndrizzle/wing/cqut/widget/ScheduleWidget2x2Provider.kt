package com.dawndrizzle.wing.cqut.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import com.dawndrizzle.wing.cqut.MainActivity
import com.dawndrizzle.wing.cqut.R

class ScheduleWidget2x2Provider : AppWidgetProvider() {

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
        val views = RemoteViews(context.packageName, R.layout.schedule_widget_2x2)
        val data = ScheduleDataHelper.loadCachedSchedule(context)
        val todayName = ScheduleDataHelper.todayWeekDayName()

        if (data != null) {
            views.setTextViewText(R.id.widget_2x2_header_left, "今天 / $todayName")
            views.setTextViewText(R.id.widget_2x2_week, "第${data.weekNum ?: "?"}周")
            val today = ScheduleDataHelper.todayEvents(data)
            val first = today.firstOrNull()
            if (first != null) {
                views.setTextViewText(R.id.widget_2x2_title, first.eventName ?: "课程")
                views.setTextViewText(R.id.widget_2x2_time, ScheduleDataHelper.formatTimeRange(first))
                views.setTextViewText(R.id.widget_2x2_location, first.address ?: "")
                val rest = today.size - 1
                views.setTextViewText(
                    R.id.widget_2x2_footer,
                    if (rest > 0) "其他${rest}节课程" else ""
                )
            } else {
                views.setTextViewText(R.id.widget_2x2_title, "今日无课")
                views.setTextViewText(R.id.widget_2x2_time, "")
                views.setTextViewText(R.id.widget_2x2_location, "")
                views.setTextViewText(R.id.widget_2x2_footer, "")
            }
        } else {
            views.setTextViewText(R.id.widget_2x2_header_left, "今天 / $todayName")
            views.setTextViewText(R.id.widget_2x2_week, "")
            views.setTextViewText(R.id.widget_2x2_title, "请先打开应用同步课表")
            views.setTextViewText(R.id.widget_2x2_time, "")
            views.setTextViewText(R.id.widget_2x2_location, "")
            views.setTextViewText(R.id.widget_2x2_footer, "")
        }

        val pending = PendingIntent.getActivity(
            context, 0,
            Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.widget_2x2_header_left, pending)
        views.setOnClickPendingIntent(android.R.id.background, pending)

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }
}
