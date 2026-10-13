# DevCleaner — macOS SwiftUI MVP

Однооконный dashboard для просмотра размера каталогов разработчика и безопасной очистки **только** Xcode DerivedData.

## Требования
- macOS 13+
- Xcode и Command Line Tools (Swift 5.9+)

## Запуск

```bash
cd DevCleaner
swift run
```

Можно также открыть `Package.swift` в Xcode и запустить исполняемую схему `DevCleaner`.

## Собрать .app

```bash
./scripts/build-app.sh
open build/DevCleaner.app
```

Для локального использования `.app` можно перенести в `/Applications`. Это локальная **неподписанная** сборка; для передачи другим пользователям нужна подпись и notarization. Сборка не публикуется в App Store.

## Структура
- `Package.swift` — описание Swift Package: Swift 5.9, macOS 13+, исполняемый target.
- `DevCleanerApp.swift` — точка входа `@main`, создаёт окно.
- `StorageCategory.swift` — фиксированный список папок и модель результата сканирования.
- `FileSystemScanner.swift` — чтение занятости диска и запуск `/usr/bin/du -sk` для размера каталогов.
- `CleanupService.swift` — удаление **содержимого только** DerivedData; никакого shell или `rm -rf`.
- `DashboardViewModel.swift` — состояние, асинхронный запуск задач, журнал и действия.
- `DashboardView.swift` — SwiftUI dashboard, кнопки и подтверждение.
- `scripts/build-app.sh` — release build и упаковка в `.app`.
- `scripts/Info.plist` — метаданные macOS-приложения.

## Безопасность
- Никакого автоматического удаления.
- Нет кнопок удаления симуляторов, Android SDK, `.android`, Gradle или глобальных кэшей.
- Перед очисткой DerivedData показывается подтверждение.
- При очистке удаляются дочерние элементы, а не корневая папка.
- Приложение не требует sudo.
- Если Xcode прямо сейчас собирает проект — дождитесь конца сборки.

## Примечания
- Размеры папок измеряются `du -sk`, поэтому могут немного отличаться от Finder.
- Некоторые папки могут быть недоступны из-за прав macOS. При необходимости разрешите доступ приложению в настройках Privacy & Security, а не запускайте его под sudo.
- В Linux сборка не поддерживается, поскольку используется SwiftUI/AppKit.
