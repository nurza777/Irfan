#!/usr/bin/env bash
#
# Проверки сервера. Запуск:
#
#   bash server/tests/run.sh
#
# Каждый набор гоняется на СВОЁЙ копии сервера со своими файлами во временном
# каталоге. Боевой сервер и его данные не трогаются вообще — по-другому
# проверять разрушающие вещи (удаление аккаунта, смена паролей, потолки на
# размер) нельзя.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
API="$ROOT/server/apiserver.py"
TESTS="$ROOT/server/tests"

command -v python3 >/dev/null || { echo "нужен python3" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

free_port() {
  python3 - <<'PY'
import socket
s = socket.socket()
s.bind(('127.0.0.1', 0))
print(s.getsockname()[1])
s.close()
PY
}

total_ok=0
total_fail=0

# suite <файл> <описание> [доп. подготовка каталога]
suite() {
  local file="$1" title="$2" prep="${3:-}"
  local dir="$WORK/$(basename "$file" .py)"
  mkdir -p "$dir/api/uploads"
  cp "$API" "$dir/"

  # Учётки ролей и данные эфира — заведомо тестовые.
  printf '{"admin":"adminpw","ustaz":"ustazpw"}' > "$dir/auth.json"
  printf '{"rtmpUrl":"rtmp://127.0.0.1/live","key":"testkey","user":"publisher","pass":"p@ss word"}' \
      > "$dir/stream.json"
  printf '{"updated":1,"teachers":[]}' > "$dir/api/teachers.json"
  printf '[]' > "$dir/api/users.json"
  printf '[]' > "$dir/api/comments.json"
  [ -n "$prep" ] && (cd "$dir" && eval "$prep")

  local port; port="$(free_port)"
  (
    cd "$dir"
    IRFAN_PORT="$port" \
    IRFAN_AUTH_FILE="$dir/auth.json" \
    IRFAN_STAFF_FILE="$dir/staff.json" \
    IRFAN_STREAM_FILE="$dir/stream.json" \
    IRFAN_MEDIA_CFG="$dir/media.json" \
    IRFAN_MEDIA_BASE="http://127.0.0.1:$port" \
    python3 apiserver.py > "$dir/server.log" 2>&1
  ) &
  local pid=$!

  # Ждём, пока поднимется, а не спим наугад.
  python3 - "$port" <<'PY'
import sys, time, urllib.request
port = sys.argv[1]
for _ in range(80):
    try:
        urllib.request.urlopen(f'http://127.0.0.1:{port}/teachers.json', timeout=1)
        sys.exit(0)
    except Exception:
        time.sleep(0.1)
sys.exit(1)
PY
  if [ $? -ne 0 ]; then
    echo "### $title — СЕРВЕР НЕ ПОДНЯЛСЯ"
    tail -5 "$dir/server.log"
    kill $pid 2>/dev/null
    total_fail=$((total_fail + 1))
    return
  fi

  echo "### $title"
  local out
  out="$(IRFAN_TEST_URL="http://127.0.0.1:$port" IRFAN_TEST_PORT="$port" \
         python3 "$file" 2>&1)"
  local rc=$?
  echo "$out" | sed 's/^/  /'
  kill $pid 2>/dev/null
  wait $pid 2>/dev/null

  local ok fail
  ok="$(echo "$out"   | sed -n 's/.*итого: \([0-9]*\) ok.*/\1/p' | tail -1)"
  fail="$(echo "$out" | sed -n 's/.*итого: [0-9]* ok, \([0-9]*\) fail.*/\1/p' | tail -1)"
  total_ok=$((total_ok + ${ok:-0}))
  total_fail=$((total_fail + ${fail:-0}))
  [ $rc -ne 0 ] && [ -z "${fail:-}" ] && total_fail=$((total_fail + 1))
  echo
}

suite "$TESTS/test_staff_auth.py"  "Учётки и токены устаза"
suite "$TESTS/test_student_key.py" "Ключ устройства ученика"
suite "$TESTS/test_limits.py"      "Потолки размера и подделка адреса"
suite "$TESTS/test_crashes.py"     "Приём сбоев приложения"
suite "$TESTS/test_restore.py"     "Перенос аккаунта на другой телефон"
suite "$TESTS/test_certificates.py" "Сертификаты и дипломы"
# Подписанные ссылки нужно проверять при ВКЛЮЧЕННОЙ проверке — на бою она
# пока выключена, чтобы не оборвать старые сборки на телефонах.
suite "$TESTS/test_media_links.py" "Подписанные ссылки на уроки" '
printf "{\"require_signed\": true, \"secret\": \"test-media-secret-0123456789\"}" > media.json
printf "video" > api/uploads/urok.mp4
printf "{\"folders\":[{\"id\":\"f1\",\"name\":\"Таджвид\"}],\"files\":{\"urok.mp4\":\"f1\"},\"titles\":{\"urok.mp4\":\"Первый урок\"}}" > media-folders.json
printf "{\"updated\":\"x\",\"teachers\":[{\"id\":\"t1\",\"name\":\"Устаз\",\"directions\":[{\"title\":\"Направление\",\"courses\":[{\"title\":\"Курс\",\"lessons\":[{\"title\":\"Урок 1\",\"url\":\"http://127.0.0.1/uploads/urok.mp4\"}]}]}]}]}" > api/courses.json
'

echo "════════════════════════════════════════"
if [ "$total_fail" -eq 0 ]; then
  echo "  ВСЁ ХОРОШО: $total_ok проверок пройдено"
else
  echo "  ПРОВАЛЕНО: $total_fail при $total_ok пройденных"
fi
exit $([ "$total_fail" -eq 0 ] && echo 0 || echo 1)
