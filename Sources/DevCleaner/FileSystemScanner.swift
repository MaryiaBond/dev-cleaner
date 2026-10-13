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

    static func scanReactNativeProjects(maximumDepth: Int = 5) -> ReactNativeProjectScanResult {
        let documents = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: documents.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return .failure("Папка ~/Documents не найдена")
        }

        do {
            let values = try documents.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                return .failure("~/Documents является символической ссылкой: поиск остановлен")
            }
        } catch {
            return .failure(error.localizedDescription)
        }

        let skippedDirectoryNames: Set<String> = [
            "node_modules", ".git", "pods", "build", ".gradle", ".expo",
            ".next", ".nuxt", "dist", "coverage", ".turbo", ".cache",
            ".yarn", ".pnpm-store", ".parcel-cache", ".metro-cache",
            "deriveddata", "carthage", "vendor"
        ]
        var projects: [ReactNativeProject] = []
        var warnings: [String] = []

        func visit(_ directory: URL, depth: Int) {
            switch reactNativeProject(at: directory) {
            case .success(let project):
                if let project { projects.append(project) }
            case .failure(let error):
                warnings.append("\(directory.path): \(error.message)")
            }

            guard depth < maximumDepth else { return }

            let contents: [URL]
            do {
                contents = try FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                    options: []
                )
            } catch {
                warnings.append("\(directory.path): \(error.localizedDescription)")
                return
            }

            for child in contents {
                do {
                    let values = try child.resourceValues(
                        forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                    )
                    guard values.isDirectory == true,
                          values.isSymbolicLink != true,
                          !skippedDirectoryNames.contains(child.lastPathComponent.lowercased()),
                          !isDependencyArchiveDirectoryName(child.lastPathComponent) else {
                        continue
                    }
                    visit(child, depth: depth + 1)
                } catch {
                    warnings.append("\(child.path): \(error.localizedDescription)")
                }
            }
        }

        visit(documents, depth: 0)
        projects.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return .success(projects, warnings: warnings)
    }

    private static func reactNativeProject(
        at directory: URL
    ) -> Result<ReactNativeProject?, ScanError> {
        let manifestURL = directory.appendingPathComponent("package.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return .success(nil)
        }

        do {
            let values = try manifestURL.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            )
            guard values.isSymbolicLink != true else {
                return .failure(ScanError(message: "package.json является символической ссылкой"))
            }
            guard values.isRegularFile == true else {
                return .failure(ScanError(message: "package.json не является обычным файлом"))
            }
            guard (values.fileSize ?? 0) <= 5_000_000 else {
                return .failure(ScanError(message: "package.json слишком большой для безопасного анализа"))
            }

            let manifest = try JSONDecoder().decode(
                PackageManifest.self,
                from: Data(contentsOf: manifestURL)
            )
            let dependencyNames = Set(
                [
                    manifest.dependencies,
                    manifest.devDependencies,
                    manifest.optionalDependencies
                ]
                .compactMap { $0 }
                .flatMap(\.keys)
            )

            let hasExpo = dependencyNames.contains("expo")
            let hasReactNative = dependencyNames.contains("react-native")
            guard hasExpo || hasReactNative else {
                return .success(nil)
            }

            let hasExpoConfiguration = [
                "app.json", "app.config.js", "app.config.ts",
                "app.config.mjs", "app.config.cjs"
            ].contains { name in
                isRegularFile(directory.appendingPathComponent(name))
            }
            let hasNativeApplicationTarget = hasAndroidApplicationTarget(in: directory)
                || hasIOSApplicationTarget(in: directory)
            let hasApplicationEntry = hasApplicationEntry(
                in: directory,
                manifestMain: manifest.main
            )
            let hasApplicationLaunchScript = manifest.scripts?.contains { name, command in
                isApplicationLaunchScript(name: name, command: command)
            } == true

            guard hasExpoConfiguration
                    || hasNativeApplicationTarget
                    || (hasApplicationEntry && hasApplicationLaunchScript) else {
                return .success(nil)
            }

            let type: ReactNativeProjectType
            if hasExpo {
                let hasNativeDirectories = ["android", "ios"].contains { name in
                    isRegularDirectory(
                        directory.appendingPathComponent(name, isDirectory: true)
                    )
                }
                type = hasNativeDirectories ? .expoWithNative : .expoManaged
            } else {
                type = .reactNativeCLI
            }

            let projectName = manifest.name.flatMap { $0.isEmpty ? nil : $0 }
                ?? directory.lastPathComponent
            let worktree = gitWorktreeInfo(at: directory)
            return .success(analyzeProject(
                at: directory,
                name: projectName,
                type: type,
                isBackup: worktree == nil
                    && isBackupProjectDirectoryName(directory.lastPathComponent),
                worktree: worktree
            ))
        } catch {
            return .failure(ScanError(message: error.localizedDescription))
        }
    }

    private static func analyzeProject(
        at directory: URL,
        name: String,
        type: ReactNativeProjectType,
        isBackup: Bool,
        worktree: GitWorktreeInfo?
    ) -> ReactNativeProject {
        let descriptors: [(String, ProjectStorageKind)] = [
            ("node_modules", .dependencies),
            ("android/build", .androidBuild),
            ("android/app/build", .androidBuild),
            ("android/.gradle", .androidGradle),
            ("ios/build", .iosBuild),
            ("ios/Pods", .cocoaPods),
            (".expo", .expo),
            (".git", worktree == nil ? .git : .gitWorktreeMetadata)
        ]
        var warnings: [String] = []
        let totalBytes: Int64?

        switch size(of: directory) {
        case .success(let bytes):
            totalBytes = bytes
        case .failure(let error):
            totalBytes = nil
            warnings.append("Общий размер: \(error.message)")
        }

        let storage = descriptors.compactMap { relativePath, kind -> ProjectStorageEntry? in
            let url = directory.appendingPathComponent(relativePath, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                return nil
            }

            do {
                let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
                guard values.isSymbolicLink != true else {
                    return ProjectStorageEntry(
                        relativePath: relativePath,
                        path: url.path,
                        kind: kind,
                        bytes: nil,
                        error: "Символическая ссылка: пропущено"
                    )
                }
                let isWorktreeMetadataFile = worktree != nil
                    && relativePath == ".git"
                    && !isDirectory.boolValue
                guard isDirectory.boolValue || isWorktreeMetadataFile else {
                    return ProjectStorageEntry(
                        relativePath: relativePath,
                        path: url.path,
                        kind: kind,
                        bytes: nil,
                        error: "Путь не является директорией"
                    )
                }
            } catch {
                return ProjectStorageEntry(
                    relativePath: relativePath,
                    path: url.path,
                    kind: kind,
                    bytes: nil,
                    error: error.localizedDescription
                )
            }

            switch size(of: url) {
            case .success(let bytes):
                return ProjectStorageEntry(
                    relativePath: relativePath,
                    path: url.path,
                    kind: kind,
                    bytes: bytes,
                    error: nil
                )
            case .failure(let error):
                return ProjectStorageEntry(
                    relativePath: relativePath,
                    path: url.path,
                    kind: kind,
                    bytes: nil,
                    error: error.message
                )
            }
        }

        return ReactNativeProject(
            name: name,
            path: directory.path,
            type: type,
            isBackup: isBackup,
            worktree: worktree,
            totalBytes: totalBytes,
            storage: storage,
            warnings: warnings
        )
    }

    private static func isRegularDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]) else {
            return false
        }
        return values.isSymbolicLink != true
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path),
              let values = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
              ) else {
            return false
        }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    private static func hasAndroidApplicationTarget(in directory: URL) -> Bool {
        let app = directory.appendingPathComponent("android/app", isDirectory: true)
        let hasBuildFile = ["build.gradle", "build.gradle.kts"].contains { name in
            isRegularFile(app.appendingPathComponent(name))
        }
        let manifest = app.appendingPathComponent("src/main/AndroidManifest.xml")
        return hasBuildFile && isRegularFile(manifest)
    }

    private static func hasIOSApplicationTarget(in directory: URL) -> Bool {
        let ios = directory.appendingPathComponent("ios", isDirectory: true)
        guard isRegularDirectory(ios),
              let contents = try? FileManager.default.contentsOfDirectory(
                at: ios,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: []
              ) else {
            return false
        }

        return contents.contains { url in
            url.pathExtension.lowercased() == "xcodeproj" && isRegularDirectory(url)
        }
    }

    private static func hasApplicationEntry(
        in directory: URL,
        manifestMain: String?
    ) -> Bool {
        let files = [
            "App.js", "App.jsx", "App.ts", "App.tsx",
            "index.js", "index.jsx", "index.ts", "index.tsx"
        ]
        if files.contains(where: { isRegularFile(directory.appendingPathComponent($0)) }) {
            return true
        }

        if ["app", "src/app"].contains(where: {
            isRegularDirectory(directory.appendingPathComponent($0, isDirectory: true))
        }) {
            return true
        }

        guard let manifestMain else { return false }
        let main = manifestMain
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "./"))
        return main == "expo-router/entry"
            || ["index.js", "index.jsx", "index.ts", "index.tsx"].contains(main)
    }

    private static func isApplicationLaunchScript(name: String, command: String) -> Bool {
        let scriptName = name.lowercased()
        let script = command.lowercased()
        let isAppCommand = script.contains("expo start")
            || script.contains("expo run:")
            || script.contains("react-native start")
            || script.contains("react-native run-")
        let isLaunchName = ["start", "android", "ios"].contains(scriptName)
        return isAppCommand || (isLaunchName && (script.contains("expo") || script.contains("react-native")))
    }

    private static func isDependencyArchiveDirectoryName(_ name: String) -> Bool {
        let normalized = name
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return normalized.contains("node_modules")
            || normalized.contains("nodemodules")
    }

    private static func isBackupProjectDirectoryName(_ name: String) -> Bool {
        let markers: Set<String> = ["backup", "bak", "copy", "old", "archive"]
        let tokens = Set(
            name.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )
        return !markers.isDisjoint(with: tokens)
    }

    private static func gitWorktreeInfo(at directory: URL) -> GitWorktreeInfo? {
        let dotGit = directory.appendingPathComponent(".git")
        guard let dotGitLine = readGitMetadataFile(dotGit),
              dotGitLine.hasPrefix("gitdir:") else {
            return nil
        }

        let rawGitDirectory = String(dotGitLine.dropFirst("gitdir:".count))
            .trimmingCharacters(in: .whitespaces)
        guard !rawGitDirectory.isEmpty else { return nil }

        let gitDirectory = resolveGitPath(rawGitDirectory, relativeTo: directory)
        guard isRegularDirectory(gitDirectory),
              isRegularFile(gitDirectory.appendingPathComponent("HEAD")),
              let backlink = readGitMetadataFile(
                gitDirectory.appendingPathComponent("gitdir")
              ),
              resolveGitPath(backlink, relativeTo: gitDirectory).path == dotGit.standardizedFileURL.path,
              let rawCommonDirectory = readGitMetadataFile(
                gitDirectory.appendingPathComponent("commondir")
              ) else {
            return nil
        }

        let commonDirectory = resolveGitPath(
            rawCommonDirectory,
            relativeTo: gitDirectory
        )
        let worktreesDirectory = commonDirectory
            .appendingPathComponent("worktrees", isDirectory: true)
            .standardizedFileURL.path + "/"
        guard isRegularDirectory(commonDirectory),
              gitDirectory.standardizedFileURL.path.hasPrefix(worktreesDirectory) else {
            return nil
        }

        let mainRepositoryPath: String?
        if commonDirectory.lastPathComponent == ".git" {
            mainRepositoryPath = commonDirectory.deletingLastPathComponent().path
        } else {
            mainRepositoryPath = nil
        }
        return GitWorktreeInfo(mainRepositoryPath: mainRepositoryPath)
    }

    private static func readGitMetadataFile(_ url: URL) -> String? {
        guard let values = try? url.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        ),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              (values.fileSize ?? 0) <= 65_536,
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8),
              let firstLine = text.split(whereSeparator: \.isNewline).first else {
            return nil
        }
        return String(firstLine).trimmingCharacters(in: .whitespaces)
    }

    private static func resolveGitPath(_ path: String, relativeTo directory: URL) -> URL {
        if NSString(string: path).isAbsolutePath {
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        return directory.appendingPathComponent(path).standardizedFileURL
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

enum ReactNativeProjectScanResult: Sendable {
    case success([ReactNativeProject], warnings: [String])
    case failure(String)
}

private struct PackageManifest: Decodable {
    let name: String?
    let main: String?
    let scripts: [String: String]?
    let dependencies: [String: String]?
    let devDependencies: [String: String]?
    let optionalDependencies: [String: String]?
}
