import SwiftUI
import WidgetKit
import Intents

enum ScheduleStyle: String, CaseIterable {
  case tiny = "tiny_course", course = "today_course", list = "today_list"
  case dual = "today_and_next", vertical = "vertical_schedule"
  var title: String {
    switch self {
    case .tiny: return "下一节课"
    case .course: return "今日课程"
    case .list: return "今日列表"
    case .dual: return "今明课表"
    case .vertical: return "纵向课表"
    }
  }
  var families: [WidgetFamily] {
    switch self {
    case .tiny: return [.systemSmall]
    case .vertical: return [.systemLarge]
    default: return [.systemMedium, .systemLarge]
    }
  }
  var canToggle: Bool { self == .course || self == .list || self == .vertical }
}

struct ScheduleEntry: TimelineEntry {
  let date: Date
  let snapshot: WidgetSnapshot?
  let error: String?
  let options: WidgetOptions
  let dayOffset: Int
}

enum ScheduleTimeline {
  static func entry(date: Date, options: WidgetOptions, style: ScheduleStyle) -> ScheduleEntry {
    let snapshot: WidgetSnapshot?
    let error: String?
    do {
      snapshot = try WidgetSnapshotStore.load()
      error = nil
    } catch let failure {
      snapshot = nil
      error = (failure as? SnapshotError)?.localizedDescription ?? "课表数据无法读取，请打开应用同步"
    }
    return makeEntry(date: date, snapshot: snapshot, error: error, options: options, style: style)
  }
  static func makeEntry(date: Date, snapshot: WidgetSnapshot?, error: String?,
    options: WidgetOptions, style: ScheduleStyle) -> ScheduleEntry {
    var offset = style.canToggle ? options.dayOffset : 0
    if #available(iOS 17.0, *), style.canToggle {
      offset = WidgetDaySelection.effectiveOffset(kind: style.rawValue, options: options,
        defaults: UserDefaults(suiteName: WidgetSnapshotStore.groupIdentifier))
    }
    return ScheduleEntry(date: date, snapshot: snapshot, error: error, options: options, dayOffset: offset)
  }
  static func timeline(options: WidgetOptions, style: ScheduleStyle) -> Timeline<ScheduleEntry> {
    let first = entry(date: Date(), options: options, style: style)
    let dates = WidgetClock.timelineDates(snapshot: first.snapshot, now: first.date,
      suggestionDays: options.refreshSuggestionDays)
    let entries = dates.map {
      makeEntry(date: $0, snapshot: first.snapshot, error: first.error, options: options, style: style)
    }
    return Timeline(entries: entries, policy: .after(dates.last!))
  }
  static func placeholder() -> ScheduleEntry {
    // Only gallery/placeholder previews use samples. Live snapshots and timelines read the store.
    let today = WidgetClock.dateKey(Date())
    let json = """
    {"schemaVersion":1,"generatedAt":0,"activeUserId":"preview","yearTerm":"","pinnedWeek":1,
    "calendarProjection":{"schema_version":1,"days":[{"date":"\(today)","kind":"normal","source_week_num":"1",
    "events":[{"eventName":"高等数学","eventID":"preview","address":"两江校区 · 第三教学楼301","memberName":"张老师",
    "sessionStart":"1","sessionLast":"2","colorIndex":0},{"eventName":"大学英语","address":"两江校区 · 第五教学楼202",
    "memberName":"李老师","sessionStart":"3","sessionLast":"2","colorIndex":1}]}]},
    "sessionClocks":[],"courseColorMap":{},"themeMode":"system","refresh":{"state":"normal","lastSuccessfulAt":null,"failure":null}}
    """
    return ScheduleEntry(date: Date(), snapshot: try? WidgetSnapshot.decode(Data(json.utf8)),
      error: nil, options: WidgetOptions(), dayOffset: 0)
  }
}

