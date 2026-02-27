import Foundation
import Combine

// MARK: - Log Level

enum LogLevel: String, CaseIterable {
    case info  = "INFO"
    case warn  = "WARN"
    case error = "ERROR"
    case debug = "DEBUG"

    var emoji: String {
        switch self {
        case .info:  return "🔵"
        case .warn:  return "🟡"
        case .error: return "🔴"
        case .debug: return "⚪️"
        }
    }
}

// MARK: - Log Entry

struct LogEntry: Identifiable {
    let id = UUID()
    let date: Date
    let level: LogLevel
    let message: String

    var formattedTime: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: date)
    }
}

// MARK: - AppLogger

/// A thread-safe, in-memory log sink.
/// Call `AppLogger.shared.log(…)` from anywhere, or use the free functions
/// `appLog`, `appWarn`, `appError`, `appDebug` for convenient call-site tagging.
final class AppLogger: ObservableObject {
    static let shared = AppLogger()

    @Published private(set) var entries: [LogEntry] = []
    @Published private(set) var unreadCount: Int = 0

    private let maxEntries = 1_000
    private let queue = DispatchQueue(label: "com.ftm.logger", qos: .utility)

    private init() {}

    // MARK: - Public API

    func log(_ message: String, level: LogLevel = .info,
             file: String = #file, line: Int = #line) {
        let filename = URL(fileURLWithPath: file).lastPathComponent
        let formatted = "[\(filename):\(line)] \(message)"
        let entry = LogEntry(date: Date(), level: level, message: formatted)

        // Mirror to Xcode / Console.app
        print("\(level.emoji) [FTM:\(level.rawValue)] \(formatted)")

        queue.async { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                self.entries.append(entry)
                self.unreadCount += 1
                if self.entries.count > self.maxEntries {
                    self.entries.removeFirst(self.entries.count - self.maxEntries)
                }
            }
        }
    }

    func clearUnread() {
        DispatchQueue.main.async { self.unreadCount = 0 }
    }

    func clear() {
        DispatchQueue.main.async {
            self.entries.removeAll()
            self.unreadCount = 0
        }
    }

    // MARK: - Export

    func exportText() -> String {
        entries.map { "[\($0.formattedTime)] [\($0.level.rawValue)] \($0.message)" }
               .joined(separator: "\n")
    }
}

// MARK: - Free convenience functions (mirrors the ftmLog style used in FirebaseSyncManager)

func appLog(_ msg: String, file: String = #file, line: Int = #line) {
    AppLogger.shared.log(msg, level: .info, file: file, line: line)
}
func appWarn(_ msg: String, file: String = #file, line: Int = #line) {
    AppLogger.shared.log(msg, level: .warn, file: file, line: line)
}
func appError(_ msg: String, file: String = #file, line: Int = #line) {
    AppLogger.shared.log(msg, level: .error, file: file, line: line)
}
func appDebug(_ msg: String, file: String = #file, line: Int = #line) {
    AppLogger.shared.log(msg, level: .debug, file: file, line: line)
}

