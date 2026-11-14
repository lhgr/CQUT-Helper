package com.dawndrizzle.wing.cqut.widget

/**
 * Builds a stable collection-adapter identity for one concrete visible data set.
 *
 * App widget hosts compare service intents without their extras. Including the
 * resolved date prevents a host from reusing yesterday's RemoteViewsFactory.
 * Including the visible-content fingerprint also replaces a factory when a
 * course starts or synchronized schedule data changes. Some launchers ignore
 * notifyAppWidgetViewDataChanged() for only a subset of widget instances.
 * The theme signature replaces cached rows when their colors change.
 */
internal object WidgetCollectionAdapterIdentity {
  fun dataUri(
    kind: String,
    appWidgetId: Int,
    dayOffset: Int,
    themeSignature: String,
    nowMillis: Long = WidgetRenderSnapshot.nowMillis(),
    contentFingerprint: String = "",
  ): String {
    val date = TodayWidgetData.dateForDayOffset(dayOffset, nowMillis)
    val contentVersion = contentFingerprint.ifBlank { "empty" }
    val themeVersion = themeSignature.replace('|', '-')
    return "cqut-helper://widget/collection/$kind/$appWidgetId/$dayOffset/" +
      "$themeVersion/$contentVersion/$date"
  }
}
