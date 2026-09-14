#!/usr/bin/env bash
#
# Съёмка скриншотов для App Store — все семь, без единого нажатия.
#
#   bash tools/shoot-screenshots.sh [UDID-симулятора]
#
# Почему так, а не «открыть и понажимать»: `simctl` умеет делать снимок, но
# не умеет нажимать, а `idb` на этой машине не стоит. Поэтому для каждого
# экрана приложение собирается с временной точкой входа
# `tools/screenshots_main.dart` — она сразу показывает нужный экран.
#
# Экраны и подписи к ним — в store/appstore.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DEVICE="${1:-iPhone 17 Pro Max}"
OUT="$ROOT/store/screenshots-6.9"
BUNDLE=kg.irfan.irfan

# Ищем нужный симулятор по имени, если UDID не передали явно.
if [[ "$DEVICE" =~ ^[0-9A-F-]{36}$ ]]; then
  UDID="$DEVICE"
else
  UDID="$(xcrun simctl list devices available \
    | grep "^    $DEVICE (" | head -1 \
    | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
fi
if [[ -z "${UDID:-}" ]]; then
  echo "!! Симулятор «$DEVICE» не найден." >&2
  exit 1
fi
echo "==> Симулятор: $DEVICE ($UDID)"

xcrun simctl boot "$UDID" 2>/dev/null || true
mkdir -p "$OUT"

# Экран → имя файла → сколько ждать до снимка. Пауза разная: каталог курсов
# тянется с сервера, а счётчик зикров готов сразу.
shots=(
  "main:01-main.png:11"
  "tracker:02-tracker.png:9"
  "quran:03-quran.png:11"
  "zikr:04-zikr.png:9"
  "names:05-names.png:10"
  "azkar:06-azkar.png:10"
  "lessons:07-courses.png:15"
)

for entry in "${shots[@]}"; do
  IFS=: read -r shot file wait <<<"$entry"
  echo "==> $file"
  flutter build ios --simulator --debug \
    -t tools/screenshots_main.dart --dart-define=SHOT="$shot" >/dev/null
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl install "$UDID" build/ios/iphonesimulator/Runner.app
  # Статус-бар задаётся заново после каждой установки: перезапуск приложения
  # его не сбрасывает, а вот перезагрузка симулятора — да.
  xcrun simctl status_bar "$UDID" override --time "09:41" \
    --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
  xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
  sleep "$wait"
  xcrun simctl io "$UDID" screenshot "$OUT/$file" >/dev/null 2>&1
done

echo
echo "==> Готово: $OUT"
ls -1 "$OUT"
