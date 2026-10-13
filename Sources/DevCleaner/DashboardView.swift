import SwiftUI
import AppKit

struct DashboardView: View {
    @ObservedObject var model: DashboardViewModel
    @State private var showCleanConfirmation = false
    @State private var expandedCategories: Set<StorageCategory> = []

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
                } label: {
                    Label("Сканировать", systemImage: "arrow.clockwise")
                }
                .disabled(model.isBusy)
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
                if model.isBusy { ProgressView().controlSize(.small) }
            }


        List(model.items) { item in
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
                } else if let children = model.children[item.category] {
                    ForEach(children) { child in
                        HStack(spacing: 10) {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)

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
                        }
                        .padding(.leading, 12)
                        .padding(.vertical, 3)
                    }

                    if children.isEmpty {
                        Text("Нет доступных элементов")
                            .foregroundStyle(.secondary)
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(
                            item.category.canClean ? Color.blue : Color.secondary
                        )
                        .frame(width: 28)

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
        .task { await model.scan() }
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
}

struct StorageChild: Identifiable, Sendable {
    let name: String
    let path: String
    let bytes: Int64

    var id: String { path }
}