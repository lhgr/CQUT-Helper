package com.dawndrizzle.wing.cqut.widget

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

object TodayWidgetData {
  data class Header(
    val scheduleName: String,
    val dateText: String,
    val weekText: String,
  )

  data class CourseItem(
    val eventId: String?,
    val name: String,
    val location: String,
    val teacher: String,
    val time: String,
    val indicatorColor: Int,
  )

  private const val PREFS_NAME = "FlutterSharedPreferences"
  private const val FLUTTER_PREFIX = "flutter."

  fun loadHeader(context: Context): Header {
    val calendar = Calendar.getInstance()
    val dateFormat = SimpleDateFormat("M.d", Locale.CHINA)
    val defaultDateText = dateFormat.format(calendar.time)
    val defaultWeekText = "周${toChineseWeekday(toMondayBasedWeekday(calendar))}"

    val today = loadTodayWeekDayAndDate(context)
    return Header(
      scheduleName = "课表",
      dateText = today?.dateText ?: defaultDateText,
      weekText = today?.weekText ?: defaultWeekText,
    )
  }

  fun loadHeaderByDayOffset(context: Context, dayOffset: Int): Header {
    val calendar = Calendar.getInstance()
    val dateFormat = SimpleDateFormat("M.d", Locale.CHINA)
    val targetCal = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, dayOffset) }
    val targetWeekDay = toMondayBasedWeekday(targetCal)

    val defaultDateText = dateFormat.format(targetCal.time)
    val defaultWeekText = "周${toChineseWeekday(targetWeekDay)}"

    return Header(
      scheduleName = "课表",
      dateText = defaultDateText,
      weekText = defaultWeekText,
    )
  }

  fun loadWeekCountText(context: Context): String {
    val data = loadScheduleJsonObject(context) ?: return ""
    if (!scheduleContainsSystemDate(data)) return ""
    val week = data.optString("weekNum", "")
    if (week.isBlank()) return ""
    return "第${week}周"
  }

  fun loadCoursesByDayOffset(context: Context, dayOffset: Int): List<CourseItem> {
    val data = loadScheduleJsonObject(context) ?: return emptyList()
    if (!scheduleContainsSystemDate(data)) return emptyList()
    val today = loadTodayWeekDayAndDateFromSchedule(data)
    val baseWeekDay =
      today?.weekDay?.toIntOrNull() ?: toMondayBasedWeekday(Calendar.getInstance())

    val rawTarget = baseWeekDay + dayOffset
    var targetWeekDay = rawTarget
    var targetData = data

    if (rawTarget > 7 && dayOffset > 0) {
      targetWeekDay = rawTarget - 7
      val next = loadNextWeekScheduleJsonObject(context)
      if (next != null) targetData = next
    } else if (rawTarget < 1 && dayOffset < 0) {
      targetWeekDay = rawTarget + 7
      val prev = loadPrevWeekScheduleJsonObject(context)
      if (prev != null) targetData = prev
    }

    return loadCoursesByWeekdayFromSchedule(targetData, targetWeekDay.coerceIn(1, 7).toString())
  }

  private fun scheduleContainsSystemDate(data: JSONObject): Boolean {
    val weekDayList = data.optJSONArray("weekDayList") ?: return false
    val systemDateText =
      SimpleDateFormat("M.d", Locale.CHINA).format(Calendar.getInstance().time)
    for (i in 0 until weekDayList.length()) {
      val d = weekDayList.optJSONObject(i) ?: continue
      val weekDate = d.optString("weekDate", "")
      if (weekDate.isNotBlank() && weekDate == systemDateText) return true
    }
    return false
  }

  private fun loadNextWeekScheduleJsonObject(context: Context): JSONObject? {
    return loadOffsetWeekScheduleJsonObject(context, offsetWeeks = 1)
  }

  private fun loadPrevWeekScheduleJsonObject(context: Context): JSONObject? {
    return loadOffsetWeekScheduleJsonObject(context, offsetWeeks = -1)
  }

  private fun loadOffsetWeekScheduleJsonObject(context: Context, offsetWeeks: Int): JSONObject? {
    val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    val userId = prefs.getString("${FLUTTER_PREFIX}account", null)?.takeIf { it.isNotBlank() } ?: return null
    val lastTerm = prefs.getString("${FLUTTER_PREFIX}schedule_last_term_$userId", null)?.takeIf { it.isNotBlank() } ?: return null
    val lastWeekStr = prefs.getString("${FLUTTER_PREFIX}schedule_last_week_$userId", null)?.takeIf { it.isNotBlank() } ?: return null
    val lastWeek = lastWeekStr.toIntOrNull() ?: return null

    val targetWeek = (lastWeek + offsetWeeks).toString()
    val scheduleKey = "${FLUTTER_PREFIX}schedule_${userId}_${lastTerm}_$targetWeek"
    val jsonStr = prefs.getString(scheduleKey, null) ?: return null
    return try {
      JSONObject(jsonStr)
    } catch (_: Exception) {
      null
    }
  }

  fun loadCoursesByWeekdayFromSchedule(data: JSONObject, weekDay: String): List<CourseItem> {
    val events = data.optJSONArray("eventList") ?: return emptyList()
    val result = ArrayList<CourseItem>(events.length())

    for (i in 0 until events.length()) {
      val e = events.optJSONObject(i) ?: continue
      val eWeekDay = e.optString("weekDay", "")
      if (eWeekDay != weekDay) continue

      val name = e.optString("eventName", "").ifBlank { "课程" }
      val location = e.optString("address", "").ifBlank { " " }
      val teacher = e.optString("memberName", "").ifBlank { " " }

      val start = e.optInt("sessionStart", -1)
      val last = e.optInt("sessionLast", -1)
      val time =
        if (start > 0 && last > 0) {
          val end = start + last - 1
          "第$start-${end}节"
        } else {
          val arr = e.optJSONArray("sessionList")
          if (arr != null && arr.length() > 0) {
            "第${joinIntArray(arr)}节"
          } else {
            ""
          }
        }

      val eventId = e.optString("eventID").ifBlank { null }
      result.add(
        CourseItem(
          eventId = eventId,
          name = name,
          location = location,
          teacher = teacher,
          time = time,
          indicatorColor = pickColor(name),
        ),
      )
    }

    result.sortBy { it.time }
    return result
  }

  fun loadTodayCourses(context: Context): List<CourseItem> {
    val data = loadScheduleJsonObject(context) ?: return emptyList()
    val today = loadTodayWeekDayAndDateFromSchedule(data) ?: loadTodayWeekDayAndDate(context)
    val todayWeekDay = today?.weekDay ?: toMondayBasedWeekday(Calendar.getInstance()).toString()

    return loadCoursesByWeekdayFromSchedule(data, todayWeekDay)
  }

  private data class TodayInfo(
    val weekDay: String,
    val dateText: String,
    val weekText: String,
  )

  private fun loadTodayWeekDayAndDate(context: Context): TodayInfo? {
    val data = loadScheduleJsonObject(context) ?: return null
    return loadTodayWeekDayAndDateFromSchedule(data)
  }

  private fun loadTodayWeekDayAndDateFromSchedule(data: JSONObject): TodayInfo? {
    val weekDayList = data.optJSONArray("weekDayList") ?: return null
    val systemDateText =
      SimpleDateFormat("M.d", Locale.CHINA).format(Calendar.getInstance().time)
    for (i in 0 until weekDayList.length()) {
      val d = weekDayList.optJSONObject(i) ?: continue
      if (!d.optBoolean("today", false)) continue

      val weekDay = d.optString("weekDay", "")
      val weekDate = d.optString("weekDate", "")
      if (weekDate.isNotBlank() && weekDate != systemDateText) continue
      val weekText =
        if (weekDay.isNotBlank()) {
          "周${toChineseWeekday(weekDay.toIntOrNull() ?: 1)}"
        } else {
          ""
        }

      val dateText =
        if (weekDate.isNotBlank()) {
          weekDate
        } else {
          ""
        }

      if (weekDay.isBlank() && dateText.isBlank()) return null
      return TodayInfo(weekDay = weekDay, dateText = dateText, weekText = weekText)
    }
    return null
  }

  fun loadScheduleJsonObject(context: Context): JSONObject? {
    val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    val userId = prefs.getString("${FLUTTER_PREFIX}account", null)?.takeIf { it.isNotBlank() } ?: return null

    val lastTerm = prefs.getString("${FLUTTER_PREFIX}schedule_last_term_$userId", null)?.takeIf { it.isNotBlank() } ?: return null
    val lastWeek = prefs.getString("${FLUTTER_PREFIX}schedule_last_week_$userId", null)?.takeIf { it.isNotBlank() } ?: return null

    val scheduleKey = "${FLUTTER_PREFIX}schedule_${userId}_${lastTerm}_$lastWeek"
    val jsonStr = prefs.getString(scheduleKey, null) ?: return null

    return try {
      JSONObject(jsonStr)
    } catch (_: Exception) {
      null
    }
  }

  private fun toMondayBasedWeekday(calendar: Calendar): Int {
    val dayOfWeek = calendar.get(Calendar.DAY_OF_WEEK)
    return (dayOfWeek + 5) % 7 + 1
  }

  private fun toChineseWeekday(mondayBased: Int): String {
    return when (mondayBased) {
      1 -> "一"
      2 -> "二"
      3 -> "三"
      4 -> "四"
      5 -> "五"
      6 -> "六"
      7 -> "日"
      else -> "一"
    }
  }

  private fun joinIntArray(arr: JSONArray): String {
    val sb = StringBuilder()
    for (i in 0 until arr.length()) {
      val v = arr.optInt(i, -1)
      if (v <= 0) continue
      if (sb.isNotEmpty()) sb.append(",")
      sb.append(v)
    }
    return sb.toString()
  }

  private fun pickColor(seed: String): Int {
    val palette =
      intArrayOf(
        0xFFE57373.toInt(),
        0xFFF06292.toInt(),
        0xFFBA68C8.toInt(),
        0xFF64B5F6.toInt(),
        0xFF4DB6AC.toInt(),
        0xFFFFB74D.toInt(),
      )
    val idx = (seed.hashCode().ushr(1)) % palette.size
    return palette[idx]
  }
}
