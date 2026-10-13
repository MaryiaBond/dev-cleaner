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
    @Published private(set) var reactNativeProjects: ReactNativeProjectsState = .idle
    private var scanGeneration = 0
    private var projectScanGeneration = 0

    var isLoadingProjects: Bool {
        if case .loading = reactNativeProjects { return true }
        return false
    }

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

    func scanReactNativeProjects() async {
        guard !isLoadingProjects else { return }
        projectScanGeneration += 1
        let generation = projectScanGeneration
        reactNativeProjects = .loading
        log.append("Поиск React Native / Expo-проектов…")

        let result = await Task.detached(priority: .userInitiated) {
            FileSystemScanner.scanReactNativeProjects()
        }.value

        guard generation == projectScanGeneration else { return }
        switch result {
        case .success(let projects, let warnings):
            reactNativeProjects = .loaded(projects, warnings: warnings)
            log.append("Найдено React Native / Expo-проектов: \(projects.count)")
            for warning in warnings {
                log.append("Предупреждение поиска проектов: \(warning)")
            }
        case .failure(let message):
            reactNativeProjects = .failure(message)
            log.append("Ошибка поиска проектов: \(message)")
        }
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
