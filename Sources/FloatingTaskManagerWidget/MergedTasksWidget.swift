import WidgetKit
import SwiftUI

private let widgetAppGroupID = "group.com.hardikbansal.floatingtaskmanager"
private let widgetSnapshotFilename = "merged-widget-snapshot.json"
private let widgetSnapshotDefaultsKey = "merged-widget-snapshot-json"

struct WidgetTaskSnapshotItem: Codable, Identifiable {
    let id: UUID
    let content: String
    let isCompleted: Bool
    let priority: String
    let status: String
    let estimatedMinutes: Int?
}

struct MergedWidgetSnapshot: Codable {
    let generatedAt: Date
    let completedCount: Int
    let totalCount: Int
    let items: [WidgetTaskSnapshotItem]
}

struct MergedWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: MergedWidgetSnapshot
}

private func durationText(minutes: Int?) -> String? {
    guard let minutes, minutes > 0 else { return nil }
    let hours = minutes / 60
    let mins = minutes % 60
    if hours > 0 && mins > 0 { return "\(hours)h \(mins)m" }
    if hours > 0 { return "\(hours)h" }
    return "\(mins)m"
}

private func loadWidgetSnapshot() -> MergedWidgetSnapshot {
    if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: widgetAppGroupID) {
        let url = container.appendingPathComponent(widgetSnapshotFilename)
        if let data = try? Data(contentsOf: url),
           let snapshot = try? JSONDecoder().decode(MergedWidgetSnapshot.self, from: data) {
            return snapshot
        }
    }

    if let json = UserDefaults(suiteName: widgetAppGroupID)?.string(forKey: widgetSnapshotDefaultsKey),
       let data = json.data(using: .utf8),
       let snapshot = try? JSONDecoder().decode(MergedWidgetSnapshot.self, from: data) {
        return snapshot
    }

    return MergedWidgetSnapshot(generatedAt: Date(), completedCount: 0, totalCount: 0, items: [])
}

struct MergedWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> MergedWidgetEntry {
        MergedWidgetEntry(
            date: Date(),
            snapshot: MergedWidgetSnapshot(
                generatedAt: Date(),
                completedCount: 2,
                totalCount: 5,
                items: [
                    WidgetTaskSnapshotItem(id: UUID(), content: "Plan sprint demo", isCompleted: false, priority: "High", status: "In Progress", estimatedMinutes: 45),
                    WidgetTaskSnapshotItem(id: UUID(), content: "Reply to design feedback", isCompleted: false, priority: "Medium", status: "Todo", estimatedMinutes: 20)
                ]
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (MergedWidgetEntry) -> Void) {
        completion(MergedWidgetEntry(date: Date(), snapshot: loadWidgetSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MergedWidgetEntry>) -> Void) {
        let entry = MergedWidgetEntry(date: Date(), snapshot: loadWidgetSnapshot())
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct MergedTasksWidgetEntryView: View {
    var entry: MergedWidgetProvider.Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if #available(iOSApplicationExtension 17.0, *) {
            contentView
                .containerBackground(for: .widget) {
                    widgetBackground
                }
        } else {
            contentView
                .background(widgetBackground)
        }
    }

    private var contentView: some View {
        let snapshot = entry.snapshot
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Merged Tasks", systemImage: "square.grid.2x2.fill")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Spacer()
                Text("\(snapshot.completedCount)/\(snapshot.totalCount)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            if snapshot.items.isEmpty {
                Text("No pending tasks")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(Array(snapshot.items.prefix(family == .systemSmall ? 3 : 5))) { item in
                    HStack(alignment: .center, spacing: 6) {
                        Circle()
                            .fill(statusColor(for: item.status))
                            .frame(width: 6, height: 6)
                        Text(item.content)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if item.priority != "None" {
                            Text(item.priority.uppercased())
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(priorityColor(for: item.priority).opacity(0.16)))
                                .foregroundColor(priorityColor(for: item.priority))
                        }
                        if let duration = durationText(minutes: item.estimatedMinutes) {
                            Text(duration)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.blue.opacity(0.16)))
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .widgetURL(URL(string: "floatingtaskmanager://merged"))
    }

    private var widgetBackground: some View {
        LinearGradient(colors: [Color(.systemBackground), Color(.secondarySystemBackground)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func statusColor(for status: String) -> Color {
        switch status {
        case "Done": return .green
        case "In Progress": return .blue
        case "Blocked": return .red
        default: return .secondary
        }
    }

    private func priorityColor(for priority: String) -> Color {
        switch priority {
        case "High": return .red
        case "Medium": return .orange
        case "Low": return .blue
        default: return .secondary
        }
    }
}

struct MergedTasksWidget: Widget {
    let kind: String = "MergedTasksWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MergedWidgetProvider()) { entry in
            MergedTasksWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Merged Tasks")
        .description("Quick glance at pending tasks across all lists.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct FloatingTaskManagerWidgets: WidgetBundle {
    var body: some Widget {
        MergedTasksWidget()
    }
}
