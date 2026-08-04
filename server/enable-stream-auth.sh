#!/usr/bin/env bash
#
# Публикация эфира под паролем (запускать НА СЕРВЕРЕ от root).
#
#   bash enable-stream-auth.sh
#
# Зачем: путь потока `live/<ключ-эфира>` был константой в сборке приложения
# устаза, а MediaMTX пускал публиковать кого угодно. В приложении из App Store
# так нельзя — строку вытащат из бинарника и вклинятся в эфир. Теперь:
#   * публиковать может только учётка `publisher` со случайным паролем;
#   * чтение (ученики, HLS, ffmpeg ABR-транскода) остаётся анонимным;
#   * пароль лежит в /etc/irfan/stream.json (chmod 600) и выдаётся приложению
#     по ручке GET /stream.json — только вошедшему устазу, по токену.
#
# Сам ключ потока не меняем: на него ссылаются mediamtx.yml и live-on.sh.
set -euo pipefail

MTX=/opt/irfan-server/mediamtx.yml
STREAM=/etc/irfan/stream.json
HOST_IP="${1:-178.104.206.100}"

[[ -f "$MTX" ]] || { echo "Нет $MTX — это точно сервер «Ирфан»?" >&2; exit 1; }

if grep -q '^authInternalUsers:' "$MTX"; then
  echo "==> authInternalUsers уже настроен, конфиг не трогаю"
else
  cp "$MTX" "$MTX.bak.$(date +%s)"
  PUBPASS="$(python3 -c 'import secrets; print(secrets.token_urlsafe(24))')"

  cat >> "$MTX" <<YML

# Публикация эфира под паролем (см. server/enable-stream-auth.sh).
# Чтение анонимное: его делают ученики и ffmpeg ABR-транскода.
authInternalUsers:
- user: any
  ips: []
  permissions:
  - action: read
  - action: playback
- user: publisher
  pass: $PUBPASS
  ips: []
  permissions:
  - action: publish
YML

  python3 - "$PUBPASS" "$STREAM" "$HOST_IP" <<'PY'
import json, os, sys
pw, path, ip = sys.argv[1], sys.argv[2], sys.argv[3]
cfg = {'rtmpUrl': f'rtmp://{ip}/live', 'key': '<ключ-эфира>',
       'user': 'publisher', 'pass': pw}
os.makedirs(os.path.dirname(path), exist_ok=True)
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, 'w', encoding='utf-8') as f:
    json.dump(cfg, f, ensure_ascii=False)
print(f'==> {path} записан (chmod 600)')
PY

  systemctl restart mediamtx
  sleep 2
fi

systemctl is-active --quiet mediamtx && echo "==> mediamtx работает"
echo "==> Проверка: публикация без пароля должна отвергаться"
echo "    ffmpeg -f lavfi -i testsrc -t 2 -f flv rtmp://127.0.0.1:1935/test/probe"
