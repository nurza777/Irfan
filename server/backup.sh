#!/usr/bin/env bash
#
# Резервная копия данных «Ирфана». Запускать НА СЕРВЕРЕ от root:
#
#   bash /opt/irfan-server/backup.sh
#
# Копируется всё, чего нет больше нигде и что не восстановить руками:
#   * реестр учеников, доступы к курсам, коды и коины;
#   * каталог курсов, новости, азкары, реестр устазов;
#   * раскладка видео по папкам и подписи (media-folders.json);
#   * учётки ролей и устазов, ключ публикации эфира, секрет подписи ссылок.
#
# Всё это вместе весит десятки килобайт — то есть копия дешёвая, и делать её
# можно хоть ежечасно.
#
# Сами уроки (25 ГБ) сюда НЕ попадают: копировать их каждый раз бессмысленно,
# а исходники лежат на ноутбуке, откуда их заливали. Вместо файлов
# сохраняется опись — имена, размеры и даты, — чтобы после аварии было видно,
# что именно надо перезалить.
set -euo pipefail

ROOT=/opt/irfan-server
DEST="${1:-$ROOT/backups}"
KEEP="${KEEP:-30}"

mkdir -p "$DEST"
chmod 700 "$DEST"

STAMP="$(date +%Y%m%d-%H%M%S)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/api" "$WORK/etc"

# Данные приложения.
for f in "$ROOT"/api/*.json; do
  [ -e "$f" ] && cp -p "$f" "$WORK/api/"
done
[ -e "$ROOT/media-folders.json" ] && cp -p "$ROOT/media-folders.json" "$WORK/"
[ -e "$ROOT/tokens.json" ]        && cp -p "$ROOT/tokens.json" "$WORK/"

# Секреты. Без них после восстановления не войдёт ни один устаз и перестанут
# открываться подписанные ссылки на уроки.
for f in /etc/irfan/*.json; do
  [ -e "$f" ] && cp -p "$f" "$WORK/etc/"
done

# Опись уроков: что лежало на диске на момент копии.
if [ -d "$ROOT/api/uploads" ]; then
  ( cd "$ROOT/api/uploads" && ls -l --time-style=+%Y-%m-%d\ %H:%M ) \
      > "$WORK/uploads-manifest.txt" 2>/dev/null || true
  du -sh "$ROOT/api/uploads" 2>/dev/null | cut -f1 > "$WORK/uploads-size.txt" || true
fi

# Короткая справка внутри архива — чтобы через полгода не гадать, что это.
cat > "$WORK/README.txt" <<TXT
Резервная копия сервера «Ирфан» от $STAMP.

api/            данные приложения (ученики, курсы, доступы, коды, новости)
etc/            учётки ролей и устазов, ключ эфира, секрет подписи ссылок
media-folders.json  раскладка видео по папкам и подписи
tokens.json     выданные токены устазов (можно не восстанавливать — просто
                войдут заново)
uploads-manifest.txt  опись уроков: сами файлы в копию НЕ входят

Как развернуть:
  tar xzf <архив> -C /tmp/restore
  cp /tmp/restore/api/*.json         /opt/irfan-server/api/
  cp /tmp/restore/media-folders.json /opt/irfan-server/
  cp /tmp/restore/etc/*.json         /etc/irfan/
  chmod 600 /etc/irfan/*.json
  systemctl restart irfan-api
TXT

ARCHIVE="$DEST/irfan-$STAMP.tar.gz"
tar czf "$ARCHIVE" -C "$WORK" .
chmod 600 "$ARCHIVE"

# Держим последние KEEP копий.
ls -1t "$DEST"/irfan-*.tar.gz 2>/dev/null | tail -n +$((KEEP + 1)) | \
  while read -r old; do rm -f "$old"; done

echo "==> $ARCHIVE ($(du -h "$ARCHIVE" | cut -f1))"
echo "==> копий в $DEST: $(ls -1 "$DEST"/irfan-*.tar.gz 2>/dev/null | wc -l | tr -d ' ')"
