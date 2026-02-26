import Foundation
import Combine
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - List Color

enum ListColor: String, Codable, CaseIterable {
    case blue, purple, pink, orange, green, yellow, gray, red, teal, indigo, mint, brown, cyan

    var swiftUIColor: Color {
        switch self {
        case .blue:   return Color(hue: 0.60, saturation: 0.75, brightness: 0.85)
        case .purple: return Color(hue: 0.75, saturation: 0.65, brightness: 0.80)
        case .pink:   return Color(hue: 0.92, saturation: 0.60, brightness: 0.90)
        case .orange: return Color(hue: 0.08, saturation: 0.80, brightness: 0.90)
        case .green:  return Color(hue: 0.38, saturation: 0.65, brightness: 0.72)
        case .yellow: return Color(hue: 0.14, saturation: 0.75, brightness: 0.90)
        case .gray:   return Color(hue: 0.0,  saturation: 0.0,  brightness: 0.60)
        case .red:    return Color(hue: 0.00, saturation: 0.72, brightness: 0.88)
        case .teal:   return Color(hue: 0.50, saturation: 0.62, brightness: 0.76)
        case .indigo: return Color(hue: 0.67, saturation: 0.62, brightness: 0.78)
        case .mint:   return Color(hue: 0.42, saturation: 0.38, brightness: 0.88)
        case .brown:  return Color(hue: 0.08, saturation: 0.48, brightness: 0.62)
        case .cyan:   return Color(hue: 0.54, saturation: 0.62, brightness: 0.90)
        }
    }

    static func from(color: Color) -> ListColor {
        // Simple hue-based mapping
        let hue: CGFloat
        #if os(macOS)
        let platformColor = NSColor(color).usingColorSpace(.deviceRGB) ?? .blue
        hue = platformColor.hueComponent
        #else
        let platformColor = UIColor(color)
        var extractedHue: CGFloat = 0
        platformColor.getHue(&extractedHue, saturation: nil, brightness: nil, alpha: nil)
        hue = extractedHue
        #endif
        switch hue {
        case 0.55...0.70: return .blue
        case 0.70...0.85: return .purple
        case 0.85...1.0, 0.0..<0.05: return .pink
        case 0.05...0.12: return .orange
        case 0.00...0.03: return .red
        case 0.30...0.50: return .green
        case 0.49...0.53: return .teal
        case 0.64...0.69: return .indigo
        case 0.40...0.45: return .mint
        case 0.52...0.56: return .cyan
        case 0.07...0.10: return .brown
        case 0.12...0.20: return .yellow
        default:          return .gray
        }
    }
}

// MARK: - Priority

enum Priority: String, Codable, CaseIterable {
    case none, low, medium, high

