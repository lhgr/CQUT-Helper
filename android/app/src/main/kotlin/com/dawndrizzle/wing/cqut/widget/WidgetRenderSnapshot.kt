package com.dawndrizzle.wing.cqut.widget

/** One synchronous render uses one instant and one copy of the session clocks.
 * Collection factories run on other threads and take their own fresh snapshot.
 */
internal object WidgetRenderSnapshot {
  internal class Snapshot(val nowMillis: Long) {
    var sessionClocks: Map<Int, Pair<Int, Int>>? = null
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
