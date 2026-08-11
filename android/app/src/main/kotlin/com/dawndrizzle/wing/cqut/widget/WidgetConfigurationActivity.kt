package com.dawndrizzle.wing.cqut.widget

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.TextView

class WidgetConfigurationActivity : Activity() {
  private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID
  private lateinit var themeGroup: RadioGroup
  private lateinit var dayGroup: RadioGroup
  private lateinit var refreshSuggestionGroup: RadioGroup
  private lateinit var customRefreshDaysInput: EditText
  private var existingConfig = WidgetInstanceConfig()
  private var supportsDaySelection = false
  private var supportsRefreshSuggestion = false

  private val followAppId = View.generateViewId()
  private val lightId = View.generateViewId()
  private val darkId = View.generateViewId()
  private val todayId = View.generateViewId()
  private val tomorrowId = View.generateViewId()
  private val refreshDailyId = View.generateViewId()
  private val refreshThreeDaysId = View.generateViewId()
  private val refreshWeeklyId = View.generateViewId()
  private val refreshCustomId = View.generateViewId()

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    setResult(RESULT_CANCELED)

    appWidgetId =
      intent?.getIntExtra(
        AppWidgetManager.EXTRA_APPWIDGET_ID,
        AppWidgetManager.INVALID_APPWIDGET_ID,
      ) ?: AppWidgetManager.INVALID_APPWIDGET_ID
    if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
      finish()
      return
    }

    val manager = AppWidgetManager.getInstance(this)
    val provider = manager.getAppWidgetInfo(appWidgetId)?.provider
    val providerName = provider?.className.orEmpty()
    if (provider?.packageName != packageName || !isKnownProvider(providerName)) {
      finish()
      return
    }
    supportsDaySelection =
      providerName == TodayListWidgetProvider::class.java.name ||
      providerName == TodayCourseWidgetProvider::class.java.name
    supportsRefreshSuggestion = providerName == TodayCourseWidgetProvider::class.java.name
    existingConfig = WidgetInstanceConfigStore.load(this, appWidgetId)
    setContentView(buildContent(existingConfig, providerName))
  }

  private fun isKnownProvider(providerName: String): Boolean {
    return providerName == TodayListWidgetProvider::class.java.name ||
      providerName == TodayAndNextWidgetProvider::class.java.name ||
      providerName == TodayCourseWidgetProvider::class.java.name
  }

  private fun buildContent(
    existing: WidgetInstanceConfig,
    providerName: String,
  ): View {
    val density = resources.displayMetrics.density
    fun dp(value: Int): Int = (value * density).toInt()

    val content =
      LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(24), dp(24), dp(24), dp(20))
      }

    content.addView(
      TextView(this).apply {
        text = "桌面小组件设置"
        textSize = 24f
        setTypeface(typeface, android.graphics.Typeface.BOLD)
      },
    )
    content.addView(
      TextView(this).apply {
        text = widgetDescription(providerName)
        textSize = 14f
        alpha = 0.72f
        setPadding(0, dp(6), 0, dp(22))
      },
    )

    content.addView(sectionTitle("外观"))
    themeGroup =
      RadioGroup(this).apply {
        orientation = RadioGroup.VERTICAL
        addView(option(followAppId, "跟随应用"))
        addView(option(lightId, "始终浅色"))
        addView(option(darkId, "始终深色"))
        check(
          when (existing.theme) {
            WidgetInstanceTheme.FOLLOW_APP -> followAppId
            WidgetInstanceTheme.LIGHT -> lightId
            WidgetInstanceTheme.DARK -> darkId
          },
        )
      }
    content.addView(themeGroup)

    dayGroup = RadioGroup(this)
    if (supportsDaySelection) {
      content.addView(
        sectionTitle("默认显示").apply {
          setPadding(0, dp(22), 0, dp(4))
        },
      )
      dayGroup.apply {
        orientation = RadioGroup.VERTICAL
        addView(option(todayId, "今天"))
        addView(option(tomorrowId, "明天"))
        check(if (existing.dayOffset == 1) tomorrowId else todayId)
      }
      content.addView(dayGroup)
    }

    refreshSuggestionGroup = RadioGroup(this)
    customRefreshDaysInput = EditText(this)
    if (supportsRefreshSuggestion) {
      content.addView(
        sectionTitle("更新提示间隔").apply {
          setPadding(0, dp(22), 0, dp(4))
        },
      )
      content.addView(
        TextView(this).apply {
          text = "超过该天数未同步时，日视图会提示刷新。"
          textSize = 13f
          alpha = 0.66f
          setPadding(0, 0, 0, dp(4))
        },
      )
      refreshSuggestionGroup.apply {
        orientation = RadioGroup.VERTICAL
        addView(option(refreshDailyId, "1 天"))
        addView(option(refreshThreeDaysId, "3 天（推荐）"))
        addView(option(refreshWeeklyId, "7 天"))
        addView(option(refreshCustomId, "自定义"))
      }
      content.addView(refreshSuggestionGroup)
      customRefreshDaysInput.apply {
        hint = "输入天数"
        inputType = android.text.InputType.TYPE_CLASS_NUMBER
        setSingleLine(true)
        setPadding(dp(16), 0, dp(16), 0)
        setOnFocusChangeListener { _, hasFocus ->
          if (hasFocus) refreshSuggestionGroup.check(refreshCustomId)
        }
        setOnClickListener { refreshSuggestionGroup.check(refreshCustomId) }
      }
      content.addView(
        customRefreshDaysInput,
        LinearLayout.LayoutParams(
          LinearLayout.LayoutParams.MATCH_PARENT,
          dp(48),
        ),
      )

      val selectedRefreshId =
        when (existing.refreshSuggestionDays) {
          1 -> refreshDailyId
          3 -> refreshThreeDaysId
          7 -> refreshWeeklyId
          else -> refreshCustomId
        }
      if (selectedRefreshId == refreshCustomId) {
        customRefreshDaysInput.setText(existing.refreshSuggestionDays.toString())
      }
      refreshSuggestionGroup.check(selectedRefreshId)
    }

    content.addView(
      TextView(this).apply {
        text = "每个小组件实例都会单独保存这些设置，长按桌面组件可再次配置。"
        textSize = 13f
        alpha = 0.66f
        setPadding(0, dp(22), 0, dp(18))
      },
    )

    val actions =
      LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.END
      }
    actions.addView(
      Button(this).apply {
        text = "取消"
        setOnClickListener { finish() }
      },
    )
    actions.addView(
      Button(this).apply {
        text =
          if (WidgetInstanceConfigStore.isConfigured(this@WidgetConfigurationActivity, appWidgetId)) {
            "保存"
          } else {
            "添加"
          }
        setOnClickListener { saveAndFinish(providerName) }
      },
    )
    content.addView(actions)

    return ScrollView(this).apply { addView(content) }
  }

  private fun sectionTitle(textValue: String): TextView {
    return TextView(this).apply {
      text = textValue
      textSize = 16f
      setTypeface(typeface, android.graphics.Typeface.BOLD)
    }
  }

  private fun option(
    idValue: Int,
    textValue: String,
  ): RadioButton {
    return RadioButton(this).apply {
      id = idValue
      text = textValue
      textSize = 16f
      minHeight = (48 * resources.displayMetrics.density).toInt()
    }
  }

  private fun widgetDescription(providerName: String): String {
    return when (providerName) {
      TodayListWidgetProvider::class.java.name -> "单日课程：以列表展示今天或明天的全部课程"
      TodayAndNextWidgetProvider::class.java.name -> "近日课程：同时展示今天和明天"
      TodayCourseWidgetProvider::class.java.name -> "日视图：可在今天和明天之间快速切换"
      else -> "为这个小组件选择独立外观和显示内容"
    }
  }

  private fun saveAndFinish(providerName: String) {
    val theme =
      when (themeGroup.checkedRadioButtonId) {
        lightId -> WidgetInstanceTheme.LIGHT
        darkId -> WidgetInstanceTheme.DARK
        else -> WidgetInstanceTheme.FOLLOW_APP
      }
    val dayOffset =
      if (supportsDaySelection && dayGroup.checkedRadioButtonId == tomorrowId) {
        1
      } else {
        0
      }
    val refreshSuggestionDays = selectedRefreshSuggestionDays() ?: return
    WidgetInstanceConfigStore.save(
      this,
      appWidgetId,
      WidgetInstanceConfig(
        theme = theme,
        dayOffset = dayOffset,
        refreshSuggestionDays = refreshSuggestionDays,
      ),
    )

    when (providerName) {
      TodayListWidgetProvider::class.java.name ->
        TodayListWidgetProvider.updateOne(this, appWidgetId)
      TodayAndNextWidgetProvider::class.java.name ->
        TodayAndNextWidgetProvider.updateOne(this, appWidgetId)
      TodayCourseWidgetProvider::class.java.name ->
        TodayCourseWidgetProvider.updateOne(this, appWidgetId)
    }
    WidgetAutoRefreshScheduler.schedule(this)

    setResult(
      RESULT_OK,
      Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId),
    )
    finish()
  }

  private fun selectedRefreshSuggestionDays(): Int? {
    if (!supportsRefreshSuggestion) return existingConfig.refreshSuggestionDays
    return when (refreshSuggestionGroup.checkedRadioButtonId) {
      refreshDailyId -> 1
      refreshThreeDaysId -> 3
      refreshWeeklyId -> 7
      else -> {
        val customDays = customRefreshDaysInput.text.toString().trim().toIntOrNull()
        if (customDays == null || customDays <= 0) {
          customRefreshDaysInput.error = "请输入大于 0 的整数天数"
          customRefreshDaysInput.requestFocus()
          null
        } else {
          customDays
        }
      }
    }
  }
}
