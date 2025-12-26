import WidgetKit
import SwiftUI

struct GradesEntry: TimelineEntry {
    let date: Date
    let gradesData: WidgetGradesData
}

struct WidgetGradesData: Decodable, Hashable {
    let periodName: String
    let grades: [WidgetGrade]
    let lastUpdated: String

    static var empty: WidgetGradesData {
        WidgetGradesData(periodName: "", grades: [], lastUpdated: "")
    }
}

struct WidgetGrade: Decodable, Hashable, Identifiable {
    var id: String { subject }
    let subject: String
    let average: String
    let rating: String?
    let totalMarks: Int?
}

struct GradesWidgetEntryView: View {
    var entry: GradesEntry
    @Environment(\.widgetFamily) var family

    var gradesToShow: Int {
        switch family {
        case .systemSmall: return 3
        case .systemMedium: return 4
        case .systemLarge: return 8
        default: return 4
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "star.fill")
                    .foregroundColor(.white)
                Text("Оценки")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                if !entry.gradesData.periodName.isEmpty {
                    Text(entry.gradesData.periodName)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                }
            }

            if entry.gradesData.grades.isEmpty {
                Spacer()
                Text("Нет оценок")
                    .foregroundColor(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                if family == .systemSmall {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(entry.gradesData.grades.prefix(gradesToShow))) { grade in
                            HStack {
                                Text(grade.subject)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Spacer()
                                Text(grade.average)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(gradeColor(for: grade.average).opacity(0.3))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(Array(entry.gradesData.grades.prefix(gradesToShow))) { grade in
                            HStack(spacing: 8) {
                                Text(grade.average)
                                    .font(.system(size: 18, weight: .bold))
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
                            .cornerRadius(10)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding()
    }

    func gradeColor(for average: String) -> Color {
        guard let value = Double(average) else { return .white }

        if value >= 4.5 {
            return Color(red: 0.3, green: 0.69, blue: 0.31)
        } else if value >= 3.5 {
            return Color(red: 1.0, green: 0.76, blue: 0.03)
        } else if value >= 2.5 {
            return Color(red: 1.0, green: 0.6, blue: 0.0)
        } else {
            return Color(red: 0.96, green: 0.26, blue: 0.21)
        }
    }
}

struct GradesWidget: Widget {
    let kind: String = "GradesWidget"

    private var gradientBackground: some View {
        LinearGradient(
            gradient: Gradient(colors: [Color(red: 0.07, green: 0.6, blue: 0.56), Color(red: 0.22, green: 0.94, blue: 0.49)]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GradesProvider()) { entry in
            if #available(macOS 14.0, *) {
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
        .description("Средний балл по предметам.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct GradesProvider: TimelineProvider {
    private static let appGroupId = "group.com.magisky.reschoolbeta"
    private static let dataKey = "widget_grades_data"

    func placeholder(in context: Context) -> GradesEntry {
        GradesEntry(date: Date(), gradesData: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (GradesEntry) -> ()) {
        let entry = GradesEntry(date: Date(), gradesData: getGradesData())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GradesEntry>) -> ()) {
        let entry = GradesEntry(date: Date(), gradesData: getGradesData())
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func getGradesData() -> WidgetGradesData {
        if let data = getFromAppGroup() {
            return data
        }

        if let data = getFromFile() {
            return data
        }

        print("[GradesWidget] No data found from any source")
        return .empty
    }

    private func getFromAppGroup() -> WidgetGradesData? {
        let userDefaults = UserDefaults(suiteName: Self.appGroupId)
        if let jsonString = userDefaults?.string(forKey: Self.dataKey),
           let data = jsonString.data(using: .utf8) {
            do {
                let decoded = try JSONDecoder().decode(WidgetGradesData.self, from: data)
                print("[GradesWidget] Decoded from App Group, grades count: \(decoded.grades.count)")
                return decoded
            } catch {
                print("[GradesWidget] Error decoding from App Group: \(error)")
            }
        }
        return nil
    }

    private func getFromFile() -> WidgetGradesData? {
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupId) {
            let fileURL = containerURL.appendingPathComponent("Library/WidgetData/\(Self.dataKey).json")
            if let data = readFromFile(url: fileURL) {
                return data
            }
        }

        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let fileURL = appSupport.appendingPathComponent("ReSchoolWidgets/\(Self.dataKey).json")
            if let data = readFromFile(url: fileURL) {
                return data
            }
        }

        return nil
    }

    private func readFromFile(url: URL) -> WidgetGradesData? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        do {
            let jsonString = try String(contentsOf: url, encoding: .utf8)
            if let jsonData = jsonString.data(using: .utf8) {
                let decoded = try JSONDecoder().decode(WidgetGradesData.self, from: jsonData)
                print("[GradesWidget] Decoded from file, grades count: \(decoded.grades.count)")
                return decoded
            }
        } catch {
            print("[GradesWidget] Error reading from file: \(error)")
        }
        return nil
    }
}