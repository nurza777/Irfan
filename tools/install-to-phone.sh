#!/usr/bin/env bash
#
# Ставит оба приложения «Ирфан» на подключённый iPhone.
#
# Единственное, что нужно сделать заранее руками: войти в Apple ID
# в Xcode → Settings → Accounts. Без этого Apple не выпускает профиль
# подписи, и сборка падает с «No Accounts» — обойти нельзя.
#
#     bash tools/install-to-phone.sh
set -uo pipefail

STUDENT=/Users/nurzaman/Documents/Irfan
USTAZ=/Users/nurzaman/Documents/IrfanUstaz

echo "==> Ищу телефон"
# Идентификатор ищем по виду UUID: в колонках переменное число слов
# (модель занимает от двух до четырёх), позиционный разбор тут врёт.
# По кабелю телефон значится «connected», по сети — «available (paired)».
LINE=$(xcrun devicectl list devices 2>/dev/null \
       | grep -E 'connected|available \(paired\)' | head -1)
DEV=$(grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' <<<"$LINE" | head -1)
NAME=$(awk '{print $1}' <<<"$LINE")
if [[ -z "${DEV:-}" ]]; then
  echo "    Телефон не найден. Подключите кабелем и разблокируйте."
  exit 1
fi
echo "    $NAME ($DEV)"

echo "==> Проверяю подпись"
# Список может существовать, но быть пустым — «( )». Ищем сам Apple ID,
# то есть строку с почтой: только она значит, что аккаунт реально добавлен.
if ! defaults read com.apple.dt.Xcode DVTDeveloperAccountManagerAppleIDLists 2>/dev/null \
     | grep -q '@'; then
  cat <<'MSG'
    В Xcode нет ни одного Apple ID — сборка не подпишется.

    Xcode → Settings → Accounts → + → Apple ID → войти,
    затем выбрать команду и нажать Download Manual Profiles.

    После этого запустите скрипт снова.
MSG
  exit 1
fi

# Команда берётся из сертификата в связке ключей: так не нужно помнить,
# под каким аккаунтом вошли.
TEAM=$(security find-identity -v -p codesigning 2>/dev/null \
       | sed -n 's/.*Apple Development: .*(\([A-Z0-9]\{10\}\)).*/\1/p' | head -1)
echo "    Сертификат найден, команда: ${TEAM:-не определена}"

build_and_install() {
  local dir="$1" title="$2" bundle="$3"
  echo
  echo "==> $title"
  cd "$dir" || return 1

  # Сначала как есть — с командой, прописанной в проекте.
  if ! flutter build ios --release > /tmp/build-$$.log 2>&1; then
    # Не вышло — повторяем с командой из сертификата: аккаунт в Xcode мог
    # оказаться другим, чем тот, под который проект настраивали.
    if [[ -z "${TEAM:-}" ]] || ! xcodebuild -workspace ios/Runner.xcworkspace \
         -scheme Runner -configuration Release \
         -destination "id=$DEV" DEVELOPMENT_TEAM="$TEAM" \
         -allowProvisioningUpdates build >> /tmp/build-$$.log 2>&1; then
      echo "    Сборка не прошла:"
      grep -E "error:" /tmp/build-$$.log | sort -u | head -5 | sed 's/^/      /'
      return 1
    fi
    echo "    (пересобрал с командой $TEAM)"
  fi

  local app
  app=$(find "$dir/build/ios/iphoneos" -maxdepth 1 -name "*.app" | head -1)
  [[ -z "$app" ]] && { echo "    Собранное приложение не найдено"; return 1; }

  echo "    Ставлю на телефон"
  if xcrun devicectl device install app --device "$DEV" "$app" \
       > /tmp/inst-$$.log 2>&1; then
    echo "    Готово: $bundle"
  else
    echo "    Установка не прошла:"
    tail -3 /tmp/inst-$$.log | sed 's/^/      /'
    return 1
  fi
}

ok=0
build_and_install "$STUDENT" "Приложение студента «Ирфан»" kg.irfan.irfan && ((ok++))
build_and_install "$USTAZ"   "Приложение устаза «Ирфан Устаз»" kg.irfan.irfanUstaz && ((ok++))

echo
echo "==> Установлено приложений: $ok из 2"
[[ $ok -eq 2 ]] && cat <<'MSG'

    На телефоне при первом запуске может понадобиться доверить профиль:
    Настройки → Основные → VPN и управление устройством → доверять.

    Подпись разработчика живёт около недели — потом переустановить.
MSG
