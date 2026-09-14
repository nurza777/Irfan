#!/usr/bin/env python3
"""Книги: каталог и раздача файлов.

Проверяем две вещи. Каталог правит только админ, а читает кто угодно — книги
открыты и без регистрации. И файлы из каталога отдаются без подписанной
ссылки, но ТОЛЬКО они: включённая защита уроков не должна слабеть от того,
что рядом появились книги.
"""
import base64
import json
import os
import urllib.error
import urllib.request

BASE = os.environ.get('IRFAN_TEST_URL', 'http://127.0.0.1:8099')
ADMIN = 'Basic ' + base64.b64encode(b'admin:adminpw').decode()
USTAZ = 'Basic ' + base64.b64encode(b'ustaz:ustazpw').decode()

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
                return r.status, (json.loads(raw) if raw else None)
            except ValueError:
                return r.status, raw
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


CATALOG = {
    'updated': 1,
    'items': [{
        'id': 'b1',
        'title': 'Рияд ас-Салихин',
        'author': 'имам ан-Навави',
        'file': 'kitab.pdf',
        'cover': 'oblozhka.jpg',
    }],
}

print('== до публикации каталога файл книги закрыт, как любой другой ==')
c, _ = call('GET', '/uploads/kitab.pdf')
check('PDF без подписи не отдан', c == 403, c)

print('== править каталог может только админ ==')
c, _ = call('PUT', '/books.json', CATALOG)
check('без пароля — отказ', c in (401, 403), c)
c, _ = call('PUT', '/books.json', CATALOG, USTAZ)
check('устазу — отказ', c == 403, c)
c, _ = call('PUT', '/books.json', CATALOG, ADMIN)
check('админу — принято', c == 201, c)

print('== каталог читается без пароля ==')
c, b = call('GET', '/books.json')
check('каталог отдан', c == 200, (c, b))
items = (b or {}).get('items') if isinstance(b, dict) else None
check('в нём одна книга', isinstance(items, list) and len(items) == 1, b)

print('== файлы из каталога идут без подписи ==')
c, b = call('GET', '/uploads/kitab.pdf')
check('PDF отдан', c == 200, c)
check('это тот самый файл', isinstance(b, bytes) and b.startswith(b'%PDF'), b)
c, _ = call('GET', '/uploads/oblozhka.jpg')
check('обложка отдана', c == 200, c)

print('== а уроки по-прежнему под замком ==')
c, _ = call('GET', '/uploads/urok.mp4')
check('урок без подписи не отдан', c == 403, c)

print('== книгу убрали из каталога — файл снова закрыт ==')
c, _ = call('PUT', '/books.json', {'updated': 2, 'items': []}, ADMIN)
check('пустой каталог принят', c == 201, c)
c, _ = call('GET', '/uploads/kitab.pdf')
check('PDF больше не отдаётся', c == 403, c)

print('== ссылка из каталога не выводит за пределы uploads ==')
c, _ = call('PUT', '/books.json', {'updated': 3, 'items': [
    {'id': 'x', 'title': 'x', 'file': '../../auth.json'}]}, ADMIN)
check('каталог с кривой ссылкой принят', c == 201, c)
c, _ = call('GET', '/uploads/auth.json')
check('чужой файл через каталог не достать', c in (401, 403, 404), c)

print(f'\n  итого: {ok} ok, {fail} fail')
raise SystemExit(1 if fail else 0)
