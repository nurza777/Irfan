#!/usr/bin/env bash
#
# Проверка восстановления. Запускать НА СЕРВЕРЕ от root:
#
#   bash /opt/irfan-server/restore-test.sh
#
# Поднимает сервер ТОЛЬКО из последнего архива, на отдельном порту и во
# временном каталоге — боевой не трогается. Без такой проверки резервная
# копия остаётся просто файлом, про который неизвестно, рабочий ли он.
#
# Пароль учётки ревьюера ниже — им проверяется, что секреты пережили копию
# (после смены пароля подставьте новый или уберите эту проверку).
set -uo pipefail

ARCHIVE="$(ls -1t /opt/irfan-server/backups/irfan-*.tar.gz | head -1)"
WORK=/tmp/restore-test
rm -rf "$WORK"; mkdir -p "$WORK/srv/api" "$WORK/unpacked"

echo "==> Разворачиваю $ARCHIVE"
tar xzf "$ARCHIVE" -C "$WORK/unpacked"
echo "    в архиве:"
find "$WORK/unpacked" -type f | sed "s|$WORK/unpacked/|      |" | sort | head -20

echo "==> Собираю из копии рабочий каталог"
cp /opt/irfan-server/apiserver.py "$WORK/srv/"
cp "$WORK/unpacked/api/"*.json "$WORK/srv/api/" 2>/dev/null
cp "$WORK/unpacked/media-folders.json" "$WORK/srv/" 2>/dev/null

PORT=8199
(
  cd "$WORK/srv"
  IRFAN_PORT=$PORT \
  IRFAN_AUTH_FILE="$WORK/unpacked/etc/auth.json" \
  IRFAN_STAFF_FILE="$WORK/unpacked/etc/staff.json" \
  IRFAN_STREAM_FILE="$WORK/unpacked/etc/stream.json" \
  IRFAN_MEDIA_CFG="$WORK/unpacked/etc/media.json" \
  python3 apiserver.py > "$WORK/server.log" 2>&1
) &
PID=$!
for _ in $(seq 40); do
  curl -s -o /dev/null "http://127.0.0.1:$PORT/teachers.json" && break
  sleep 0.25
done

echo "==> Проверяю восстановленный сервер"
ADMIN=$(python3 -c "import json;d=json.load(open('$WORK/unpacked/etc/auth.json'));print('admin:'+d['admin'])")

printf "    ученики на месте:      "
curl -s -u "$ADMIN" "http://127.0.0.1:$PORT/users.json" | \
  python3 -c "import json,sys;print(len(json.load(sys.stdin)),'записей')"
printf "    каталог курсов:        "
curl -s "http://127.0.0.1:$PORT/courses.json" | python3 -c "
import json,sys
d=json.load(sys.stdin)
n=sum(len(c.get('lessons') or []) for t in d.get('teachers',[]) for dd in t.get('directions',[]) for c in dd.get('courses',[]))
print(len(d.get('teachers',[])),'устаз(ов),',n,'уроков')"
printf "    выданные доступы:      "
curl -s -u "$ADMIN" "http://127.0.0.1:$PORT/access.json" | \
  python3 -c "import json,sys;print(len(json.load(sys.stdin)),'шт.')"
printf "    учётки устазов:        "
curl -s -u "$ADMIN" "http://127.0.0.1:$PORT/staff.json" | \
  python3 -c "import json,sys;print(len(json.load(sys.stdin)['staff']),'шт.')"

# Самое главное: работает ли ВХОД по восстановленным учёткам.
printf "    вход устаза из копии:  "
curl -s -X POST "http://127.0.0.1:$PORT/auth/token" -H 'Content-Type: application/json' \
  -d '{"login":"review","password":"⟨ПАРОЛЬ_РЕВЬЮ⟩"}' | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('РАБОТАЕТ, роль', d.get('role')) if d.get('token') else print('НЕ РАБОТАЕТ:', d)"
printf "    ключ эфира:            "
curl -s -u "$ADMIN" "http://127.0.0.1:$PORT/stream.json" | python3 -c "
import json,sys;d=json.load(sys.stdin);print('на месте' if d.get('streamKey') else 'ПОТЕРЯН')"

kill $PID 2>/dev/null
rm -rf "$WORK"
echo "==> Временный каталог убран, боевой сервер не тронут"
