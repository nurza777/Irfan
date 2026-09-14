#!/usr/bin/env python3
"""Проверка переноса аккаунта на другой телефон.

Аккаунт ученика живёт на устройстве: пароля на сервере нет, вся история — в
хранилище приложения. Сервер хранит слепок этой истории и отдаёт его новому
телефону, если тот доказал право на номер. Здесь проверяется ровно это право:
кто может положить слепок, кто может его забрать и что после переезда прежний
телефон теряет доступ к записи.
"""
import base64
import hashlib
import json
import os
import sys
import urllib.error
import urllib.request

BASE = os.environ.get('IRFAN_TEST_URL', 'http://127.0.0.1:8099')
ADMIN = 'Basic ' + base64.b64encode(b'admin:adminpw').decode()
MINE = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='    # старый телефон
NEW = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB='     # новый телефон
THIRD = 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC='   # посторонний
CREATED = 1750000000000
PHONE = '0555111222'
FULL = '+996555111222'

SNAP = {'v': 1,
        's': {'tracker_2026-08-01': '{"fajr":"read"}',
              'tracker_2026-08-02': '{"fajr":"read"}'},
        'i': {'coins_spent': 100},
        'b': {}, 'd': {}, 'l': {}}

ok = fail = 0

# Проверок здесь больше, чем сервер пускает анонимных POST с одного адреса за
# минуту (RATE_ANON), и на середине набора начиналось бы «too many requests».
# Ждать минуту посреди прогона незачем: адрес берётся из X-Real-IP (сервер
# верит этому заголовку от localhost — так к нему приходит nginx), поэтому
# каждая проверка представляется своим адресом. Заодно этот путь и
# проверяется по дороге.
_seq = 0


def call(method, path, body=None, auth=None):
    global _seq
    _seq += 1
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method)
    req.add_header('X-Real-IP', f'10.0.{_seq // 250}.{_seq % 250}')
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


def profile(secret, phone=PHONE, name='Ученик', pw=None):
    body = {'phone': phone, 'name': name, 'age': 30,
            'city': 'Бишкек', 'createdAt': CREATED, 'secret': secret}
    if pw is not None:
        body['pass'] = pw
    return call('POST', '/users', body)


# Доказательство пароля: приложение считает PBKDF2 от пароля с солью из
# номера и шлёт шестнадцатеричную строку. Здесь важна не сама функция, а
# то, что значение одинаково с любого телефона, — берём просто хеш.
def proof(password):
    return hashlib.sha256(password.encode()).hexdigest()


def fresh_ticket(phone=PHONE):
    """Проходит подтверждение номера как это делает приложение."""
    call('POST', '/verify/request', {'phone': phone})
    _, codes = call('GET', '/verifications.json', None, ADMIN)
    entry = [c for c in codes if not c.get('used')][-1]
    _, b = call('POST', '/verify/confirm',
                {'phone': phone, 'code': entry['code']})
    return (b or {}).get('restoreTicket', '')


print('== слепок кладёт только владелец записи ==')
c, b = call('POST', '/backup', {'phone': PHONE, 'secret': MINE, 'data': SNAP})
check('без записи в реестре слепок не принимается', c == 404, (c, b))

c, b = profile(MINE)
check('владелец завёл запись', c == 201, (c, b))

c, b = call('POST', '/backup', {'phone': PHONE, 'secret': THIRD, 'data': SNAP})
check('чужой ключ отвергнут', c == 403, (c, b))
c, b = call('POST', '/backup', {'phone': PHONE, 'data': SNAP})
check('без ключа не принимается', c == 403, (c, b))
c, b = call('POST', '/backup', {'phone': PHONE, 'secret': MINE, 'data': SNAP})
check('владелец сохранил слепок', c == 201 and b.get('updatedAt'), (c, b))

c, b = call('POST', '/backup', {'phone': PHONE, 'secret': MINE, 'data': 'нет'})
check('слепок не-объектом отвергнут', c == 400, (c, b))
big = {'v': 1, 's': {f'tracker_{i}': 'x' * 200 for i in range(1200)},
       'i': {}, 'b': {}, 'd': {}, 'l': {}}
c, b = call('POST', '/backup', {'phone': PHONE, 'secret': MINE, 'data': big})
check('слишком большой слепок отвергнут', c == 413, (c, b))

