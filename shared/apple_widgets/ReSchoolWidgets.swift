import WidgetKit
import SwiftUI

@main
struct ReSchoolWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ScheduleWidget()
        HomeworkWidget()
        GradesWidget()
    }
}

struct WidgetScheduleDay: Decodable {
    let date: String
    let dateISO: String?
    let lessons: [WidgetLesson]
    var dayStartMs: Double? = nil
    var dayEndMs: Double? = nil
    var schoolEndMs: Double? = nil

    var hasLessons: Bool { lessons.contains { !$0.isPlaceholder } }
    func contains(_ date: Date) -> Bool {
        if let start = dayStartMs, let end = dayEndMs {
            let instant = date.timeIntervalSince1970 * 1000
            return instant >= start && instant < end
        }
        return dateISO == WidgetDates.key(date)
    }
    func schoolEnded(at date: Date) -> Bool {
        guard hasLessons, let end = schoolEndMs else { return false }
        return date.timeIntervalSince1970 * 1000 >= end
    }
}

struct WidgetScheduleData: Decodable {
    let date: String
    let dateISO: String?
    let lessons: [WidgetLesson]
    let lastUpdated: String
    let days: [WidgetScheduleDay]?
    var dayStartMs: Double? = nil
    var dayEndMs: Double? = nil
    var schoolEndMs: Double? = nil

    static let empty = WidgetScheduleData(date: "", dateISO: nil, lessons: [], lastUpdated: "", days: nil)

    var calendarDays: [WidgetScheduleDay] {
        var result = days ?? []
        if let key = dateISO, !result.contains(where: { $0.dateISO == key }) {
            result.append(WidgetScheduleDay(date: date, dateISO: dateISO, lessons: lessons,
                                           dayStartMs: dayStartMs, dayEndMs: dayEndMs, schoolEndMs: schoolEndMs))
        }
        return result.sorted { ($0.dateISO ?? "") < ($1.dateISO ?? "") }
    }

    func currentDay(at date: Date) -> WidgetScheduleDay? {
        calendarDays.first { $0.contains(date) }
    }

    func day(at date: Date) -> WidgetScheduleDay? {
        guard let today = currentDay(at: date) else { return nil }
        if today.hasLessons && !today.schoolEnded(at: date) { return today }
        return calendarDays.first { ($0.dateISO ?? "") > (today.dateISO ?? "") && $0.hasLessons }
    }

}

struct WidgetLesson: Decodable {
    let num: Int
    let subject: String
    let teacher: String
    let startTime: String
    let endTime: String
    let mark: String?
    let isPlaceholder: Bool
}

struct WidgetHomeworkData: Decodable {
    let items: [WidgetHomeworkItem]
    let lastUpdated: String
    static let empty = WidgetHomeworkData(items: [], lastUpdated: "")
}

struct WidgetHomeworkItem: Decodable {
    let subject: String
    let text: String
    let date: String
    let dateISO: String?
    let deadline: String?
    let hasFiles: Bool
}

struct WidgetGradesData: Decodable {
    let periodName: String
    let grades: [WidgetGrade]
    let lastUpdated: String
    static let empty = WidgetGradesData(periodName: "", grades: [], lastUpdated: "")
}

struct WidgetGrade: Decodable {
    let subject: String
    let average: String
    let rating: String?
    let totalMarks: Int?
}

struct WidgetSettings: Decodable {
    var scheduleEnabled: Bool?
    var homeworkEnabled: Bool?
    var gradesEnabled: Bool?
    var homeworkItemsCount: Int?
    var gradesSubjectsCount: Int?
    var showTeacherInSchedule: Bool?
    var showDeadlineInHomework: Bool?

    func enabled(_ type: String) -> Bool {
        switch type {
        case "schedule": return scheduleEnabled != false
        case "homework": return homeworkEnabled != false
        default: return gradesEnabled != false
        }
    }
}

struct WidgetPalette: Decodable {
    let background: UInt64
    let surface: UInt64
    let text: UInt64
    let secondary: UInt64
    let accent: UInt64

    static let light = WidgetPalette(background: 0xFFFBF8FF, surface: 0xFFF0EDF6, text: 0xFF1B1B1F, secondary: 0xFF45464F, accent: 0xFF1D6FEB)
    static let dark = WidgetPalette(background: 0xFF1B1B1F, surface: 0xFF24252B, text: 0xFFE4E2E9, secondary: 0xFFC5C6D0, accent: 0xFFAAC7FF)
}

struct WidgetAppearance: Decodable {
    var mode: String?
    var light: WidgetPalette?
    var dark: WidgetPalette?

    func palette(for system: ColorScheme) -> WidgetPalette {
        let useDark = mode == "dark" || (mode != "light" && system == .dark)
        return useDark ? (dark ?? .dark) : (light ?? .light)
    }
}

