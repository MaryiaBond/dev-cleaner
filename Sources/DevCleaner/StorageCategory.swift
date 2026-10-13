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
