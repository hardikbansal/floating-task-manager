import SwiftUI
import AppKit
import UserNotifications

// MARK: - Task List View

struct TaskListView: View {
    @ObservedObject var list: TaskList
    @EnvironmentObject var store: TaskStore
    @EnvironmentObject var windowManager: WindowManager
    @AppStorage("baseFontSize") var baseFontSize: Double = 13.0
    @AppStorage("windowOpacity") var windowOpacity: Double = 0.95
    @AppStorage("enableShadows") var enableShadows: Bool = true
    @State private var newItemContent: String = ""
    @State private var showColorPicker = false

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ──────────────────────────────────────────────
            HStack(spacing: 12) {
                // Compact color swatch button
                Button(action: { showColorPicker.toggle() }) {
                    Circle()
                        .fill(list.color.swiftUIColor)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                        .shadow(color: list.color.swiftUIColor.opacity(0.3), radius: 4)
                }
                .buttonStyle(PremiumButtonStyle())
                .popover(isPresented: $showColorPicker, arrowEdge: .bottom) {
                    ColorSwatchPicker(selected: $list.color, onPick: { store.save() })
                }

                TextField("List Title", text: $list.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .textFieldStyle(PlainTextFieldStyle())
                    .onSubmit { store.save() }

                Spacer()

                HStack(spacing: 8) {
                    // Sort button
                    Button(action: { 
                        withAnimation(PremiumTheme.spring()) {
                            list.sortDescending.toggle()
                            list.sortItemsByPriority()
                            store.save() 
                        }
                    }) {
                        Image(systemName: list.sortDescending ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(list.color.swiftUIColor)
                    }
                    .buttonStyle(PremiumButtonStyle())
                    .help(list.sortDescending ? "Sort: High to Low" : "Sort: Low to High")

                    // Close button
                    Button(action: { windowManager.closeListWindow(for: list.id) }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PremiumButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                MeshGradientView(baseColor: list.color.swiftUIColor)
                    .opacity(0.15)
                    .overlay(VisualEffectView(material: .headerView, blendingMode: .withinWindow).opacity(0.5))
            )

            Divider().opacity(0.1)

            // ── Items ──
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 4) {
                    ForEach($list.items) { $item in
                        TaskItemRow(item: $item,
                                    onDelete: { 
                                        withAnimation(.spring()) {
                                            list.items.removeAll { $0.id == item.id }
                                            store.save()
                                        }
                                    },
                                    onChange:  { store.save() })
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 8)
            }

            Divider().opacity(0.1)

            // ── Add task row ────────────────────────────────────────
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .foregroundColor(list.color.swiftUIColor)
                    .font(.system(size: 14, weight: .bold))
                
                TextField("Add a task...", text: $newItemContent)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: baseFontSize, weight: .medium, design: .rounded))
                    .onSubmit { 
                        withAnimation(.spring()) {
                            addItem()
                        }
                    }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.02))

            Divider().opacity(0.1)

            // ── Footer ──────────────────────────────────────────────
            HStack {
                let done = list.items.filter(\.isCompleted).count
                let total = list.items.count
                Text(total == 0 ? "No tasks" : "\(done) of \(total) completed")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                Spacer()
                Text("⌘⇧N  New List")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 280, minHeight: 320)
        .background(GlassBackground(cornerRadius: 16))
        .containerShape(RoundedRectangle(cornerRadius: 16))
        .opacity(windowOpacity)
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
        HStack(alignment: .center, spacing: 10) {
            // Checkbox
            ModernCheckbox(isChecked: $item.isCompleted, color: .blue)
                .onChange(of: item.isCompleted) { newValue in
                    if newValue {
                        removeReminder()
                    }
                    onChange()
                }

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
                .font(.system(size: baseFontSize, weight: item.isBold ? .bold : .medium, design: .rounded))
                .italic(item.isItalic)
                .strikethrough(item.isCompleted || item.isStrikethrough, color: .secondary)
                .foregroundColor(item.isCompleted ? .secondary.opacity(0.6) : .primary)

            // Priority Tag
            if item.priority != .none {
                Text(item.priority.title.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(item.priority.color.opacity(0.12))
                            .overlay(Capsule().stroke(item.priority.color.opacity(0.2), lineWidth: 0.5))
                    )
                    .foregroundColor(item.priority.color)
            }

            // Format toolbar
            if rowHovered {
                HStack(spacing: 4) {
                    HStack(spacing: 2) {
                        FormatToggle(icon: "bold",           active: item.isBold)            { item.isBold.toggle();           onChange() }
                        FormatToggle(icon: "italic",         active: item.isItalic)          { item.isItalic.toggle();         onChange() }
                        FormatToggle(icon: "strikethrough",  active: item.isStrikethrough)   { item.isStrikethrough.toggle();  onChange() }
                    }
                    .padding(2)
                    .background(Capsule().fill(Color.primary.opacity(0.05)))
                    
                    Divider().frame(height: 12)

                    // Reminder Button
                    Button(action: { 
                        tempReminderDate = item.reminderDate ?? Date().addingTimeInterval(3600)
                        showReminderPicker.toggle() 
                    }) {
                        Image(systemName: item.reminderDate == nil ? "bell" : "bell.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(item.reminderDate == nil ? .secondary : .blue)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(item.reminderDate != nil ? Color.blue.opacity(0.1) : Color.clear))
                    }
                    .buttonStyle(PremiumButtonStyle())
                    .popover(isPresented: $showReminderPicker) {
                        VStack(spacing: 12) {
                            Text("Set Reminder")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                            
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
                        .padding(16)
                    }
                    
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
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(item.priority != .none ? item.priority.color.opacity(0.1) : Color.clear))
                    }
                    .fixedSize()

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundColor(.red.opacity(0.8))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(PremiumButtonStyle())
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(rowHovered ? Color.primary.opacity(0.04) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.primary.opacity(rowHovered ? 0.05 : 0), lineWidth: 0.5)
                )
        )
        .contentShape(Rectangle())
        .onHover { rowHovered = $0 }
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: rowHovered)
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