struct WidgetPreferences {
    let settings: WidgetSettings
    let appearance: WidgetAppearance
    static func load() -> WidgetPreferences {
        WidgetPreferences(
            settings: WidgetStore.read("widget_config") ?? WidgetSettings(),
            appearance: WidgetStore.read("widget_appearance") ?? WidgetAppearance()
        )
    }
}

/// оба расширения apple читают общие снимки, на macos файл заменяем атомарно до обновления
enum WidgetStore {
    static let appGroup = "group.com.magisky.reschoolbeta"
    static func read<T: Decodable>(_ key: String) -> T? {
        #if os(macOS)
        if let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup),
           let data = try? Data(contentsOf: directory.appendingPathComponent("Library/WidgetData/\(key).json")),
           let value = try? JSONDecoder().decode(T.self, from: data) {
            return value
        }
        #endif
        guard let raw = UserDefaults(suiteName: appGroup)?.string(forKey: key),
              let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

enum WidgetDates {
    static func key(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func timeline(from now: Date = Date(), schedule: WidgetScheduleData? = nil) -> [Date] {
        // будущие записи переключают дни из кеша, даже если приложение закрыто
        let start = Calendar.current.startOfDay(for: now)
        let midnights = (1...8).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
        let horizon = midnights.last ?? now
        let transitions = (schedule?.calendarDays ?? []).flatMap { day in
            [day.dayStartMs, day.schoolEndMs].compactMap { $0 }.map { Date(timeIntervalSince1970: $0 / 1000) }
        }.filter { $0 > now && $0 <= horizon }
        return Array(Set([now] + midnights + transitions)).sorted()
    }

    static func updated(_ raw: String, at date: Date) -> String {
        guard !raw.isEmpty else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        var parsed = formatter.date(from: raw)
        if parsed == nil {
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
            parsed = formatter.date(from: raw)
        }
        guard let value = parsed else { return "" }
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = Calendar.current.isDate(value, inSameDayAs: date) ? "HH:mm" : "d MMM, HH:mm"
        return "Обновлено \(formatter.string(from: value))"
    }
}

extension Color {
    init(widgetARGB: UInt64) {
        self.init(.sRGB, red: Double((widgetARGB >> 16) & 255) / 255,
                  green: Double((widgetARGB >> 8) & 255) / 255,
                  blue: Double(widgetARGB & 255) / 255, opacity: 1)
    }
}

struct WidgetRow {
    let title: String
    let detail: String
    let meta: String
    let badge: String
}

struct WidgetCanvas: View {
    let type: String
    let title: String
    let icon: String
    let subtitle: String
    let updated: String
    let emptyMessage: String
    let rows: [WidgetRow]
    let preferences: WidgetPreferences
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    private var palette: WidgetPalette { preferences.appearance.palette(for: colorScheme) }
    private var enabled: Bool { preferences.settings.enabled(type) }
    private var denseSchedule: Bool { type == "schedule" && family == .systemLarge }
    private var padding: CGFloat {
        if #available(iOS 17.0, macOS 14.0, *) { return 0 }
        return 14
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: denseSchedule ? 6 : 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color(widgetARGB: palette.accent))
                    .accessibilityHidden(true)
                if denseSchedule {
                    Text(title).font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(widgetARGB: palette.text)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(enabled ? subtitle : "Выключен в настройках")
                        .font(.system(size: 10)).foregroundColor(Color(widgetARGB: palette.secondary))
                        .lineLimit(1)
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(widgetARGB: palette.text)).lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text(enabled ? subtitle : "Выключен в настройках")
                            .font(.system(size: 10)).foregroundColor(Color(widgetARGB: palette.secondary))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
            if rows.isEmpty || !enabled {
                Text(enabled ? emptyMessage : "Включите виджет в приложении")
                    .font(.system(size: 12)).foregroundColor(Color(widgetARGB: palette.secondary))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if denseSchedule {
                WidgetScheduleList(rows: rows, palette: palette)
            } else {
                GeometryReader { geometry in
                    let columns = family != .systemSmall && type != "schedule" ? 2 : 1
                    let spacing: CGFloat = type == "grades" ? 4 : 6
                    let preferredHeight: CGFloat = type == "homework" ? 70 : (type == "schedule" ? 52 : 40)
                    let targetHeight: CGFloat = type == "grades" ? 34 : preferredHeight
                    let capacity = max(1, Int((geometry.size.height + spacing) / (targetHeight + spacing))) * columns
                    let overflowHeight: CGFloat = type == "grades" && rows.count > capacity ? 16 : 0
                    let availableHeight = max(0, geometry.size.height - overflowHeight)
                    let lineCount = max(1, Int((availableHeight + spacing) / (targetHeight + spacing)))
                    let count = min(rows.count, lineCount * columns)
                    let visibleLines = (count + columns - 1) / columns
                    let height = max(0, (availableHeight - CGFloat(visibleLines - 1) * spacing) / CGFloat(visibleLines))
                    VStack(alignment: .leading, spacing: spacing) {
                        ForEach(0..<visibleLines, id: \.self) { line in
                            HStack(spacing: spacing) {
                                ForEach(0..<columns, id: \.self) { column in
                                    let index = line * columns + column
                                    if index < count {
                                        WidgetRowView(row: rows[index], palette: palette, compact: height < 64,
                                                      dense: type == "grades" && height < 40)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    } else {
                                        Color.clear.frame(maxWidth: .infinity)
                                    }
                                }
                            }.frame(height: min(height, preferredHeight))
                        }
                        if type == "grades" && count < rows.count {
                            Text("Ещё предметов: \(rows.count - count)")
                                .font(.system(size: 9))
                                .foregroundColor(Color(widgetARGB: palette.secondary))
                                .lineLimit(1)
                                .frame(height: 12)
                        }
                    }
                }
            }
            if enabled && !updated.isEmpty {
                Text(updated).font(.system(size: 9)).foregroundColor(Color(widgetARGB: palette.secondary))
                    .lineLimit(1)
            }
        }
        .padding(padding)
        .widgetURL(URL(string: "reschool://widget/\(type)"))
    }

