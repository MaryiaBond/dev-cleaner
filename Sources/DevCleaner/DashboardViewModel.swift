import Foundation
import AppKit

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var items: [StorageItem] = []
    @Published private(set) var disk: DiskUsage?
    @Published private(set) var isBusy = false
    @Published private(set) var log: [String] = []
    @Published private(set) var children: [StorageCategory: ChildScanResult] = [:]
    @Published private(set) var loadingChildren: Set<StorageCategory> = []
    private var scanGeneration = 0

    func scan(reloading requestedCategories: Set<StorageCategory> = []) async {
        guard !isBusy else { return }
        let categoriesToReload = requestedCategories
            .union(children.keys)
            .union(loadingChildren)
        invalidateChildScans()
        let generation = scanGeneration

        isBusy = true
        log.append("Запущено сканирование…")
        let result = await Task.detached(priority: .userInitiated) {
            (FileSystemScanner.scan(), FileSystemScanner.diskUsage())
        }.value

        guard generation == scanGeneration else { return }
        items = result.0
        disk = result.1
        log.append("Сканирование завершено")
        isBusy = false

        for category in categoriesToReload {
            await loadChildren(for: category)
        }
    }

    func cleanDerivedData() async {
        guard !isBusy else { return }
        let categoriesToReload = Set(children.keys).union(loadingChildren)
        invalidateChildScans()
        isBusy = true
        log.append("Очистка DerivedData…")
        let report = await Task.detached(priority: .userInitiated) {
            CleanupService.cleanDerivedData()
        }.value
        log.append("Удалено объектов: \(report.removed)")
        for error in report.failures { log.append("Ошибка: \(error)") }
        isBusy = false
        await scan(reloading: categoriesToReload)
    }

    func cleanGradle(_ target: GradleCleanupTarget) async {
        guard !isBusy else { return }
        let categoriesToReload = Set(children.keys).union(loadingChildren)
        invalidateChildScans()
        isBusy = true
        log.append("Очистка \(target.title): \(target.path)")

        let report = await Task.detached(priority: .userInitiated) {
            CleanupService.cleanGradle(target)
        }.value

        log.append("Удалено объектов: \(report.removed)")
        for error in report.failures { log.append("Ошибка: \(error)") }
        isBusy = false
        await scan(reloading: categoriesToReload.union([.gradle]))
    }

    func reveal(_ category: StorageCategory) {
        let url = URL(fileURLWithPath: category.path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }


    func loadChildren(for category: StorageCategory) async {
        guard !isBusy,
            children[category] == nil,
            !loadingChildren.contains(category) else {
            return
        }

        let generation = scanGeneration
        loadingChildren.insert(category)

        let result = await Task.detached(priority: .userInitiated) {
            FileSystemScanner.scanChildren(of: category)
        }.value

        guard generation == scanGeneration else { return }
        children[category] = result
        loadingChildren.remove(category)
    }

    private func invalidateChildScans() {
        scanGeneration += 1
        children.removeAll()
        loadingChildren.removeAll()
    }
}
