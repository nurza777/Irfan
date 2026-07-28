#!/usr/bin/env bash
#
# Включение HTTPS на сервере «Ирфан» (Hetzner). Запускать НА СЕРВЕРЕ от root,
# когда домен уже куплен и его A-запись указывает на 178.104.206.100.
#
#   ssh root@178.104.206.100
#   bash enable-https.sh irfan.example.com admin@example.com
#
# Что делает:
#   1. ставит nginx и certbot;
#   2. поднимает reverse-proxy: :443 → apiserver.py (:8090) и HLS (:8888);
#   3. выпускает сертификат Let's Encrypt с автопродлением;
#   4. закрывает прямой доступ к 8090/8888 снаружи (остаётся только 443).
#
# После этого в приложениях поменять базовый адрес на https://<домен>
# и убрать NSAllowsArbitraryLoads из ios/Runner/Info.plist в обоих проектах.
set -euo pipefail

DOMAIN="${1:-}"
EMAIL="${2:-}"
if [[ -z "$DOMAIN" || -z "$EMAIL" ]]; then
  echo "Использование: bash enable-https.sh <домен> <email-для-Let's-Encrypt>" >&2
  exit 1
fi

echo "==> Домен: $DOMAIN"

# Проверяем, что домен уже смотрит на этот сервер: certbot иначе просто
# провалится на HTTP-01, и разбираться будет дольше.
SERVER_IP="$(curl -fsS https://api.ipify.org || true)"
DOMAIN_IP="$(getent hosts "$DOMAIN" | awk '{print $1}' | head -1 || true)"
if [[ -n "$SERVER_IP" && -n "$DOMAIN_IP" && "$SERVER_IP" != "$DOMAIN_IP" ]]; then
  echo "!! $DOMAIN указывает на $DOMAIN_IP, а сервер — $SERVER_IP." >&2
  echo "   Поправьте A-запись и подождите обновления DNS." >&2
  exit 1
fi

apt-get update -qq
apt-get install -y -qq nginx certbot python3-certbot-nginx

cat > /etc/nginx/sites-available/irfan <<NGINX
server {
    listen 80;
    server_name $DOMAIN;

    # API и статика (курсы, новости, азкары, реестр, коды выкупа)
    location / {
        proxy_pass http://127.0.0.1:8090;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        client_max_body_size 512M;   # загрузка видеоуроков
    }

    # HLS прямого эфира (MediaMTX)
    location /hls-live/ {
        proxy_pass http://127.0.0.1:8888/;
        proxy_set_header Host \$host;
        proxy_buffering off;
    }
}
NGINX

ln -sf /etc/nginx/sites-available/irfan /etc/nginx/sites-enabled/irfan
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx

certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect
systemctl enable --now certbot.timer   # автопродление

# Наружу оставляем только 80/443 (и 1935 для RTMP от устаза).
# Порты 8090/8888 теперь доступны лишь локально, через nginx.
if command -v ufw >/dev/null; then
  ufw allow 80/tcp   || true
  ufw allow 443/tcp  || true
  ufw allow 1935/tcp || true
  ufw deny 8090/tcp  || true
  ufw deny 8888/tcp  || true
fi

echo
echo "==> Готово. Проверьте: curl -I https://$DOMAIN/courses.json"
echo "==> Дальше в обоих приложениях:"
echo "    - базовый адрес → https://$DOMAIN"
echo "    - убрать NSAllowsArbitraryLoads из ios/Runner/Info.plist"
echo "    - live-on.sh на сервере: URL эфира → https://$DOMAIN/hls-live/..."
