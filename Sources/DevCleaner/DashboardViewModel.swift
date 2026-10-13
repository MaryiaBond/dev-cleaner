import Foundation
import AppKit

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var items: [StorageItem] = []
    @Published private(set) var disk: DiskUsage?
    @Published private(set) var isBusy = false
    @Published private(set) var log: [String] = []
    @Published private(set) var children: [StorageCategory: [StorageChild]] = [:]
    @Published private(set) var loadingChildren: Set<StorageCategory> = []

    func scan() async {
        guard !isBusy else { return }
        isBusy = true
        log.append("Запущено сканирование…")
        let result = await Task.detached(priority: .userInitiated) {
            (FileSystemScanner.scan(), FileSystemScanner.diskUsage())
        }.value
        items = result.0
        disk = result.1
        log.append("Сканирование завершено")
        isBusy = false
    }

    func cleanDerivedData() async {
        guard !isBusy else { return }
        isBusy = true
        log.append("Очистка DerivedData…")
        let report = await Task.detached(priority: .userInitiated) {
            CleanupService.cleanDerivedData()
        }.value
        log.append("Удалено объектов: \(report.removed)")
        for error in report.failures { log.append("Ошибка: \(error)") }
        isBusy = false
        await scan()
    }

    func reveal(_ category: StorageCategory) {
        let url = URL(fileURLWithPath: category.path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }


    func loadChildren(for category: StorageCategory) async {
        guard children[category] == nil,
            !loadingChildren.contains(category) else {
            return
        }

        loadingChildren.insert(category)

        let result = await Task.detached(priority: .userInitiated) {
            FileSystemScanner.scanChildren(of: category)
        }.value

        children[category] = result
        loadingChildren.remove(category)
    }
}