struct LegacyScheduleProvider<Configuration: INIntent & ScheduleWidgetConfiguration>: IntentTimelineProvider {
  let style: ScheduleStyle
  func placeholder(in context: Context) -> ScheduleEntry { ScheduleTimeline.placeholder() }
  func getSnapshot(for configuration: Configuration, in context: Context,
    completion: @escaping (ScheduleEntry) -> Void) {
    completion(context.isPreview ? ScheduleTimeline.placeholder()
      : ScheduleTimeline.entry(date: Date(), options: configuration.options, style: style))
  }
  func getTimeline(for configuration: Configuration, in context: Context,
    completion: @escaping (Timeline<ScheduleEntry>) -> Void) {
    completion(ScheduleTimeline.timeline(options: configuration.options, style: style))
  }
}

struct CourseScheduleWidget: Widget {
  let style: ScheduleStyle

  init() { self.init(style: .course) }
  init(style: ScheduleStyle) { self.style = style }

  var body: some WidgetConfiguration {
    IntentConfiguration(kind: style.rawValue, intent: WidgetConfigurationIntent.self,
      provider: LegacyScheduleProvider<WidgetConfigurationIntent>(style: style)) { entry in
        ScheduleWidgetView(entry: entry, style: style)
      }
      .configurationDisplayName(style.title)
      .description("查看课程、地点和上课时间，打开应用同步课表。")
      .supportedFamilies(style.families)
  }
}

struct FixedCourseScheduleWidget: Widget {
  let style: ScheduleStyle

  init() { self.init(style: .tiny) }
  init(style: ScheduleStyle) { self.style = style }

  var body: some WidgetConfiguration {
    IntentConfiguration(kind: style.rawValue, intent: FixedWidgetConfigurationIntent.self,
      provider: LegacyScheduleProvider<FixedWidgetConfigurationIntent>(style: style)) { entry in
        ScheduleWidgetView(entry: entry, style: style)
      }
      .configurationDisplayName(style.title)
      .description("查看课程、地点和上课时间，打开应用同步课表。")
      .supportedFamilies(style.families)
  }
}

@main
struct CQUTWidgetsBundle: WidgetBundle {
  var body: some Widget {
    FixedCourseScheduleWidget(style: .tiny)
    CourseScheduleWidget(style: .course)
    CourseScheduleWidget(style: .list)
    FixedCourseScheduleWidget(style: .dual)
    CourseScheduleWidget(style: .vertical)
  }
}

private struct ScheduleWidgetView: View {
  let entry: ScheduleEntry
  let style: ScheduleStyle
  var body: some View {
    if #available(iOS 16.0, *) {
      RenderingAwareScheduleView(entry: entry, style: style)
    } else {
      ScheduleWidgetContent(entry: entry, style: style, tinted: false)
    }
  }
}

@available(iOS 16.0, *)
private struct RenderingAwareScheduleView: View {
  let entry: ScheduleEntry
  let style: ScheduleStyle
  @Environment(\.widgetRenderingMode) private var renderingMode
  var body: some View {
    ScheduleWidgetContent(entry: entry, style: style, tinted: renderingMode != .fullColor)
  }
}

private struct ScheduleWidgetContent: View {
  let entry: ScheduleEntry
  let style: ScheduleStyle
  let tinted: Bool
  @Environment(\.widgetFamily) private var family
  @Environment(\.colorScheme) private var systemScheme

  private var dark: Bool {
    let theme = entry.options.theme == "app" ? (entry.snapshot?.themeMode ?? "system") : entry.options.theme
    return theme == "dark" || (theme == "system" && systemScheme == .dark)
  }
  private var background: Color { tinted ? .clear : Color(hex: dark ? 0x232A35 : 0xFFFFFF) }
  private var primary: Color { tinted ? .primary : Color(hex: dark ? 0xF4F6FA : 0x172238) }
  private var secondary: Color { tinted ? .secondary : Color(hex: dark ? 0xB7C1D0 : 0x5D6B82) }
  private var targetDate: Date { WidgetClock.day(entry.date, offset: entry.dayOffset) }
  private var presentation: WidgetPresentation {
    entry.snapshot?.presentation(now: entry.date, suggestionDays: entry.options.refreshSuggestionDays)
      ?? WidgetPresentation(state: "error", text: entry.error ?? "请打开应用同步课表")
  }

