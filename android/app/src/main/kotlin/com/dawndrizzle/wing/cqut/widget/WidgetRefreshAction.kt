package com.dawndrizzle.wing.cqut.widget

/** Accessible action labels shared by widgets with a dedicated refresh button. */
internal fun refreshActionDescription(refresh: TodayWidgetData.RefreshPresentation): String =
  when (refresh.state) {
    TodayWidgetData.RefreshPresentationState.CREDENTIAL_INVALID -> "${refresh.text}，点击打开应用"
    TodayWidgetData.RefreshPresentationState.LOADING -> "正在更新课表，请稍候"
    TodayWidgetData.RefreshPresentationState.NORMAL -> "刷新课表"
    else -> "${refresh.text}，点击刷新课表"
  }
