import SwiftUI
import Combine

class TaskStore: ObservableObject {
    @Published var lists: [TaskList] = []

    private let savePath: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        savePath = appSupport
            .appendingPathComponent("FloatingTaskManager")
            .appendingPathComponent("tasks.json")

        try? FileManager.default.createDirectory(
            at: savePath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        load()
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(lists)
            try data.write(to: savePath)
        } catch {
            print("Failed to save tasks: \(error)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: savePath.path) else { return }
        do {
            let data = try Data(contentsOf: savePath)
            lists = try JSONDecoder().decode([TaskList].self, from: data)
        } catch {
            print("Failed to load tasks: \(error)")
        }
    }

    func createNewList() {
        let newList = TaskList(title: "New List")
        lists.append(newList)
        save()
    }

    func deleteList(_ list: TaskList) {
        lists.removeAll { $0.id == list.id }
        save()
    }
}
