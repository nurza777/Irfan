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
import re
import subprocess
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

CONFIG = os.environ.get('IRFAN_APNS_CFG', '/etc/irfan/apns.json')
# Android: служебный аккаунт Firebase (JSON, скачивается в консоли Firebase:
# Настройки проекта → Сервисные аккаунты → «Создать закрытый ключ»).
# Пока файла нет, пуши на Android молча не отправляются — как и APNs без
# своего ключа: сервер и эфир обязаны работать без уведомлений.
FCM_CONFIG = os.environ.get('IRFAN_FCM_CFG', '/etc/irfan/fcm.json')
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
    токен того же телефона заменялся, а не копился вечно: и APNs, и FCM
    выдают новый токен после переустановки, и без этого список рос бы
    бесконечно.
    """
    token = str(token or '').strip()
    platform = platform if platform in ('ios', 'android') else 'ios'
    # Проверяем форму токена, чтобы в файл не попадал мусор от случайного
    # или злонамеренного запроса. У APNs это шестнадцатеричная строка, у
    # FCM — длиннее и с буквами, двоеточием, дефисом и подчёркиванием.
    if not _token_ok(token, platform):
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


_FCM_TOKEN_RE = re.compile(r'^[A-Za-z0-9:_\-]{20,400}$')


def _token_ok(token, platform):
    if not token:
        return False
    if platform == 'android':
        return bool(_FCM_TOKEN_RE.match(token))
    return len(token) <= 200 and all(c in '0123456789abcdefABCDEF'
                                     for c in token)


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
    """Шлёт уведомление на известные устройства — iOS через APNs, Android через FCM.

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
    items = _load()
    if only is not None:
        items = [r for r in items if only(r)]
    if not items:
        return (0, 0)
    ios = [r for r in items if (r.get('platform') or 'ios') == 'ios']
    android = [r for r in items if r.get('platform') == 'android']
    ok_i, dead_i = _send_apns(ios, title, body, screen, urgent)
    ok_a, dead_a = _send_fcm(android, title, body, screen, urgent)
    dead = dead_i + dead_a
    if dead:
        forget(dead)
        print(f'push: убрано недействительных токенов — {len(dead)}')
    return (ok_i + ok_a, len(items))


def _send_apns(items, title, body, screen, urgent):
    """APNs. Возвращает (доставлено, мёртвые токены)."""
    if not items:
        return (0, [])
    cfg = _cfg()
    if not cfg:
        print('apns: /etc/irfan/apns.json нет — пуши iOS не настроены, пропускаю')
        return (0, [])
    auth = _jwt(cfg)
    if not auth:
        return (0, [])

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
    return (ok, dead)


_fcm_cache = {'token': None, 'exp': 0}


def _fcm_cfg():
    try:
        with open(FCM_CONFIG, encoding='utf-8') as f:
            c = json.load(f)
    except (OSError, ValueError):
        return None
    if not isinstance(c, dict):
        return None
    if not all(c.get(k) for k in ('project_id', 'client_email', 'private_key')):
        print('fcm: в fcm.json нет project_id, client_email или private_key')
        return None
    return c


def _fcm_access_token(cfg):
    """Токен доступа Google OAuth для FCM. Живёт час — держим в памяти.

    Подписываем запрос сами (PyJWT + RS256), а не библиотекой google-auth:
    на сервере её нет, а тянуть пакет ради одного запроса незачем.
    """
    now = int(time.time())
    if _fcm_cache['token'] and _fcm_cache['exp'] - 120 > now:
        return _fcm_cache['token']
    try:
        import jwt as pyjwt
        assertion = pyjwt.encode({
            'iss': cfg['client_email'],
            'scope': 'https://www.googleapis.com/auth/firebase.messaging',
            'aud': 'https://oauth2.googleapis.com/token',
            'iat': now,
            'exp': now + 3600,
        }, cfg['private_key'], algorithm='RS256')
        data = urllib.parse.urlencode({
            'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            'assertion': assertion,
        }).encode()
        req = urllib.request.Request('https://oauth2.googleapis.com/token',
                                     data=data, method='POST')
        with urllib.request.urlopen(req, timeout=15) as r:
            got = json.load(r)
        _fcm_cache.update(token=got['access_token'],
                          exp=now + int(got.get('expires_in', 3600)))
        return _fcm_cache['token']
    except Exception as e:            # noqa: BLE001 — причина уходит в лог
        print('fcm: не удалось получить токен доступа:', e)
        return None


def _send_fcm(items, title, body, screen, urgent):
    """FCM HTTP v1. Возвращает (доставлено, мёртвые токены)."""
    if not items:
        return (0, [])
    cfg = _fcm_cfg()
    if not cfg:
        print('fcm: /etc/irfan/fcm.json нет — пуши Android не настроены, пропускаю')
        return (0, [])
    access = _fcm_access_token(cfg)
    if not access:
        return (0, [])
    url = ('https://fcm.googleapis.com/v1/projects/'
           f'{cfg["project_id"]}/messages:send')
    ok, dead = 0, []
    for rec in items:
        tok = rec.get('token')
        if not tok:
            continue
        message = {
            'token': tok,
            'notification': {'title': title, 'body': body},
            'data': {'screen': screen},
            'android': {
                # HIGH будит телефон из режима сна — эфиру это нужно, ответу
                # поддержки нет (см. `urgent`).
                'priority': 'HIGH' if urgent else 'NORMAL',
                'notification': {
                    # Канал заводит приложение (MainActivity): у эфира свой,
                    # чтобы его можно было выключить отдельно от азана.
                    'channel_id': 'live',
                    'sound': 'default',
                },
            },
        }
        req = urllib.request.Request(
            url, method='POST',
            data=json.dumps({'message': message}, ensure_ascii=False).encode(),
            headers={'Authorization': f'Bearer {access}',
                     'Content-Type': 'application/json; charset=utf-8'})
        try:
            with urllib.request.urlopen(req, timeout=15):
                ok += 1
        except urllib.error.HTTPError as e:
            raw = e.read().decode('utf-8', 'replace')
            # 404 — токена больше нет (удалили приложение); UNREGISTERED и
            # INVALID_ARGUMENT про токен — тоже держать незачем.
            if e.code == 404 or 'UNREGISTERED' in raw or (
                    e.code == 400 and 'registration token' in raw):
                dead.append(tok)
            else:
                print(f'fcm: код {e.code} для токена ...{tok[-8:]}: {raw[:200]}')
        except (urllib.error.URLError, OSError) as e:
            print('fcm: сбой отправки:', e)
    return (ok, dead)


if __name__ == '__main__':
    import sys
    # Вызывается из live-on.sh: push.py "<заголовок>" "<текст>"
    t = sys.argv[1] if len(sys.argv) > 1 else 'Начался прямой эфир'
    b = sys.argv[2] if len(sys.argv) > 2 else 'Устаз вышел в эфир — заходите.'
    sent, total = send(t, b)
    print(f'apns: отправлено {sent} из {total}')
