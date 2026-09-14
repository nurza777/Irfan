#!/usr/bin/env python3
"""Чат с поддержкой: доступ к переписке и роли.

Главное, что проверяем, — переписка личная. Одного номера телефона для
доступа мало: иначе прохожий, знающий номер, читал бы чужие обращения.
"""
import base64
import json
import os
import urllib.error
import urllib.request

BASE = os.environ.get('IRFAN_TEST_URL', 'http://127.0.0.1:8099')
ADMIN = 'Basic ' + base64.b64encode(b'admin:adminpw').decode()
MINE = 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC='
THEIRS = 'DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD='
PHONE = '0555777888'

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


print('== ученик заводится и пишет в поддержку ==')
call('POST', '/users', {'phone': PHONE, 'name': 'Айгерим', 'age': 25,
                        'secret': MINE, 'createdAt': 1750000000000})
c, b = call('POST', '/support/send', {'phone': PHONE, 'secret': MINE,
                                      'text': 'Здравствуйте, не открывается курс'})
check('сообщение принято', c == 201, (c, b))
check('текст сохранён', isinstance(b, dict) and 'курс' in b.get('text', ''), b)

print('== чужой ключ к переписке не пускают ==')
c, b = call('POST', '/support/history', {'phone': PHONE, 'secret': THEIRS})
check('чтение чужим ключом отбито', c == 403, (c, b))
c, b = call('POST', '/support/send', {'phone': PHONE, 'secret': THEIRS,
                                      'text': 'пишу от чужого имени'})
check('запись чужим ключом отбита', c == 403, (c, b))

print('== без ключа вовсе — тоже нет ==')
c, b = call('POST', '/support/history', {'phone': PHONE})
check('чтение без ключа отбито', c == 403, (c, b))

print('== владелец читает свою переписку ==')
c, b = call('POST', '/support/history', {'phone': PHONE, 'secret': MINE})
check('переписка отдана', c == 200, (c, b))
msgs = (b or {}).get('messages') or []
check('в ней одно сообщение', len(msgs) == 1, msgs)
check('оно от ученика', msgs and msgs[0].get('from') == 'user', msgs)

print('== персонал видит очередь и отвечает ==')
c, b = call('POST', '/support/threads', None, ADMIN)
check('список переписок отдан', c == 200, (c, b))
th = (b or {}).get('threads') or []
check('переписка в списке', any(t['student'].endswith('777888') for t in th), th)

c, b = call('POST', '/support/reply',
            {'student': PHONE, 'text': 'Проверили, доступ выдали'}, ADMIN)
check('ответ принят', c == 201, (c, b))

print('== ученику без прав очередь недоступна ==')
c, b = call('POST', '/support/threads', None)
check('очередь без пароля отбита', c in (401, 403), (c, b))
c, b = call('POST', '/support/reply', {'student': PHONE, 'text': 'я админ'})
check('ответ без пароля отбит', c in (401, 403), (c, b))

print('== ответ дошёл до ученика ==')
c, b = call('POST', '/support/history', {'phone': PHONE, 'secret': MINE})
msgs = (b or {}).get('messages') or []
check('сообщений стало два', len(msgs) == 2, msgs)
check('второе — от поддержки', len(msgs) > 1 and msgs[1].get('from') == 'staff', msgs)

print('== пустое сообщение не проходит ==')
c, b = call('POST', '/support/send', {'phone': PHONE, 'secret': MINE, 'text': '   '})
check('пустое отклонено', c == 400, (c, b))

print('== счётчик непрочитанных ответов ==')
c, b = call('POST', '/support/unread', {'phone': PHONE, 'secret': MINE})
check('после чтения переписки — ноль', c == 200 and b.get('unread') == 0, (c, b))
call('POST', '/support/reply', {'student': PHONE, 'text': 'Ещё один ответ'}, ADMIN)
c, b = call('POST', '/support/unread', {'phone': PHONE, 'secret': MINE})
check('новый ответ посчитан', c == 200 and b.get('unread') == 1, (c, b))
c, b = call('POST', '/support/unread', {'phone': PHONE, 'secret': MINE})
check('сам запрос счётчик не сбрасывает', c == 200 and b.get('unread') == 1, (c, b))
c, b = call('POST', '/support/unread', {'phone': PHONE, 'secret': THEIRS})
check('с чужим ключом счётчик не отдан', c == 403, (c, b))
call('POST', '/support/history', {'phone': PHONE, 'secret': MINE})
c, b = call('POST', '/support/unread', {'phone': PHONE, 'secret': MINE})
check('открыл переписку — снова ноль', c == 200 and b.get('unread') == 0, (c, b))

print(f'\n  итого: {ok} ok, {fail} fail')
raise SystemExit(1 if fail else 0)
