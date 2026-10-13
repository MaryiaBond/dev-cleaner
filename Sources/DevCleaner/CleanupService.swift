import Foundation

struct CleanupReport: Sendable {
    let removed: Int
    let failures: [String]
}

enum CleanupService {
    static func cleanDerivedData() -> CleanupReport {
        let manager = FileManager.default
        let target = StorageCategory.derivedData.path
        let expected = manager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Developer/Xcode/DerivedData").path

        // Allowlist: ни один пользовательский путь не может быть подставлен сюда.
        guard URL(fileURLWithPath: target).standardizedFileURL.path == URL(fileURLWithPath: expected).standardizedFileURL.path else {
            return CleanupReport(removed: 0, failures: ["Неверный путь очистки"])
        }

        var isDir: ObjCBool = false
        guard manager.fileExists(atPath: target, isDirectory: &isDir) else {
            return CleanupReport(removed: 0, failures: [])
        }
        guard isDir.boolValue,
              let attributes = try? manager.attributesOfItem(atPath: target),
              (attributes[.type] as? FileAttributeType) == .typeDirectory else {
            return CleanupReport(removed: 0, failures: ["Целевая папка не является обычной директорией"])
        }

        do {
            let children = try manager.contentsOfDirectory(at: URL(fileURLWithPath: target), includingPropertiesForKeys: nil, options: [])
            var removed = 0
            var failures: [String] = []
            for child in children {
                do {
                    try manager.removeItem(at: child) // Символическая ссылка удаляется сама, без перехода по ней.
                    removed += 1
                } catch {
                    failures.append("\(child.lastPathComponent): \(error.localizedDescription)")
                }
            }
            return CleanupReport(removed: removed, failures: failures)
        } catch {
            return CleanupReport(removed: 0, failures: [error.localizedDescription])
        }
    }
}
