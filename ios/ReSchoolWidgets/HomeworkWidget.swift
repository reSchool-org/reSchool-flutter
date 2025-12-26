import WidgetKit
import SwiftUI

struct HomeworkEntry: TimelineEntry {
    let date: Date
    let homeworkData: WidgetHomeworkData
}

struct HomeworkProvider: TimelineProvider {
    func placeholder(in context: Context) -> HomeworkEntry {
        HomeworkEntry(date: Date(), homeworkData: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (HomeworkEntry) -> ()) {
        let data = WidgetDataProvider.loadHomeworkData()
        completion(HomeworkEntry(date: Date(), homeworkData: data))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HomeworkEntry>) -> ()) {
        let data = WidgetDataProvider.loadHomeworkData()
        let entry = HomeworkEntry(date: Date(), homeworkData: data)

        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct HomeworkWidgetEntryView: View {
    var entry: HomeworkProvider.Entry
    @Environment(\.widgetFamily) var family

    private var itemsToShow: Int {
        switch family {
        case .systemSmall: return 2
        case .systemMedium: return 3
        case .systemLarge: return 6
        default: return 3
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(
                icon: "doc.text.fill",
                title: "Домашние задания",
                subtitle: entry.homeworkData.items.isEmpty ? nil : "\(entry.homeworkData.items.count) заданий"
            )

            if entry.homeworkData.items.isEmpty {
                Spacer()
                EmptyStateView(icon: "checkmark.circle.fill", message: "Нет заданий")
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
                    ForEach(Array(entry.homeworkData.items.prefix(itemsToShow))) { item in
                        HomeworkItemRow(item: item, isCompact: family == .systemSmall)
                    }
                }

                if entry.homeworkData.items.count > itemsToShow {
                    Text("+ ещё \(entry.homeworkData.items.count - itemsToShow)")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.6))
                }

                Spacer(minLength: 0)
            }
        }
        .padding(family == .systemSmall ? 12 : 14)
    }
}

struct HomeworkItemRow: View {
    let item: WidgetHomeworkItem
    let isCompact: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "book.fill")
                .font(.system(size: isCompact ? 10 : 11))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: isCompact ? 14 : 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.subject)
                    .font(.system(size: isCompact ? 11 : 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(item.text)
                    .font(.system(size: isCompact ? 9 : 10))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(isCompact ? 1 : 2)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(item.date)
                    .font(.system(size: isCompact ? 9 : 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))

                if item.hasFiles {
                    Image(systemName: "paperclip")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct HomeworkWidget: Widget {
    let kind: String = "HomeworkWidget"

    private var gradientBackground: some View {
        LinearGradient(
            gradient: Gradient(colors: [Color(hex: "FF512F"), Color(hex: "DD2476")]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HomeworkProvider()) { entry in
            if #available(iOS 17.0, *) {
                HomeworkWidgetEntryView(entry: entry)
                    .containerBackground(for: .widget) {
                        gradientBackground
                    }
            } else {
                ZStack {
                    gradientBackground
                    HomeworkWidgetEntryView(entry: entry)
                }
            }
        }
        .configurationDisplayName("Домашние задания")
        .description("Ближайшие задания")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct HomeworkWidget_Previews: PreviewProvider {
    static var previews: some View {
        let sampleData = WidgetHomeworkData(
            items: [
                WidgetHomeworkItem(subject: "Математика", text: "Решить задачи 15-20 из учебника", date: "20 дек", deadline: "21 дек 08:30", hasFiles: true),
                WidgetHomeworkItem(subject: "Русский язык", text: "Написать сочинение на тему «Зима»", date: "21 дек", deadline: nil, hasFiles: false),
                WidgetHomeworkItem(subject: "Физика", text: "Лабораторная работа №5", date: "22 дек", deadline: "23 дек 14:00", hasFiles: true),
            ],
            lastUpdated: ""
        )

        HomeworkWidgetEntryView(entry: HomeworkEntry(date: Date(), homeworkData: sampleData))
            .previewContext(WidgetPreviewContext(family: .systemMedium))
    }
}