print('== слепок не раздаётся по HTTP ==')
name = hashlib.sha256(('irfan-snap:' + FULL).encode()).hexdigest()[:32]
# 401 наравне с 404: сервер закрывает паролем всякий .json, не объявленный
# открытым, и до поиска файла дело не доходит. Проверяем суть — слепок не
# отдаётся, — а не конкретный код отказа.
c, _ = call('GET', f'/snapshots/{name}.json')
check('прямая ссылка на слепок не открывается', c in (401, 403, 404), c)
c, _ = call('GET', f'/../snapshots/{name}.json')
check('и через выход из каталога тоже', c in (400, 401, 403, 404), c)

print('== тот же телефон после переустановки: код не нужен ==')
c, b = call('POST', '/account/restore', {'phone': PHONE, 'secret': MINE})
check('свой ключ пускает без кода', c == 200, (c, b))
check('история вернулась',
      isinstance(b, dict) and b.get('data', {}).get('s', {}).get(
          'tracker_2026-08-01'), b)
check('анкета вернулась', b['profile'].get('name') == 'Ученик', b['profile'])
check('дата создания сохранена',
      b['profile'].get('accountCreatedAt') == CREATED, b['profile'])
check('потраченное берётся из реестра', b.get('spent') == 0, b.get('spent'))

print('== новый телефон без кода не пускают ==')
c, b = call('POST', '/account/restore', {'phone': PHONE, 'secret': NEW})
check('чужой ключ без разрешения отвергнут', c == 403, (c, b))
c, b = call('POST', '/account/restore', {'phone': PHONE, 'secret': NEW,
                                         'ticket': 'x' * 32})
check('выдуманное разрешение отвергнуто', c == 403, (c, b))

print('== подтверждение номера даёт разрешение на перенос ==')
ticket = fresh_ticket()
check('разрешение выдано', len(ticket) >= 16, ticket)

c, b = call('POST', '/account/restore', {'phone': PHONE, 'ticket': ticket})
check('без ключа устройства перенос не делается', c == 400, (c, b))

c, b = call('POST', '/account/restore', {'phone': PHONE, 'secret': NEW,
                                         'ticket': ticket})
check('новый телефон забрал аккаунт', c == 200, (c, b))
check('история приехала на новый телефон',
      isinstance(b, dict) and b.get('data', {}).get('s', {}).get(
          'tracker_2026-08-02'), b)

c, b = call('POST', '/account/restore', {'phone': PHONE, 'secret': THIRD,
                                         'ticket': ticket})
check('разрешение одноразовое', c == 403, (c, b))

print('== после переезда прежний телефон теряет запись ==')
c, b = profile(MINE, name='Старый телефон')
check('прежний ключ больше не пишет анкету', c == 403, (c, b))
c, b = profile(NEW, name='Новый телефон')
check('новый ключ пишет', c == 201, (c, b))
c, b = call('POST', '/backup', {'phone': PHONE, 'secret': MINE, 'data': SNAP})
check('и слепок прежним ключом не кладётся', c == 403, (c, b))

print('== заблокированный аккаунт не восстанавливается ==')
call('POST', '/users/flag', {'phone': PHONE, 'blocked': True}, ADMIN)
c, b = call('POST', '/account/restore', {'phone': PHONE, 'secret': NEW})
check('блокировка сильнее ключа устройства', c == 403
      and b.get('error') == 'blocked', (c, b))
call('POST', '/users/flag', {'phone': PHONE, 'blocked': False}, ADMIN)

print('== удаление аккаунта уносит и слепок ==')
c, b = call('POST', '/account/delete', {'phone': PHONE, 'secret': NEW})
check('владелец удалил аккаунт', c == 200 and b.get('deleted'), (c, b))
c, b = call('POST', '/account/restore', {'phone': PHONE, 'secret': NEW})
check('восстанавливать нечего', c == 404, (c, b))
# Заводим номер заново: если слепок пережил удаление, история воскреснет.
c, b = profile(THIRD, name='Другой человек')
check('номер заводится заново', c == 201, (c, b))
c, b = call('POST', '/account/restore', {'phone': PHONE, 'secret': THIRD})
check('истории прежнего владельца нет', c == 200 and b.get('data') is None,
      (c, b))

print('== админ убрал ученика из реестра — слепок тоже ==')
c, b = call('POST', '/backup', {'phone': PHONE, 'secret': THIRD, 'data': SNAP})
check('слепок сохранён', c == 201, (c, b))
c, b = call('POST', '/users/delete', {'phone': PHONE}, ADMIN)
check('админ удалил запись', c == 200, (c, b))
c, b = profile(MINE, name='Третий')
check('номер заводится снова', c == 201, (c, b))
c, b = call('POST', '/account/restore', {'phone': PHONE, 'secret': MINE})
check('слепка не осталось', c == 200 and b.get('data') is None, (c, b))

