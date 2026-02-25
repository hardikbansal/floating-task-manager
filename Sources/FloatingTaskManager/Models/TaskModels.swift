import Foundation
import Combine
import SwiftUI

// MARK: - List Color

enum ListColor: String, Codable, CaseIterable {
    case blue, purple, pink, orange, green, yellow, gray

    var swiftUIColor: Color {
        switch self {
        case .blue:   return Color(hue: 0.60, saturation: 0.75, brightness: 0.85)
        case .purple: return Color(hue: 0.75, saturation: 0.65, brightness: 0.80)
        case .pink:   return Color(hue: 0.92, saturation: 0.60, brightness: 0.90)
        case .orange: return Color(hue: 0.08, saturation: 0.80, brightness: 0.90)
        case .green:  return Color(hue: 0.38, saturation: 0.65, brightness: 0.72)
        case .yellow: return Color(hue: 0.14, saturation: 0.75, brightness: 0.90)
        case .gray:   return Color(hue: 0.0,  saturation: 0.0,  brightness: 0.60)
        }
    }

    static func from(color: Color) -> ListColor {
        // Simple hue-based mapping
        let nsColor = NSColor(color).usingColorSpace(.deviceRGB) ?? .blue
        let hue = nsColor.hueComponent
        switch hue {
        case 0.55...0.70: return .blue
        case 0.70...0.85: return .purple
        case 0.85...1.0, 0.0..<0.05: return .pink
        case 0.05...0.12: return .orange
        case 0.30...0.50: return .green
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

// MARK: - Task Item

struct TaskItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var content: String
    var isCompleted: Bool = false
    var isBold: Bool = false
    var isItalic: Bool = false
    var isStrikethrough: Bool = false
    var priority: Priority = .none
    var reminderDate: Date?
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
    }

    enum CodingKeys: String, CodingKey {
        case id, title, items, position, size, color, sortDescending, isVisible
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
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id,       forKey: .id)
        try container.encode(title,    forKey: .title)
        try container.encode(items,    forKey: .items)
        try container.encode(position, forKey: .position)
        try container.encode(size,     forKey: .size)
        try container.encode(color,    forKey: .color)
        try container.encode(sortDescending, forKey: .sortDescending)
        try container.encode(isVisible, forKey: .isVisible)
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
