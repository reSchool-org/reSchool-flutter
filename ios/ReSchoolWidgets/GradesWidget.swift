import WidgetKit
import SwiftUI

struct GradesEntry: TimelineEntry {
    let date: Date
    let gradesData: WidgetGradesData
}

struct GradesProvider: TimelineProvider {
    func placeholder(in context: Context) -> GradesEntry {
        GradesEntry(date: Date(), gradesData: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (GradesEntry) -> ()) {
        let data = WidgetDataProvider.loadGradesData()
        completion(GradesEntry(date: Date(), gradesData: data))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GradesEntry>) -> ()) {
        let data = WidgetDataProvider.loadGradesData()
        let entry = GradesEntry(date: Date(), gradesData: data)

        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct GradesWidgetEntryView: View {
    var entry: GradesProvider.Entry
    @Environment(\.widgetFamily) var family

    private var gradesToShow: Int {
        switch family {
        case .systemSmall: return 3
        case .systemMedium: return 4
        case .systemLarge: return 8
        default: return 4
        }
    }

    private var columns: Int {
        switch family {
        case .systemSmall: return 1
        case .systemMedium: return 2
        case .systemLarge: return 2
        default: return 2
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(
                icon: "star.fill",
                title: "Оценки",
                subtitle: entry.gradesData.periodName.isEmpty ? nil : entry.gradesData.periodName
            )

            if entry.gradesData.grades.isEmpty {
                Spacer()
                EmptyStateView(icon: "star.slash.fill", message: "Нет оценок")
                Spacer()
            } else {
                if family == .systemSmall {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(entry.gradesData.grades.prefix(gradesToShow))) { grade in
                            GradeRowCompact(grade: grade)
                        }
                    }
                } else {
                    let items = Array(entry.gradesData.grades.prefix(gradesToShow))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
                        ForEach(items) { grade in
                            GradeCard(grade: grade)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .padding(family == .systemSmall ? 12 : 14)
    }
}

struct GradeRowCompact: View {
    let grade: WidgetGrade

    var body: some View {
        HStack {
            Text(grade.subject)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)

            Spacer()

            Text(grade.average)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(gradeColor(for: grade.average).opacity(0.3))
                .clipShape(Capsule())
        }
    }
}

struct GradeCard: View {
    let grade: WidgetGrade

    var body: some View {
        HStack(spacing: 8) {
            Text(grade.average)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(gradeColor(for: grade.average).opacity(0.3))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 0) {
                Text(grade.subject)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                if let rating = grade.rating, !rating.isEmpty {
                    Text(rating)
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

func gradeColor(for average: String) -> Color {
    guard let value = Double(average) else { return .white }

    if value >= 4.5 {
        return Color(hex: "4CAF50")
    } else if value >= 3.5 {
        return Color(hex: "FFC107")
    } else if value >= 2.5 {
        return Color(hex: "FF9800")
    } else {
        return Color(hex: "F44336")
    }
}

struct GradesWidget: Widget {
    let kind: String = "GradesWidget"

    private var gradientBackground: some View {
        LinearGradient(
            gradient: Gradient(colors: [Color(hex: "11998E"), Color(hex: "38EF7D")]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GradesProvider()) { entry in
            if #available(iOS 17.0, *) {
                GradesWidgetEntryView(entry: entry)
                    .containerBackground(for: .widget) {
                        gradientBackground
                    }
            } else {
                ZStack {
                    gradientBackground
                    GradesWidgetEntryView(entry: entry)
                }
            }
        }
        .configurationDisplayName("Оценки")
        .description("Средние баллы по предметам")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct GradesWidget_Previews: PreviewProvider {
    static var previews: some View {
        let sampleData = WidgetGradesData(
            periodName: "2 четверть",
            grades: [
                WidgetGrade(subject: "Математика", average: "4.8", rating: "Отлично", totalMarks: 12),
                WidgetGrade(subject: "Русский язык", average: "4.2", rating: "Хорошо", totalMarks: 8),
                WidgetGrade(subject: "Физика", average: "5.0", rating: "Отлично", totalMarks: 6),
                WidgetGrade(subject: "История", average: "3.7", rating: "Хорошо", totalMarks: 5),
            ],
            lastUpdated: ""
        )

        GradesWidgetEntryView(entry: GradesEntry(date: Date(), gradesData: sampleData))
            .previewContext(WidgetPreviewContext(family: .systemMedium))
    }
}