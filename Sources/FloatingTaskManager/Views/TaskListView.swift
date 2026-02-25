import SwiftUI
import AppKit

// MARK: - Task List View

struct TaskListView: View {
    @ObservedObject var list: TaskList
    @EnvironmentObject var store: TaskStore
    @EnvironmentObject var windowManager: WindowManager
    @AppStorage("baseFontSize") var baseFontSize: Double = 13.0
    @AppStorage("windowOpacity") var windowOpacity: Double = 0.95
    @AppStorage("enableShadows") var enableShadows: Bool = true
    @State private var newItemContent: String = ""
    @State private var isHoveringHeader = false
    @State private var showColorPicker = false

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ──────────────────────────────────────────────
            HStack(spacing: 8) {
                // Compact color swatch button
                Button(action: { showColorPicker.toggle() }) {
                    Circle()
                        .fill(list.color.swiftUIColor)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 1))
                        .shadow(color: list.color.swiftUIColor.opacity(0.5), radius: 3)
                }
                .buttonStyle(PlainButtonStyle())
                .popover(isPresented: $showColorPicker, arrowEdge: .bottom) {
                    ColorSwatchPicker(selected: $list.color, onPick: { store.save() })
                }

                TextField("List Title", text: $list.title)
                    .font(.system(size: 14, weight: .semibold))
                    .textFieldStyle(PlainTextFieldStyle())
                    .onSubmit { store.save() }

                Spacer()

                // Sort button (Always Visible)
                Button(action: { 
                    list.sortDescending.toggle()
                    list.sortItemsByPriority()
                    store.save() 
                }) {
                    Image(systemName: list.sortDescending ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(list.color.swiftUIColor)
                }
                .buttonStyle(PlainButtonStyle())
                .help(list.sortDescending ? "Sort: High to Low" : "Sort: Low to High")
                .padding(.trailing, 4)

                // Close button (Always Visible)
                Button(action: { windowManager.closeListWindow(for: list.id) }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(list.color.swiftUIColor.opacity(0.12))

            Divider().opacity(0.25)

            // ── Items (ScrollView avoids AppKit row-height errors) ──
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 1) {
                    ForEach($list.items) { $item in
                        TaskItemRow(item: $item,
                                    onDelete: { list.items.removeAll { $0.id == item.id }; store.save() },
                                    onChange:  { store.save() })
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
            }

            Divider().opacity(0.2)

            // ── Add task row ────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .foregroundColor(list.color.swiftUIColor.opacity(0.8))
                    .font(.system(size: 13))
                TextField("Add task...", text: $newItemContent)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: baseFontSize))
                    .onSubmit { addItem() }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider().opacity(0.2)

            // ── Footer ──────────────────────────────────────────────
            HStack {
                let done = list.items.filter(\.isCompleted).count
                let total = list.items.count
                Text(total == 0 ? "No tasks" : "\(done) / \(total) done")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                Text("⌘⇧N  new list")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.4))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
        .frame(minWidth: 270, minHeight: 300)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .opacity(windowOpacity)
                .ignoresSafeArea()
        )
        .onChange(of: enableShadows) { newValue in
            windowManager.updateWindowsAppearance()
        }
        .onChange(of: windowOpacity) { _ in
            windowManager.updateWindowsAppearance()
        }
    }

    private func addItem() {
        let trimmed = newItemContent.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        list.items.append(TaskItem(content: trimmed))
        newItemContent = ""
        store.save()
    }
}

// MARK: - Compact Color Swatch Picker

struct ColorSwatchPicker: View {
    @Binding var selected: ListColor
    var onPick: () -> Void

    let columns = Array(repeating: GridItem(.fixed(28), spacing: 8), count: 4)

