package com.dawndrizzle.wing.cqut.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import com.dawndrizzle.wing.cqut.R

private const val ACTION_UI_MODE_CHANGED = "android.intent.action.UI_MODE_CHANGED"
private const val ACTION_APPWIDGET_UPDATE_OPTIONS = "android.appwidget.action.APPWIDGET_UPDATE_OPTIONS"

class TodayCourseWidgetProvider : AppWidgetProvider() {
  override fun onUpdate(
    context: Context,
    appWidgetManager: AppWidgetManager,
    appWidgetIds: IntArray,
  ) {
    WidgetThemeSyncDispatcher.dispatch(context, WidgetThemeTrigger.INITIALIZATION)
  }

  override fun onReceive(context: Context, intent: Intent) {
    super.onReceive(context, intent)
    when (intent.action) {
      ACTION_REFRESH -> WidgetThemeSyncDispatcher.dispatch(context, WidgetThemeTrigger.DATA_REFRESH)
      ACTION_MANUAL_REFRESH -> ScheduleWidgetRefreshWork.enqueue(context)
      Intent.ACTION_CONFIGURATION_CHANGED ->
        WidgetThemeSyncDispatcher.dispatch(context, WidgetThemeTrigger.SYSTEM_THEME_CHANGED)
      ACTION_UI_MODE_CHANGED ->
        WidgetThemeSyncDispatcher.dispatch(context, WidgetThemeTrigger.SYSTEM_THEME_CHANGED)
      ACTION_APPWIDGET_UPDATE_OPTIONS ->
        WidgetThemeSyncDispatcher.dispatch(context, WidgetThemeTrigger.SYSTEM_THEME_CHANGED)
      ACTION_TOGGLE_DAY -> {
        val appWidgetId =
          intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
        if (appWidgetId != AppWidgetManager.INVALID_APPWIDGET_ID) {
          toggleDayOffset(context, appWidgetId)
        } else {
          WidgetThemeSyncDispatcher.dispatch(context, WidgetThemeTrigger.DATA_REFRESH)
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
    WidgetThemeSyncDispatcher.dispatch(context, WidgetThemeTrigger.SYSTEM_THEME_CHANGED)
  }

  override fun onDeleted(
    context: Context,
    appWidgetIds: IntArray,
  ) {
    WidgetInstanceConfigStore.delete(context, appWidgetIds)
    super.onDeleted(context, appWidgetIds)
  }

  companion object {
    const val ACTION_REFRESH = "com.dawndrizzle.wing.cqut.widget.TODAY_COURSE_REFRESH"
    const val ACTION_TOGGLE_DAY = "com.dawndrizzle.wing.cqut.widget.TODAY_COURSE_TOGGLE_DAY"
    const val ACTION_MANUAL_REFRESH =
      "com.dawndrizzle.wing.cqut.widget.TODAY_COURSE_MANUAL_REFRESH"
    fun updateAll(context: Context, theme: WidgetThemeResolution? = null) {
      val appWidgetManager = AppWidgetManager.getInstance(context)
      val ids =
        appWidgetManager.getAppWidgetIds(ComponentName(context, TodayCourseWidgetProvider::class.java))
      updateAppWidgets(context, appWidgetManager, ids, theme)
    }

    private fun updateAppWidgets(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      theme: WidgetThemeResolution? = null,
    ) {
      val fallbackTheme = theme ?: WidgetTheme.resolve(context, WidgetThemeTrigger.DATA_REFRESH)
      for (appWidgetId in appWidgetIds) {
        val resolvedTheme =
          WidgetInstanceConfigStore.resolveTheme(context, appWidgetId, fallbackTheme)
        updateAppWidget(context, appWidgetManager, appWidgetId, resolvedTheme)
      }
    }

    fun updateOne(
      context: Context,
      appWidgetId: Int,
    ) {
      val appWidgetManager = AppWidgetManager.getInstance(context)
      val fallbackTheme = WidgetTheme.resolve(context, WidgetThemeTrigger.DATA_REFRESH)
      val theme = WidgetInstanceConfigStore.resolveTheme(context, appWidgetId, fallbackTheme)
      updateAppWidget(context, appWidgetManager, appWidgetId, theme)
    }

    private fun updateAppWidget(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetId: Int,
      theme: WidgetThemeResolution,
    ) {
      val views = RemoteViews(context.packageName, R.layout.widget_today_course)

      val palette = theme.palette
      views.setImageViewResource(
        R.id.iv_appwidget,
        palette.imageBackgroundRes,
      )
      views.setTextColor(R.id.tv_schedule_name, palette.primaryText)
      views.setTextColor(R.id.tv_date, palette.primaryText)
      views.setTextColor(R.id.tv_week_count, palette.secondaryText)
      views.setTextColor(R.id.tv_week, palette.accent)
      views.setTextColor(R.id.empty_text, palette.secondaryText)
      views.setTextColor(R.id.tv_sync_status, palette.secondaryText)
      views.setInt(R.id.iv_next, "setColorFilter", palette.icon)
      views.setInt(R.id.theme_transition_overlay, "setBackgroundColor", palette.transitionOverlay)
      views.setViewVisibility(
        R.id.theme_transition_overlay,
        if (theme.shouldAnimate) android.view.View.VISIBLE else android.view.View.GONE,
      )

      val dayOffset = getDayOffset(context, appWidgetId)
      val header = TodayWidgetData.loadHeaderByDayOffset(context, dayOffset)
      val weekCount = TodayWidgetData.loadWeekCountText(context)
      views.setTextViewText(R.id.tv_schedule_name, header.scheduleName)
      views.setTextViewText(R.id.tv_date, header.dateText)
      val weekCountPart = if (weekCount.isNotBlank()) " | $weekCount    " else " | "
      views.setTextViewText(R.id.tv_week_count, weekCountPart)
      views.setTextViewText(R.id.tv_week, header.weekText)
      views.setTextViewText(
        R.id.empty_text,
        TodayWidgetData.loadEmptyStateText(context, dayOffset),
      )
      val refreshPresentation = TodayWidgetData.loadRefreshPresentation(context)
      views.setTextViewText(R.id.tv_sync_status, refreshPresentation.text)
      views.setViewVisibility(
        R.id.tv_sync_status,
        if (refreshPresentation.text.isBlank()) android.view.View.GONE else android.view.View.VISIBLE,
      )

      val svcIntent = Intent(context, CourseListWidgetService::class.java).apply {
        putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        putExtra(CourseListWidgetService.EXTRA_DAY_OFFSET, dayOffset)
        putExtra(CourseListWidgetService.EXTRA_ADD_FIRST_ITEM_TOP_SPACING, true)
        data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME) + "#$dayOffset")
      }
      views.setRemoteAdapter(R.id.lv_course, svcIntent)
      views.setEmptyView(R.id.lv_course, android.R.id.empty)

      views.setFloat(R.id.iv_next, "setRotation", if (dayOffset == 0) 180f else 0f)
      val toggleIntent =
        Intent(context, TodayCourseWidgetProvider::class.java).apply {
          action = ACTION_TOGGLE_DAY
          putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
          data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME) + "#toggle-$appWidgetId")
        }
      val togglePendingIntent =
        PendingIntent.getBroadcast(
          context,
          appWidgetId,
          toggleIntent,
          PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
      val manualRefreshIntent =
        Intent(context, TodayCourseWidgetProvider::class.java).apply {
          action = ACTION_MANUAL_REFRESH
          putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
          data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME) + "#refresh-$appWidgetId")
        }
      val manualRefreshPendingIntent =
        PendingIntent.getBroadcast(
          context,
          appWidgetId + 10000,
          manualRefreshIntent,
          PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
      val isNormal =
        refreshPresentation.state == TodayWidgetData.RefreshPresentationState.NORMAL
      val isLoading =
        refreshPresentation.state == TodayWidgetData.RefreshPresentationState.LOADING
      val isCredentialInvalid =
        refreshPresentation.state ==
          TodayWidgetData.RefreshPresentationState.CREDENTIAL_INVALID
      views.setImageViewResource(
        R.id.iv_next,
        if (isNormal) R.drawable.ic_back else android.R.drawable.ic_popup_sync,
      )
      views.setFloat(R.id.iv_next, "setRotation", if (isNormal && dayOffset == 0) 180f else 0f)
      views.setBoolean(R.id.iv_next, "setEnabled", !isLoading)
      when {
        refreshPresentation.usesRefreshAction ->
          views.setOnClickPendingIntent(R.id.iv_next, manualRefreshPendingIntent)
        isLoading ->
          views.setOnClickPendingIntent(R.id.iv_next, manualRefreshPendingIntent)
        !isCredentialInvalid ->
          views.setOnClickPendingIntent(R.id.iv_next, togglePendingIntent)
      }

      val rootPendingIntent =
        WidgetNavigationPendingIntent.create(
          context,
          appWidgetId,
          dayOffset,
          false,
        )
      val coursePendingIntent =
        WidgetNavigationPendingIntent.create(
          context,
          appWidgetId,
          dayOffset,
          true,
        )
      if (rootPendingIntent != null) {
        views.setOnClickPendingIntent(R.id.widget_root, rootPendingIntent)
        views.setOnClickPendingIntent(R.id.rl_appwidget, rootPendingIntent)
        views.setOnClickPendingIntent(R.id.rl_title, rootPendingIntent)
        views.setOnClickPendingIntent(android.R.id.empty, rootPendingIntent)
        if (isCredentialInvalid) {
          views.setOnClickPendingIntent(R.id.iv_next, rootPendingIntent)
        }
      }
      if (coursePendingIntent != null) {
        views.setPendingIntentTemplate(R.id.lv_course, coursePendingIntent)
      }

      appWidgetManager.updateAppWidget(appWidgetId, views)
      appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.lv_course)
    }

    private fun getDayOffset(context: Context, appWidgetId: Int): Int {
      return WidgetInstanceConfigStore.load(context, appWidgetId).dayOffset
    }

    private fun toggleDayOffset(context: Context, appWidgetId: Int) {
      val current = WidgetInstanceConfigStore.load(context, appWidgetId).dayOffset
      val next = if (current == 0) 1 else 0
      WidgetInstanceConfigStore.saveDayOffset(context, appWidgetId, next)

      val appWidgetManager = AppWidgetManager.getInstance(context)
      val fallbackTheme = WidgetTheme.resolve(context, WidgetThemeTrigger.DATA_REFRESH)
      val theme = WidgetInstanceConfigStore.resolveTheme(context, appWidgetId, fallbackTheme)
      updateAppWidget(context, appWidgetManager, appWidgetId, theme)
      WidgetAutoRefreshScheduler.schedule(context)
    }
  }
}
