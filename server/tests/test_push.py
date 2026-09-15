#!/usr/bin/env python3
"""Пуши: токены iOS и Android и отправка через FCM.

Сеть не трогаем: запросы к Google подменяются. Проверяем то, что ломается
тихо и без подмены не видно, — какие токены принимаются, что именно уходит в
FCM и что делается с токенами удалённых приложений.
"""
import io
import json
import os
import sys
import tempfile
import urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

WORK = tempfile.mkdtemp()
os.environ['IRFAN_PUSH_TOKENS'] = os.path.join(WORK, 'push-tokens.json')
os.environ['IRFAN_APNS_CFG'] = os.path.join(WORK, 'no-apns.json')
os.environ['IRFAN_FCM_CFG'] = os.path.join(WORK, 'fcm.json')

import push  # noqa: E402

ok = fail = 0


def check(name, cond, detail=''):
    global ok, fail
    if cond:
        ok += 1
        print(f'  ok   {name}')
    else:
        fail += 1
        print(f'  FAIL {name} {detail}')


IOS = 'a1b2' * 16
ANDROID_OK = 'dX3kQ9:APA91b' + 'Hk7_x-Z' * 20
ANDROID_GONE = 'fGone:APA91b' + 'Q1w2e3r' * 20

print('== какие токены принимаются ==')
check('токен iOS принят', push.register(IOS, 'dev-ios', 'ios') == 1)
check('токен Android принят', push.register(ANDROID_OK, 'dev-a1', 'android') == 2)
check('второй Android принят', push.register(ANDROID_GONE, 'dev-a2', 'android') == 3)
check('мусор под видом Android отбит',
      push.register('<script>alert(1)</script>', 'x', 'android') is None)
check('токен Android под видом iOS отбит', push.register(ANDROID_OK, 'x', 'ios') is None)
check('неизвестная платформа считается iOS',
      push.register('zz' * 40, 'x', 'windows') is None)
saved = json.load(open(os.environ['IRFAN_PUSH_TOKENS']))
check('платформы записаны', sorted(r['platform'] for r in saved) == ['android', 'android', 'ios'],
      saved)

print('== без ключей ничего не отправляется и не падает ==')
check('без fcm.json и apns.json — (0, всего)', push.send('t', 'b') == (0, 3))

print('== отправка через FCM ==')
json.dump({'project_id': 'irfan-test', 'client_email': 'bot@irfan-test.iam',
           'private_key': 'не используется: токен доступа подменён'},
          open(os.environ['IRFAN_FCM_CFG'], 'w'))
push._fcm_access_token = lambda cfg: 'ACCESS'
sent = []


def fake_urlopen(req, timeout=0):
    body = json.loads(req.data.decode())
    sent.append({'url': req.full_url, 'auth': req.get_header('Authorization'),
                 'message': body['message']})
    if body['message']['token'] == ANDROID_GONE:
        raise urllib.error.HTTPError(req.full_url, 404, 'Not Found', {},
                                     io.BytesIO(b'{"error":{"status":"NOT_FOUND"}}'))

    class R:
        def __enter__(self):
            return self

        def __exit__(self, *a):
            return False
    return R()


push.urllib.request.urlopen = fake_urlopen
delivered, total = push.send('Начался прямой эфир', 'Урок таджвида', urgent=True)
check('на Android ушло два запроса', len(sent) == 2, sent)
check('доставлено одно, всего три', (delivered, total) == (1, 3), (delivered, total))
m = sent[0]['message'] if sent else {}
check('адрес проекта верный',
      sent and sent[0]['url'].endswith('/projects/irfan-test/messages:send'), sent[:1])
check('авторизация токеном доступа', sent and sent[0]['auth'] == 'Bearer ACCESS', sent[:1])
check('заголовок и текст на месте',
      m.get('notification') == {'title': 'Начался прямой эфир', 'body': 'Урок таджвида'}, m)
check('канал «live» и высокий приоритет',
      m.get('android', {}).get('priority') == 'HIGH'
      and m.get('android', {}).get('notification', {}).get('channel_id') == 'live', m)
check('экран передан в data', m.get('data') == {'screen': 'live'}, m)
left = [r['token'] for r in json.load(open(os.environ['IRFAN_PUSH_TOKENS']))]
check('токен удалённого приложения выброшен', ANDROID_GONE not in left, left)
check('рабочие токены остались', ANDROID_OK in left and IOS in left, left)

print('== ответ поддержки — не срочный ==')
sent.clear()
push.send('Ответ поддержки', 'Здравствуйте', screen='support', urgent=False,
          only=lambda r: r.get('device') == 'dev-a1')
check('ушёл только одному адресату', len(sent) == 1, sent)
check('обычный приоритет', sent and sent[0]['message']['android']['priority'] == 'NORMAL', sent)
check('экран поддержки', sent and sent[0]['message']['data'] == {'screen': 'support'}, sent)

print(f'\n  итого: {ok} ok, {fail} fail')
raise SystemExit(1 if fail else 0)
