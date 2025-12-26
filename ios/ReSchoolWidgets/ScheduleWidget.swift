import WidgetKit
import SwiftUI

struct ScheduleEntry: TimelineEntry {
    let date: Date
    let scheduleData: WidgetScheduleData
}

struct ScheduleProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScheduleEntry {
        ScheduleEntry(date: Date(), scheduleData: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (ScheduleEntry) -> ()) {
        let data = WidgetDataProvider.loadScheduleData()
        completion(ScheduleEntry(date: Date(), scheduleData: data))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScheduleEntry>) -> ()) {
        let data = WidgetDataProvider.loadScheduleData()
        let entry = ScheduleEntry(date: Date(), scheduleData: data)

        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct ScheduleWidgetEntryView: View {
    var entry: ScheduleProvider.Entry
    @Environment(\.widgetFamily) var family

    private var lessonsToShow: Int {
        switch family {
        case .systemSmall: return 3
        case .systemMedium: return 4
        case .systemLarge: return 8
        default: return 4
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(
                icon: "calendar",
                title: "Расписание",
                subtitle: entry.scheduleData.date.isEmpty ? nil : entry.scheduleData.date
            )

            if entry.scheduleData.lessons.isEmpty {
                Spacer()
                EmptyStateView(icon: "calendar.badge.exclamationmark", message: "Нет уроков")
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: family == .systemSmall ? 4 : 6) {
                    ForEach(Array(entry.scheduleData.lessons.prefix(lessonsToShow))) { lesson in
                        ScheduleLessonRow(lesson: lesson, isCompact: family == .systemSmall)
                    }
                }

                if entry.scheduleData.lessons.count > lessonsToShow {
                    Text("+ ещё \(entry.scheduleData.lessons.count - lessonsToShow)")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.6))
                }

                Spacer(minLength: 0)
            }
        }
        .padding(family == .systemSmall ? 12 : 14)
    }
}

struct ScheduleLessonRow: View {
    let lesson: WidgetLesson
    let isCompact: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("\(lesson.num)")
                .font(.system(size: isCompact ? 11 : 12, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: isCompact ? 16 : 18, height: isCompact ? 16 : 18)
                .background(Color.white.opacity(0.2))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 0) {
                Text(lesson.subject)
                    .font(.system(size: isCompact ? 11 : 12, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)

                if !isCompact && !lesson.teacher.isEmpty {
                    Text(lesson.teacher)
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(lesson.startTime)
                .font(.system(size: isCompact ? 10 : 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))

            if let mark = lesson.mark, !mark.isEmpty {
                Text(mark)
                    .font(.system(size: isCompact ? 10 : 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.25))
                    .clipShape(Capsule())
            }
        }
    }
}

struct ScheduleWidget: Widget {
    let kind: String = "ScheduleWidget"

    private var gradientBackground: some View {
        LinearGradient(
            gradient: Gradient(colors: [Color(hex: "6A11CB"), Color(hex: "2575FC")]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ScheduleProvider()) { entry in
            if #available(iOS 17.0, *) {
                ScheduleWidgetEntryView(entry: entry)
                    .containerBackground(for: .widget) {
                        gradientBackground
                    }
            } else {
                ZStack {
                    gradientBackground
                    ScheduleWidgetEntryView(entry: entry)
                }
            }
        }
        .configurationDisplayName("Расписание")
        .description("Уроки на сегодня")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct ScheduleWidget_Previews: PreviewProvider {
    static var previews: some View {
        let sampleData = WidgetScheduleData(
            date: "19 декабря",
            lessons: [
                WidgetLesson(num: 1, subject: "Математика", teacher: "Иванова А.П.", startTime: "08:30", endTime: "09:15", mark: "5", isPlaceholder: false),
                WidgetLesson(num: 2, subject: "Русский язык", teacher: "Петрова М.И.", startTime: "09:25", endTime: "10:10", mark: nil, isPlaceholder: false),
                WidgetLesson(num: 3, subject: "Физика", teacher: "Сидоров К.В.", startTime: "10:30", endTime: "11:15", mark: nil, isPlaceholder: false),
                WidgetLesson(num: 4, subject: "История", teacher: "Козлова Е.С.", startTime: "11:25", endTime: "12:10", mark: "4", isPlaceholder: false),
            ],
            lastUpdated: ""
        )

        ScheduleWidgetEntryView(entry: ScheduleEntry(date: Date(), scheduleData: sampleData))
            .previewContext(WidgetPreviewContext(family: .systemMedium))
    }
}