package com.dawndrizzle.wing.cqut.widget

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import java.util.Locale

/**
 * Reads schedule data from Flutter SharedPreferences (same keys as lib).
 * Keys use "flutter." prefix on Android.
 */
object ScheduleDataHelper {
    private const val PREFS_NAME = "FlutterSharedPreferences"
    private const val KEY_PREFIX = "flutter."

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun key(raw: String) = KEY_PREFIX + raw

    fun getUserId(context: Context): String? {
        return prefs(context).getString(key("account"), null)?.takeIf { it.isNotEmpty() }
    }

    /**
     * Load cached schedule JSON for the last viewed week/term.
     * Returns null if not logged in or no cache.
     */
    fun loadCachedSchedule(context: Context): ScheduleData? {
        val userId = getUserId(context) ?: return null
        val prefs = prefs(context)
        val lastWeek = prefs.getString(key("schedule_last_week_$userId"), null) ?: return null
        val lastTerm = prefs.getString(key("schedule_last_term_$userId"), null) ?: return null
        val cacheKey = "schedule_${userId}_${lastTerm}_$lastWeek"
        val jsonStr = prefs.getString(key(cacheKey), null) ?: return null
        return parseScheduleJson(jsonStr)
    }

    fun parseScheduleJson(jsonStr: String): ScheduleData? {
        return try {
            val obj = JSONObject(jsonStr)
            val weekNum = obj.optString("weekNum", null).takeIf { !it.isNullOrEmpty() }
            val yearTerm = obj.optString("yearTerm", null).takeIf { !it.isNullOrEmpty() }
            val weekList = parseStringList(obj.optJSONArray("weekList"))
            val weekDayList = parseWeekDayList(obj.optJSONArray("weekDayList"))
            val eventList = parseEventList(obj.optJSONArray("eventList"))
            ScheduleData(
                weekNum = weekNum,
                yearTerm = yearTerm,
                weekList = weekList,
                weekDayList = weekDayList,
                eventList = eventList
            )
        } catch (_: Exception) {
            null
        }
    }

    private fun parseStringList(arr: JSONArray?): List<String>? {
        if (arr == null) return null
        val list = mutableListOf<String>()
        for (i in 0 until arr.length()) {
            arr.optString(i, null)?.takeIf { it.isNotEmpty() }?.let { list.add(it) }
        }
        return list.takeIf { it.isNotEmpty() }
    }

    private fun parseWeekDayList(arr: JSONArray?): List<WeekDayItem>? {
        if (arr == null) return null
        val list = mutableListOf<WeekDayItem>()
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            list.add(
                WeekDayItem(
                    weekDay = o.optString("weekDay", null).takeIf { !it.isNullOrEmpty() },
                    weekDate = o.optString("weekDate", null).takeIf { !it.isNullOrEmpty() },
                    today = if (o.has("today")) o.optBoolean("today") else null
                )
            )
        }
        return list.takeIf { it.isNotEmpty() }
    }

    private fun parseEventList(arr: JSONArray?): List<EventItem>? {
        if (arr == null) return null
        val list = mutableListOf<EventItem>()
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            list.add(
                EventItem(
                    weekNum = o.optString("weekNum", null).takeIf { !it.isNullOrEmpty() },
                    weekDay = o.optString("weekDay", null).takeIf { !it.isNullOrEmpty() },
                    sessionStart = o.optString("sessionStart", null).takeIf { !it.isNullOrEmpty() },
                    sessionLast = o.optString("sessionLast", null).takeIf { !it.isNullOrEmpty() },
                    sessionList = parseStringList(o.optJSONArray("sessionList")),
                    eventName = o.optString("eventName", null).takeIf { !it.isNullOrEmpty() },
                    address = o.optString("address", null).takeIf { !it.isNullOrEmpty() },
                    memberName = o.optString("memberName", null).takeIf { !it.isNullOrEmpty() }
                )
            )
        }
        return list.takeIf { it.isNotEmpty() }
    }

    /** 今天在周几：1=周一 … 7=周日 */
    fun todayWeekDayIndex(): Int {
        var d = Calendar.getInstance(Locale.getDefault()).get(Calendar.DAY_OF_WEEK)
        if (d == Calendar.SUNDAY) d = 8
        return d - 1
    }

    /** 今天的中文星期，如 "星期四" */
    fun todayWeekDayName(): String {
        val names = arrayOf("周一", "周二", "周三", "周四", "周五", "周六", "周日")
        val i = todayWeekDayIndex()
        return names.getOrElse(i) { "周?" }
    }

    /** 将 session 时间转为可显示的 "08:00" 等；若 API 有 sessionList 可用，否则用 sessionStart/sessionLast 或占位 */
    fun formatTimeRange(event: EventItem): String {
        val list = event.sessionList
        if (!list.isNullOrEmpty()) {
            val first = list.first().trim()
            val last = list.last().trim()
            if (first.isNotEmpty() && last.isNotEmpty()) return "$first-$last"
        }
        val s = event.sessionStart?.trim() ?: ""
        val e = event.sessionLast?.trim() ?: ""
        return when {
            s.isNotEmpty() && e.isNotEmpty() -> "$s-$e"
            s.isNotEmpty() -> s
            else -> ""
        }
    }

    /** 从 eventList 中筛出“今天”的课，并按时间排序（按 sessionStart 或 sessionList 首元素） */
    fun todayEvents(data: ScheduleData): List<EventItem> {
        val events = data.eventList ?: return emptyList()
        val todayName = todayWeekDayName()
        val todayList = events.filter { it.weekDay == todayName }
        return todayList.sortedBy { e ->
            e.sessionList?.firstOrNull()?.trim() ?: e.sessionStart ?: ""
        }
    }

    /** 按 weekDayList 顺序得到一周的星期名列表，用于 4x4 网格表头 */
    fun weekDayNames(data: ScheduleData): List<String> {
        val list = data.weekDayList ?: return listOf("周一", "周二", "周三", "周四", "周五", "周六", "周日")
        return list.mapNotNull { it.weekDay }
    }

    /** 获取某天某节的课程（用于网格）；weekDay 如 "周一"，session 如 "08:00" 或节次 */
    fun eventAt(data: ScheduleData, weekDay: String, sessionKey: String): EventItem? {
        val events = data.eventList ?: return null
        return events.firstOrNull { e ->
            e.weekDay == weekDay && (
                e.sessionList?.any { it.trim() == sessionKey } == true ||
                e.sessionStart == sessionKey
            )
        }
    }

    /** 为课程条分配颜色索引 */
    fun colorIndexForEvent(eventName: String?, index: Int): Int {
        val hash = (eventName ?: "").hashCode()
        return (hash and 0x7FFF).rem(8).let { if (it < 0) it + 8 else it }
    }
}

data class ScheduleData(
    val weekNum: String? = null,
    val yearTerm: String? = null,
    val weekList: List<String>? = null,
    val weekDayList: List<WeekDayItem>? = null,
    val eventList: List<EventItem>? = null
)

data class WeekDayItem(
    val weekDay: String?,
    val weekDate: String?,
    val today: Boolean?
)

data class EventItem(
    val weekNum: String? = null,
    val weekDay: String? = null,
    val sessionStart: String? = null,
    val sessionLast: String? = null,
    val sessionList: List<String>? = null,
    val eventName: String? = null,
    val address: String? = null,
    val memberName: String? = null
)
