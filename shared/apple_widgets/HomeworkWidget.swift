import WidgetKit
import SwiftUI

struct HomeworkEntry: TimelineEntry {
    let date: Date
    let data: WidgetHomeworkData
    let schedule: WidgetScheduleData
    let preferences: WidgetPreferences
}

struct HomeworkProvider: TimelineProvider {
    func placeholder(in context: Context) -> HomeworkEntry {
        HomeworkEntry(date: Date(), data: .empty, schedule: .empty, preferences: .load())
    }
    func getSnapshot(in context: Context, completion: @escaping (HomeworkEntry) -> Void) {
        completion(HomeworkEntry(date: Date(), data: WidgetStore.read("widget_homework_data") ?? .empty,
                                 schedule: WidgetStore.read("widget_schedule_data") ?? .empty, preferences: .load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<HomeworkEntry>) -> Void) {
        let data: WidgetHomeworkData = WidgetStore.read("widget_homework_data") ?? .empty
        let schedule: WidgetScheduleData = WidgetStore.read("widget_schedule_data") ?? .empty
        let preferences = WidgetPreferences.load()
        let dates = WidgetDates.timeline(schedule: schedule)
        completion(Timeline(entries: dates.map { HomeworkEntry(date: $0, data: data, schedule: schedule, preferences: preferences) }, policy: .after(dates.last!)))
    }
}

struct HomeworkWidgetEntryView: View {
    let entry: HomeworkEntry
    var body: some View {
        let settings = entry.preferences.settings
        let schoolDay = entry.schedule.currentDay(at: entry.date)
        let today = schoolDay?.dateISO ?? WidgetDates.key(entry.date)
        let schoolEnded = schoolDay?.schoolEnded(at: entry.date) ?? false
        let rows = entry.data.items.filter {
            let key = $0.dateISO ?? ""
            return schoolEnded ? key > today : key >= today
        }
            .prefix(max(1, min(20, settings.homeworkItemsCount ?? 5))).map { item in
                WidgetRow(title: item.subject,
                          detail: item.text.isEmpty ? (item.hasFiles ? "Задание во вложении" : "Без описания") : item.text,
                          meta: [item.date,
                                 settings.showDeadlineInHomework == false ? "" : item.deadline.map { "До \($0)" } ?? "",
                                 item.hasFiles ? "Есть файлы" : ""].filter { !$0.isEmpty }.joined(separator: " · "),
                          badge: "")
            }
        WidgetCanvas(type: "homework", title: "Домашние задания", icon: "book",
                     subtitle: "Ближайшие задания",
                     updated: WidgetDates.updated(entry.data.lastUpdated, at: entry.date),
                     emptyMessage: entry.data.lastUpdated.isEmpty ? "Откройте приложение для обновления" : "Ближайших заданий нет",
                     rows: rows, preferences: entry.preferences)
    }
}

struct HomeworkWidget: Widget {
    let kind = "HomeworkWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HomeworkProvider()) { entry in HomeworkWidgetEntryView(entry: entry) }
            .configurationDisplayName("Домашние задания")
            .description("Ближайшие задания и сроки сдачи")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
