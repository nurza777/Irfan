#!/bin/sh
# Вызывается nginx-rtmp при старте публикации. $1 — имя (ключ) потока.
# Принимаем только поток с правильным ключом.
#
# Ключ НЕ хранится в репозитории. Положите его на сервере в файл
# /etc/irfan/stream.key (одна строка), права 600:
#   sudo install -d -m700 /etc/irfan
#   printf '%s' 'ДЛИННЫЙ_СЛУЧАЙНЫЙ_КЛЮЧ' | sudo tee /etc/irfan/stream.key >/dev/null
#   sudo chmod 600 /etc/irfan/stream.key
KEY_FILE="/etc/irfan/stream.key"
[ -r "$KEY_FILE" ] || exit 1
KEY=$(head -c 128 "$KEY_FILE" | tr -d '\r\n')
[ -n "$KEY" ] || exit 1
[ "$1" = "$KEY" ] || exit 1

# Заголовок эфира приложение устаза кладёт в live-title.txt заранее.
TITLE="Прямой эфир устаза"
if [ -s /var/www/irfan-api/live-title.txt ]; then
  TITLE=$(head -c 200 /var/www/irfan-api/live-title.txt | tr -d '"\n')
fi

cat > /var/www/irfan-live/status.json <<EOF
{"live": true, "title": "$TITLE", "url": "hls/$1.m3u8"}
EOF
