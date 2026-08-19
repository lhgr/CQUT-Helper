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
    val followWidgetDayOffset = intent.getBooleanExtra(EXTRA_FOLLOW_WIDGET_DAY_OFFSET, false)
    val addFirstItemTopSpacing = intent.getBooleanExtra(EXTRA_ADD_FIRST_ITEM_TOP_SPACING, false)
    return CourseListRemoteViewsFactory(
      applicationContext,
      appWidgetId,
      dayOffset,
      followWidgetDayOffset,
      addFirstItemTopSpacing,
    )
  }

  companion object {
    const val EXTRA_DAY_OFFSET = "dayOffset"
    const val EXTRA_FOLLOW_WIDGET_DAY_OFFSET = "followWidgetDayOffset"
    const val EXTRA_ADD_FIRST_ITEM_TOP_SPACING = "addFirstItemTopSpacing"
    const val FIRST_ITEM_TOP_SPACING_DP = 8
  }
}

private class CourseListRemoteViewsFactory(
  private val context: Context,
  private val appWidgetId: Int,
  initialDayOffset: Int,
  private val followWidgetDayOffset: Boolean,
  private val addFirstItemTopSpacing: Boolean,
) : RemoteViewsService.RemoteViewsFactory {
  private var items: List<TodayWidgetData.CourseItem> = emptyList()
  private var dayOffset: Int = initialDayOffset

  override fun onCreate() {
    items = TodayWidgetData.loadCoursesByDayOffset(context, dayOffset)
  }

  override fun onDataSetChanged() {
    if (followWidgetDayOffset) {
      dayOffset = WidgetInstanceConfigStore.load(context, appWidgetId).dayOffset
    }
    items = TodayWidgetData.loadCoursesByDayOffset(context, dayOffset)
  }

  override fun onDestroy() {
    items = emptyList()
  }

  override fun getCount(): Int = items.size

  override fun getViewAt(position: Int): RemoteViews {
    val item = items.getOrNull(position)
    val views = RemoteViews(context.packageName, R.layout.widget_today_list_item)
    val theme = WidgetInstanceConfigStore.resolveTheme(context, appWidgetId)
    val palette = theme.palette
    views.setInt(
      R.id.ll_content,
      "setBackgroundResource",
      palette.itemBackgroundRes,
    )
    WidgetRemoteViewsTheme.setColor(views, R.id.tv_course_name, "setTextColor", theme) {
      it.primaryText
    }
    WidgetRemoteViewsTheme.setColor(views, R.id.tv_campus, "setTextColor", theme) {
      it.secondaryText
    }
    WidgetRemoteViewsTheme.setColor(views, R.id.tv_classroom, "setTextColor", theme) {
      it.secondaryText
    }
    WidgetRemoteViewsTheme.setColor(views, R.id.tv_teacher, "setTextColor", theme) {
      it.secondaryText
    }
    WidgetRemoteViewsTheme.setColor(views, R.id.tv_periods, "setTextColor", theme) {
      it.secondaryText
    }
    val topSpacingPx =
      if (addFirstItemTopSpacing && position == 0) {
        (CourseListWidgetService.FIRST_ITEM_TOP_SPACING_DP * context.resources.displayMetrics.density).toInt()
      } else {
        0
      }
    views.setViewPadding(R.id.ll_item, 0, topSpacingPx, 0, 0)

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
      putExtra(WidgetNavigationPendingIntent.EXTRA_EVENT_NAME, item.name)
      putExtra(WidgetNavigationPendingIntent.EXTRA_EVENT_ID, item.eventId)
    }
    views.setOnClickFillInIntent(R.id.ll_item, fillInIntent)

    return views
  }

  override fun getLoadingView(): RemoteViews? = null

  override fun getViewTypeCount(): Int = 1

  override fun getItemId(position: Int): Long = position.toLong()

  override fun hasStableIds(): Boolean = true
}
