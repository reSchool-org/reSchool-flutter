import WidgetKit
import SwiftUI

struct HomeworkEntry: TimelineEntry {
    let date: Date
    let homeworkData: WidgetHomeworkData
}

struct WidgetHomeworkData: Decodable, Hashable {
    let items: [WidgetHomeworkItem]
    let lastUpdated: String

    static var empty: WidgetHomeworkData {
        WidgetHomeworkData(items: [], lastUpdated: "")
    }
}

struct WidgetHomeworkItem: Decodable, Hashable, Identifiable {
    var id: String { "\(subject)-\(date)" }
    let subject: String
    let text: String
    let date: String
    let deadline: String?
    let hasFiles: Bool
}

struct HomeworkWidgetEntryView: View {
    var entry: HomeworkEntry
    @Environment(\.widgetFamily) var family

    var itemsToShow: Int {
        switch family {
        case .systemSmall: return 2
        case .systemMedium: return 3
        case .systemLarge: return 6
        default: return 3
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(.white)
                Text("Домашние задания")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                if !entry.homeworkData.items.isEmpty {
                    Text("\(entry.homeworkData.items.count)")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                }
            }

            if entry.homeworkData.items.isEmpty {
                Spacer()
                Text("Нет заданий")
                    .foregroundColor(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(entry.homeworkData.items.prefix(itemsToShow))) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "book.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.8))
                                .frame(width: 14)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.subject)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)

                                Text(item.text)
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.8))
                                    .lineLimit(family == .systemSmall ? 1 : 2)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(item.date)
                                    .font(.system(size: 10, weight: .medium))
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
                        .cornerRadius(8)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding()
    }
}

struct HomeworkWidget: Widget {
    let kind: String = "HomeworkWidget"

    private var gradientBackground: some View {
        LinearGradient(
            gradient: Gradient(colors: [Color(red: 1.0, green: 0.32, blue: 0.18), Color(red: 0.87, green: 0.14, blue: 0.46)]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HomeworkProvider()) { entry in
            if #available(macOS 14.0, *) {
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
        .description("Ваши ближайшие задания.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct HomeworkProvider: TimelineProvider {
    private static let appGroupId = "group.com.magisky.reschoolbeta"
    private static let dataKey = "widget_homework_data"

    func placeholder(in context: Context) -> HomeworkEntry {
        HomeworkEntry(date: Date(), homeworkData: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (HomeworkEntry) -> ()) {
        let entry = HomeworkEntry(date: Date(), homeworkData: getHomeworkData())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HomeworkEntry>) -> ()) {
        let entry = HomeworkEntry(date: Date(), homeworkData: getHomeworkData())
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func getHomeworkData() -> WidgetHomeworkData {
        if let data = getFromAppGroup() {
            return data
        }

        if let data = getFromFile() {
            return data
        }

        print("[HomeworkWidget] No data found from any source")
        return .empty
    }

    private func getFromAppGroup() -> WidgetHomeworkData? {
        let userDefaults = UserDefaults(suiteName: Self.appGroupId)
        if let jsonString = userDefaults?.string(forKey: Self.dataKey),
           let data = jsonString.data(using: .utf8) {
            do {
                let decoded = try JSONDecoder().decode(WidgetHomeworkData.self, from: data)
                print("[HomeworkWidget] Decoded from App Group, items count: \(decoded.items.count)")
                return decoded
            } catch {
                print("[HomeworkWidget] Error decoding from App Group: \(error)")
            }
        }
        return nil
    }

    private func getFromFile() -> WidgetHomeworkData? {
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

    private func readFromFile(url: URL) -> WidgetHomeworkData? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        do {
            let jsonString = try String(contentsOf: url, encoding: .utf8)
            if let jsonData = jsonString.data(using: .utf8) {
                let decoded = try JSONDecoder().decode(WidgetHomeworkData.self, from: jsonData)
                print("[HomeworkWidget] Decoded from file, items count: \(decoded.items.count)")
                return decoded
            }
        } catch {
            print("[HomeworkWidget] Error reading from file: \(error)")
        }
        return nil
    }
}