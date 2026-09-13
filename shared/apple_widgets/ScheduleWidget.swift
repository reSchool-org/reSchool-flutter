import WidgetKit
import SwiftUI

struct ScheduleEntry: TimelineEntry {
    let date: Date
    let data: WidgetScheduleData
    let preferences: WidgetPreferences
}

struct ScheduleProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScheduleEntry {
        ScheduleEntry(date: Date(), data: .empty, preferences: .load())
    }
    func getSnapshot(in context: Context, completion: @escaping (ScheduleEntry) -> Void) {
        completion(ScheduleEntry(date: Date(), data: WidgetStore.read("widget_schedule_data") ?? .empty, preferences: .load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ScheduleEntry>) -> Void) {
        let data: WidgetScheduleData = WidgetStore.read("widget_schedule_data") ?? .empty
        let preferences = WidgetPreferences.load()
        let dates = WidgetDates.timeline()
        completion(Timeline(entries: dates.map { ScheduleEntry(date: $0, data: data, preferences: preferences) }, policy: .after(dates.last!)))
    }
}

struct ScheduleWidgetEntryView: View {
    let entry: ScheduleEntry
    var body: some View {
        let day = entry.data.day(at: entry.date)
        let rows = (day?.lessons ?? []).filter { !$0.isPlaceholder }.map { lesson in
            WidgetRow(title: lesson.subject,
                      detail: entry.preferences.settings.showTeacherInSchedule == false ? "" : lesson.teacher,
                      meta: [lesson.startTime, lesson.endTime].filter { !$0.isEmpty }.joined(separator: " - "),
                      badge: String(lesson.num))
        }
        WidgetCanvas(type: "schedule", title: "Расписание", icon: "calendar",
                     subtitle: day?.date ?? "На сегодня",
                     updated: WidgetDates.updated(entry.data.lastUpdated, at: entry.date),
                     emptyMessage: day == nil ? "Откройте приложение для обновления" : "Сегодня уроков нет",
                     rows: rows, preferences: entry.preferences)
    }
}

struct ScheduleWidget: Widget {
    let kind = "ScheduleWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ScheduleProvider()) { entry in ScheduleWidgetEntryView(entry: entry) }
            .configurationDisplayName("Расписание")
            .description("Уроки на сегодня")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
