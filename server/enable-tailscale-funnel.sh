#!/usr/bin/env bash
#
# HTTPS для админки «Ирфан» БЕЗ покупки домена — через Tailscale Funnel.
#
# Что получаем:
#   • стабильную ссылку вида https://irfan-server.<ваш-хвост>.ts.net
#   • настоящий сертификат Let's Encrypt, который выпускается и хранится
#     НА ЭТОМ ЖЕ сервере — шифрование сквозное, посредник не расшифровывает
#   • ничего не нужно открывать в файрволе: Tailscale сам звонит наружу
#
# Чего это НЕ делает:
#   • не переводит на HTTPS приложение студентов (там остаётся IP по HTTP);
#     гнать видео через Funnel нельзя — это не CDN, а канал для служебного
#     доступа. Видео и эфир продолжают идти напрямую с сервера.
#
# Запускать НА СЕРВЕРЕ от root:
#     bash enable-tailscale-funnel.sh
#
# Перед этим:
#   1. Завести бесплатный аккаунт на tailscale.com
#   2. Создать ключ: Settings → Keys → Generate auth key (Reusable не нужен)
#   3. Включить Funnel: Access controls → добавить в политику узел
#      "nodeAttrs": [{"target": ["*"], "attr": ["funnel"]}]
set -euo pipefail

PORT="${PORT:-8090}"
HOSTNAME_TS="${HOSTNAME_TS:-irfan-server}"

if ! command -v tailscale >/dev/null; then
  echo "==> Ставлю Tailscale"
  curl -fsSL https://tailscale.com/install.sh | sh
fi

if ! tailscale status >/dev/null 2>&1; then
  echo "==> Нужно подключить сервер к вашей сети Tailscale."
  if [[ -n "${TS_AUTHKEY:-}" ]]; then
    tailscale up --hostname="$HOSTNAME_TS" --authkey="$TS_AUTHKEY"
  else
    echo "    Ключа в TS_AUTHKEY нет — открою ссылку для входа в браузере."
    echo "    Либо перезапустите так:  TS_AUTHKEY=tskey-... bash $0"
    tailscale up --hostname="$HOSTNAME_TS"
  fi
fi

echo "==> Включаю Funnel на порт $PORT"
# serve — маршрут внутрь, funnel — публикация его наружу по HTTPS.
tailscale serve --bg "http://127.0.0.1:${PORT}"
tailscale funnel --bg "http://127.0.0.1:${PORT}"

URL="$(tailscale status --json 2>/dev/null \
  | grep -o '"DNSName":"[^"]*"' | head -1 | cut -d'"' -f4 | sed 's/\.$//')"

echo
echo "==> Готово."
if [[ -n "$URL" ]]; then
  echo "    Админка: https://${URL}/admin.html"
else
  echo "    Адрес посмотрите командой: tailscale funnel status"
fi
echo
echo "    Сертификат выпускается на этот сервер и обновляется сам."
echo "    Порт $PORT наружу открывать НЕ нужно — можно закрыть:"
echo "        ufw deny ${PORT}/tcp"
echo
echo "    Проверить:  tailscale funnel status"
echo "    Выключить:  tailscale funnel --https=443 off"
