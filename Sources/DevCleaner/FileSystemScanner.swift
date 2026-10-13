import Foundation

enum FileSystemScanner {
    static func scan() -> [StorageItem] {
        StorageCategory.allCases.map { category in
            let url = URL(fileURLWithPath: category.path)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return StorageItem(category: category, bytes: nil, note: "Папка не найдена")
            }

            // Не переходим по ссылкам на другие директории.
            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
               (attributes[.type] as? FileAttributeType) == .typeSymbolicLink {
                return StorageItem(category: category, bytes: nil, note: "Символическая ссылка: пропущено")
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
            process.arguments = ["-sk", url.path]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0,
                      let output = String(data: data, encoding: .utf8),
                      let first = output.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).first,
                      let kib = Int64(first) else {
                    return StorageItem(category: category, bytes: nil, note: "Ошибка чтения или недостаточно прав")
                }
                return StorageItem(category: category, bytes: kib * 1024, note: nil)
            } catch {
                return StorageItem(category: category, bytes: nil, note: error.localizedDescription)
            }
        }
    }

    static func diskUsage() -> DiskUsage? {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let total = attributes[.systemSize] as? NSNumber,
              let free = attributes[.systemFreeSize] as? NSNumber else { return nil }
        return DiskUsage(total: total.int64Value, free: free.int64Value)
    }


    static func scanChildren(of category: StorageCategory) -> [StorageChild] {
        let directory = URL(
            fileURLWithPath: category.path,
            isDirectory: true
        )

        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: []
        ) else {
            return []
        }

        return urls.compactMap { url -> StorageChild? in
            let values = try? url.resourceValues(
                forKeys: [.isSymbolicLinkKey]
            )

            guard values?.isSymbolicLink != true else {
                return nil
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
            process.arguments = ["-sk", url.path]

            let output = Pipe()
            process.standardOutput = output
            process.standardError = Pipe()

            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                guard process.terminationStatus == 0,
                    let text = String(data: data, encoding: .utf8),
                    let first = text.split(whereSeparator: \.isWhitespace).first,
                    let kib = Int64(first) else {
                    return nil
                }

                return StorageChild(
                    name: url.lastPathComponent,
                    path: url.path,
                    bytes: kib * 1024
                )
            } catch {
                return nil
            }
        }
        .sorted { $0.bytes > $1.bytes }
    }
}
