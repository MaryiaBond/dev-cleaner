import SwiftUI
import AppKit

struct DashboardView: View {
    @ObservedObject var model: DashboardViewModel
    @State private var showCleanConfirmation = false
    @State private var expandedCategories: Set<StorageCategory> = []
    @State private var pendingGradleCleanup: PendingGradleCleanup?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DevCleaner").font(.largeTitle.bold())
                    Text("Место на диске, Xcode и Android — в одном окне")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await model.scan() }
                    Task { await model.scanReactNativeProjects() }
                } label: {
                    Label("Сканировать", systemImage: "arrow.clockwise")
                }
                .disabled(model.isBusy || model.isLoadingProjects)
                .buttonStyle(.borderedProminent)
            }

            if let disk = model.disk {
                HStack(spacing: 12) {
                    statistic("Общий объём", bytes: disk.total, symbol: "internaldrive")
                    statistic("Занято", bytes: disk.used, symbol: "externaldrive.fill")
                    statistic("Свободно", bytes: disk.free, symbol: "checkmark.circle")
                }
            }

            HStack {
                Text("Кэши и инструменты").font(.title3.bold())
                Spacer()
                if model.isBusy || model.isLoadingProjects {
                    ProgressView().controlSize(.small)
                }
            }


        List {
            ForEach(model.items) { item in
                DisclosureGroup(
                isExpanded: Binding(
                    get: {
                        expandedCategories.contains(item.category)
                    },
                    set: { isExpanded in
                        if isExpanded {
                            expandedCategories.insert(item.category)

                            Task {
                                await model.loadChildren(
                                    for: item.category
                                )
                            }
                        } else {
                            expandedCategories.remove(item.category)
                        }
                    }
                )
                ) {
                if model.loadingChildren.contains(item.category) {
                    ProgressView("Анализ папок...")
                        .padding(.vertical, 8)
                } else if let result = model.children[item.category] {
                    switch result {
                    case .loaded(let children, let warnings):
                        ForEach(children) { child in
                            HStack(spacing: 10) {
                                Image(systemName: child.isDirectory ? "folder" : "doc")
                                    .foregroundStyle(.secondary)
                                    .frame(width: DashboardRowLayout.childIconWidth)

                                Text(child.name)
                                    .font(.subheadline)

                                Spacer()

                                Text(Self.format(child.bytes))
                                    .font(.subheadline.monospacedDigit())

                                Button {
                                    NSWorkspace.shared.activateFileViewerSelecting([
                                        URL(fileURLWithPath: child.path)
                                    ])
                                } label: {
                                    Image(systemName: "arrow.up.forward.square")
                                }
                                .buttonStyle(.borderless)
                                .help("Показать в Finder")

                                if item.category == .gradle,
                                   child.isDirectory,
                                   let target = Self.gradleTarget(for: child) {
                                    Button("Очистить", role: .destructive) {
                                        pendingGradleCleanup = PendingGradleCleanup(
                                            target: target,
                                            bytes: child.bytes
                                        )
                                    }
                                    .disabled(model.isBusy || child.bytes == 0)
                                }
                            }
                            .padding(.vertical, 3)
                        }

                        if children.isEmpty && warnings.isEmpty {
                            Text("Папка пуста")
                                .foregroundStyle(.secondary)
                        }

                        ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                            Label(warning, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    case .missing:
                        Text("Папка не найдена")
                            .foregroundStyle(.secondary)
                    case .failure(let message):
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                } label: {
                HStack(spacing: 12) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(
                            item.category.canClean ? Color.blue : Color.secondary
                        )
                        .frame(
                            width: DashboardRowLayout.categoryIconWidth,
                            height: DashboardRowLayout.iconSize
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.category.rawValue)
                            .font(.headline)

                        Text(item.category.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(item.category.path)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        if let bytes = item.bytes {
                            Text(Self.format(bytes))
                                .font(.headline.monospacedDigit())
                        } else {
                            Text(item.note ?? "—")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 8) {
                            Button("Finder") {
                                model.reveal(item.category)
                            }
                            .disabled(item.bytes == nil)

                            if item.category.canClean {
                                Button("Очистить", role: .destructive) {
                                    showCleanConfirmation = true
                                }
                                .disabled(
                                    model.isBusy ||
                                    item.bytes == nil ||
                                    item.bytes == 0
                                )
                            }
                        }
                    }
                }
                .padding(.vertical, 5)
                }
                .disclosureGroupStyle(AlignedDisclosureGroupStyle())
            }

            reactNativeProjectsSection
        }
        .listStyle(.inset)


            DisclosureGroup("Журнал операций") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(model.log.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(8)
                }
                .frame(height: 88)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(22)
        .confirmationDialog("Очистить Xcode DerivedData?", isPresented: $showCleanConfirmation, titleVisibility: .visible) {
            Button("Удалить содержимое DerivedData", role: .destructive) {
                Task { await model.cleanDerivedData() }
            }
        } message: {
            Text("Будет очищена только папка ~/Library/Developer/Xcode/DerivedData. Следующая сборка Xcode может занять больше времени. Закрой активные сборки перед очисткой.")
        }
        .confirmationDialog(
            pendingGradleCleanup.map { "Очистить \($0.target.title)?" } ?? "Очистить Gradle?",
            isPresented: Binding(
                get: { pendingGradleCleanup != nil },
                set: { if !$0 { pendingGradleCleanup = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingGradleCleanup
        ) { cleanup in
            Button("Удалить содержимое", role: .destructive) {
                pendingGradleCleanup = nil
                Task { await model.cleanGradle(cleanup.target) }
            }
        } message: { cleanup in
            Text("Размер: \(Self.format(cleanup.bytes))\nПуть: \(cleanup.target.path)\n\(cleanup.target.consequence) Завершите активные сборки Gradle перед очисткой.")
        }
        .task { await model.scan() }
        .task { await model.scanReactNativeProjects() }
    }

    private func statistic(_ title: String, bytes: Int64, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.subheadline).foregroundStyle(.secondary)
            Text(Self.format(bytes)).font(.title2.bold().monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    private static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private static func gradleTarget(for child: StorageChild) -> GradleCleanupTarget? {
        GradleCleanupTarget.allCases.first {
            URL(fileURLWithPath: $0.path).standardizedFileURL.path
                == URL(fileURLWithPath: child.path).standardizedFileURL.path
        }
    }

    @ViewBuilder
    private var reactNativeProjectsSection: some View {
        Section {
            switch model.reactNativeProjects {
            case .idle:
                Text("Поиск ещё не запускался")
                    .foregroundStyle(.secondary)
            case .loading:
                ProgressView("Поиск проектов в ~/Documents…")
                    .padding(.vertical, 8)
            case .failure(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            case .loaded(let projects, let warnings):
                if projects.isEmpty {
                    Text("React Native / Expo-проекты не найдены")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(projects) { project in
                        projectDisclosure(project)
                    }
                }

                if !warnings.isEmpty {
                    DisclosureGroup("Предупреждения поиска: \(warnings.count)") {
                        ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                            Text(warning)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        } header: {
            Text("React Native / Expo Projects")
                .font(.headline)
        }
    }

    private func projectDisclosure(_ project: ReactNativeProject) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                if project.storage.isEmpty {
                    Text("Анализируемые каталоги не найдены")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(project.storage) { entry in
                        HStack(spacing: 10) {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                                .frame(width: DashboardRowLayout.childIconWidth)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.relativePath)
                                    .font(.subheadline)
                                Text(entry.kind.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if let bytes = entry.bytes {
                                Text(Self.format(bytes))
                                    .font(.subheadline.monospacedDigit())
                            } else {
                                Text("Недоступно")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }

                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([
                                    URL(fileURLWithPath: entry.path)
                                ])
                            } label: {
                                Image(systemName: "arrow.up.forward.square")
                            }
                            .buttonStyle(.borderless)
                            .help("Показать в Finder")
                        }
                    }
                }

                if let worktree = project.worktree {
                    Label {
                        if let mainRepositoryPath = worktree.mainRepositoryPath {
                            Text("Worktree основного репозитория: \(mainRepositoryPath)")
                                .textSelection(.enabled)
                        } else {
                            Text("Git worktree")
                        }
                    } icon: {
                        Image(systemName: "arrow.triangle.branch")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                let details = project.warnings + project.storage.compactMap { entry in
                    entry.error.map { "\(entry.relativePath): \($0)" }
                }
                if !details.isEmpty {
                    DisclosureGroup("Предупреждения: \(details.count)") {
                        ForEach(Array(details.enumerated()), id: \.offset) { _, warning in
                            Text(warning)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }

                Text("Общий размер проекта считается отдельно; размеры вложенных каталогов не суммируются.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 5)
        } label: {
            HStack(spacing: 12) {
                projectIcon(project)

                VStack(alignment: .leading, spacing: 3) {
                    Text(project.name)
                        .font(.headline)
                    Text(projectDescription(project))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(project.path)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                if let bytes = project.totalBytes {
                    Text(Self.format(bytes))
                        .font(.headline.monospacedDigit())
                } else {
                    Text("Недоступно")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Button("Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([
                        URL(fileURLWithPath: project.path)
                    ])
                }
            }
        }
        .disclosureGroupStyle(AlignedDisclosureGroupStyle())
    }

    private func projectDescription(_ project: ReactNativeProject) -> String {
        if project.worktree != nil {
            return "\(project.type.rawValue) • Worktree"
        }
        if project.isBackup {
            return "\(project.type.rawValue) • Backup"
        }
        return project.type.rawValue
    }

    private func projectIcon(_ project: ReactNativeProject) -> some View {
        HStack(spacing: 3) {
            switch project.type {
            case .expoWithNative, .expoManaged:
                Text("E")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.purple)
                    .frame(width: 20, height: 20)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(.purple, lineWidth: 1.5)
                    }
            case .reactNativeCLI:
                Image(systemName: "iphone")
                    .foregroundStyle(.blue)
                    .frame(width: 20, height: 20)
            }

            if project.worktree != nil {
                Image(systemName: "arrow.triangle.branch")
                    .font(.caption2)
                    .foregroundStyle(.cyan)
                    .help("Git worktree")
            } else if project.isBackup {
                Image(systemName: "archivebox.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .help("Резервная копия проекта")
            }
        }
        .frame(
            width: DashboardRowLayout.categoryIconWidth,
            height: DashboardRowLayout.iconSize
        )
    }
}

private enum DashboardRowLayout {
    static let disclosureWidth: CGFloat = 24
    static let categoryIconWidth: CGFloat = 40
    static let iconSize: CGFloat = 28
    static let childIconWidth: CGFloat = 20
    static let categorySpacing: CGFloat = 12
    static let childIndent = disclosureWidth + categoryIconWidth + categorySpacing
}

private struct AlignedDisclosureGroupStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                Button {
                    configuration.isExpanded.toggle()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        .frame(
                            width: DashboardRowLayout.disclosureWidth,
                            height: DashboardRowLayout.iconSize,
                            alignment: .center
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    configuration.isExpanded ? "Свернуть категорию" : "Раскрыть категорию"
                )

                configuration.label
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if configuration.isExpanded {
                configuration.content
                    .padding(.leading, DashboardRowLayout.childIndent)
            }
        }
    }
}

private struct PendingGradleCleanup {
    let target: GradleCleanupTarget
    let bytes: Int64
}

struct StorageChild: Identifiable, Sendable {
    let name: String
    let path: String
    let bytes: Int64
    let isDirectory: Bool

    var id: String { path }
}
