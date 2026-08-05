#!/usr/bin/env python3
"""Проверка потолков размера и определения адреса клиента."""
import base64
import json
import os
import socket
import sys

HOST = os.environ.get('IRFAN_TEST_HOST', '127.0.0.1')
PORT = int(os.environ.get('IRFAN_TEST_PORT', '8099'))
ADMIN = 'Basic ' + base64.b64encode(b'admin:adminpw').decode()
ok = fail = 0


def raw_request(head, body=b''):
    """Шлём запрос вручную: нужно уметь врать в Content-Length."""
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
    line = data.split(b'\r\n', 1)[0].decode('latin-1')
    return line


def check(name, cond, detail=''):
    global ok, fail
    if cond:
        ok += 1
        print(f'  ok   {name}')
    else:
        fail += 1
        print(f'  FAIL {name} {detail}')


print('== потолок тела POST ==')
# Врём про гигабайт, но ничего не шлём: раньше сервер попытался бы это выделить.
line = raw_request(
    f'POST /comments HTTP/1.1\r\nHost: x\r\n'
    f'Content-Type: application/json\r\nContent-Length: {2**30}\r\n')
check('гигабайтное тело отвергнуто', '413' in line, line)

body = json.dumps({'name': 'Тест', 'text': 'привет'}).encode()
line = raw_request(
    f'POST /comments HTTP/1.1\r\nHost: x\r\n'
    f'Content-Type: application/json\r\nContent-Length: {len(body)}\r\n', body)
check('обычный комментарий проходит', '201' in line, line)

line = raw_request(
    'POST /comments HTTP/1.1\r\nHost: x\r\n'
    'Content-Type: application/json\r\nContent-Length: abc\r\n')
check('кривая длина — 400, не падение', '400' in line, line)

body = b'["\xd0\xbd\xd0\xb5", "\xd1\x81\xd0\xbb\xd0\xbe\xd0\xb2\xd0\xb0\xd1\x80\xd1\x8c"]'
line = raw_request(
    f'POST /users HTTP/1.1\r\nHost: x\r\n'
    f'Content-Type: application/json\r\nContent-Length: {len(body)}\r\n', body)
check('JSON-список вместо объекта — 400', '400' in line, line)

print('== потолок PUT ==')
line = raw_request(
    f'PUT /courses.json HTTP/1.1\r\nHost: x\r\nAuthorization: {ADMIN}\r\n'
    f'Content-Type: application/json\r\nContent-Length: {2**30}\r\n')
check('гигабайтный JSON отвергнут', '413' in line, line)

line = raw_request(
    f'PUT /uploads/big.mp4 HTTP/1.1\r\nHost: x\r\nAuthorization: {ADMIN}\r\n'
    f'Content-Type: video/mp4\r\nContent-Length: {8 * 1024**3}\r\n')
check('урок больше 4 ГБ отвергнут', '413' in line, line)

body = b'\x00\x01\x02'
line = raw_request(
    f'PUT /uploads/small.mp4 HTTP/1.1\r\nHost: x\r\nAuthorization: {ADMIN}\r\n'
    f'Content-Type: video/mp4\r\nContent-Length: {len(body)}\r\n', body)
check('небольшой урок проходит', '201' in line, line)

print('== подделка адреса клиента ==')
# Сервер слушает на 127.0.0.1, значит для него мы «прокси» — ровно тот
# случай, ради которого заголовки и читаются.
for i in range(12):
    raw_request(
        f'POST /auth/token HTTP/1.1\r\nHost: x\r\n'
        f'X-Forwarded-For: 9.9.9.{i}, 203.0.113.7\r\n'
        f'Content-Type: application/json\r\nContent-Length: 2\r\n', b'{}')
line = raw_request(
    'POST /auth/token HTTP/1.1\r\nHost: x\r\n'
    'X-Forwarded-For: 9.9.9.99, 203.0.113.7\r\n'
    'Content-Type: application/json\r\nContent-Length: 2\r\n', b'{}')
check('смена первого элемента не обходит лимит', '429' in line, line)

line = raw_request(
    'POST /auth/token HTTP/1.1\r\nHost: x\r\n'
    'X-Real-IP: 198.51.100.5\r\n'
    'X-Forwarded-For: 9.9.9.99, 203.0.113.7\r\n'
    'Content-Type: application/json\r\nContent-Length: 2\r\n', b'{}')
check('другой X-Real-IP считается отдельно', '429' not in line, line)

print(f'\nитого: {ok} ok, {fail} fail')
sys.exit(1 if fail else 0)
