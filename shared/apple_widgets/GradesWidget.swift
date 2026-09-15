import WidgetKit
import SwiftUI

struct GradesEntry: TimelineEntry {
    let date: Date
    let data: WidgetGradesData
    let preferences: WidgetPreferences
}

struct GradesProvider: TimelineProvider {
    func placeholder(in context: Context) -> GradesEntry {
        GradesEntry(date: Date(), data: .empty, preferences: .load())
    }
    func getSnapshot(in context: Context, completion: @escaping (GradesEntry) -> Void) {
        completion(GradesEntry(date: Date(), data: WidgetStore.read("widget_grades_data") ?? .empty, preferences: .load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<GradesEntry>) -> Void) {
        let data: WidgetGradesData = WidgetStore.read("widget_grades_data") ?? .empty
        let preferences = WidgetPreferences.load()
        let dates = WidgetDates.timeline()
        completion(Timeline(entries: dates.map { GradesEntry(date: $0, data: data, preferences: preferences) }, policy: .after(dates.last!)))
    }
}

struct GradesWidgetEntryView: View {
    let entry: GradesEntry
    var body: some View {
        // вместимость определяет размер виджета, а не сохранённый лимит в 6 предметов.
        let rows = entry.data.grades.map { grade in
            WidgetRow(title: grade.subject, detail: grade.rating ?? "", meta: "", badge: grade.average.isEmpty ? "-" : grade.average)
        }
        WidgetCanvas(type: "grades", title: "Оценки", icon: "chart.bar",
                     subtitle: entry.data.periodName,
                     updated: WidgetDates.updated(entry.data.lastUpdated, at: entry.date),
                     emptyMessage: entry.data.lastUpdated.isEmpty ? "Откройте приложение для обновления" : "Пока нет оценок",
                     rows: rows, preferences: entry.preferences)
    }
}

struct GradesWidget: Widget {
    let kind = "GradesWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GradesProvider()) { entry in GradesWidgetEntryView(entry: entry) }
            .configurationDisplayName("Оценки")
            .description("Средние баллы по предметам")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
