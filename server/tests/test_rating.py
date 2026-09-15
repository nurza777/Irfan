#!/usr/bin/env python3
"""Соревнование и приглашения: очки, места, круг друзей, защита от накрутки."""
import base64
import json
import os
import urllib.error
import urllib.request

BASE = os.environ.get('IRFAN_TEST_URL', 'http://127.0.0.1:8099')
ADMIN = 'Basic ' + base64.b64encode(b'admin:adminpw').decode()
# Дата создания аккаунта — июнь 2025. Раньше 2025-01-01 сервер даты не
# принимает (защита от «состаривания» аккаунта ради накрутки) и подставляет
# «сейчас», отчего потолок правдоподобия становится крошечным. На этом
# и спотыкался первый вариант теста: 300 намазов резались до 10.
CREATED = 1748736000000

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


def secret(n):
    return f'key-{n}-' + 'x' * 20


def student(n, name, prayers, score, phone=None):
    phone = phone or f'05551100{n:02d}'
    call('POST', '/users', {
        'phone': phone, 'name': name, 'secret': secret(n),
        'prayersRead': prayers, 'score': score, 'streak': prayers // 5,
        'createdAt': CREATED,
    })
    return phone


print('== трое учеников с разными очками ==')
p1 = student(1, 'Первый', 300, 1800)
p2 = student(2, 'Второй', 100, 600)
p3 = student(3, 'Третий', 50, 300)

c, b = call('POST', '/rating', {'phone': p2, 'secret': secret(2)})
check('рейтинг отдан', c == 200, (c, b))
top = (b or {}).get('top') or []
check('в таблице все трое', len(top) >= 3, len(top))
check('первым идёт лучший', top and top[0]['name'] == 'Первый', top[:1])
check('очки больше потолка кошелька',
      top and top[0]['points'] > 1000, top[:1] if top else None)

print('== номера телефонов наружу не уходят ==')
blob = json.dumps(b, ensure_ascii=False)
check('в ответе нет номеров', '0555110' not in blob and '+996555110' not in blob,
      [x for x in blob.split('"') if '5551' in x][:3])

print('== своё место видно и отмечено ==')
me = (b or {}).get('me') or {}
check('место посчитано', me.get('rank') == 2, me)
mine = [r for r in top if r.get('me')]
check('своя строка помечена', len(mine) == 1, mine)

print('== трату кошелька рейтинг не замечает ==')
# Имя передаём обязательно: без него сервер ставит «Без имени» и затирает
# прежнее — анкета присылается целиком, а не частями.
call('POST', '/users', {'phone': p1, 'name': 'Первый', 'secret': secret(1),
                        'prayersRead': 300, 'score': 1800, 'spent': 500,
                        'createdAt': CREATED})
c, b2 = call('POST', '/rating', {'phone': p1, 'secret': secret(1)})
first = ((b2 or {}).get('top') or [{}])[0]
check('лучший остался лучшим', first.get('name') == 'Первый', first)

print('== накрутку очков режет потолок ==')
# Аккаунт ЗАВЕДЁН ТОЛЬКО ЧТО — потолок правдоподобия минимальный.
import time as _t
young = '0555119999'
call('POST', '/users', {'phone': young, 'name': 'Новичок',
                        'secret': secret(9), 'prayersRead': 5,
                        'score': 999999, 'streak': 1,
                        'createdAt': int(_t.time() * 1000)})
c, b3 = call('POST', '/rating', {'phone': young, 'secret': secret(9)})
row = next((r for r in ((b3 or {}).get('top') or []) if r['name'] == 'Новичок'), {})
check('миллион очков не засчитан', row.get('points', 0) < 5000, row)

print('== приглашения ==')
c, b4 = call('POST', '/rating', {'phone': p1, 'secret': secret(1)})
code = ((b4 or {}).get('referral') or {}).get('code') or ''
check('код приглашения выдан', len(code) == 6, code)
points_before = ((b4 or {}).get('me') or {}).get('points')

c, b5 = call('POST', '/referral/apply', {'phone': p3, 'secret': secret(3),
                                         'code': code})
check('код принят', c == 200, (c, b5))
c, _ = call('POST', '/referral/apply', {'phone': p3, 'secret': secret(3),
                                        'code': code})
check('второй раз не принимается', c == 409, c)
c, _ = call('POST', '/referral/apply', {'phone': p1, 'secret': secret(1),
                                        'code': code})
check('свой же код не принимается', c == 409, c)
c, _ = call('POST', '/referral/apply', {'phone': p2, 'secret': secret(2),
                                        'code': 'ZZZZZZ'})
check('неизвестный код отбит', c == 404, c)

print('== очков за приглашения нет ==')
# Бонусы убраны: код давал +100 за каждого активного, и давние ученики могли
# разом «пригласиться» к одному человеку. Код теперь только про круг друзей.
c, b6 = call('POST', '/rating', {'phone': p1, 'secret': secret(1)})
ref = (b6 or {}).get('referral') or {}
check('приглашённый посчитан', ref.get('invited') == 1, ref)
check('очки пригласившего не выросли',
      ((b6 or {}).get('me') or {}).get('points') == points_before,
      (points_before, (b6 or {}).get('me')))
check('полей бонуса в ответе нет',
      not any(k in ref for k in ('bonus', 'counted', 'perFriend')), ref)

empty = student(8, 'Пустой', 0, 0, phone='0555118888')
call('POST', '/referral/apply', {'phone': empty, 'secret': secret(8),
                                 'code': code})
c, b7 = call('POST', '/rating', {'phone': p1, 'secret': secret(1)})
ref2 = (b7 or {}).get('referral') or {}
check('второй приглашённый тоже посчитан', ref2.get('invited') == 2, ref2)

print('== круг друзей ==')
c, b8 = call('POST', '/rating', {'phone': p3, 'secret': secret(3)})
fr = [r['name'] for r in ((b8 or {}).get('friends') or [])]
check('в кругу есть я и пригласивший',
      'Третий' in fr and 'Первый' in fr, fr)
# «Пустой» приглашён тем же человеком — он позван вместе со мной, и это
# намеренно: круг складывается из приглашений, а не из отдельных заявок.
check('позванный вместе со мной тоже в кругу', 'Пустой' in fr, fr)
check('посторонний в круг не попал', 'Второй' not in fr, fr)

print('== без ключа устройства рейтинг не отдаётся ==')
c, _ = call('POST', '/rating', {'phone': p1})
check('без ключа отказ', c == 403, c)
c, _ = call('POST', '/rating', {'phone': p1, 'secret': secret(2)})
check('чужой ключ не проходит', c == 403, c)

print(f'\n  итого: {ok} ok, {fail} fail')
raise SystemExit(1 if fail else 0)
