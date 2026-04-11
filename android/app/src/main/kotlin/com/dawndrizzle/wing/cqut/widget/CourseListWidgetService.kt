package com.dawndrizzle.wing.cqut.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import com.dawndrizzle.wing.cqut.R

class CourseListWidgetService : RemoteViewsService() {
  override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
    val appWidgetId = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
    val dayOffset = intent.getIntExtra(EXTRA_DAY_OFFSET, 0)
    return CourseListRemoteViewsFactory(applicationContext, appWidgetId, dayOffset)
  }

  companion object {
    const val EXTRA_DAY_OFFSET = "dayOffset"
  }
}

private class CourseListRemoteViewsFactory(
  private val context: Context,
  private val appWidgetId: Int,
  private val dayOffset: Int,
) : RemoteViewsService.RemoteViewsFactory {
  private var items: List<TodayWidgetData.CourseItem> = emptyList()

  override fun onCreate() {
    items = TodayWidgetData.loadCoursesByDayOffset(context, dayOffset)
  }

  override fun onDataSetChanged() {
    items = TodayWidgetData.loadCoursesByDayOffset(context, dayOffset)
  }

  override fun onDestroy() {
    items = emptyList()
  }

  override fun getCount(): Int = items.size

  override fun getViewAt(position: Int): RemoteViews {
    val item = items.getOrNull(position)
    val views = RemoteViews(context.packageName, R.layout.widget_today_list_item)
    val palette = WidgetTheme.resolve(context, WidgetThemeTrigger.DATA_REFRESH).palette
    views.setInt(
      R.id.ll_content,
      "setBackgroundResource",
      palette.itemBackgroundRes,
    )
    views.setTextColor(R.id.tv_course_name, palette.primaryText)
    views.setTextColor(R.id.tv_campus, palette.secondaryText)
    views.setTextColor(R.id.tv_classroom, palette.secondaryText)
    views.setTextColor(R.id.tv_teacher, palette.secondaryText)
    views.setTextColor(R.id.tv_periods, palette.secondaryText)

    if (item == null) {
      views.setTextViewText(R.id.tv_course_name, "")
      views.setTextViewText(R.id.tv_campus, "")
      views.setTextViewText(R.id.tv_classroom, "")
      views.setTextViewText(R.id.tv_teacher, "")
      views.setTextViewText(R.id.tv_periods, "")
      views.setInt(R.id.iv_indicator, "setColorFilter", 0x00000000)
      return views
    }

    views.setTextViewText(R.id.tv_course_name, item.name)
    views.setTextViewText(R.id.tv_campus, item.campus)
    views.setTextViewText(R.id.tv_classroom, item.classroom)
    views.setTextViewText(R.id.tv_teacher, item.teacher)
    views.setTextViewText(R.id.tv_periods, item.periods)
    views.setInt(R.id.iv_indicator, "setColorFilter", item.indicatorColor)

    val fillInIntent = Intent().apply {
      putExtra("eventName", item.name)
      putExtra("eventId", item.eventId)
    }
    views.setOnClickFillInIntent(R.id.ll_item, fillInIntent)

    return views
  }

  override fun getLoadingView(): RemoteViews? = null

  override fun getViewTypeCount(): Int = 1

  override fun getItemId(position: Int): Long = position.toLong()

  override fun hasStableIds(): Boolean = true
}
