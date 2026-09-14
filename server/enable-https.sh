#!/usr/bin/env bash
#
# Перевод сервера «Ирфан» на HTTPS. Запускать НА СЕРВЕРЕ от root, когда домен
# куплен и его A-запись уже указывает на этот сервер:
#
#   ssh root@178.104.206.100
#   bash /opt/irfan-server/enable-https.sh api.irfan.kg admin@example.kg irfan.kg
#
# Первый домен — основной: именно он попадает в ссылки, которые сервер раздаёт
# приложению (уроки, эфир). Остальные просто добавляются в тот же сертификат и
# ведут на тот же сервер — так корень домена может отдавать privacy.html, не
# требуя второго сертификата.
#
# Что делает:
#   1. ставит nginx и certbot, поднимает reverse-proxy :443 → apiserver (:8090);
#   2. выпускает сертификат Let's Encrypt на все перечисленные домены
#      с автопродлением;
#   3. переводит НА HTTPS всё, что раздаёт адреса клиентам:
#        - MEDIA_BASE (ссылки на новые загруженные уроки),
#        - live-on.sh (адрес HLS-потока эфира в status.json),
#        - уже опубликованные уроки в courses.json;
#   4. печатает, что осталось сделать руками (приложение и firewall).
#
# ВАЖНО, чего этот скрипт НЕ делает:
#   * не закрывает порт 8090 — на него ходят телефоны со СТАРОЙ сборкой
#     приложения. Закрывать можно только когда все обновятся, и делать это
#     надо в панели Hetzner: ufw на сервере выключен, его правила ничего
#     не решают.
set -euo pipefail

DOMAIN="${1:-}"
EMAIL="${2:-}"
if [[ -z "$DOMAIN" || -z "$EMAIL" ]]; then
  echo "Использование: bash enable-https.sh <домен> <email> [ещё домены...]" >&2
  exit 1
fi
shift 2
ALL_DOMAINS=("$DOMAIN" ${@+"$@"})

ROOT=/opt/irfan-server
API="$ROOT/api"

