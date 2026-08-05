#!/usr/bin/env python3
"""Сквозная проверка токенов устаза против локальной копии сервера."""
import base64
import json
import os
import sys
import urllib.error
import urllib.request

BASE = os.environ.get('IRFAN_TEST_URL', 'http://127.0.0.1:8099')
ADMIN = 'Basic ' + base64.b64encode(b'admin:adminpw').decode()
USTAZ = 'Basic ' + base64.b64encode(b'ustaz:ustazpw').decode()

ok = fail = 0


def call(method, path, body=None, auth=None, ctype='application/json'):
    data = None
    if body is not None:
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
    req = urllib.request.Request(BASE + path, data=data, method=method)
    if auth:
        req.add_header('Authorization', auth)
    if data:
        req.add_header('Content-Type', ctype)
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


print('== заведение учётки устаза ==')
c, b = call('POST', '/staff', {'op': 'create', 'login': 'anon',
                               'password': 'ustaz-pass-123'})
check('без пароля учётку не завести', c == 401, (c, b))

c, b = call('POST', '/staff', {'op': 'create', 'login': 'fartah',
                               'password': 'ustaz-pass-123',
                               'name': 'Фартах устаз'}, ADMIN)
check('админ заводит учётку', c == 201, (c, b))
tid = b.get('teacherId') if isinstance(b, dict) else None
check('вернулся teacherId', bool(tid), b)

c, b = call('POST', '/staff', {'op': 'create', 'login': 'fartah',
                               'password': 'ustaz-pass-123'}, ADMIN)
check('повторный логин отвергнут', c == 409, (c, b))

c, b = call('POST', '/staff', {'op': 'create', 'login': 'x',
                               'password': 'ustaz-pass-123'}, ADMIN)
check('короткий логин отвергнут', c == 400, (c, b))

c, b = call('POST', '/staff', {'op': 'create', 'login': 'other',
                               'password': 'short'}, ADMIN)
check('короткий пароль отвергнут', c == 400, (c, b))

c, b = call('POST', '/staff', {'op': 'create', 'login': 'stranger',
                               'password': 'ustaz-pass-123'}, USTAZ)
check('устаз не заводит учётки', c == 401, (c, b))

print('== вход ==')
c, b = call('POST', '/auth/token', {'login': 'fartah', 'password': 'nope'})
check('неверный пароль — 401', c == 401, (c, b))

c, b = call('POST', '/auth/token', {'login': 'fartah',
                                    'password': 'ustaz-pass-123'})
check('вход выдал токен', c == 200 and b.get('token'), (c, b))
token = b.get('token') if isinstance(b, dict) else None
BEARER = 'Bearer ' + (token or '')
check('в ответе роль ustaz', b.get('role') == 'ustaz', b)
check('в ответе тот же teacherId', b.get('teacherId') == tid, b)

c, b = call('POST', '/auth/check', {}, BEARER)
check('токен опознаётся', c == 200 and b.get('login') == 'fartah', (c, b))

c, b = call('POST', '/auth/check', {}, 'Bearer forged-token-000')
check('поддельный токен — 401', c == 401, (c, b))

print('== права токена ==')
c, b = call('PUT', f'/courses_pending_{tid}.json',
            {'updated': '1', 'directions': []}, BEARER)
check('пишет свою заявку', c == 201, (c, b))

c, b = call('PUT', '/courses_pending_deadbeefdeadbeef.json',
            {'updated': '1'}, BEARER)
check('чужая заявка запрещена', c == 403, (c, b))

c, b = call('PUT', '/courses_pending.json', {'updated': '1'}, BEARER)
check('общая заявка запрещена', c == 403, (c, b))

c, b = call('PUT', '/courses.json', {'updated': '1'}, BEARER)
check('live-каталог запрещён', c == 403, (c, b))

c, b = call('GET', '/users.json', None, BEARER)
check('реестр учеников закрыт', c == 401, (c, b))

c, b = call('PUT', '/uploads/urok.mp4', b'\x00\x01\x02', BEARER, 'video/mp4')
check('загрузка урока разрешена', c == 201, (c, b))

print('== ключ эфира ==')
c, b = call('GET', '/stream.json')
check('без входа ключ не отдаётся', c == 401, (c, b))
c, b = call('GET', '/stream.json', None, BEARER)
check('по токену ключ отдаётся', c == 200 and 'user=publisher' in
      str(b.get('streamKey')), (c, b))
check('пароль публикации закодирован',
      'p%40ss%20word' in str(b.get('streamKey')), b)

print('== отзыв доступа ==')
c, b = call('POST', '/staff', {'op': 'disable', 'login': 'fartah'}, ADMIN)
check('админ отключил учётку', c == 200, (c, b))
c, b = call('POST', '/auth/check', {}, BEARER)
check('токен отключённого не работает', c == 401, (c, b))
c, b = call('POST', '/auth/token', {'login': 'fartah',
                                    'password': 'ustaz-pass-123'})
check('отключённый не входит', c == 401, (c, b))

c, b = call('POST', '/staff', {'op': 'enable', 'login': 'fartah'}, ADMIN)
c, b = call('POST', '/auth/token', {'login': 'fartah',
                                    'password': 'ustaz-pass-123'})
check('после включения входит снова', c == 200, (c, b))
tok2 = 'Bearer ' + b.get('token')

c, b = call('POST', '/auth/logout', {}, tok2)
check('выход отвечает ok', c == 200, (c, b))
c, b = call('POST', '/auth/check', {}, tok2)
check('после выхода токен мёртв', c == 401, (c, b))

print('== список учёток ==')
c, b = call('GET', '/staff.json', None, ADMIN)
check('панель видит список', c == 200 and b['staff'][0]['login'] == 'fartah',
      (c, b))
check('хеши паролей не отдаются', 'pass' not in b['staff'][0], b)
c, b = call('GET', '/staff.json')
check('список закрыт без админа', c == 401, (c, b))

print(f'\nитого: {ok} ok, {fail} fail')
sys.exit(1 if fail else 0)
