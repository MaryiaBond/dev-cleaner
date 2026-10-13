import Foundation

struct CleanupReport: Sendable {
    let removed: Int
    let failures: [String]
}

enum CleanupService {
    private static let gradleAllowlist: [GradleCleanupTarget: String] = [
        .caches: "caches",
        .daemon: "daemon",
        .native: "native",
        .wrapperDists: "wrapper/dists",
        .temporary: ".tmp"
    ]

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

    static func cleanGradle(_ target: GradleCleanupTarget) -> CleanupReport {
        let manager = FileManager.default
        guard let relativePath = gradleAllowlist[target] else {
            return CleanupReport(removed: 0, failures: ["Цель не входит в allowlist Gradle"])
        }

        let gradleRoot = manager.homeDirectoryForCurrentUser
            .appendingPathComponent(".gradle", isDirectory: true)
            .standardizedFileURL
        let targetURL = gradleRoot
            .appendingPathComponent(relativePath, isDirectory: true)
            .standardizedFileURL

        guard targetURL.path != gradleRoot.path,
              targetURL.path.hasPrefix(gradleRoot.path + "/"),
              targetURL.path == URL(fileURLWithPath: target.path).standardizedFileURL.path else {
            return CleanupReport(removed: 0, failures: ["Неверный путь очистки Gradle"])
        }

        var current = manager.homeDirectoryForCurrentUser
        for component in [".gradle"] + relativePath.split(separator: "/").map(String.init) {
            current.appendPathComponent(component, isDirectory: true)

            let attributes: [FileAttributeKey: Any]
            do {
                attributes = try manager.attributesOfItem(atPath: current.path)
            } catch {
                return CleanupReport(
                    removed: 0,
                    failures: ["Не удалось проверить \(current.path): \(error.localizedDescription)"]
                )
            }
            guard (attributes[.type] as? FileAttributeType) != .typeSymbolicLink else {
                return CleanupReport(
                    removed: 0,
                    failures: ["Символические ссылки в пути очистки запрещены: \(current.path)"]
                )
            }
            guard (attributes[.type] as? FileAttributeType) == .typeDirectory else {
                return CleanupReport(
                    removed: 0,
                    failures: ["Путь очистки не является директорией: \(current.path)"]
                )
            }
        }

        guard targetURL.resolvingSymlinksInPath().standardizedFileURL.path == targetURL.path else {
            return CleanupReport(removed: 0, failures: ["Канонический путь цели не совпадает с allowlist"])
        }

        if let reason = gradleActivityBlockReason() {
            return CleanupReport(removed: 0, failures: [reason])
        }

        guard targetURL.resolvingSymlinksInPath().standardizedFileURL.path == targetURL.path else {
            return CleanupReport(removed: 0, failures: ["Путь цели изменился перед удалением. Очистка отменена."])
        }

        do {
            let children = try manager.contentsOfDirectory(
                at: targetURL,
                includingPropertiesForKeys: [.isSymbolicLinkKey],
                options: []
            )
            var removed = 0
            var failures: [String] = []

            for child in children {
                guard child.standardizedFileURL.path.hasPrefix(targetURL.path + "/") else {
                    failures.append("Пропущен элемент вне разрешённого пути: \(child.lastPathComponent)")
                    continue
                }

                do {
                    // removeItem удаляет саму символическую ссылку, не переходя к её цели.
                    try manager.removeItem(at: child)
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

    private static func gradleActivityBlockReason() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "command="]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard process.terminationStatus == 0,
                  let text = String(data: data, encoding: .utf8) else {
                return "Не удалось безопасно проверить активные процессы Gradle. Очистка отменена."
            }

            let markers = [
                "gradledaemon",
                "gradlewrappermain",
                "org.gradle.launcher.main",
                "/gradlew",
                " gradlew "
            ]
            let hasGradleProcess = text
                .split(separator: "\n")
                .map { $0.lowercased() }
                .contains { command in markers.contains { command.contains($0) } }

            if hasGradleProcess {
                return "Обнаружен активный процесс Gradle или Gradle Daemon. Завершите сборки и остановите daemon перед очисткой."
            }
            return nil
        } catch {
            return "Не удалось проверить активные процессы Gradle: \(error.localizedDescription). Очистка отменена."
        }
    }
}
