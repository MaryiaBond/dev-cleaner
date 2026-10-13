#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
swift build -c release
APP="$PWD/build/DevCleaner.app"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/DevCleaner "$APP/Contents/MacOS/DevCleaner"
cp scripts/Info.plist "$APP/Contents/Info.plist"
echo "Готово: $APP"
echo "Запуск: open '$APP'"
