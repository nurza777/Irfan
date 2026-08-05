#!/usr/bin/env bash
#
# Забирает резервные копии с сервера НА ЭТОТ МАК:
#
#   bash tools/pull-backup.sh              # только данные (десятки КБ)
#   bash tools/pull-backup.sh --lessons    # ещё и уроки (25 ГБ, долго)
#
# Ради этого всё и затевалось: копии на самом сервере спасают от случайного
# удаления, но не от смерти диска. Наружу — значит на другую машину.
#
# Уроки тянутся с докачкой (--partial), обрыв связи не начинает всё заново.
set -euo pipefail

SERVER="${IRFAN_SERVER:-root@178.104.206.100}"
DEST="${IRFAN_BACKUP_DIR:-$HOME/irfan-backups}"
WITH_LESSONS=0
[ "${1:-}" = "--lessons" ] && WITH_LESSONS=1

mkdir -p "$DEST/data"

echo "==> Свежая копия на сервере"
ssh "$SERVER" 'bash /opt/irfan-server/backup.sh' | sed 's/^/    /'

echo "==> Забираю архивы данных"
rsync -az --delete-after \
    "$SERVER:/opt/irfan-server/backups/" "$DEST/data/"

count="$(ls -1 "$DEST"/data/irfan-*.tar.gz 2>/dev/null | wc -l | tr -d ' ')"
size="$(du -sh "$DEST/data" 2>/dev/null | cut -f1)"
echo "    архивов: $count, всего $size"

if [ "$WITH_LESSONS" = "1" ]; then
  echo "==> Забираю уроки (это надолго)"
  mkdir -p "$DEST/uploads"
  rsync -avP --partial \
      "$SERVER:/opt/irfan-server/api/uploads/" "$DEST/uploads/"
  echo "    уроков: $(ls -1 "$DEST/uploads" | wc -l | tr -d ' '), $(du -sh "$DEST/uploads" | cut -f1)"
fi

echo
echo "==> Всё в $DEST"
echo "    В архиве лежат и секреты (учётки устазов, ключ эфира, секрет"
echo "    подписи ссылок) — держите папку там, куда нет доступа посторонним."
