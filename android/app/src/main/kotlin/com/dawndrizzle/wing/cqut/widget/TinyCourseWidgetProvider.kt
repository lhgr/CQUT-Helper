package com.dawndrizzle.wing.cqut.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import com.dawndrizzle.wing.cqut.R

class TinyCourseWidgetProvider : AppWidgetProvider() {
  override fun onUpdate(
    context: Context,
    appWidgetManager: AppWidgetManager,
    appWidgetIds: IntArray,
  ) {
    val theme = WidgetTheme.resolve(context, WidgetThemeTrigger.DATA_REFRESH)
    updateAppWidgets(context, appWidgetManager, appWidgetIds, theme)
    WidgetRefreshCoordinator.ensureScheduled(context, "tiny_course_update")
  }

  override fun onEnabled(context: Context) {
    super.onEnabled(context)
    WidgetRefreshCoordinator.ensureScheduled(context, "tiny_course_enabled")
  }

  override fun onReceive(context: Context, intent: Intent) {
    super.onReceive(context, intent)
    when (intent.action) {
      ACTION_REFRESH -> WidgetRefreshCoordinator.refreshAndRepair(context, "tiny_course_action")
      ACTION_THEME_REFRESH -> {
        updateTheme(context)
        WidgetRefreshCoordinator.ensureScheduled(context, "tiny_course_theme")
      }
      ACTION_MANUAL_REFRESH -> {
        val appWidgetId =
          intent.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
          )
        if (appWidgetId != AppWidgetManager.INVALID_APPWIDGET_ID) {
          ScheduleWidgetRefreshWork.enqueue(context, appWidgetId)
        }
      }
    }
  }

  override fun onAppWidgetOptionsChanged(
    context: Context,
    appWidgetManager: AppWidgetManager,
    appWidgetId: Int,
    newOptions: android.os.Bundle,
  ) {
    super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
    updateOne(context, appWidgetId)
    WidgetRefreshCoordinator.ensureScheduled(context, "tiny_course_options")
  }

  override fun onDeleted(context: Context, appWidgetIds: IntArray) {
    WidgetInstanceConfigStore.delete(context, appWidgetIds)
    super.onDeleted(context, appWidgetIds)
    WidgetRefreshCoordinator.cancelIfUnused(context, "tiny_course_deleted")
  }

  override fun onDisabled(context: Context) {
    super.onDisabled(context)
    WidgetRefreshCoordinator.cancelIfUnused(context, "tiny_course_disabled")
  }

  companion object {
    const val ACTION_REFRESH = "com.dawndrizzle.wing.cqut.widget.TINY_COURSE_REFRESH"
    const val ACTION_THEME_REFRESH =
      "com.dawndrizzle.wing.cqut.widget.TINY_COURSE_THEME_REFRESH"
    const val ACTION_MANUAL_REFRESH =
      "com.dawndrizzle.wing.cqut.widget.TINY_COURSE_MANUAL_REFRESH"

    fun updateAll(context: Context, theme: WidgetThemeResolution? = null) {
      val manager = AppWidgetManager.getInstance(context)
      val ids = manager.getAppWidgetIds(ComponentName(context, TinyCourseWidgetProvider::class.java))
      updateAppWidgets(context, manager, ids, theme)
    }

    fun updateTheme(context: Context, appWidgetIds: IntArray? = null) {
      updateRefreshPresentation(context, appWidgetIds)
    }

    fun updateRefreshPresentation(
      context: Context,
      appWidgetIds: IntArray? = null,
      theme: WidgetThemeResolution? = null,
    ) {
      val manager = AppWidgetManager.getInstance(context)
      val ids =
        appWidgetIds
          ?: manager.getAppWidgetIds(ComponentName(context, TinyCourseWidgetProvider::class.java))
      updateAppWidgets(context, manager, ids, theme)
    }

    fun updateOne(context: Context, appWidgetId: Int) {
      val manager = AppWidgetManager.getInstance(context)
      val fallback = WidgetTheme.resolve(context, WidgetThemeTrigger.DATA_REFRESH)
      val theme = WidgetInstanceConfigStore.resolveTheme(context, appWidgetId, fallback)
      updateAppWidget(context, manager, appWidgetId, theme)
    }

    private fun updateAppWidgets(
      context: Context,
      manager: AppWidgetManager,
      appWidgetIds: IntArray,
      theme: WidgetThemeResolution? = null,
    ) {
      val fallback = theme ?: WidgetTheme.resolve(context, WidgetThemeTrigger.DATA_REFRESH)
      for (appWidgetId in appWidgetIds) {
        val resolved = WidgetInstanceConfigStore.resolveTheme(context, appWidgetId, fallback)
        updateAppWidget(context, manager, appWidgetId, resolved)
      }
    }

    private fun updateAppWidget(
      context: Context,
      manager: AppWidgetManager,
      appWidgetId: Int,
      theme: WidgetThemeResolution,
    ) {
      val views = RemoteViews(context.packageName, R.layout.widget_tiny_course)
      bindPresentation(context, views, appWidgetId, theme)
      manager.updateAppWidget(appWidgetId, views)
    }

    private fun bindPresentation(
      context: Context,
      views: RemoteViews,
      appWidgetId: Int,
      theme: WidgetThemeResolution,
    ) {
      val palette = theme.palette
      views.setInt(R.id.widget_card, "setBackgroundResource", palette.backgroundRes)
      WidgetRemoteViewsTheme.setColor(views, R.id.tv_course_name, "setTextColor", theme) {
        it.primaryText
      }
      WidgetRemoteViewsTheme.setColor(views, R.id.tv_course_time, "setTextColor", theme) {
        it.secondaryText
      }
      WidgetRemoteViewsTheme.setColor(views, R.id.tv_course_location, "setTextColor", theme) {
        it.secondaryText
      }
      WidgetRemoteViewsTheme.setColor(views, R.id.tv_status_title, "setTextColor", theme) {
        it.primaryText
      }
      WidgetRemoteViewsTheme.setColor(views, R.id.tv_status_message, "setTextColor", theme) {
        it.secondaryText
      }
      WidgetRemoteViewsTheme.setColor(views, R.id.iv_refresh, "setColorFilter", theme) {
        it.icon
      }
      WidgetRemoteViewsTheme.setColor(
        views,
        R.id.theme_transition_overlay,
        "setBackgroundColor",
        theme,
      ) { it.transitionOverlay }
      views.setViewVisibility(
        R.id.theme_transition_overlay,
        if (theme.shouldAnimate) View.VISIBLE else View.GONE,
      )

      val courses = TodayWidgetData.loadTodayCourses(context)
      val nextCourse = TodayWidgetData.selectNextCourse(courses)
      val refresh =
        TodayWidgetData.loadRefreshPresentation(
          context,
          appWidgetId,
          requiredDayOffsets = intArrayOf(0),
        )

      views.setViewVisibility(R.id.course_content, View.GONE)
      views.setViewVisibility(R.id.iv_indicator, View.GONE)
      views.setViewVisibility(R.id.status_content, View.GONE)
      views.setViewVisibility(R.id.iv_refresh, if (refresh.showsRefreshButton) android.view.View.VISIBLE else android.view.View.GONE)
      views.setBoolean(
        R.id.iv_refresh,
        "setEnabled",
        refresh.state != TodayWidgetData.RefreshPresentationState.LOADING,
      )

      val rootIntent =
        if (nextCourse != null) {
          bindCourse(views, nextCourse, courses.size)
          WidgetNavigationPendingIntent.createForCourse(
            context,
            appWidgetId,
            0,
            nextCourse.name,
            nextCourse.eventId,
          )
        } else {
          bindStatus(context, views, refresh)
          WidgetNavigationPendingIntent.create(context, appWidgetId, 0, false)
        }
      if (rootIntent != null) {
        views.setOnClickPendingIntent(R.id.widget_root, null)
        views.setOnClickPendingIntent(R.id.course_content, rootIntent)
        views.setOnClickPendingIntent(R.id.status_content, rootIntent)
      }

      val manualRefreshIntent =
        Intent(context, TinyCourseWidgetProvider::class.java).apply {
          action = ACTION_MANUAL_REFRESH
          putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
          data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME) + "#manual-refresh-$appWidgetId")
        }
      val manualRefreshPendingIntent =
        PendingIntent.getBroadcast(
          context,
          appWidgetId + 30000,
          manualRefreshIntent,
          PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
      views.setImageViewResource(R.id.iv_refresh, R.drawable.ic_widget_refresh)
      views.setContentDescription(R.id.iv_refresh, refreshActionDescription(refresh))
      val refreshIntent =
        if (refresh.state == TodayWidgetData.RefreshPresentationState.CREDENTIAL_INVALID) {
          WidgetNavigationPendingIntent.create(context, appWidgetId, 0, false)
        } else {
          manualRefreshPendingIntent
        }
      if (refreshIntent != null) {
        views.setOnClickPendingIntent(R.id.iv_refresh, refreshIntent)
      }
    }

    private fun bindCourse(
      views: RemoteViews,
      course: TodayWidgetData.CourseItem,
      remainingCount: Int,
    ) {
      views.setViewVisibility(R.id.course_content, View.VISIBLE)
      views.setViewVisibility(R.id.iv_indicator, View.VISIBLE)
      views.setTextViewText(R.id.tv_course_name, course.name)
      val clock =
        if (course.startTime.isNotBlank() && course.endTime.isNotBlank()) {
          "${course.startTime}-${course.endTime}"
        } else {
          course.periods
        }
      views.setTextViewText(R.id.tv_course_time, "$clock · 余${remainingCount}门")
      val location =
        listOf(course.campus.trim(), course.classroom.trim())
          .filter { it.isNotEmpty() }
          .joinToString(" ")
      views.setTextViewText(
        R.id.tv_course_location,
        location,
      )
      views.setInt(R.id.iv_indicator, "setColorFilter", course.indicatorColor)
    }

    private fun bindStatus(
      context: Context,
      views: RemoteViews,
      refresh: TodayWidgetData.RefreshPresentation,
    ) {
      views.setViewVisibility(R.id.status_content, View.VISIBLE)
      val title =
        if (refresh.state == TodayWidgetData.RefreshPresentationState.NORMAL) {
          TodayWidgetData.loadTodayCourseStateText(context)
        } else {
          refresh.text
        }
      val message =
        when {
          refresh.state == TodayWidgetData.RefreshPresentationState.CREDENTIAL_INVALID ->
            "点击打开应用"
          refresh.state == TodayWidgetData.RefreshPresentationState.LOADING -> "请稍候"
          refresh.usesRefreshAction -> "点击右侧刷新"
          else -> ""
        }
      views.setTextViewText(R.id.tv_status_title, title)
      views.setTextViewText(R.id.tv_status_message, message)
      views.setViewVisibility(
        R.id.tv_status_message,
        if (message.isBlank()) View.GONE else View.VISIBLE,
      )
    }
  }
}
