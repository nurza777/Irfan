#!/usr/bin/env python3
"""Обращения к App Store Connect API по ключу команды.

Зачем: смена сборки у версии, проверка обработки загрузки и отправка на
проверку — всё это иначе делается только руками в браузере. Ключ лежит
у владельца на диске и сюда не копируется.
"""
import json
import os
import sys
import time
import urllib.request

import jwt

# Опознаватели ключа — рядом с самим ключом, вне репозитория: он публичный.
# Формат ~/Documents/irfan-keys/asc.json: {"key_id": "...", "issuer": "..."}.
# Переменные окружения ASC_KEY_ID / ASC_ISSUER / ASC_KEY важнее файла.
_KEYS_DIR = os.path.expanduser('~/Documents/irfan-keys')
try:
    with open(os.path.join(_KEYS_DIR, 'asc.json')) as _f:
        _LOCAL = json.load(_f)
except (OSError, ValueError):
    _LOCAL = {}
KEY_ID = os.environ.get('ASC_KEY_ID') or _LOCAL.get('key_id', '')
ISSUER = os.environ.get('ASC_ISSUER') or _LOCAL.get('issuer', '')
if not KEY_ID or not ISSUER:
    sys.exit(f'Нет key_id/issuer: заполните {_KEYS_DIR}/asc.json '
             'или ASC_KEY_ID и ASC_ISSUER')
KEY_PATH = os.environ.get(
    'ASC_KEY', os.path.join(_KEYS_DIR, f'AuthKey_{KEY_ID}.p8'))
BASE = 'https://api.appstoreconnect.apple.com'


def token():
    with open(KEY_PATH) as f:
        key = f.read()
    now = int(time.time())
    return jwt.encode(
        {'iss': ISSUER, 'iat': now, 'exp': now + 900, 'aud': 'appstoreconnect-v1'},
        key, algorithm='ES256', headers={'kid': KEY_ID, 'typ': 'JWT'})


def call(method, path, body=None):
    req = urllib.request.Request(
        BASE + path, method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={'Authorization': 'Bearer ' + token(),
                 'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {'raw': raw.decode(errors='replace')[:500]}


if __name__ == '__main__':
    method, path = sys.argv[1], sys.argv[2]
    body = json.loads(sys.argv[3]) if len(sys.argv) > 3 else None
    code, data = call(method, path, body)
    print(code)
    print(json.dumps(data, ensure_ascii=False, indent=2)[:4000])