echo "==> Основной домен: $DOMAIN"
[[ $# -gt 0 ]] && echo "==> Дополнительно в сертификат: $*"

# Проверяем, что домены уже смотрят на этот сервер: иначе certbot провалится
# на HTTP-01, и разбираться будет дольше.
SERVER_IP="$(curl -fsS https://api.ipify.org || true)"
for d in "${ALL_DOMAINS[@]}"; do
  d_ip="$(getent hosts "$d" | awk '{print $1}' | head -1 || true)"
  if [[ -z "$d_ip" ]]; then
    echo "!! $d пока никуда не указывает — A-запись не создана или не разошлась." >&2
    exit 1
  fi
  if [[ -n "$SERVER_IP" && "$SERVER_IP" != "$d_ip" ]]; then
    echo "!! $d указывает на $d_ip, а сервер — $SERVER_IP." >&2
    echo "   Поправьте A-запись и подождите обновления DNS." >&2
    exit 1
  fi
  echo "    $d → $d_ip"
done

apt-get update -qq
apt-get install -y -qq nginx certbot python3-certbot-nginx

# Слушаем ТОЛЬКО публичный адрес, а не 0.0.0.0.
#
# На этом сервере :443 на своём адресе уже держит tailscaled (через него
# открывается веб-панель по защищённой ссылке *.ts.net). Wildcard-слушатель
# nginx с ним конфликтует и не даёт подняться — поэтому привязка к IP.
cat > /etc/nginx/sites-available/irfan <<NGINX
server {
    listen $SERVER_IP:80;
    server_name ${ALL_DOMAINS[*]};

    # API, статика и HLS эфира — всё отдаёт apiserver.py.
    location / {
        proxy_pass http://127.0.0.1:8090;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        # Уроки — сотни мегабайт: и заливка, и перемотка идут через nginx.
        client_max_body_size 2048M;
        proxy_request_buffering off;
        proxy_buffering off;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }
}
NGINX

ln -sf /etc/nginx/sites-available/irfan /etc/nginx/sites-enabled/irfan
rm -f /etc/nginx/sites-enabled/default
nginx -t
# Именно restart, а не reload. Свежепоставленный nginx уже слушает 0.0.0.0:80
# со своим дефолтным конфигом, а reload не умеет переехать с wildcard-порта
# на конкретный IP: мастер-процесс продолжает держать 0.0.0.0:80, bind()
# на $SERVER_IP:80 падает с EADDRINUSE, и nginx тихо остаётся на старом
# конфиге — systemctl reload при этом рапортует об успехе.
systemctl enable nginx
systemctl restart nginx

# Убеждаемся, что конфиг реально применился: иначе certbot получит 404
# на ACME-проверку и придётся разбираться заново.
sleep 1
if ! ss -tln | grep -q "$SERVER_IP:80"; then
  echo "!! nginx не слушает $SERVER_IP:80 — конфиг не применился." >&2
  tail -5 /var/log/nginx/error.log >&2
  exit 1
fi
echo "==> nginx слушает $SERVER_IP:80"

CERTBOT_ARGS=()
for d in "${ALL_DOMAINS[@]}"; do CERTBOT_ARGS+=(-d "$d"); done
certbot --nginx "${CERTBOT_ARGS[@]}" --non-interactive --agree-tos -m "$EMAIL" --redirect
systemctl enable --now certbot.timer   # автопродление

# Certbot дописывает `listen 443 ssl` на ВСЕ адреса и про tailscaled не знает,
# а тот уже держит :443 на своём адресе — bind падает с EADDRINUSE, и nginx
# остаётся работать со старым конфигом, без HTTPS. Привязываем :443 к тому же
# публичному IP, что и :80.
sed -i "s|^\(\s*\)listen 443 ssl;|\1listen $SERVER_IP:443 ssl;|" \
    /etc/nginx/sites-available/irfan
nginx -t
systemctl restart nginx

sleep 1
if ! ss -tln | grep -q "$SERVER_IP:443"; then
  echo "!! nginx не слушает $SERVER_IP:443 — HTTPS не поднялся." >&2
  tail -5 /var/log/nginx/error.log >&2
  exit 1
fi
echo "==> nginx слушает $SERVER_IP:443"

BASE="https://$DOMAIN"

# --- Ссылки, которые сервер раздаёт клиентам ------------------------------

# 1. Новые загрузки: apiserver подставляет MEDIA_BASE в publicUrl.
mkdir -p /etc/systemd/system/irfan-api.service.d
cat > /etc/systemd/system/irfan-api.service.d/media-base.conf <<CONF
[Service]
Environment=IRFAN_MEDIA_BASE=$BASE
CONF
systemctl daemon-reload
systemctl restart irfan-api

# 2. Эфир: адрес HLS-потока пишется в status.json при старте трансляции.
if [[ -f "$ROOT/live-on.sh" ]]; then
  cp "$ROOT/live-on.sh" "$ROOT/live-on.sh.bak.$(date +%s)"
  sed -i "s|http://[0-9.]*:8090/hls/master.m3u8|$BASE/hls/master.m3u8|g" \
      "$ROOT/live-on.sh"
  echo "==> live-on.sh: адрес эфира → $BASE/hls/master.m3u8"
fi

# 3. Уже опубликованные уроки: без этого приложение со снятым ATS-исключением
#    перестанет их открывать (http-ссылки внутри https-приложения).
python3 - "$API/courses.json" "$BASE" <<'PY'
import json, re, shutil, sys, time
path, base = sys.argv[1], sys.argv[2]
try:
    with open(path, encoding='utf-8') as f:
        cat = json.load(f)
except (FileNotFoundError, ValueError):
    print('==> courses.json не прочитан — уроки не трогаю')
    sys.exit(0)
shutil.copy2(path, f'{path}.before-https.{int(time.time())}')
rx = re.compile(r'^http://[0-9.]+(?::\d+)?')
n = 0


def fix(block):
    global n
    for d in block.get('directions') or []:
        for c in d.get('courses') or []:
            for les in c.get('lessons') or []:
                url = les.get('url') or ''
                new = rx.sub(base, url)
                if new != url:
                    les['url'] = new
                    n += 1


for t in cat.get('teachers') or []:
    fix(t)
fix(cat)
with open(path, 'w', encoding='utf-8') as f:
    json.dump(cat, f, ensure_ascii=False, indent=2)
print(f'==> courses.json: переписано ссылок на уроки — {n}')
PY

echo
echo "==> Готово. Проверьте:"
echo "    curl -I $BASE/courses.json"
echo
echo "==> Осталось сделать руками:"
echo "    1) В приложении: ApiConfig.defaultBase → '$BASE',"
echo "       затем убрать NSAllowsArbitraryLoads из ios/Runner/Info.plist,"
echo "       пересобрать и выложить."
echo "    2) Порт 8090 НЕ закрывать, пока на телефонах есть старая сборка."
echo "       Когда все обновятся — закрыть 8090 и 8888 в панели Hetzner"
echo "       (ufw на сервере выключен, его правила ни на что не влияют)."
