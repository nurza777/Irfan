#!/usr/bin/env python3
"""Новость с фото: от загрузки устазом до ленты ученика.

Экранную часть (выбор файла в галерее) тестами не покрыть, а всё, что
после неё, — можно: файл уходит тем же PUT в uploads/, что и уроки, ссылка
на него попадает в заявку, админ одобряет, и вложение оказывается в
news.json, откуда его читает приложение. Каждый шаг тут отдельно, чтобы при
поломке было видно, какой именно.
"""
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

# Настоящий (минимальный) JPEG: сервер смотрит на расширение, но пусть
# в uploads/ лежит файл, а не выдумка.
JPEG = base64.b64decode(
    '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRof'
    'Hh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAAB'
    'AAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q==')


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
        with urllib.request.urlopen(req, timeout=10) as r:
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


print('== устаз прикладывает фото ==')
c, b = call('PUT', '/uploads/novost-foto.jpg', JPEG, USTAZ, 'image/jpeg')
check('фото загружается устазом', c in (200, 201), (c, b))
photo_url = b.get('publicUrl') if isinstance(b, dict) else ''
check('сервер вернул адрес файла', bool(photo_url), b)

c, _ = call('PUT', '/uploads/zlo.exe', b'MZ', USTAZ, 'application/octet-stream')
check('посторонний тип файла не принимается', c == 415, c)

c, _ = call('PUT', '/uploads/chuzhoe.jpg', JPEG, None, 'image/jpeg')
check('без входа в кабинет загрузить нельзя', c in (401, 403), c)

print('== заявка на новость с вложением ==')
pending = {
    'status': 'pending',
    'submittedAt': '2026-09-18T10:00:00.000',
    'author': 'Устаз',
    'items': [{
        'title': 'Открытие курса',
        'body': 'Занятия в понедельник.',
        'date': '2026-09-18T09:00:00.000',
        'media': [{'type': 'image', 'url': photo_url}],
    }],
}
c, _ = call('PUT', '/news_pending.json', pending, USTAZ)
check('заявка уходит на модерацию', c in (200, 201), c)

c, b = call('GET', '/news_pending.json', None, ADMIN)
got = (b.get('items') or [{}])[0].get('media') if isinstance(b, dict) else None
check('админ видит вложение в заявке',
      bool(got) and got[0].get('url') == photo_url, b)

print('== публикация ученикам ==')
live = {'updated': 'x', 'items': pending['items']}
c, _ = call('PUT', '/news.json', live, ADMIN)
check('админ публикует новость', c in (200, 201), c)

c, b = call('GET', '/news.json')
items = b.get('items') if isinstance(b, dict) else []
media = (items or [{}])[0].get('media') or []
check('ученик получает новость с фото',
      bool(media) and media[0].get('type') == 'image', b)
check('ссылка ведёт в uploads', '/uploads/' in (media[0].get('url') if media else ''),
      media)

print('== фото новости открыто всем ==')
name = (media[0]['url'].rsplit('/', 1)[-1]) if media else ''
c, _ = call('GET', f'/uploads/{name}')
check('фото отдаётся без входа', c == 200, c)

print(f'\nитого: {ok} ok, {fail} fail')
sys.exit(1 if fail else 0)
