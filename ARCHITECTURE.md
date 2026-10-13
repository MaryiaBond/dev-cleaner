# DevCleaner — архитектура

> Это живая карта проекта. **Сверять с локальными исходниками перед изменениями.** Текущее состояние сверено с рабочей копией: приложение сканирует диск и поддерживает раскрытие категорий с вложенными элементами.

## Цель и границы
Одно окно с информацией о диске, кэшах Xcode/Android/macOS, React Native / Expo-проектах и явно разрешённых действиях. Без backend, БД и сетевого слоя.

## Технологии
- Swift 5.9+ / Swift Package Manager
- macOS 13+
- SwiftUI — декларативный интерфейс
- AppKit (`NSWorkspace`) — открыть путь в Finder
- Foundation (`FileManager`, `Process`) — файловая система и `du`
- MVVM-lite; без внешних зависимостей и без тестов на текущем этапе

## Минимальная структура

```text
DevCleaner/
├── Package.swift                  # конфигурация SwiftPM
├── README.md                      # запуск и сборка
├── AGENTS.md                      # правила для агента
├── ARCHITECTURE.md                # карта приложения
├── ROADMAP.md                     # план разработки
├── Sources/DevCleaner/
│   ├── DevCleanerApp.swift        # @main, окно, жизненный цикл
│   ├── DashboardView.swift        # UI, подтверждения, лог и модель StorageChild
│   ├── DashboardViewModel.swift   # @MainActor, @Published, сценарии действий
│   ├── StorageCategory.swift      # категории, allowlist и модели проектов
│   ├── FileSystemScanner.swift    # размеры и поиск RN/Expo-проектов
│   └── CleanupService.swift       # строго ограниченные операции удаления
└── scripts/
    ├── build-app.sh               # сборка standalone .app
    └── Info.plist                 # метаданные пакета приложения
```

`StorageChild` фактически объявлен в конце `DashboardView.swift`; в рамках сверки модель не переносится. Новые сервисы не выделяются ради одного небольшого метода.

## Кто за что отвечает

| Часть | Ответственность | Не должна |
| --- | --- | --- |
| `DevCleanerApp.swift` | запуск и создание окна | сканировать/удалять |
| `DashboardView.swift` | показывать данные; принимать нажатия; диалоги; хранить `StorageChild` | вычислять размеры; удалять данные |
| `DashboardViewModel.swift` | хранить состояние, запускать задачи, собирать результат, логировать | напрямую реализовывать рекурсивную очистку |
| `StorageCategory.swift` | категории, модели хранилища/проектов и `GradleCleanupTarget` | осуществлять I/O |
| `FileSystemScanner.swift` | read-only измерение и ограниченный поиск RN/Expo-проектов | удалять |
| `CleanupService.swift` | allowlist, проверки и контролируемое удаление | решать, как нарисовать UI |

## Поток сканирования

```text
DashboardView: пользователь нажал «Сканировать»
  → DashboardViewModel.scan()
    → сброс children и новое поколение сканирования
    → фоновая задача
      → FileSystemScanner.scan() + diskUsage()
    → обновление @Published items, disk, log только для актуального поколения
  → SwiftUI перерисовывает окно
```

Раскрытие категории идёт по цепочке:
`DisclosureGroup` → `DashboardViewModel.loadChildren(for:)` → `FileSystemScanner.scanChildren(of:)` → `ChildScanResult`. Результат различает пустую, отсутствующую и недоступную папку, а частичные ошибки показывает как warnings. `du` получает путь в `arguments`; stdout и stderr читаются без риска взаимной блокировки.

## React Native / Expo Projects

`DashboardView` запускает `DashboardViewModel.scanReactNativeProjects()` параллельно с общим сканированием. `FileSystemScanner` обходит `~/Documents` до глубины 5, не следует по симлинкам и не заходит в `node_modules`, его архивные варианты (`node_modules_backup`, `node_modules-old`, `node_modules_copy` и составные имена), `.git`, `Pods`, `build`, `.gradle`, `.expo` и другие generated-каталоги. Ошибка одной папки становится warning и не прерывает поиск.

Кандидат должен иметь обычный `package.json` и зависимость `expo` или `react-native`, но этого недостаточно. Приложение подтверждает хотя бы один сильный сигнал: Expo-конфигурация (`app.json`, варианты `app.config.*`) или настоящий native application target; либо совместно entry point/структура приложения (`App.*`, `index.*`, `app/`, `src/app/`, поддерживаемый `main`) и script запуска Expo/RN. Поэтому библиотека с одной framework-зависимостью не считается приложением. Expo с `android` и/или `ios` классифицируется как Expo with native, Expo без них — managed, а `react-native` без `expo` — React Native CLI.

