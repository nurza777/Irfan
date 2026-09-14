#!/usr/bin/env python3
"""Пуш-уведомления через APNs: хранилище токенов и отправка.

Зачем отдельным файлом, а не внутри apiserver.py: отправкой занимается ещё и
`live-on.sh` при старте эфира — то есть код нужен и как модуль, и как команда.

Ключ APNs (.p8) заводится в аккаунте Apple Developer и на сервере лежит в
`/etc/irfan/`, рядом с остальными секретами и вне раздаваемого каталога.
Настройки — `/etc/irfan/apns.json`:

    {
      "key_path":  "/etc/irfan/apns.p8",
      "key_id":    "ABCD123456",          # 10 знаков, из имени файла ключа
      "team_id":   "6W553K32Y3",          # Apple Developer → Membership
      "bundle_id": "kg.irfan.irfan",
      "production": false                 # true после выхода в App Store
    }

Пока файла нет, отправка молча ничего не делает: сервер должен продолжать
работать и без пушей, а эфир — начинаться, даже если Apple недоступна.
"""

import json
import os
import subprocess
import threading
import time

CONFIG = os.environ.get('IRFAN_APNS_CFG', '/etc/irfan/apns.json')
# Токены устройств — опознаватели, поэтому файл лежит РЯДОМ с api/, а не
# внутри: всё, что внутри, раздаётся по HTTP.
TOKENS = os.environ.get('IRFAN_PUSH_TOKENS',
                        '/opt/irfan-server/push-tokens.json')

_lock = threading.Lock()
_jwt_cache = {'token': None, 'made': 0}


def _cfg():
    try:
        with open(CONFIG, encoding='utf-8') as f:
            c = json.load(f)
        return c if isinstance(c, dict) else None
    except (OSError, ValueError):
        return None


def _load():
    try:
        with open(TOKENS, encoding='utf-8') as f:
            d = json.load(f)
        return d if isinstance(d, list) else []
    except (OSError, ValueError):
        return []


def _save(items):
    tmp = TOKENS + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(items, f, ensure_ascii=False, indent=2)
    os.replace(tmp, TOKENS)
    try:
        os.chmod(TOKENS, 0o600)
    except OSError:
        pass


def register(token, device=None, platform='ios'):
    """Запоминает токен устройства. Возвращает сколько токенов всего.

    Ключ устройства храним рядом, чтобы при переустановке приложения старый
    токен того же телефона заменялся, а не копился вечно: APNs выдаёт новый
    токен после переустановки, и без этого список рос бы бесконечно.
    """
    token = str(token or '').strip()
    # Токен APNs — шестнадцатеричная строка. Проверяем, чтобы в файл не
    # попадал мусор от случайного или злонамеренного запроса.
    if not token or len(token) > 200 or any(
            c not in '0123456789abcdefABCDEF' for c in token):
        return None
    device = str(device or '')[:200]
    now = int(time.time() * 1000)
    with _lock:
        items = [r for r in _load()
                 if r.get('token') != token
                 and not (device and r.get('device') == device)]
        items.append({'token': token, 'device': device,
                      'platform': platform, 'at': now})
        _save(items)
        return len(items)


def forget(tokens):
    """Убирает токены, которые Apple объявила недействительными."""
    dead = set(tokens)
    if not dead:
        return
    with _lock:
        _save([r for r in _load() if r.get('token') not in dead])


def _jwt(cfg):
    """Токен авторизации APNs. Живёт час; Apple отвергает старше часа и
    ругается на слишком частый выпуск — поэтому кэшируем."""
    now = time.time()
    if _jwt_cache['token'] and now - _jwt_cache['made'] < 1800:
        return _jwt_cache['token']
    try:
        import jwt as pyjwt
        with open(cfg['key_path'], 'rb') as f:
            key = f.read()
        tok = pyjwt.encode(
            {'iss': cfg['team_id'], 'iat': int(now)},
            key, algorithm='ES256',
            headers={'kid': cfg['key_id']})
        _jwt_cache.update(token=tok, made=now)
        return tok
    except Exception as e:            # noqa: BLE001 — причина уходит в лог
        print('apns: не удалось подписать токен:', e)
        return None


def send(title, body, screen='live', only=None, urgent=True):
    """Шлёт уведомление на известные устройства.

    `only` — отбор адресатов: функция, получающая запись токена и
    отвечающая, слать ли на неё. Без отбора — всем (так объявляется эфир).
    Ответ поддержки, наоборот, адресный: он уходит только на телефоны того
    ученика, которому ответили.

    `urgent` — пробиваться ли сквозь «Не беспокоить». Эфиру можно: он идёт
    здесь и сейчас. Ответу поддержки — нет: он подождёт, пока человек
    освободится.

    Возвращает (доставлено, всего). Ошибки не бросает: отправка вызывается
    из хука старта эфира, и падение здесь не должно мешать трансляции.
    """
    cfg = _cfg()
    if not cfg:
        print('apns: /etc/irfan/apns.json нет — пуши не настроены, пропускаю')
        return (0, 0)
    items = _load()
    if only is not None:
        items = [r for r in items if only(r)]
    if not items:
        return (0, 0)
    auth = _jwt(cfg)
    if not auth:
        return (0, len(items))

    host = ('api.push.apple.com' if cfg.get('production')
            else 'api.sandbox.push.apple.com')
    payload = json.dumps({
        'aps': {
            'alert': {'title': title, 'body': body},
            'sound': 'default',
            # Эфир идёт здесь и сейчас — уведомление должно пробиться
            # сквозь «Не беспокоить», как и напоминание о намазе.
            'interruption-level': 'time-sensitive' if urgent else 'active',
        },
        'irfan': {'screen': screen},
    }, ensure_ascii=False)

    ok, dead = 0, []
    for rec in items:
        tok = rec.get('token')
        if not tok:
            continue
        try:
            r = subprocess.run(
                ['curl', '-s', '--http2', '-m', '10',
                 '-o', '/dev/null', '-w', '%{http_code}',
                 '-H', f'authorization: bearer {auth}',
                 '-H', f'apns-topic: {cfg["bundle_id"]}',
                 '-H', 'apns-push-type: alert',
                 '-H', 'apns-priority: 10',
                 '-d', payload,
                 f'https://{host}/3/device/{tok}'],
                capture_output=True, text=True, timeout=15)
            code = (r.stdout or '').strip()
            if code == '200':
                ok += 1
            elif code in ('400', '410'):
                # 410 — устройство больше не принимает, 400 — токен не годится
                # (например, песочница против боевого APNs). И то и другое
                # значит: держать его в списке незачем.
                dead.append(tok)
            else:
                print(f'apns: код {code} для токена ...{tok[-8:]}')
        except (subprocess.SubprocessError, OSError) as e:
            print('apns: сбой отправки:', e)
    if dead:
        forget(dead)
        print(f'apns: убрано недействительных токенов — {len(dead)}')
    return (ok, len(items))


if __name__ == '__main__':
    import sys
    # Вызывается из live-on.sh: push.py "<заголовок>" "<текст>"
    t = sys.argv[1] if len(sys.argv) > 1 else 'Начался прямой эфир'
    b = sys.argv[2] if len(sys.argv) > 2 else 'Устаз вышел в эфир — заходите.'
    sent, total = send(t, b)
    print(f'apns: отправлено {sent} из {total}')
