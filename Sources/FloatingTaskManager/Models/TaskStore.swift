import SwiftUI
import Combine
import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

class TaskStore: ObservableObject {
    @Published var lists: [TaskList] = []
    @Published var mergedTaskOrder: [UUID] = []
    @Published var mergedListPosition: CGPoint = .zero
    @Published var mergedListSize: CGSize = CGSize(width: 350, height: 500)

    private var cancellables = Set<AnyCancellable>()

    private let savePath: URL

    init() {
        let fileManager = FileManager.default
        let localPath = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FloatingTaskManager")
            .appendingPathComponent("tasks.json")

        // Try to find iCloud container
        if let icloudURL = fileManager.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents")
            .appendingPathComponent("tasks.json") {
            
            savePath = icloudURL
            print("☁️ Using iCloud storage: \(savePath.path)")
            
            // Ensure Documents directory exists in iCloud
            try? fileManager.createDirectory(at: icloudURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            
            // If local file exists but iCloud doesn't, migrate it
            if fileManager.fileExists(atPath: localPath.path) && !fileManager.fileExists(atPath: icloudURL.path) {
                print("📦 Migrating local data to iCloud...")
                try? fileManager.copyItem(at: localPath, to: icloudURL)
            }
        } else {
            savePath = localPath
            print("💾 Using local storage: \(savePath.path)")
        }

        try? fileManager.createDirectory(
            at: savePath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        load()
        setupObservers()
        setupFilePresenter()
    }

    private func setupFilePresenter() {
        // Simple polling for now or use NSFilePresenter for more robust sync.
        // For simplicity, we'll reload when the app becomes active or on a timer if needed.
        #if os(macOS)
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.load()
        }
        #else
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.load()
        }
        #endif
    }

    private func setupObservers() {
        cancellables.removeAll()
        for list in lists {
            list.objectWillChange
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &cancellables)
        }
    }

    func save() {
        do {
            let wrapper = StoreWrapper(
                lists: lists, 
                mergedTaskOrder: mergedTaskOrder,
                mergedListPosition: mergedListPosition,
                mergedListSize: mergedListSize
            )
            let data = try JSONEncoder().encode(wrapper)
            try data.write(to: savePath)
        } catch {
            print("Failed to save tasks: \(error)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: savePath.path) else { return }
        do {
            let data = try Data(contentsOf: savePath)
            if let wrapper = try? JSONDecoder().decode(StoreWrapper.self, from: data) {
                lists = wrapper.lists
                mergedTaskOrder = wrapper.mergedTaskOrder
                mergedListPosition = wrapper.mergedListPosition ?? .zero
                mergedListSize = wrapper.mergedListSize ?? CGSize(width: 350, height: 500)
                setupObservers()
            } else {
                // Fallback for old format
                lists = try JSONDecoder().decode([TaskList].self, from: data)
            }
        } catch {
            print("Failed to load tasks: \(error)")
        }
    }

    func createNewList() {
        let newList = TaskList(title: "New List")
        lists.append(newList)
        setupObservers()
        save()
    }

    func deleteList(_ list: TaskList) {
        lists.removeAll { $0.id == list.id }
        setupObservers()
        save()
    }

    func getAllTasks() -> [TaskItem] {
        lists.flatMap { $0.items }
    }
}

struct StoreWrapper: Codable {
    var lists: [TaskList]
    var mergedTaskOrder: [UUID]
    var mergedListPosition: CGPoint?
    var mergedListSize: CGSize?
}
