#!/usr/bin/env python3
"""Подписанные ссылки на уроки: выдача, проверка и то, что сортировка цела."""
import base64
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

BASE = os.environ.get('IRFAN_TEST_URL', 'http://127.0.0.1:8099')
ADMIN = 'Basic ' + base64.b64encode(b'admin:adminpw').decode()
SECRET = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
CREATED = 1750000000000
PHONE = '0555444333'
ok = fail = 0


def call(method, path, body=None, auth=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method)
    if auth:
        req.add_header('Authorization', auth)
    if data:
        req.add_header('Content-Type', 'application/json')
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            raw = r.read()
            try:
                return r.status, json.loads(raw)
            except ValueError:
                return r.status, raw
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except ValueError:
            return e.code, raw


def check(name, cond, detail=''):
    global ok, fail
    if cond:
        ok += 1
        print(f'  ok   {name}')
    else:
        fail += 1
        print(f'  FAIL {name} {detail}')


# Ученик заводится и закрепляет за собой ключ устройства.
call('POST', '/users', {'phone': PHONE, 'name': 'Ученик',
                        'createdAt': CREATED, 'secret': SECRET})

print('== выдача ссылки ==')
c, b = call('POST', '/media/link', {'name': 'urok.mp4', 'phone': PHONE,
                                    'createdAt': CREATED, 'secret': SECRET})
check('ученик получает ссылку', c == 200 and 'sig=' in str(b.get('url')), (c, b))
signed = b.get('url', '') if isinstance(b, dict) else ''

c, b = call('POST', '/media/link', {'name': 'urok.mp4'})
check('без ключа ссылку не дают', c == 403, (c, b))

c, b = call('POST', '/media/link', {'name': 'urok.mp4', 'phone': PHONE,
                                    'createdAt': CREATED,
                                    'secret': 'BBBBBBBBBBBBBBBBBBBBBBBBBBBB'})
check('чужой ключ не проходит', c == 403, (c, b))

c, b = call('POST', '/media/link', {'name': 'urok.mp4'}, ADMIN)
check('персонал получает по своей авторизации', c == 200, (c, b))

c, b = call('POST', '/media/link', {'name': 'нет-такого.mp4', 'phone': PHONE,
                                    'createdAt': CREATED, 'secret': SECRET})
check('несуществующий файл — 404', c == 404, (c, b))

print('== проверка при отдаче ==')
path = '/uploads/' + signed.split('/uploads/')[-1] if signed else ''
c, _ = call('GET', path)
check('по подписанной ссылке урок отдаётся', c == 200, c)

c, _ = call('GET', '/uploads/urok.mp4')
check('без подписи — отказ', c == 403, c)

bad = path.replace('sig=', 'sig=0') if 'sig=' in path else path
c, _ = call('GET', bad)
check('испорченная подпись — отказ', c == 403, c)

old = '/uploads/urok.mp4?exp=1000000000&sig=' + '0' * 32
c, _ = call('GET', old)
check('просроченная ссылка — отказ', c == 403, c)

c, _ = call('GET', '/uploads/urok.mp4', None, ADMIN)
check('панель смотрит напрямую', c == 200, c)

print('== вложения новостей открыты всем ==')
# Новости читают и до регистрации: подпись просить не у кого.
c, _ = call('GET', '/uploads/novost.jpg')
check('фото новости отдаётся без подписи', c == 200, c)

c, _ = call('GET', '/uploads/urok.mp4')
check('урок рядом по-прежнему закрыт', c == 403, c)

print('== сортировка не пострадала ==')
c, b = call('GET', '/media.json', None, ADMIN)
items = {m['name']: m for m in (b.get('items') or [])} if isinstance(b, dict) else {}
check('файл на месте в списке', 'urok.mp4' in items, list(items)[:3])
check('папка сохранилась',
      items.get('urok.mp4', {}).get('folder') == 'f1', items.get('urok.mp4'))
check('подпись сохранилась',
      items.get('urok.mp4', {}).get('title') == 'Первый урок',
      items.get('urok.mp4'))
check('привязка к уроку цела',
      bool(items.get('urok.mp4', {}).get('usedIn')), items.get('urok.mp4'))

print(f'\nитого: {ok} ok, {fail} fail')
sys.exit(1 if fail else 0)
