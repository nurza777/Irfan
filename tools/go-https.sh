#!/usr/bin/env bash
#
# Переезд приложения на HTTPS — одной командой, когда домен уже указывает
# на сервер:
#
#   bash tools/go-https.sh api.example.kg admin@example.kg
#
# Делает всё, что осталось для подачи в App Store, кроме внешних действий
# (A-запись, загрузка сборки, заполнение анкет):
#   1. на сервере — nginx + сертификат + перевод ссылок на https
#      (server/enable-https.sh, он же чинит уроки в courses.json);
#   2. в приложении — ApiConfig.defaultBase на новый адрес;
#   3. убирает ATS-исключение NSAllowsArbitraryLoads: с https оно не нужно,
#      а с ним Apple задаёт лишние вопросы;
#   4. пересобирает релиз и прогоняет тесты.
#
# Скрипт идемпотентен: повторный запуск ничего не ломает.
set -euo pipefail

DOMAIN="${1:-}"
EMAIL="${2:-}"
SERVER="${3:-root@178.104.206.100}"

if [[ -z "$DOMAIN" || -z "$EMAIL" ]]; then
  echo "Использование: bash tools/go-https.sh <домен> <email> [ssh-адрес]" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "==> 1/4. Проверяю, что домен указывает на сервер"
DOMAIN_IP="$(dig +short "$DOMAIN" A | tail -1)"
if [[ -z "$DOMAIN_IP" ]]; then
  echo "!! $DOMAIN никуда не указывает — A-запись не создана или не разошлась." >&2
  echo "   В панели cctld.kg: тип A, имя ${DOMAIN%%.*}, значение — IP сервера." >&2
  exit 1
fi
echo "    $DOMAIN → $DOMAIN_IP"

echo "==> 2/4. Включаю HTTPS на сервере"
scp -q server/enable-https.sh "$SERVER:/opt/irfan-server/"
# shellcheck disable=SC2029
ssh "$SERVER" "bash /opt/irfan-server/enable-https.sh '$DOMAIN' '$EMAIL'"

echo "==> 3/4. Переключаю приложение"
python3 - "$DOMAIN" <<'PY'
import pathlib, re, sys
domain = sys.argv[1]
base = f'https://{domain}'

cfg = pathlib.Path('lib/services/api_config.dart')
s = cfg.read_text(encoding='utf-8')
s2 = re.sub(r"static const defaultBase = '[^']*';",
            f"static const defaultBase = '{base}';", s)
# Комментарий-напоминание про долг больше не нужен — долг закрыт.
s2 = s2.replace(
    "  // TODO(security): перевести на https://<домен> и убрать ATS-исключение\n"
    "  // (NSAllowsArbitraryLoads) в ios/Runner/Info.plist.\n", '')
cfg.write_text(s2, encoding='utf-8')
print(f'    ApiConfig.defaultBase → {base}'
      if s2 != s else '    ApiConfig уже на этом адресе')

plist = pathlib.Path('ios/Runner/Info.plist')
p = plist.read_text(encoding='utf-8')
# ATS-исключение убираем целиком вместе с обёрткой NSAppTransportSecurity:
# по https оно не нужно, а его наличие — повод для вопросов на ревью.
p2 = re.sub(
    r'\t<key>NSAppTransportSecurity</key>\n\t<dict>\n'
    r'\t\t<key>NSAllowsArbitraryLoads</key>\n\t\t<true/>\n\t</dict>\n', '', p)
plist.write_text(p2, encoding='utf-8')
print('    NSAllowsArbitraryLoads убран'
      if p2 != p else '    ATS-исключения уже нет')
PY

echo "==> 4/4. Проверяю сборку"
flutter analyze
flutter test
flutter build ios --release --no-codesign

echo
echo "==> Готово. Проверьте вживую:"
echo "    curl -I https://$DOMAIN/courses.json"
echo "    curl -I https://$DOMAIN/privacy.html"
echo
echo "==> Дальше — только внешние шаги (см. store/appstore.md):"
echo "    архив в Xcode → App Store Connect → анкеты → Submit."
