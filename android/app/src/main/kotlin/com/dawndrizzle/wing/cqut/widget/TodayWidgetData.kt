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
  private const val KEY_WIDGET_WEEK_PREFIX = "${FLUTTER_PREFIX}schedule_widget_week_"
  private const val KEY_WIDGET_TERM_PREFIX = "${FLUTTER_PREFIX}schedule_widget_term_"
  private const val KEY_LAST_WEEK_PREFIX = "${FLUTTER_PREFIX}schedule_last_week_"
  private const val KEY_LAST_TERM_PREFIX = "${FLUTTER_PREFIX}schedule_last_term_"

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
    val baseWeekDay = toMondayBasedWeekday(Calendar.getInstance())

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
    val weekDayList = data.optJSONArray("weekDayList")
    if (weekDayList == null || weekDayList.length() == 0) {
      val events = data.optJSONArray("eventList")
      return events != null && events.length() > 0
    }
    for (i in 0 until weekDayList.length()) {
      val d = weekDayList.optJSONObject(i) ?: continue
      val weekDate = d.optString("weekDate", "")
      if (d.optBoolean("today", false)) return true
      if (weekDate.isBlank()) return true
      if (isSameAsSystemDate(weekDate)) return true
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
    val baseTerm =
      prefs.getString("$KEY_WIDGET_TERM_PREFIX$userId", null)?.takeIf { it.isNotBlank() }
        ?: prefs.getString("$KEY_LAST_TERM_PREFIX$userId", null)?.takeIf { it.isNotBlank() }
        ?: return null
    val baseWeekStr =
      prefs.getString("$KEY_WIDGET_WEEK_PREFIX$userId", null)?.takeIf { it.isNotBlank() }
        ?: prefs.getString("$KEY_LAST_WEEK_PREFIX$userId", null)?.takeIf { it.isNotBlank() }
        ?: return null
    val baseWeek = baseWeekStr.toIntOrNull() ?: return null

    val targetWeek = (baseWeek + offsetWeeks).toString()
    val scheduleKey = "${FLUTTER_PREFIX}schedule_${userId}_${baseTerm}_$targetWeek"
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
    val todayWeekDay = toMondayBasedWeekday(Calendar.getInstance()).toString()

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
    for (i in 0 until weekDayList.length()) {
      val d = weekDayList.optJSONObject(i) ?: continue
      if (!d.optBoolean("today", false)) continue

      val weekDay = d.optString("weekDay", "")
      val weekDate = d.optString("weekDate", "")
      if (weekDate.isNotBlank() && !isSameAsSystemDate(weekDate)) continue
      val computedWeekDay = mondayBasedWeekdayFromWeekDateText(weekDate)
      val weekText =
        when {
          computedWeekDay != null -> "周${toChineseWeekday(computedWeekDay)}"
          weekDay.isNotBlank() -> "周${toChineseWeekday(weekDay.toIntOrNull() ?: 1)}"
          else -> ""
        }

      val dateText =
        if (weekDate.isNotBlank()) {
          weekDate
        } else {
          ""
        }

      if (weekDay.isBlank() && dateText.isBlank()) return null
      val normalizedWeekDay =
        when {
          computedWeekDay != null -> computedWeekDay.toString()
          weekDay.isNotBlank() -> weekDay
          else -> ""
        }
      return TodayInfo(weekDay = normalizedWeekDay, dateText = dateText, weekText = weekText)
    }
    return null
  }

  fun loadScheduleJsonObject(context: Context): JSONObject? {
    val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    val userId = prefs.getString("${FLUTTER_PREFIX}account", null)?.takeIf { it.isNotBlank() } ?: return null

    val term =
      prefs.getString("$KEY_WIDGET_TERM_PREFIX$userId", null)?.takeIf { it.isNotBlank() }
        ?: prefs.getString("$KEY_LAST_TERM_PREFIX$userId", null)?.takeIf { it.isNotBlank() }
        ?: return null
    val week =
      prefs.getString("$KEY_WIDGET_WEEK_PREFIX$userId", null)?.takeIf { it.isNotBlank() }
        ?: prefs.getString("$KEY_LAST_WEEK_PREFIX$userId", null)?.takeIf { it.isNotBlank() }
        ?: return null

    val scheduleKey = "${FLUTTER_PREFIX}schedule_${userId}_${term}_$week"
    val jsonStr = prefs.getString(scheduleKey, null) ?: return null

    return try {
      JSONObject(jsonStr)
    } catch (_: Exception) {
      null
    }
  }

  private fun isSameAsSystemDate(weekDateText: String): Boolean {
    val md = extractMonthDay(weekDateText) ?: return false
    val cal = Calendar.getInstance()
    val sysMonth = cal.get(Calendar.MONTH) + 1
    val sysDay = cal.get(Calendar.DAY_OF_MONTH)
    return md.first == sysMonth && md.second == sysDay
  }

  private fun mondayBasedWeekdayFromWeekDateText(weekDateText: String): Int? {
    val md = extractMonthDay(weekDateText) ?: return null
    val calNow = Calendar.getInstance()
    val nowYear = calNow.get(Calendar.YEAR)
    val nowMonth = calNow.get(Calendar.MONTH) + 1
    val nowDay = calNow.get(Calendar.DAY_OF_MONTH)

    val base = Calendar.getInstance().apply {
      set(Calendar.YEAR, nowYear)
      set(Calendar.MONTH, md.first - 1)
      set(Calendar.DAY_OF_MONTH, md.second)
      set(Calendar.HOUR_OF_DAY, 0)
      set(Calendar.MINUTE, 0)
      set(Calendar.SECOND, 0)
      set(Calendar.MILLISECOND, 0)
    }

    val nowDate = Calendar.getInstance().apply {
      set(Calendar.YEAR, nowYear)
      set(Calendar.MONTH, nowMonth - 1)
      set(Calendar.DAY_OF_MONTH, nowDay)
      set(Calendar.HOUR_OF_DAY, 0)
      set(Calendar.MINUTE, 0)
      set(Calendar.SECOND, 0)
      set(Calendar.MILLISECOND, 0)
    }

    val diffDays = ((base.timeInMillis - nowDate.timeInMillis) / (24L * 60 * 60 * 1000)).toInt()
    if (kotlin.math.abs(diffDays) > 183) {
      val adjustedYear = if (diffDays > 0) nowYear - 1 else nowYear + 1
      base.set(Calendar.YEAR, adjustedYear)
    }

    return toMondayBasedWeekday(base)
  }

  private fun extractMonthDay(raw: String): Pair<Int, Int>? {
    val s = raw.trim()
    if (s.isEmpty()) return null

    val nums = Regex("""\d{1,4}""").findAll(s).map { it.value }.toList()
    if (nums.size < 2) return null

    val month: Int
    val day: Int
    if (nums[0].length == 4 && nums.size >= 3) {
      month = nums[1].toIntOrNull() ?: return null
      day = nums[2].toIntOrNull() ?: return null
    } else {
      month = nums[0].toIntOrNull() ?: return null
      day = nums[1].toIntOrNull() ?: return null
    }

    if (month !in 1..12) return null
    if (day !in 1..31) return null
    return month to day
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
