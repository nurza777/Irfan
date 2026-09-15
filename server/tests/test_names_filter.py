#!/usr/bin/env python3
"""Брань в именах: таблица соревнования и чат эфира.

Имена видят все — участники таблицы и зрители эфира, среди которых дети на
уроке. Фильтр тот же, что у сообщений чата, плюс обход латинскими буквами.

Отдельным набором, а не внутри проверок рейтинга: анонимные запросы (анкеты,
рейтинг, чат) ограничены 20 в минуту с адреса, и в общем наборе эти проверки
упирались в 429. Каждый набор поднимает свой сервер со своим счётчиком.
"""
import json
import os
import urllib.error
import urllib.request

BASE = os.environ.get('IRFAN_TEST_URL', 'http://127.0.0.1:8099')
# Аккаунты «давние» — чтобы очки не срезал потолок правдоподобия.
CREATED = 1750000000000

ok = fail = 0


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method)
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


def secret(n):
    return f'key-{n}-' + 'x' * 20


def student(n, name):
    phone = f'05551200{n:02d}'
    call('POST', '/users', {
        'phone': phone, 'name': name, 'secret': secret(n),
        'prayersRead': 40, 'score': 200, 'streak': 8, 'createdAt': CREATED,
    })
    return phone


print('== брань в именах таблицы закрыта ==')
me = student(1, 'Сука Иванов')
# «xуй» с ЛАТИНСКОЙ x — обход, которым пользуются чаще всего.
student(2, 'Большой xуй')
# Обычные слова, похожие на корни из списка, трогать нельзя.
clean = 'Хлебников Застрахуем Команда'
student(3, clean)
c, b = call('POST', '/rating', {'phone': me, 'secret': secret(1)})
check('рейтинг отдан', c == 200, (c, b))
names = [r['name'] for r in ((b or {}).get('top') or [])]
check('«Сука» закрыта', 'С*** Иванов' in names, names)
check('латинская подмена тоже закрыта', 'Большой x**' in names, names)
check('обычные слова не тронуты', clean in names, names)
blob = json.dumps(b, ensure_ascii=False).lower()
check('в ответе нет исходной брани',
      'сука' not in blob and 'xуй' not in blob, blob[:200])

print('== в чате эфира ==')
c, cm = call('POST', '/comments', {'name': 'Бляха сука', 'text': 'салам'})
check('имя закрыто, «бляха» цела',
      c == 201 and (cm or {}).get('name') == 'Бляха с***', (c, cm))
c, cm2 = call('POST', '/comments', {'name': 'Айбек', 'text': 'кто пиzдит?'})
# Слово закрывается целиком, первая буква остаётся — как в чате было и раньше.
check('текст закрыт и с латинской z, имя цело',
      c == 201 and (cm2 or {}).get('name') == 'Айбек'
      and (cm2 or {}).get('text') == 'кто п*****?', (c, cm2))

print(f'\n  итого: {ok} ok, {fail} fail')
raise SystemExit(1 if fail else 0)