  var body: some View {
    content
      .padding(contentPadding)
      .foregroundColor(primary)
      .environment(\.colorScheme, dark ? .dark : .light)
      .widgetURL(link(date: targetDate, course: tinyCourse,
        action: tinyCourse != nil || presentation.state == "normal" ? "open" : "sync"))
      .modifier(WidgetSurface(color: background))
  }

  private var contentPadding: CGFloat {
    if #available(iOS 17.0, *) { return 0 }
    return style == .tiny ? 12 : 13
  }

  private var tinyCourse: WidgetCourse? {
    style == .tiny ? entry.snapshot?.courses(on: targetDate, now: entry.date).first : nil
  }

  @ViewBuilder private var content: some View {
    if style == .tiny {
      tiny
    } else {
      VStack(alignment: .leading, spacing: 8) {
        header
        if family != .systemMedium && !presentation.text.isEmpty {
          Text(presentation.text).font(.system(size: 10)).foregroundColor(secondary).lineLimit(2)
        }
        if presentation.state == "login" || entry.snapshot == nil {
          empty(presentation.text)
        } else if style == .dual {
          HStack(alignment: .top, spacing: 10) {
            dayColumn(offset: 0)
            Rectangle().fill(Color(hex: dark ? 0x3A4658 : 0xDCE3ED)).frame(width: 1)
            dayColumn(offset: 1)
          }
        } else {
          dayContent(date: targetDate)
        }
      }
    }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 8) {
      VStack(alignment: .leading, spacing: 3) {
        Text(style == .list || style == .dual ? "课表" : WidgetClock.format(targetDate, "M月d日"))
          .font(.system(size: style == .list || style == .dual ? 15 : 18, weight: .bold))
        if family == .systemMedium && !presentation.text.isEmpty {
          Text(presentation.text).font(.system(size: 10)).foregroundColor(secondary).lineLimit(1)
        } else {
          HStack(spacing: 5) {
            Text(style == .list || style == .dual ? WidgetClock.format(targetDate, "M.d") : "课表").fontWeight(.bold)
            if let week = entry.snapshot?.day(targetDate)?.sourceWeek, !week.isEmpty {
              Text("| 第\(week)周")
            }
            Text(dayMetadata(targetDate)).foregroundColor(tinted ? primary : Color(hex: dark ? 0xA8BCFF : 0x3856A6))
          }
          .font(.system(size: 10)).lineLimit(1)
        }
      }
      Spacer(minLength: 0)
      if #available(iOS 17.0, *), style.canToggle {
        Button(intent: ToggleScheduleDay(kind: style.rawValue, options: entry.options)) {
          Image(systemName: entry.dayOffset == 0 ? "chevron.right" : "chevron.left")
            .font(.system(size: 13, weight: .bold)).frame(width: 28, height: 30)
        }.buttonStyle(.plain).accessibilityLabel(entry.dayOffset == 0 ? "查看明天" : "查看今天")
      }
      Link(destination: link(date: targetDate, action: "sync")) {
        Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .semibold))
          .frame(width: 26, height: 30)
      }.accessibilityLabel("打开应用同步课表")
    }
  }

  private func dayMetadata(_ date: Date) -> String {
    let weekday = WidgetClock.format(date, "EEE")
    guard let day = entry.snapshot?.day(date) else { return weekday }
    if day.kind == "holiday" { return (day.label ?? "").isEmpty ? "休" : "休 · \(day.label!)" }
    if day.kind == "teaching_day" {
      let source = day.sourceDate.flatMap(WidgetClock.parseDate) ?? date
      return "调·\(WidgetClock.format(source, "EEE"))"
    }
    return weekday
  }

  private func dayColumn(offset: Int) -> some View {
    let date = WidgetClock.day(entry.date, offset: offset)
    return VStack(alignment: .leading, spacing: 6) {
      Text(offset == 0 ? "今天" : "明天").font(.system(size: 12, weight: .bold))
      dayContent(date: date)
    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func dayContent(date: Date) -> some View {
    GeometryReader { geometry in
      let courses = entry.snapshot?.courses(on: date, now: entry.date) ?? []
      let compact = family == .systemMedium
      let cardHeight: CGFloat = compact ? 42 : style == .vertical ? 68 : 64
      let capacity = WidgetCourseLayout.capacity(contentHeight: Double(geometry.size.height),
        rowHeight: Double(cardHeight), courseCount: courses.count)
      VStack(alignment: .leading, spacing: 6) {
        if courses.isEmpty {
          empty(entry.snapshot?.emptyText(on: date, now: entry.date) ?? presentation.text)
        } else {
          ForEach(Array(courses.prefix(capacity).enumerated()), id: \.offset) { _, course in
            Link(destination: link(date: date, course: course)) {
              courseCard(course, compact: compact, vertical: style == .vertical)
                .frame(height: cardHeight)
            }
          }
          if courses.count > capacity {
            Link(destination: link(date: date)) {
              Text("还有\(courses.count - capacity)节")
                .font(.system(size: 11, weight: .medium)).foregroundColor(secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
        }
      }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  private func empty(_ text: String) -> some View {
    Text(text).font(.system(size: 12)).foregroundColor(secondary)
      .multilineTextAlignment(.center).frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var tiny: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("下一节课").font(.system(size: 11, weight: .medium)).foregroundColor(secondary)
      if presentation.state == "login" || entry.snapshot == nil {
        Text(presentation.text).font(.system(size: 13, weight: .semibold)).lineLimit(3)
      } else if let course = tinyCourse {
        let palette = CoursePalette.colors(course.colorIndex, dark: dark)
        let count = entry.snapshot?.courses(on: targetDate, now: entry.date).count ?? 1
        HStack(spacing: 8) {
          RoundedRectangle(cornerRadius: 2).fill(tinted ? primary : palette.accent).frame(width: 4)
          VStack(alignment: .leading, spacing: 4) {
            Text(course.event.name).font(.system(size: 16, weight: .bold)).lineLimit(1)
            Text(course.startTime.isEmpty ? course.event.periods : "\(course.startTime)–\(course.endTime)")
              .font(.system(size: 11)).lineLimit(1)
            Text(course.event.location).font(.system(size: 10)).foregroundColor(secondary).lineLimit(1)
            Text(count == 1 ? "今日最后一节" : "后续\(count - 1)节")
              .font(.system(size: 9)).foregroundColor(secondary).lineLimit(1)
          }
        }
      } else {
        Text(entry.snapshot?.emptyText(on: targetDate, now: entry.date) ?? presentation.text)
          .font(.system(size: 13, weight: .semibold)).lineLimit(3)
      }
      Spacer(minLength: 0)
      if !presentation.text.isEmpty && presentation.state != "login" && entry.snapshot != nil {
        Text(presentation.text).font(.system(size: 9)).foregroundColor(secondary).lineLimit(1)
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func courseCard(_ course: WidgetCourse, compact: Bool, vertical: Bool) -> some View {
    let palette = CoursePalette.colors(course.colorIndex, dark: dark)
    return HStack(spacing: 7) {
      RoundedRectangle(cornerRadius: 2).fill(tinted ? primary : palette.accent).frame(width: 3)
      if vertical {
        VStack(spacing: 4) {
          Text(course.startTime.isEmpty ? "—" : course.startTime).font(.system(size: 12, weight: .bold))
          Text(course.endTime.isEmpty ? "—" : course.endTime).font(.system(size: 11)).foregroundColor(secondary)
        }.frame(width: 43)
        Rectangle().fill(Color(hex: dark ? 0x3A4658 : 0xDCE3ED)).frame(width: 1)
      }
      VStack(alignment: .leading, spacing: 3) {
        Text(course.event.name).font(.system(size: compact ? 12 : 13, weight: .bold)).lineLimit(compact ? 1 : 2)
        if compact {
          Text([course.startTime.isEmpty ? course.event.periods : course.startTime, course.event.location]
            .filter { !$0.isEmpty }.joined(separator: " · "))
            .font(.system(size: 9)).foregroundColor(secondary).lineLimit(1)
        } else {
          Text(course.event.location).font(.system(size: 10)).foregroundColor(secondary).lineLimit(1)
          Text([course.event.periods, course.event.memberName ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
            .font(.system(size: 9)).foregroundColor(secondary).lineLimit(1)
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
    }.padding(.horizontal, 8).padding(.vertical, compact ? 5 : 7)
      .background(RoundedRectangle(cornerRadius: 10).fill(tinted ? Color.primary.opacity(0.10) : palette.background))
      .contentShape(Rectangle())
  }

  private func link(date: Date, course: WidgetCourse? = nil, action: String = "open") -> URL {
    var components = URLComponents()
    components.scheme = "cqut"
    components.host = "widget"
    components.queryItems = [URLQueryItem(name: "date", value: WidgetClock.dateKey(date)),
      URLQueryItem(name: "action", value: action)]
    if let course = course {
      components.queryItems?.append(URLQueryItem(name: "eventId", value: course.event.eventID))
      components.queryItems?.append(URLQueryItem(name: "eventName", value: course.event.name))
    }
    return components.url!
  }
}

private struct WidgetSurface: ViewModifier {
  let color: Color
  @ViewBuilder func body(content: Content) -> some View {
    if #available(iOS 17.0, *) { content.containerBackground(color, for: .widget) }
    else { content.background(color) }
  }
}

private enum CoursePalette {
  private static let backgrounds: [UInt32] = [
    0xE6F4FF, 0xFDEBDD, 0xDEFBF7, 0xEEEDFF, 0xFCEBCD, 0xFFEFF0, 0xFFEEF8,
    0xE2F9F3, 0xFFF9C9, 0xFAEDFF, 0xF4F2FD, 0xE6E6FF, 0xEEFDDD, 0xEADEFB,
    0xFFEFED, 0xCDF2FC, 0xEFFFFF, 0xEEFFFF, 0xF9F5E2, 0xEDF0FF, 0xF2F4FD
  ]
  private static let accents: [UInt32] = [
    0x1473A3, 0xAC3E15, 0x0F7B78, 0x621EA4, 0x915D12, 0xAC1522, 0xAC152C,
    0x0F7A7B, 0x846C10, 0x781CA6, 0x3215AC, 0x1426A3, 0x80AC15, 0x480F7B,
    0xA4671E, 0x127B91, 0x15ACA8, 0x1568AC, 0x717B0F, 0x1C3CA6, 0x152EAC
  ]
  static func colors(_ index: Int, dark: Bool) -> (background: Color, accent: Color) {
    let safe = (index % backgrounds.count + backgrounds.count) % backgrounds.count
    return (Color(hex: dark ? recolor(backgrounds[safe], saturation: 0.42, lightness: 0.20) : backgrounds[safe]),
      Color(hex: dark ? recolor(accents[safe], saturation: 0.58, lightness: 0.80) : accents[safe]))
  }
  private static func recolor(_ color: UInt32, saturation: Double, lightness: Double) -> UInt32 {
    let r = Double((color >> 16) & 255) / 255
    let g = Double((color >> 8) & 255) / 255
    let b = Double(color & 255) / 255
    let maximum = max(r, g, b), minimum = min(r, g, b), delta = maximum - minimum
    var hue: Double = 0
    if delta != 0 {
      if maximum == r { hue = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
      else if maximum == g { hue = 60 * ((b - r) / delta + 2) }
      else { hue = 60 * ((r - g) / delta + 4) }
    }
    if hue < 0 { hue += 360 }
    let chroma = (1 - abs(2 * lightness - 1)) * saturation
    let secondary = chroma * (1 - abs((hue / 60).truncatingRemainder(dividingBy: 2) - 1))
    let match = lightness - chroma / 2
    let rgb: (Double, Double, Double)
    switch hue {
    case ..<60: rgb = (chroma, secondary, 0)
    case ..<120: rgb = (secondary, chroma, 0)
    case ..<180: rgb = (0, chroma, secondary)
    case ..<240: rgb = (0, secondary, chroma)
    case ..<300: rgb = (secondary, 0, chroma)
    default: rgb = (chroma, 0, secondary)
    }
    func channel(_ value: Double) -> UInt32 { UInt32(min(255, max(0, ((value + match) * 255).rounded()))) }
    return channel(rgb.0) << 16 | channel(rgb.1) << 8 | channel(rgb.2)
  }
}

private extension Color {
  init(hex: UInt32) {
    self.init(.sRGB, red: Double((hex >> 16) & 255) / 255,
      green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
  }
}
