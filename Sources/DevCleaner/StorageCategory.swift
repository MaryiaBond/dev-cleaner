import Foundation

enum StorageCategory: String, CaseIterable, Identifiable, Sendable {
    case derivedData = "Xcode DerivedData"
    case deviceSupport = "iOS DeviceSupport"
    case simulators = "iOS Simulators"
    case gradle = "Gradle"
    case android = "Android configuration"
    case androidSDK = "Android SDK"
    case macCaches = "macOS Caches"

    var id: String { rawValue }

    var path: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        switch self {
        case .derivedData: return home + "/Library/Developer/Xcode/DerivedData"
        case .deviceSupport: return home + "/Library/Developer/Xcode/iOS DeviceSupport"
        case .simulators: return home + "/Library/Developer/CoreSimulator"
        case .gradle: return home + "/.gradle"
        case .android: return home + "/.android"
        case .androidSDK: return home + "/Library/Android/sdk"
        case .macCaches: return home + "/Library/Caches"
        }
    }

    var detail: String {
        switch self {
        case .derivedData: return "Промежуточные файлы сборок Xcode"
        case .deviceSupport: return "Данные поддержки физических iPhone"
        case .simulators: return "Устройства и данные iOS Simulator — не удаляем"
        case .gradle: return "Кэши и зависимости сборок Android"
        case .android: return "Настройки Android и виртуальные устройства"
        case .androidSDK: return "Android SDK и инструменты сборки"
        case .macCaches: return "Кэши пользовательских приложений"
        }
    }

    var canClean: Bool { self == .derivedData }
}

enum GradleCleanupTarget: String, CaseIterable, Identifiable, Sendable {
    case caches
    case daemon
    case native
    case wrapperDists
    case temporary

    var id: String { rawValue }

    var relativePath: String {
        switch self {
        case .caches: return "caches"
        case .daemon: return "daemon"
        case .native: return "native"
        case .wrapperDists: return "wrapper/dists"
        case .temporary: return ".tmp"
        }
    }

    var title: String {
        switch self {
        case .caches: return "Gradle caches"
        case .daemon: return "Gradle daemon"
        case .native: return "Gradle native"
        case .wrapperDists: return "Gradle wrapper distributions"
        case .temporary: return "Gradle temporary files"
        }
    }

    var consequence: String {
        switch self {
        case .caches:
            return "Зависимости и артефакты могут скачиваться и собираться заново."
        case .daemon:
            return "Gradle создаст данные daemon заново при следующем запуске."
        case .native:
            return "Нативные компоненты Gradle могут быть распакованы заново."
        case .wrapperDists:
            return "Дистрибутивы Gradle будут скачаны заново при следующей сборке."
        case .temporary:
            return "Временные файлы Gradle будут созданы заново при необходимости."
        }
    }

    var path: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gradle", isDirectory: true)
            .appendingPathComponent(relativePath, isDirectory: true)
            .path
    }
}

struct StorageItem: Identifiable, Sendable {
    let category: StorageCategory
    let bytes: Int64?
    let note: String?
    var id: String { category.id }
}

struct DiskUsage: Sendable {
    let total: Int64
    let free: Int64
    var used: Int64 { max(0, total - free) }
}

enum ReactNativeProjectType: String, Sendable {
    case expoWithNative = "Expo с native-директориями"
    case expoManaged = "Expo без native-директорий"
    case reactNativeCLI = "React Native CLI"
}

enum ProjectStorageKind: String, Sendable {
    case dependencies = "Зависимости"
    case androidBuild = "Результаты Android-сборки"
    case androidGradle = "Локальные данные Gradle проекта"
    case iosBuild = "Результаты iOS-сборки"
    case cocoaPods = "Зависимости CocoaPods"
    case expo = "Локальные данные Expo"
    case git = "История Git — только анализ"
    case gitWorktreeMetadata = "Метаданные Git worktree — только анализ"
}

struct ProjectStorageEntry: Identifiable, Sendable {
    let relativePath: String
    let path: String
    let kind: ProjectStorageKind
    let bytes: Int64?
    let error: String?

    var id: String { path }
}

struct GitWorktreeInfo: Sendable {
    let mainRepositoryPath: String?
}

struct ReactNativeProject: Identifiable, Sendable {
    let name: String
    let path: String
    let type: ReactNativeProjectType
    let isBackup: Bool
    let worktree: GitWorktreeInfo?
    let totalBytes: Int64?
    let storage: [ProjectStorageEntry]
    let warnings: [String]

    var id: String { path }
}

enum ReactNativeProjectsState: Sendable {
    case idle
    case loading
    case loaded([ReactNativeProject], warnings: [String])
    case failure(String)
}