    var title: String {
        switch self {
        case .none: return "None"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    var color: Color {
        switch self {
        case .none: return .secondary
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        }
    }

    var numericValue: Int {
        switch self {
        case .none: return 0
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        }
    }
}

// MARK: - Task Status

enum TaskStatus: String, Codable, CaseIterable {
    case todo, inProgress, blocked, done

    var title: String {
        switch self {
        case .todo: return "Todo"
        case .inProgress: return "In Progress"
        case .blocked: return "Blocked"
        case .done: return "Done"
        }
    }

    var color: Color {
        switch self {
        case .todo: return .secondary
        case .inProgress: return .blue
        case .blocked: return .red
        case .done: return .green
        }
    }

    var icon: String {
        switch self {
        case .todo: return "circle"
        case .inProgress: return "arrow.triangle.2.circlepath"
        case .blocked: return "exclamationmark.octagon.fill"
        case .done: return "checkmark.circle.fill"
        }
    }
}

// MARK: - Task Item

struct TaskItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var content: String
    var isCompleted: Bool = false
    var isBold: Bool = false
    var isItalic: Bool = false
    var isStrikethrough: Bool = false
    var priority: Priority = .none
    var status: TaskStatus = .todo
    var estimatedMinutes: Int?
    var reminderDate: Date?
    /// Wall-clock time of the last local edit. Used for last-writer-wins merge.
    var lastModified: Date = Date()

    enum CodingKeys: String, CodingKey {
        case id, content, isCompleted, isBold, isItalic, isStrikethrough, priority, status, estimatedMinutes, reminderDate, lastModified
    }

    init(id: UUID = UUID(),
         content: String,
         isCompleted: Bool = false,
         isBold: Bool = false,
         isItalic: Bool = false,
         isStrikethrough: Bool = false,
         priority: Priority = .none,
         status: TaskStatus = .todo,
         estimatedMinutes: Int? = nil,
         reminderDate: Date? = nil,
         lastModified: Date = Date()) {
        self.id = id
        self.content = content
        self.isCompleted = isCompleted
        self.isBold = isBold
        self.isItalic = isItalic
        self.isStrikethrough = isStrikethrough
        self.priority = priority
        self.status = status
        self.estimatedMinutes = estimatedMinutes
        self.reminderDate = reminderDate
        self.lastModified = lastModified
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        content = (try? container.decode(String.self, forKey: .content)) ?? ""
        isCompleted = (try? container.decode(Bool.self, forKey: .isCompleted)) ?? false
        isBold = (try? container.decode(Bool.self, forKey: .isBold)) ?? false
        isItalic = (try? container.decode(Bool.self, forKey: .isItalic)) ?? false
        isStrikethrough = (try? container.decode(Bool.self, forKey: .isStrikethrough)) ?? false
        priority = (try? container.decode(Priority.self, forKey: .priority)) ?? .none
        status = (try? container.decode(TaskStatus.self, forKey: .status)) ?? .todo
        estimatedMinutes = try? container.decode(Int.self, forKey: .estimatedMinutes)
        reminderDate = try? container.decode(Date.self, forKey: .reminderDate)
        lastModified = (try? container.decode(Date.self, forKey: .lastModified)) ?? Date(timeIntervalSince1970: 0)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(content, forKey: .content)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encode(isBold, forKey: .isBold)
        try container.encode(isItalic, forKey: .isItalic)
        try container.encode(isStrikethrough, forKey: .isStrikethrough)
        try container.encode(priority, forKey: .priority)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(estimatedMinutes, forKey: .estimatedMinutes)
        try container.encodeIfPresent(reminderDate, forKey: .reminderDate)
        try container.encode(lastModified, forKey: .lastModified)
    }
}

// MARK: - Task List

class TaskList: Identifiable, Codable, Equatable, ObservableObject {
    var id = UUID()
    @Published var title: String
    @Published var items: [TaskItem] = []
    @Published var position: CGPoint = .zero
    @Published var size: CGSize = CGSize(width: 300, height: 400)
    @Published var color: ListColor = .blue
    @Published var sortDescending: Bool = true
    @Published var isVisible: Bool = true
    /// Wall-clock time of the last local edit to this list's metadata.
    var lastModified: Date = Date()
    /// Tombstone map: item id → time it was deleted.
    /// Items in this set are never resurrected by remote merges.
    var deletedItemIDs: [UUID: Date] = [:]

    init(id: UUID = UUID(), title: String, items: [TaskItem] = [],
         position: CGPoint = .zero, size: CGSize = CGSize(width: 300, height: 400),
         color: ListColor = .blue, isVisible: Bool = true) {
        self.id = id
        self.title = title
        self.items = items
        self.position = position
        self.size = size
        self.color = color
        self.sortDescending = true
        self.isVisible = isVisible
        self.lastModified = Date()
        self.deletedItemIDs = [:]
    }

    enum CodingKeys: String, CodingKey {
        case id, title, items, position, size, color, sortDescending, isVisible, lastModified, deletedItemIDs
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id       = try container.decode(UUID.self,      forKey: .id)
        title    = try container.decode(String.self,    forKey: .title)
        items    = (try? container.decode([TaskItem].self, forKey: .items)) ?? []
        position = (try? container.decode(CGPoint.self,   forKey: .position)) ?? .zero
        size     = (try? container.decode(CGSize.self,    forKey: .size)) ?? CGSize(width: 300, height: 400)
        color    = (try? container.decode(ListColor.self, forKey: .color)) ?? .blue
        sortDescending = (try? container.decode(Bool.self, forKey: .sortDescending)) ?? true
        isVisible = (try? container.decode(Bool.self, forKey: .isVisible)) ?? true
        lastModified = (try? container.decode(Date.self, forKey: .lastModified)) ?? Date(timeIntervalSince1970: 0)
        deletedItemIDs = (try? container.decode([UUID: Date].self, forKey: .deletedItemIDs)) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id,             forKey: .id)
        try container.encode(title,          forKey: .title)
        try container.encode(items,          forKey: .items)
        try container.encode(position,       forKey: .position)
        try container.encode(size,           forKey: .size)
        try container.encode(color,          forKey: .color)
        try container.encode(sortDescending, forKey: .sortDescending)
        try container.encode(isVisible,      forKey: .isVisible)
        try container.encode(lastModified,   forKey: .lastModified)
        try container.encode(deletedItemIDs, forKey: .deletedItemIDs)
    }

    func sortItemsByPriority() {
        items.sort { (a, b) -> Bool in
            if a.isCompleted != b.isCompleted {
                return !a.isCompleted // Incomplete first
            }
            if a.priority.numericValue != b.priority.numericValue {
                return sortDescending ? 
                    a.priority.numericValue > b.priority.numericValue : // High priority first
                    a.priority.numericValue < b.priority.numericValue   // Low priority first
            }
            return a.content < b.content // Alphabetical as tie-breaker
        }
    }

    static func == (lhs: TaskList, rhs: TaskList) -> Bool {
        lhs.id == rhs.id
    }
}
