package com.dawndrizzle.wing.cqut.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import com.dawndrizzle.wing.cqut.R

class VerticalCourseListWidgetService : RemoteViewsService() {
  override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
    val appWidgetId =
      intent.getIntExtra(
        AppWidgetManager.EXTRA_APPWIDGET_ID,
        AppWidgetManager.INVALID_APPWIDGET_ID,
      )
    val dayOffset = intent.getIntExtra(EXTRA_DAY_OFFSET, 0)
    return VerticalCourseListRemoteViewsFactory(
      applicationContext,
      appWidgetId,
      dayOffset,
    )
  }

  companion object {
    const val EXTRA_DAY_OFFSET = "dayOffset"
  }
}

private class VerticalCourseListRemoteViewsFactory(
  private val context: Context,
  private val appWidgetId: Int,
  private val dayOffset: Int,
) : RemoteViewsService.RemoteViewsFactory {
  private var items: List<TodayWidgetData.CourseItem> = emptyList()

  override fun onCreate() {
    reload()
  }

  override fun onDataSetChanged() {
    reload()
  }

  override fun onDestroy() {
    items = emptyList()
  }

  override fun getCount(): Int = items.size

  override fun getViewAt(position: Int): RemoteViews {
    val item = items.getOrNull(position)
    val views = RemoteViews(context.packageName, R.layout.widget_vertical_schedule_item)
    val theme = WidgetInstanceConfigStore.resolveTheme(context, appWidgetId)
    val palette = theme.palette

    views.setInt(R.id.ll_content, "setBackgroundResource", palette.itemBackgroundRes)
    WidgetRemoteViewsTheme.setColor(views, R.id.tv_course_start_time, "setTextColor", theme) {
      it.primaryText
    }
    WidgetRemoteViewsTheme.setColor(views, R.id.tv_course_end_time, "setTextColor", theme) {
      it.secondaryText
    }
    WidgetRemoteViewsTheme.setColor(views, R.id.tv_course_name, "setTextColor", theme) {
      it.primaryText
    }
    WidgetRemoteViewsTheme.setColor(views, R.id.tv_course_location, "setTextColor", theme) {
      it.secondaryText
    }
    WidgetRemoteViewsTheme.setColor(views, R.id.tv_course_meta, "setTextColor", theme) {
      it.secondaryText
    }
    WidgetRemoteViewsTheme.setColor(views, R.id.time_divider, "setBackgroundColor", theme) {
      it.divider
    }

    if (item == null) {
      views.setTextViewText(R.id.tv_course_start_time, "")
      views.setTextViewText(R.id.tv_course_end_time, "")
      views.setTextViewText(R.id.tv_course_name, "")
      views.setTextViewText(R.id.tv_course_location, "")
      views.setTextViewText(R.id.tv_course_meta, "")
      views.setInt(R.id.iv_indicator, "setColorFilter", 0x00000000)
      return views
    }

    val hasClock = item.startTime.isNotBlank() && item.endTime.isNotBlank()
    views.setTextViewText(
      R.id.tv_course_start_time,
      if (hasClock) item.startTime else item.periods,
    )
    views.setTextViewText(R.id.tv_course_end_time, if (hasClock) item.endTime else "")
    views.setViewVisibility(R.id.tv_course_end_time, if (hasClock) View.VISIBLE else View.GONE)
    views.setTextViewText(R.id.tv_course_name, item.name)
    views.setTextViewText(R.id.tv_course_location, courseLocation(item))
    views.setTextViewText(
      R.id.tv_course_meta,
      listOfNotNull(
        item.teacher.trim().takeIf { it.isNotEmpty() },
        item.periods.takeIf { hasClock && it.isNotBlank() },
      ).joinToString(" · "),
    )
    views.setInt(R.id.iv_indicator, "setColorFilter", item.indicatorColor)

    val fillInIntent = Intent().apply {
      putExtra(WidgetNavigationPendingIntent.EXTRA_EVENT_NAME, item.name)
      putExtra(WidgetNavigationPendingIntent.EXTRA_EVENT_ID, item.eventId)
    }
    views.setOnClickFillInIntent(R.id.ll_item, fillInIntent)
    return views
  }

  override fun getLoadingView(): RemoteViews? = null

  override fun getViewTypeCount(): Int = 1

  override fun getItemId(position: Int): Long {
    val item = items.getOrNull(position) ?: return position.toLong()
    val stableKey =
      item.eventId?.takeIf { it.isNotBlank() }
        ?: "${item.courseKey}|${item.sortOrder}|${item.periods}"
    return stableKey.hashCode().toLong()
  }

  override fun hasStableIds(): Boolean = true

  private fun reload() {
    items = TodayWidgetData.loadCoursesByDayOffset(context, dayOffset)
  }

  private fun courseLocation(item: TodayWidgetData.CourseItem): String {
    return listOf(item.campus.trim(), item.classroom.trim())
      .filter { it.isNotEmpty() }
      .joinToString(" ")
  }
}