    var body: some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            content.containerBackground(for: .widget) { Color(widgetARGB: palette.background) }
        } else {
            content.background(Color(widgetARGB: palette.background))
        }
    }
}

/// В большом расписании высоту отдаём урокам, а время ставим рядом с предметом.
private struct WidgetScheduleList: View {
    let rows: [WidgetRow]
    let palette: WidgetPalette

    var body: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 2
            let minimumHeight: CGFloat = 30
            let capacity = max(1, Int((geometry.size.height + spacing) / (minimumHeight + spacing)))
            let overflowHeight: CGFloat = rows.count > capacity ? 14 : 0
            let availableHeight = max(0, geometry.size.height - overflowHeight)
            let count = min(rows.count, max(1, Int((availableHeight + spacing) / (minimumHeight + spacing))))
            let rowHeight = min(40, max(0, (availableHeight - CGFloat(count - 1) * spacing) / CGFloat(count)))
            VStack(alignment: .leading, spacing: spacing) {
                ForEach(0..<count, id: \.self) { index in
                    WidgetScheduleRowView(row: rows[index], palette: palette)
                        .frame(height: rowHeight)
                }
                if count < rows.count {
                    Text("Ещё \(rows.count - count) \(lessonWord(rows.count - count))")
                        .font(.system(size: 9))
                        .foregroundColor(Color(widgetARGB: palette.secondary))
                        .lineLimit(1)
                        .frame(height: 12)
                }
            }
        }
    }

    private func lessonWord(_ count: Int) -> String {
        if (11...14).contains(count % 100) { return "уроков" }
        switch count % 10 {
        case 1: return "урок"
        case 2...4: return "урока"
        default: return "уроков"
        }
    }
}

private struct WidgetScheduleRowView: View {
    let row: WidgetRow
    let palette: WidgetPalette

    var body: some View {
        HStack(spacing: 6) {
            Text(row.badge)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(Color(widgetARGB: palette.accent))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title).font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(widgetARGB: palette.text))
                if !row.detail.isEmpty {
                    Text(row.detail).font(.system(size: 9))
                        .foregroundColor(Color(widgetARGB: palette.secondary))
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.meta).font(.system(size: 9)).monospacedDigit()
                .foregroundColor(Color(widgetARGB: palette.secondary))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            if #available(iOS 16.0, macOS 13.0, *) {
                WidgetRowBackground(color: Color(widgetARGB: palette.surface))
            } else {
                Color(widgetARGB: palette.surface)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .combine)
    }
}

struct WidgetRowView: View {
    let row: WidgetRow
    let palette: WidgetPalette
    let compact: Bool
    var dense: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.system(size: dense ? 11 : 12, weight: .semibold))
                    .foregroundColor(Color(widgetARGB: palette.text)).lineLimit(1)
                if !row.detail.isEmpty {
                    Text(row.detail).font(.system(size: dense ? 9 : 10))
                        .foregroundColor(Color(widgetARGB: palette.secondary)).lineLimit(compact ? 1 : 2)
                }
                if !row.meta.isEmpty {
                    Text(row.meta).font(.system(size: 9))
                        .foregroundColor(Color(widgetARGB: palette.secondary)).lineLimit(1)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if !row.badge.isEmpty {
                Text(row.badge).font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(widgetARGB: palette.accent))
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, dense ? 3 : 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            if #available(iOS 16.0, macOS 13.0, *) {
                WidgetRowBackground(color: Color(widgetARGB: palette.surface))
            } else {
                Color(widgetARGB: palette.surface)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

@available(iOS 16.0, macOS 13.0, *)
private struct WidgetRowBackground: View {
    let color: Color
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        // в тонированном режиме текст и плотный фон становятся белыми
        // делаем прозрачнее только фон, чтобы текст оставался читаемым
        color.opacity(renderingMode == .accented ? 0.12 : 1)
    }
}
