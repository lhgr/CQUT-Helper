import AppIntents
import Intents
import WidgetKit

@available(iOS 17.0, *)
struct ToggleScheduleDay: AppIntent {
  static var title: LocalizedStringResource = "切换今天和明天"
  static var openAppWhenRun = false
  @Parameter(title: "小组件样式") var kind: String
  @Parameter(title: "配置日期") var configuredDay: Int
  @Parameter(title: "外观") var configuredTheme: String
  @Parameter(title: "同步提醒天数") var configuredDays: Int

  init() {}
  init(kind: String, options: WidgetOptions) {
    self.kind = kind
    configuredDay = options.dayOffset
    configuredTheme = options.theme
    configuredDays = options.refreshSuggestionDays
  }

  func perform() async throws -> some IntentResult {
    _ = try WidgetSnapshotStore.container()
    let options = WidgetOptions(dayOffset: configuredDay, theme: configuredTheme,
      refreshSuggestionDays: configuredDays)
    WidgetDaySelection.toggle(kind: kind, options: options,
      defaults: UserDefaults(suiteName: WidgetSnapshotStore.groupIdentifier))
    WidgetCenter.shared.reloadTimelines(ofKind: kind)
    return .result()
  }
}

protocol ScheduleWidgetConfiguration {
  var options: WidgetOptions { get }
}

extension WidgetConfigurationIntent: ScheduleWidgetConfiguration {
  var options: WidgetOptions {
    // SiriKit's generated enum values are accessed through their stable raw values.
    let day = (value(forKey: "dayOffset") as? NSNumber)?.intValue ?? 0
    let themeValue = (value(forKey: "theme") as? NSNumber)?.intValue ?? 1
    let days = (value(forKey: "refreshSuggestionDays") as? NSNumber)?.intValue ?? 3
    return WidgetOptions(dayOffset: day == 2 ? 1 : 0, theme: themeValue == 2 ? "light" : themeValue == 3 ? "dark" : "app",
      refreshSuggestionDays: days)
  }
}

extension FixedWidgetConfigurationIntent: ScheduleWidgetConfiguration {
  var options: WidgetOptions {
    let themeValue = (value(forKey: "theme") as? NSNumber)?.intValue ?? 1
    let days = (value(forKey: "refreshSuggestionDays") as? NSNumber)?.intValue ?? 3
    return WidgetOptions(theme: themeValue == 2 ? "light" : themeValue == 3 ? "dark" : "app",
      refreshSuggestionDays: days)
  }
}
