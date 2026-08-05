#!/usr/bin/env python3
"""Приём сбоев: группировка по видам и закрытость от посторонних."""
import base64
import json
import os
import sys
import urllib.error
import urllib.request

BASE = os.environ.get('IRFAN_TEST_URL', 'http://127.0.0.1:8099')
ADMIN = 'Basic ' + base64.b64encode(b'admin:adminpw').decode()
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


CRASH = {'error': 'Null check operator used on a null value',
         'stack': '#0 _HomePageState.build (home_page.dart:120)\n'
                  '#1 StatefulElement.build',
         'fatal': True, 'version': '1.0.0+1', 'platform': 'ios 18.0'}

print('== приём ==')
c, b = call('POST', '/crash', CRASH)
check('сбой принят', c == 201, (c, b))

c, b = call('POST', '/crash', {'error': ''})
check('пустой отвергнут', c == 400, (c, b))

print('== группировка ==')
for _ in range(4):
    call('POST', '/crash', CRASH)
c, b = call('GET', '/crashes.json', None, ADMIN)
check('один вид, а не пять записей', isinstance(b, list) and len(b) == 1, b)
check('счётчик вырос до 5', b[0].get('count') == 5 if b else False, b)
check('версия сохранена', (b[0].get('version') if b else '') == '1.0.0+1', b)

other = dict(CRASH, error='RangeError (index): Invalid value')
call('POST', '/crash', other)
c, b = call('GET', '/crashes.json', None, ADMIN)
check('другая ошибка — отдельная запись', len(b) == 2, len(b))

# Тот же текст, но упало в другом месте — это другой сбой.
same_text = dict(CRASH, stack='#0 _ZikrPageState.build (zikr_page.dart:44)')
call('POST', '/crash', same_text)
c, b = call('GET', '/crashes.json', None, ADMIN)
check('то же сообщение из другого места — отдельно', len(b) == 3, len(b))

print('== доступ ==')
c, _ = call('GET', '/crashes.json')
check('посторонний список не видит', c == 401, c)

print(f'\nитого: {ok} ok, {fail} fail')
sys.exit(1 if fail else 0)
