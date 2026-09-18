#!/usr/bin/env python3
"""Доверие заголовкам с адресом клиента — только от своего nginx.

Запросы с localhost приходят не только от прокси: так же выглядит любой
локальный проброс наружу (например, Tailscale Funnel, который ходил прямо
в порт сервера). Без метки прокси клиент сам назначал себе адрес и обходил
ограничение на перебор пароля — эти проверки следят, чтобы так больше не
было, и чтобы настоящий nginx при этом работал как раньше.
"""
import os
import socket
import sys

HOST = os.environ.get('IRFAN_TEST_HOST', '127.0.0.1')
PORT = int(os.environ.get('IRFAN_TEST_PORT', '8099'))
SECRET = os.environ.get('IRFAN_TEST_FRONT_SECRET', 'test-front-secret')
ok = fail = 0


def raw_request(head, body=b''):
    s = socket.create_connection((HOST, PORT), timeout=5)
    s.sendall(head.encode() + b'\r\n' + body)
    s.settimeout(5)
    data = b''
    try:
        while b'\r\n\r\n' not in data:
            chunk = s.recv(4096)
            if not chunk:
                break
            data += chunk
    except socket.timeout:
        pass
    s.close()
    return data.split(b'\r\n', 1)[0].decode('latin-1')


def check(name, cond, detail=''):
    global ok, fail
    if cond:
        ok += 1
        print(f'  ok   {name}')
    else:
        fail += 1
        print(f'  FAIL {name} {detail}')


def token_try(ip, front=False):
    head = ('POST /auth/token HTTP/1.1\r\nHost: x\r\n'
            f'X-Real-IP: {ip}\r\n')
    if front:
        head += f'X-Irfan-Front: {SECRET}\r\n'
    head += 'Content-Type: application/json\r\nContent-Length: 2\r\n'
    return raw_request(head, b'{}')


print('== без метки прокси заголовкам не верят ==')
# Каждый запрос называет себя новым адресом. Раньше этого хватало, чтобы
# счётчик начинался заново и перебор шёл бесконечно.
for i in range(12):
    token_try(f'203.0.113.{i}')
line = token_try('203.0.113.200')
check('подделка X-Real-IP не обходит лимит', '429' in line, line)

print('== с меткой прокси всё работает как раньше ==')
# nginx ставит метку сам, клиент её прислать не может: секрет лежит
# в /etc/irfan/front.json рядом с остальными ключами.
line = token_try('198.51.100.77', front=True)
check('запрос от nginx с новым адресом считается отдельно',
      '429' not in line, line)

line = token_try('198.51.100.78', front=False)
check('тот же адрес без метки по-прежнему под общим счётчиком',
      '429' in line, line)

print(f'\nитого: {ok} ok, {fail} fail')
sys.exit(1 if fail else 0)