Признак резервной копии хранится отдельно от типа проекта. После подтверждения приложения имя его собственной директории разбирается на слова `backup`, `bak`, `copy`, `old`, `archive`; имена родительских каталогов не наследуются. В UI Expo и React Native имеют разные локальные иконки, а backup дополнительно помечается архивным символом и текстом `Backup`.

Linked Git worktree определяется не по имени: обычный файл `.git` должен содержать `gitdir`, целевой служебный каталог — `HEAD`, `commondir` и корректную обратную ссылку `gitdir`, а сам каталог должен находиться внутри `<common git dir>/worktrees`. Worktree сохраняет основной тип Expo/RN, не получает `Backup` и по возможности показывает путь основного репозитория. Его рабочая копия и файл `.git` учитываются только при анализе; общий Git-каталог не добавляется к размеру worktree.

Общий размер считается один раз от корня проекта. `node_modules`, `android/build`, `android/app/build`, `android/.gradle`, `ios/build`, `ios/Pods`, `.expo` и `.git` показываются как разбивка и не суммируются. Глобальные Gradle/npm/Metro-кэши в размер проекта не добавляются. Секция UI имеет `loading`, `empty`, `failure` и частичные warnings; удаления в ней нет.

Категории и строки проектов используют один `AlignedDisclosureGroupStyle`: стрелка и иконка занимают фиксированные колонки, label центрируется по вертикали, а содержимое раскрытой строки начинается после обеих колонок. Ширина колонки иконки не меняется из-за меток Backup/Worktree.

## Поток очистки

```text
Кнопка «Очистить»
  → диалог с подтверждением
  → DashboardViewModel.cleanDerivedData() / cleanGradle(target)
  → фоновый вызов CleanupService
  → проверка allowlist и типа целевой директории
  → удаление содержимого, не самой целевой директории
  → отчёт об успехах/ошибках
  → повторное сканирование
```

**Разрешённая очистка:** Xcode DerivedData и содержимое пяти Gradle-каталогов:

| Цель | Последствие |
| --- | --- |
| `~/.gradle/caches` | повторное скачивание зависимостей и сборка артефактов |
| `~/.gradle/daemon` | повторное создание данных daemon |
| `~/.gradle/native` | повторная распаковка нативных компонентов |
| `~/.gradle/wrapper/dists` | повторное скачивание дистрибутивов Gradle |
| `~/.gradle/.tmp` | повторное создание временных файлов |

UI сопоставляет строку с `GradleCleanupTarget`, но допуск повторно проверяет `CleanupService`: allowlist, канонический путь, тип каталога, симлинки в цепочке пути и Gradle-процессы. Удаляется только содержимое цели; корневой каталог сохраняется. После операции общие и дочерние размеры пересчитываются.

## Важные принципы
1. Одно окно, простой список, минимум сущностей.
2. Явное разделение чтения и удаления.
3. UI может запретить кнопку, но безопасность обеспечивает сервис.
4. Размеры пересчитываются после изменения данных.
5. Симлинки не должны позволять выходить из разрешённых директорий; любые новые операции удаления требуют отдельного review.
6. Ошибки доступа и частичные результаты должны быть видимы.
7. Не хранить секреты, не собирать аналитику, не отправлять пути в сеть.
8. На данном этапе нет автоматизации очистки, автозапуска, фонового наблюдения и тестов.

## Параллели с React Native

| Swift / SwiftUI | Примерный аналог |
| --- | --- |
| `struct DashboardView: View` | React function component |
| `@State` | `useState` локального UI |
| `ObservableObject` + `@Published` | observable state/store + обновления UI |
| `@ObservedObject` | подписка View на модель |
| `enum StorageCategory` | TS union/enum с вычисляемыми свойствами |
| `struct StorageItem` | TS interface/type с поведением |
| `Task { await ... }` | запуск async-операции из обработчика |
| `DisclosureGroup` | Accordion |
| `FileManager`, `Process` | нативные файловые API / child_process (приблизительно) |

## Как вводить изменения
Один небольшой шаг → просмотр diff → `swift build` → ручная проверка в окне → обсуждение с владельцем → следующий шаг. Команда `swift run` запускает приложение; `./scripts/build-app.sh` собирает `.app`.
