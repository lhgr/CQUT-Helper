package com.dawndrizzle.wing.cqut.widget

/** One synchronous render uses one instant and one copy of the session clocks.
 * Collection factories run on other threads and take their own fresh snapshot.
 */
internal object WidgetRenderSnapshot {
  internal class Snapshot(val nowMillis: Long) {
    var sessionClocks: Map<Int, Pair<Int, Int>>? = null

    private var projectionRaw: String? = null
    private var projection: TodayWidgetData.CalendarProjection? = null

    fun loadCalendarProjection(
      raw: String,
      decode: () -> TodayWidgetData.CalendarProjection?,
    ): TodayWidgetData.CalendarProjection? {
      if (projectionRaw != raw) {
        projection = decode()
        projectionRaw = raw
      }
      return projection
    }
  }

  internal val current = ThreadLocal<Snapshot>()

  fun nowMillis(): Long = current.get()?.nowMillis ?: System.currentTimeMillis()

  inline fun <T> withSnapshot(nowMillis: Long = nowMillis(), block: () -> T): T {
    if (current.get() != null) return block()
    current.set(Snapshot(nowMillis))
    try {
      return block()
    } finally {
      current.remove()
    }
  }
}