print('== вход на новом телефоне по номеру и паролю ==')
#
# Это главный путь внутрь: кода подтверждения в приложении больше нет.
PW_PHONE = '0777111222'
GOOD, BAD = proof('pravilnyi'), proof('nepravilnyi')

c, b = profile(MINE, phone=PW_PHONE, name='С паролем', pw=GOOD)
check('запись завелась с паролем', c == 201, (c, b))
check('хеш пароля наружу не отдаётся', 'pw' not in (b or {}), b)

c, b = call('POST', '/backup',
            {'phone': PW_PHONE, 'secret': MINE, 'data': SNAP})
check('слепок сохранён', c == 201, (c, b))

c, b = call('POST', '/account/restore',
            {'phone': PW_PHONE, 'secret': NEW, 'pass': BAD})
check('неверный пароль не пускает', c == 403
      and (b or {}).get('error') == 'bad password', (c, b))

c, b = call('POST', '/account/restore', {'phone': PW_PHONE, 'secret': NEW})
check('без пароля и разрешения не пускает', c == 403, (c, b))

c, b = call('POST', '/account/restore',
            {'phone': PW_PHONE, 'secret': NEW, 'pass': GOOD})
check('верный пароль пускает с нового телефона', c == 200, (c, b))
check('история приехала',
      len(((b or {}).get('data') or {}).get('s') or {}) == 2, b)

c, b = profile(MINE, phone=PW_PHONE, name='Старый', pw=GOOD)
check('прежний телефон потерял запись', c == 403, (c, b))

print('== пароль можно сменить со своего телефона ==')
NEWPW = proof('drugoi')
c, b = profile(NEW, phone=PW_PHONE, name='С паролем', pw=NEWPW)
check('владелец прислал новый пароль', c == 201, (c, b))
c, b = call('POST', '/account/restore',
            {'phone': PW_PHONE, 'secret': THIRD, 'pass': GOOD})
check('прежний пароль больше не подходит', c == 403, (c, b))
c, b = call('POST', '/account/restore',
            {'phone': PW_PHONE, 'secret': THIRD, 'pass': NEWPW})
check('новый подходит', c == 200, (c, b))

print('== запись без пароля достаётся первому паролю ==')
#
# Так выглядят аккаунты, заведённые прежними сборками: пароля на сервере у
# них нет. Отказать нельзя — человек остался бы без своей истории.
OLD_PHONE = '0777333444'
c, b = profile(MINE, phone=OLD_PHONE, name='Старая запись')
check('запись без пароля завелась', c == 201, (c, b))
c, b = call('POST', '/account/restore',
            {'phone': OLD_PHONE, 'secret': NEW, 'pass': GOOD})
check('первый присланный пароль пускает', c == 200, (c, b))
c, b = call('POST', '/account/restore',
            {'phone': OLD_PHONE, 'secret': THIRD, 'pass': BAD})
check('и с этой минуты запись закрыта им', c == 403, (c, b))

print('== админ сбрасывает забытый пароль ==')
c, b = call('POST', '/users/resetpass', {'phone': OLD_PHONE}, ADMIN)
check('сброс прошёл', c == 200 and (b or {}).get('reset'), (c, b))
c, b = call('POST', '/users/resetpass', {'phone': OLD_PHONE})
check('без прав не сбросить', c in (401, 403), (c, b))
c, b = call('POST', '/account/restore',
            {'phone': OLD_PHONE, 'secret': THIRD, 'pass': BAD})
check('после сброса заходит любой пароль', c == 200, (c, b))
c, b = call('POST', '/account/restore',
            {'phone': OLD_PHONE, 'secret': NEW, 'pass': GOOD})
check('и он же становится новым', c == 403, (c, b))

print('== мусор вместо пароля не записывается ==')
JUNK_PHONE = '0777555666'
c, b = profile(MINE, phone=JUNK_PHONE, name='Мусор', pw='не-шестнадцатеричное')
check('запись завелась', c == 201, (c, b))
c, b = call('POST', '/account/restore',
            {'phone': JUNK_PHONE, 'secret': NEW, 'pass': 'zzzz'})
check('мусорное доказательство не считается паролем', c == 403, (c, b))

print('== код подтверждения живёт час ==')
call('POST', '/verify/request', {'phone': '0700999888'})
_, codes = call('GET', '/verifications.json', None, ADMIN)
entry = [c for c in codes if c.get('phone') == '+996700999888'][-1]
life = entry['expiresAt'] - entry['createdAt']
check('срок кода — 60 минут', life == 60 * 60 * 1000, life)

print(f'\nитого: {ok} ok, {fail} fail')
sys.exit(1 if fail else 0)