    var body: some View {
        VStack(spacing: 8) {
            Text("List Color")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(ListColor.allCases, id: \.self) { color in
                    Button(action: { selected = color; onPick() }) {
                        ZStack {
                            Circle()
                                .fill(color.swiftUIColor)
                                .frame(width: 24, height: 24)
                            if selected == color {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(12)
        .background(VisualEffectView(material: .menu, blendingMode: .behindWindow))
    }
}

import UserNotifications

struct TaskItemRow: View {
    @Binding var item: TaskItem
    @AppStorage("baseFontSize") var baseFontSize: Double = 13.0
    var onDelete: () -> Void
    var onChange: () -> Void

    @State private var rowHovered = false
    @State private var showReminderPicker = false
    @State private var tempReminderDate = Date()

    private var notificationCenter: UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app") else {
            return nil
        }
        return UNUserNotificationCenter.current()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Checkbox
            Button(action: { 
                item.isCompleted.toggle()
                if item.isCompleted {
                    removeReminder()
                }
                onChange() 
            }) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(item.isCompleted ? .blue : .secondary)
                    .font(.system(size: baseFontSize + 2))
            }
            .buttonStyle(PlainButtonStyle())

            // Reminder Indicator
            if let reminder = item.reminderDate, !item.isCompleted {
                Image(systemName: "clock.fill")
                    .font(.system(size: 8))
                    .foregroundColor(reminder < Date() ? .red : .blue)
                    .help("Reminder: \(reminder.formatted())")
            }

            // Text field
            TextField("Task...", text: $item.content, onCommit: onChange)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: baseFontSize, weight: item.isBold ? .bold : .regular))
                .italic(item.isItalic)
                .strikethrough(item.isCompleted || item.isStrikethrough, color: .secondary)
                .foregroundColor(item.isCompleted ? .secondary : .primary)

            // Priority Tag
            if item.priority != .none {
                Text(item.priority.title.uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(item.priority.color.opacity(0.15))
                    .foregroundColor(item.priority.color)
                    .cornerRadius(4)
            }

            // Format toolbar — single onHover on row keeps this flicker-free
            if rowHovered {
                HStack(spacing: 2) {
                    FormatToggle(icon: "bold",           active: item.isBold)            { item.isBold.toggle();           onChange() }
                    FormatToggle(icon: "italic",         active: item.isItalic)          { item.isItalic.toggle();         onChange() }
                    FormatToggle(icon: "strikethrough",  active: item.isStrikethrough)   { item.isStrikethrough.toggle();  onChange() }
                    
                    Divider().frame(height: 12).padding(.horizontal, 1)

                    // Reminder Button
                    Button(action: { 
                        tempReminderDate = item.reminderDate ?? Date().addingTimeInterval(3600)
                        showReminderPicker.toggle() 
                    }) {
                        Image(systemName: item.reminderDate == nil ? "bell" : "bell.fill")
                            .font(.system(size: 10))
                            .foregroundColor(item.reminderDate == nil ? .secondary : .blue)
                            .frame(width: 20, height: 20)
                            .background(RoundedRectangle(cornerRadius: 4).fill(item.reminderDate != nil ? Color.blue.opacity(0.1) : Color.clear))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .popover(isPresented: $showReminderPicker) {
                        VStack(spacing: 8) {
                            Text("Set Reminder")
                                .font(.system(size: 11, weight: .bold))
                            
                            DatePicker("", selection: $tempReminderDate)
                                .datePickerStyle(GraphicalDatePickerStyle())
                                .labelsHidden()
                                .frame(width: 260)

                            HStack {
                                if item.reminderDate != nil {
                                    Button("Clear") {
                                        removeReminder()
                                        showReminderPicker = false
                                    }
                                    .buttonStyle(.borderless)
                                    .foregroundColor(.red)
                                }
                                Spacer()
                                Button("Cancel") { showReminderPicker = false }
                                    .buttonStyle(.borderless)
                                Button("Set") {
                                    setReminder(at: tempReminderDate)
                                    showReminderPicker = false
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                        .padding(12)
                    }
                    
                    Divider().frame(height: 12).padding(.horizontal, 1)
                    
                    // Priority Picker
                    Menu {
                        ForEach(Priority.allCases, id: \.self) { p in
                            Button(action: { item.priority = p; onChange() }) {
                                HStack {
                                    Text(p.title)
                                    if item.priority == p {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 10))
                            .foregroundColor(item.priority == .none ? .secondary : item.priority.color)
                            .frame(width: 20, height: 20)
                            .background(RoundedRectangle(cornerRadius: 4).fill(item.priority != .none ? item.priority.color.opacity(0.1) : Color.clear))
                    }
                    .fixedSize()

                    Divider().frame(height: 12).padding(.horizontal, 1)
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .transition(.opacity.animation(.easeInOut(duration: 0.1)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(rowHovered ? Color.primary.opacity(0.06) : Color.clear)
        )
        .onHover { rowHovered = $0 }   // single hover — no flicker
    }

    private func setReminder(at date: Date) {
        item.reminderDate = date
        onChange()

        guard notificationCenter != nil else {
            print("⚠️ Cannot schedule notification: Not in an app bundle.")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Task Reminder"
        content.body = item.content
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(identifier: item.id.uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private func removeReminder() {
        item.reminderDate = nil
        onChange()
        notificationCenter?.removePendingNotificationRequests(withIdentifiers: [item.id.uuidString])
    }
}

// MARK: - Format Toggle

struct FormatToggle: View {
    let icon: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: active ? .bold : .regular))
                .foregroundColor(active ? .blue : .secondary)
                .frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: 4)
                    .fill(active ? Color.blue.opacity(0.15) : Color.clear))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Visual Effect

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
