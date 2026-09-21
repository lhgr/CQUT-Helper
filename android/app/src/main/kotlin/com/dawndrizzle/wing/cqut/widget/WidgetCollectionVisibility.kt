package com.dawndrizzle.wing.cqut.widget

import android.view.View
import android.widget.RemoteViews

internal data class WidgetCollectionVisibilityState(
  val showList: Boolean,
  val showEmpty: Boolean,
)

/**
 * Makes the empty transition independent from launcher collection callbacks.
 *
 * Some launchers keep the final RemoteViews row visible when a factory changes
 * from one item to zero. Explicitly hiding the collection in the provider's
 * ordinary partial payload lets the empty state win even if adapter rebinding
 * or notifyAppWidgetViewDataChanged() is delayed or dropped.
 */
internal object WidgetCollectionVisibility {
  fun stateFor(itemCount: Int): WidgetCollectionVisibilityState {
    val hasItems = itemCount > 0
    return WidgetCollectionVisibilityState(
      showList = hasItems,
      showEmpty = !hasItems,
    )
  }

  fun bind(
    views: RemoteViews,
    listViewId: Int,
    emptyViewId: Int,
    itemCount: Int,
  ) {
    val state = stateFor(itemCount)
    views.setViewVisibility(listViewId, if (state.showList) View.VISIBLE else View.GONE)
    views.setViewVisibility(emptyViewId, if (state.showEmpty) View.VISIBLE else View.GONE)
  }
}
