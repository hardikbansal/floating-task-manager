#if os(macOS)
import SwiftUI
import AppKit
// MARK: - Log Viewer View
struct LogViewerView: View {
    @ObservedObject private var logger = AppLogger.shared
    @State private var filterLevel: LogLevel? = nil
    @State private var searchText: String = ""
    @State private var autoScroll: Bool = true
    @State private var copyToast: Bool = false
    private var filteredEntries: [LogEntry] {
        logger.entries.filter { entry in
            let levelMatch = filterLevel == nil || entry.level == filterLevel
            let textMatch  = searchText.isEmpty ||
                             entry.message.localizedCaseInsensitiveContains(searchText)
            return levelMatch && textMatch
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            // ── Toolbar ──────────────────────────────────────────────
            HStack(spacing: 10) {
                Image(systemName: "terminal.fill")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14, weight: .semibold))
                Text("Sync Logs")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
                // Search
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 11))
                    TextField("Filter…", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 12, design: .rounded))
                        .frame(width: 140)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 11))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                // Level filter pills
                HStack(spacing: 4) {
                    levelPill(nil, label: "ALL")
                    ForEach(LogLevel.allCases, id: \.self) { lvl in
                        levelPill(lvl, label: lvl.rawValue)
                    }
                }
                // Auto-scroll toggle
                Button(action: { autoScroll.toggle() }) {
                    Image(systemName: autoScroll ? "arrow.down.to.line.compact" : "pause.fill")
                        .font(.system(size: 12))
                        .foregroundColor(autoScroll ? .blue : .secondary)
                }
                .buttonStyle(PremiumButtonStyle())
                .help(autoScroll ? "Auto-scroll ON" : "Auto-scroll OFF")
                // Copy
                Button(action: copyLogs) {
                    Image(systemName: copyToast ? "checkmark" : "doc.on.clipboard")
                        .font(.system(size: 12))
                        .foregroundColor(copyToast ? .green : .secondary)
                }
                .buttonStyle(PremiumButtonStyle())
                .help("Copy all logs to clipboard")
                // Clear
                Button(action: { logger.clear() }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(PremiumButtonStyle())
                .help("Clear logs")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                VisualEffectView(material: .headerView, blendingMode: .withinWindow)
                    .opacity(0.8)
            )
            Divider().opacity(0.15)
            // ── Log entries ──────────────────────────────────────────
            if filteredEntries.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text(logger.entries.isEmpty ? "No logs yet." : "No entries match filter.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(filteredEntries) { entry in
                                LogRowView(entry: entry)
                                    .id(entry.id)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onChange(of: filteredEntries.count) { _ in
                        if autoScroll, let last = filteredEntries.last {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                    .onAppear {
                        if let last = filteredEntries.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            Divider().opacity(0.1)
            // ── Status bar ───────────────────────────────────────────
            HStack(spacing: 12) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(statusText)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(filteredEntries.count) entries")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        .background(
            VisualEffectView(material: .windowBackground, blendingMode: .behindWindow)
        )
        .onAppear { logger.clearUnread() }
    }
    // MARK: - Sub-views
    @ViewBuilder
    private func levelPill(_ level: LogLevel?, label: String) -> some View {
        let isSelected = filterLevel == level
        Button(action: { filterLevel = level }) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(isSelected ? .white : .secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(isSelected ? pillColor(level) : Color.primary.opacity(0.07))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
    private func pillColor(_ level: LogLevel?) -> Color {
        guard let level else { return .blue }
        switch level {
        case .info:  return .blue
        case .warn:  return .orange
        case .error: return .red
        case .debug: return .secondary
        }
    }
    private var statusColor: Color {
        let hasErrors = logger.entries.last(where: { $0.level == .error }) != nil
        let hasWarns  = logger.entries.last(where: { $0.level == .warn  }) != nil
        if hasErrors { return .red }
        if hasWarns  { return .orange }
        return .green
    }
    private var statusText: String {
        let errors = logger.entries.filter { $0.level == .error }.count
        let warns  = logger.entries.filter { $0.level == .warn  }.count
        if errors > 0 { return "\(errors) error(s)" }
        if warns  > 0 { return "\(warns) warning(s)" }
        return "All clear"
    }
    private func copyLogs() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logger.exportText(), forType: .string)
        copyToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copyToast = false }
    }
}
// MARK: - Log Row
private struct LogRowView: View {
    let entry: LogEntry
    @State private var hovered = false
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.level.emoji)
                .font(.system(size: 11))
                .frame(width: 18)
            Text(entry.formattedTime)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 88, alignment: .leading)
            Text(entry.level.rawValue)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundColor(levelColor)
                .frame(width: 38, alignment: .center)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(levelColor.opacity(0.12))
                )
            Text(entry.message)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(.primary.opacity(0.85))
                .textSelection(.enabled)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(hovered ? Color.primary.opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }
    private var levelColor: Color {
        switch entry.level {
        case .info:  return .blue
        case .warn:  return .orange
        case .error: return .red
        case .debug: return .secondary
        }
    }
}
#endif
