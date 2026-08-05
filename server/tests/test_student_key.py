#!/usr/bin/env python3
"""Проверка защиты записи ученика ключом устройства."""
import base64
import json
import os
import sys
import urllib.error
import urllib.request

BASE = os.environ.get('IRFAN_TEST_URL', 'http://127.0.0.1:8099')
ADMIN = 'Basic ' + base64.b64encode(b'admin:adminpw').decode()
MINE = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='   # секрет владельца
THEIRS = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB='  # секрет чужака
CREATED = 1750000000000

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
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except ValueError:
            return e.code, raw.decode('utf-8', 'replace')


def check(name, cond, detail=''):
    global ok, fail
    if cond:
        ok += 1
        print(f'  ok   {name}')
    else:
        fail += 1
        print(f'  FAIL {name} {detail}')


def profile(secret=None, name='Настоящий', created=CREATED, phone='0555111222'):
    body = {'phone': phone, 'name': name, 'age': 30, 'city': 'Бишкек',
            'createdAt': created}
    if secret:
        body['secret'] = secret
    return call('POST', '/users', body)


print('== новая запись закрепляется за устройством ==')
c, b = profile(MINE)
check('владелец завёл запись', c == 201, (c, b))
check('ключ наружу не отдаётся', isinstance(b, dict) and 'authKey' not in b, b)

c, b = profile(MINE, name='Настоящий-2')
check('владелец правит свою запись', c == 201, (c, b))
check('имя обновилось', b.get('name') == 'Настоящий-2', b)

print('== чужой не может тронуть запись ==')
c, b = profile(THEIRS, name='Взломщик')
check('чужой ключ отвергнут', c == 403, (c, b))
c, b = call('GET', '/users.json', None, ADMIN)
rec = next(u for u in b if u['phone'] == '+996555111222')
check('имя не подменено', rec['name'] == 'Настоящий-2', rec['name'])

c, b = profile(None, name='Старое приложение')
check('запрос без ключа тоже отвергнут', c == 403, (c, b))

print('== выкуп коинов ==')
c, b = call('POST', '/redeem', {'phone': '0555111222', 'itemId': 'tasbih',
                                'secret': THEIRS})
check('чужой не выкупает награду', c == 403, (c, b))

print('== удаление аккаунта ==')
c, b = call('POST', '/account/delete', {'phone': '0555111222',
                                        'secret': THEIRS,
                                        'createdAt': CREATED})
check('чужой не удаляет аккаунт', c == 403, (c, b))
c, b = call('POST', '/account/delete', {'phone': '0555111222'})
check('без ключа не удаляет', c == 403, (c, b))
c, b = call('GET', '/users.json', None, ADMIN)
check('запись на месте', any(u['phone'] == '+996555111222' for u in b), b)

print('== старая запись (без ключа) переходит владельцу ==')
# Имитируем запись прежней сборки: заводим без ключа.
c, b = profile(None, name='Старый', phone='0555333444', created=CREATED)
check('старое приложение заводит запись', c == 201, (c, b))
c, b = profile(THEIRS, name='Чужак', phone='0555333444', created=1)
check('чужак с неверной датой не забирает', c == 403, (c, b))
c, b = profile(MINE, name='Старый', phone='0555333444', created=CREATED)
check('владелец с верной датой забирает', c == 201, (c, b))
c, b = profile(THEIRS, name='Чужак', phone='0555333444', created=CREATED)
check('после закрепления чужак не проходит', c == 403, (c, b))

print('== владелец удаляет свой аккаунт ==')
c, b = call('POST', '/account/delete', {'phone': '0555111222',
                                        'secret': MINE, 'createdAt': CREATED})
check('удаление владельцем работает', c == 200 and b.get('deleted'), (c, b))

print(f'\nитого: {ok} ok, {fail} fail')
sys.exit(1 if fail else 0)
