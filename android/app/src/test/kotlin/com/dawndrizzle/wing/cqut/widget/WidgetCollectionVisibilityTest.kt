package com.dawndrizzle.wing.cqut.widget

import org.junit.Assert.assertEquals
import org.junit.Test

class WidgetCollectionVisibilityTest {
  @Test
  fun `non-empty collection shows list and hides empty state`() {
    assertEquals(
      WidgetCollectionVisibilityState(showList = true, showEmpty = false),
      WidgetCollectionVisibility.stateFor(1),
    )
  }

  @Test
  fun `zero item transition hides stale list and shows empty state`() {
    assertEquals(
      WidgetCollectionVisibilityState(showList = false, showEmpty = true),
      WidgetCollectionVisibility.stateFor(0),
    )
  }
}
