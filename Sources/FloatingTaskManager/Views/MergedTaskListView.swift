import SwiftUI

struct MergedTaskListView: View {
    @EnvironmentObject var store: TaskStore
    @EnvironmentObject var windowManager: WindowManager
    @AppStorage("baseFontSize") var baseFontSize: Double = 13.0
    @AppStorage("windowOpacity") var windowOpacity: Double = 0.95

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Merged Tasks")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
                Button(action: { windowManager.closeListWindow(for: windowManager.MERGED_LIST_ID) }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PremiumButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(VisualEffectView(material: .headerView, blendingMode: .withinWindow).opacity(0.5))

            Divider().opacity(0.1)

            // Items
            List {
                ForEach(orderedTasks) { task in
                    MergedTaskRow(task: task)
                }
                .onMove(perform: moveTasks)
            }
            .listStyle(PlainListStyle())
            .scrollContentBackground(.hidden)

            Divider().opacity(0.1)

            // Footer
            HStack {
                let allTasks = store.getAllTasks()
                let done = allTasks.filter(\.isCompleted).count
                let total = allTasks.count
                Text("\(done) of \(total) completed across all lists")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 320, minHeight: 400)
        .background(GlassBackground(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .containerShape(RoundedRectangle(cornerRadius: 16))
        .opacity(windowOpacity)
    }

    private var orderedTasks: [TaskItem] {
        let allTasks = store.getAllTasks().filter { !$0.isCompleted }
        let taskMap = Dictionary(uniqueKeysWithValues: allTasks.map { ($0.id, $0) })
        
        var sortedTasks: [TaskItem] = []
        
        // Add tasks that are in the order list
        for id in store.mergedTaskOrder {
            if let task = taskMap[id] {
                sortedTasks.append(task)
            }
        }
        
        // Add any remaining tasks that weren't in the order list
        let orderedIDs = Set(store.mergedTaskOrder)
        for task in allTasks {
            if !orderedIDs.contains(task.id) {
                sortedTasks.append(task)
            }
        }
        
        return sortedTasks
    }

    private func moveTasks(from source: IndexSet, to destination: Int) {
        var newOrder = orderedTasks.map { $0.id }
        newOrder.move(fromOffsets: source, toOffset: destination)
        store.mergedTaskOrder = newOrder
        store.save()
    }
}

struct MergedTaskRow: View {
    let task: TaskItem
    @EnvironmentObject var store: TaskStore
    @AppStorage("baseFontSize") var baseFontSize: Double = 13.0

    var body: some View {
        HStack(spacing: 10) {
            // Read-only checkbox (since it's a merged view, we could make it editable but let's keep it simple first)
            // Actually, user might want to toggle here too.
            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(task.isCompleted ? .blue : .secondary)
                .onTapGesture {
                    toggleTaskCompletion()
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(task.content)
                    .font(.system(size: baseFontSize, weight: task.isBold ? .bold : .medium, design: .rounded))
                    .strikethrough(task.isCompleted || task.isStrikethrough)
                    .italic(task.isItalic)
                    .foregroundColor(task.isCompleted ? .secondary : .primary)
                
                HStack(spacing: 6) {
                    // List Tag
                    if let list = store.lists.first(where: { $0.items.contains(where: { $0.id == task.id }) }) {
                        Text(list.title)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(list.color.swiftUIColor)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(list.color.swiftUIColor.opacity(0.1))
                            .cornerRadius(4)
                    }

                    // Priority Tag
                    if task.priority != .none {
                        Text(task.priority.title.uppercased())
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(task.priority.color.opacity(0.12))
                                    .overlay(Capsule().stroke(task.priority.color.opacity(0.2), lineWidth: 0.5))
                            )
                            .foregroundColor(task.priority.color)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }

    private func toggleTaskCompletion() {
        for i in 0..<store.lists.count {
            if let j = store.lists[i].items.firstIndex(where: { $0.id == task.id }) {
                store.lists[i].items[j].isCompleted.toggle()
                store.save()
                return
            }
        }
    }
}
