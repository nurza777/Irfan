#!/usr/bin/env python3
"""Выдача, правка и отзыв сертификатов.

Бланк с печатью организации — документ: его выдаёт только админ, номер не
должен повторяться никогда, а двойное нажатие не должно оборачиваться двумя
одинаковыми дипломами.
"""
import base64
import json
import os
import urllib.error
import urllib.request

BASE = os.environ.get('IRFAN_TEST_URL', 'http://127.0.0.1:8099')
ADMIN = 'Basic ' + base64.b64encode(b'admin:adminpw').decode()
USTAZ = 'Basic ' + base64.b64encode(b'ustaz:ustazpw').decode()
PHONE = '+996555111222'
OTHER = '+996555333444'

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


# Заводим двух учеников: имя и пол берутся из реестра.
call('POST', '/users', {'phone': PHONE, 'name': 'ашырматова жаркын',
                        'gender': 'female'})
call('POST', '/users', {'phone': OTHER, 'name': 'Тураев Зафархужа',
                        'gender': 'male'})

# — Права
st, _ = call('POST', '/certificates/issue', {'template': 'diploma'})
check('без входа выдать нельзя', st == 401, st)
st, _ = call('POST', '/certificates/issue',
             {'template': 'diploma', 'lang': 'ru', 'title': 'x',
              'students': [{'phone': PHONE}]}, auth=USTAZ)
# Отказ по роли этот сервер отдаёт кодом 401 везде (`_deny`), а не 403.
check('устазу выдавать нельзя', st == 401, st)
st, _ = call('GET', '/certificates.json')
check('реестр анонимно не читается', st == 401, st)

# — Настраиваемые поводы
st, body = call('POST', '/cert/modules', {'items': [
    {'id': 'm1', 'label': 'Модуль 1', 'template': 'diploma',
     'ru': 'первого модуля по чтению Корана',
     'ky': 'Куран окуу боюнча биринчи модулду'},
    {'id': 'p2', 'label': 'Двухмесячная программа',
     'template': 'certificate', 'ru': 'двухмесячной программы'},
    {'label': '', 'ru': 'без названия'},
]}, auth=ADMIN)
check('модули сохраняются', st == 200 and len(body['items']) == 2, body)
check('повод без названия отброшен',
      st == 200 and all(m['label'] for m in body['items']), body)

# — Выдача пачкой
st, body = call('POST', '/certificates/issue', {
    'template': 'diploma', 'lang': 'ru', 'moduleId': 'm1',
    'course': 'Таджвид/Основы', 'teacher': 'Фархат ажы Юсупов Ирфан',
    'students': [{'phone': PHONE, 'name': 'Ашырматова Жаркын'},
                 {'phone': OTHER}],
}, auth=ADMIN)
check('выдано двоим сразу', st == 201 and len(body['issued']) == 2, body)
first = body['issued'][0] if st == 201 else {}
check('номер вида IRF-<год>-<счётчик>',
      first.get('number', '').startswith('IRF-') and
      len(first.get('number', '')) == 15, first.get('number'))
check('текст повода подставлен из настроек',
      first.get('title') == 'первого модуля по чтению Корана', first)
check('имя из формы важнее анкеты',
      first.get('name') == 'Ашырматова Жаркын', first.get('name'))
check('пол подтянут из реестра для обращения',
      first.get('gender') == 'female', first.get('gender'))
second = body['issued'][1] if st == 201 else {}
check('без имени в форме берётся анкета',
      second.get('name') == 'Тураев Зафархужа', second.get('name'))
check('номера у двоих разные',
      first.get('number') != second.get('number'), body)

# — Повтор
st, body = call('POST', '/certificates/issue', {
    'template': 'diploma', 'lang': 'ru', 'moduleId': 'm1',
    'course': 'Таджвид/Основы', 'students': [{'phone': PHONE}],
}, auth=ADMIN)
check('тот же диплом второй раз не выдаётся',
      st == 201 and not body['issued'] and
      body['skipped'][0]['why'] == 'already', body)

# Другой модуль тому же ученику — это уже другой документ.
st, body = call('POST', '/certificates/issue', {
    'template': 'certificate', 'lang': 'ky', 'moduleId': 'p2',
    'students': [{'phone': PHONE}],
}, auth=ADMIN)
check('другой повод выдаётся тому же ученику',
      st == 201 and len(body['issued']) == 1, body)
check('для кыргызского бланка берётся русский текст, если своего нет',
      st == 201 and body['issued'][0]['title'] == 'двухмесячной программы',
      body)

# — Что видит ученик
st, body = call('POST', '/users', {'phone': PHONE, 'name': 'ашырматова жаркын'})
mine = body.get('certificates') if st == 201 else None
check('ученик получает свои сертификаты', isinstance(mine, list) and
      len(mine) == 2, mine)
check('телефон в выдаче ученику не дублируется',
      isinstance(mine, list) and all('student' not in c for c in mine), mine)

# — Правка
st, body = call('POST', '/certificates/update', {
    'number': first.get('number'), 'name': 'Ашырматова Жаркын кызы',
}, auth=ADMIN)
check('имя правится', st == 200 and body['name'] == 'Ашырматова Жаркын кызы',
      body)
st, body = call('POST', '/certificates/update',
                {'number': 'IRF-2026-999999', 'name': 'x'}, auth=ADMIN)
check('правка несуществующего — 404', st == 404, st)
st, body = call('POST', '/certificates/update',
                {'number': first.get('number'), 'lang': 'de'}, auth=ADMIN)
check('чужой язык не принимается', st == 400, st)

# — Отзыв
st, body = call('POST', '/certificates/update',
                {'number': first.get('number'), 'status': 'revoked'},
                auth=ADMIN)
check('сертификат отзывается', st == 200 and body['status'] == 'revoked', body)
st, body = call('POST', '/users', {'phone': PHONE})
check('отозванный у ученика не показывается',
      st == 201 and len(body.get('certificates') or []) == 1,
      body.get('certificates'))

# — Удаление и номера
st, body = call('POST', '/certificates/delete',
                {'number': first.get('number')}, auth=ADMIN)
check('запись удаляется', st == 200 and body.get('deleted'), body)
st, body = call('POST', '/certificates/issue', {
    'template': 'gift', 'lang': 'ru', 'title': 'подарочный',
    'giftFrom': 'Жунусов Нурсултандан', 'students': [{'phone': PHONE}],
}, auth=ADMIN)
new_number = body['issued'][0]['number'] if st == 201 else ''
check('номер после удаления не переиспользуется',
      new_number and new_number != first.get('number'), new_number)
check('даритель попадает в запись',
      st == 201 and body['issued'][0]['giftFrom'] == 'Жунусов Нурсултандан',
      body)

# — Выдача на номер, которого нет в реестре
st, body = call('POST', '/certificates/issue', {
    'template': 'diploma', 'lang': 'ru', 'title': 'первого модуля',
    'students': [{'phone': '+996700999888', 'name': 'Новый Ученик'}],
}, auth=ADMIN)
check('можно выдать тому, у кого ещё нет приложения',
      st == 201 and len(body['issued']) == 1, body)
st, body = call('POST', '/certificates/issue', {
    'template': 'diploma', 'lang': 'ru', 'title': 'x',
    'students': [{'phone': '+996700111000'}],
}, auth=ADMIN)
check('без имени и без анкеты — пропуск, а не пустой бланк',
      st == 201 and body['skipped'][0]['why'] == 'no name', body)

print(f'\n  итог: {ok} ok, {fail} fail')
raise SystemExit(1 if fail else 0)
