package com.dawndrizzle.wing.cqut.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import androidx.core.content.ContextCompat
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import com.dawndrizzle.wing.cqut.MainActivity
import com.dawndrizzle.wing.cqut.R

class ScheduleWidget4x4GridProvider : AppWidgetProvider() {

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
        val views = RemoteViews(context.packageName, R.layout.schedule_widget_4x4_grid)
        val data = ScheduleDataHelper.loadCachedSchedule(context)
        val cellColorResIds = intArrayOf(
            R.color.widget_course_pink,
            R.color.widget_course_blue,
            R.color.widget_course_green,
            R.color.widget_course_orange,
            R.color.widget_course_pink,
            R.color.widget_course_blue,
            R.color.widget_course_green,
            R.color.widget_course_orange
        )

        if (data != null) {
            views.setTextViewText(R.id.widget_4x4_grid_week, "第${data.weekNum ?: "?"}周")
            val days = ScheduleDataHelper.weekDayNames(data).take(4)
            val dayIds = listOf(R.id.widget_4x4_grid_day1, R.id.widget_4x4_grid_day2, R.id.widget_4x4_grid_day3, R.id.widget_4x4_grid_day4)
            days.forEachIndexed { i, name -> views.setTextViewText(dayIds[i], name) }
            for (r in 1..4) for (c in 1..4) {
                val day = days.getOrNull(c - 1) ?: ""
                val event = findEventInGrid(data, r, c, day)
                val cellId = cellId(r, c)
                val txtId = cellTextId(r, c)
                if (event != null && txtId != null) {
                    val colorIdx = ScheduleDataHelper.colorIndexForEvent(event.eventName, (r - 1) * 4 + c)
                    val color = ContextCompat.getColor(context, cellColorResIds[colorIdx])
                    views.setInt(cellId, "setBackgroundColor", color)
                    views.setTextViewText(txtId, formatCellText(event))
                    views.setViewVisibility(txtId, android.view.View.VISIBLE)
                } else {
                    views.setInt(cellId, "setBackgroundResource", R.drawable.widget_cell_bg_empty)
                    if (txtId != null) views.setViewVisibility(txtId, android.view.View.GONE)
                }
            }
        } else {
            views.setTextViewText(R.id.widget_4x4_grid_week, "请先打开应用同步课表")
            listOf(R.id.widget_4x4_grid_day1, R.id.widget_4x4_grid_day2, R.id.widget_4x4_grid_day3, R.id.widget_4x4_grid_day4).forEach {
                views.setTextViewText(it, "")
            }
        }

        val pending = PendingIntent.getActivity(
            context, 0,
            Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(android.R.id.background, pending)
        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    private val timeSlots = listOf("07:00", "09:00", "11:00", "14:00")

    private fun findEventInGrid(data: ScheduleData, row: Int, col: Int, weekDay: String): EventItem? {
        val events = data.eventList ?: return null
        val day = listOf("周一", "周二", "周三", "周四").getOrNull(col - 1) ?: weekDay
        val slot = timeSlots.getOrNull(row - 1) ?: return null
        return events.firstOrNull { e ->
            e.weekDay == day && (e.sessionList?.any { it.trim().startsWith(slot) || it.contains(slot) } == true || e.sessionStart == slot)
        }
    }

    private fun cellId(row: Int, col: Int): Int = when (row) {
        1 -> when (col) { 1 -> R.id.widget_4x4_grid_cell1_1; 2 -> R.id.widget_4x4_grid_cell1_2; 3 -> R.id.widget_4x4_grid_cell1_3; else -> R.id.widget_4x4_grid_cell1_4 }
        2 -> when (col) { 1 -> R.id.widget_4x4_grid_cell2_1; 2 -> R.id.widget_4x4_grid_cell2_2; 3 -> R.id.widget_4x4_grid_cell2_3; else -> R.id.widget_4x4_grid_cell2_4 }
        3 -> when (col) { 1 -> R.id.widget_4x4_grid_cell3_1; 2 -> R.id.widget_4x4_grid_cell3_2; 3 -> R.id.widget_4x4_grid_cell3_3; else -> R.id.widget_4x4_grid_cell3_4 }
        else -> when (col) { 1 -> R.id.widget_4x4_grid_cell4_1; 2 -> R.id.widget_4x4_grid_cell4_2; 3 -> R.id.widget_4x4_grid_cell4_3; else -> R.id.widget_4x4_grid_cell4_4 }
    }

    private fun cellTextId(row: Int, col: Int): Int? = if (row == 1 && col == 1) R.id.widget_4x4_grid_txt_1_1 else null

    private fun formatCellText(e: EventItem): String {
        val name = e.eventName ?: ""
        val loc = e.address?.let { "@$it" } ?: ""
        return if (loc.isEmpty()) name else "$name\n$loc"
    }
}
