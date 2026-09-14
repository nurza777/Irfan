#!/bin/sh
# Вызывается nginx-rtmp при окончании публикации.
cat > /var/www/irfan-live/status.json <<EOF
{"live": false, "title": "", "url": ""}
EOF
