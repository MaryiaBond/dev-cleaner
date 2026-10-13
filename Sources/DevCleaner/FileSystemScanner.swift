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

            switch size(of: url) {
            case .success(let bytes):
                return StorageItem(category: category, bytes: bytes, note: nil)
            case .failure(let error):
                return StorageItem(category: category, bytes: nil, note: error.message)
            }
        }
    }

    static func diskUsage() -> DiskUsage? {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let total = attributes[.systemSize] as? NSNumber,
              let free = attributes[.systemFreeSize] as? NSNumber else { return nil }
        return DiskUsage(total: total.int64Value, free: free.int64Value)
    }


    static func scanChildren(of category: StorageCategory) -> ChildScanResult {
        let directory = URL(
            fileURLWithPath: category.path,
            isDirectory: true
        )

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) else {
            return .missing
        }
        guard isDirectory.boolValue else {
            return .failure("Путь не является директорией")
        }

        do {
            let values = try directory.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                return .failure("Символическая ссылка: сканирование запрещено")
            }
        } catch {
            return .failure(error.localizedDescription)
        }

        let urls: [URL]
        do {
            var contents = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: []
            )

            if category == .gradle {
                let wrapperDists = URL(
                    fileURLWithPath: GradleCleanupTarget.wrapperDists.path,
                    isDirectory: true
                )
                if FileManager.default.fileExists(atPath: wrapperDists.path) {
                    contents.append(wrapperDists)
                }
            }
            urls = contents
        } catch {
            return .failure(error.localizedDescription)
        }

        var children: [StorageChild] = []
        var warnings: [String] = []

        for url in urls {
            do {
                let values = try url.resourceValues(
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                )

                guard values.isSymbolicLink != true else {
                    warnings.append("\(url.lastPathComponent): символическая ссылка пропущена")
                    continue
                }

                switch size(of: url) {
                case .success(let bytes):
                    let name = url.path == GradleCleanupTarget.wrapperDists.path
                        ? GradleCleanupTarget.wrapperDists.relativePath
                        : url.lastPathComponent
                    children.append(StorageChild(
                        name: name,
                        path: url.path,
                        bytes: bytes,
                        isDirectory: values.isDirectory == true
                    ))
                case .failure(let error):
                    warnings.append("\(url.lastPathComponent): \(error.message)")
                }
            } catch {
                warnings.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        return .loaded(
            children.sorted { $0.bytes > $1.bytes },
            warnings: warnings
        )
    }

    private static func size(of url: URL) -> Result<Int64, ScanError> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-sk", url.path]

        // Один канал для stdout и stderr читается, пока процесс работает:
        // ни один из потоков вывода не может заполнить отдельный буфер и заблокировать du.
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard process.terminationStatus == 0 else {
                return .failure(ScanError(
                    message: text.isEmpty ? "du завершился с кодом \(process.terminationStatus)" : text
                ))
            }
            guard let first = text.split(whereSeparator: \.isWhitespace).first,
                  let kib = Int64(first) else {
                return .failure(ScanError(message: "Не удалось прочитать результат du"))
            }
            return .success(kib * 1024)
        } catch {
            return .failure(ScanError(message: error.localizedDescription))
        }
    }
}

struct ScanError: Error, Sendable {
    let message: String
}

enum ChildScanResult: Sendable {
    case loaded([StorageChild], warnings: [String])
    case missing
    case failure(String)
}
