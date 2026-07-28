#!/usr/bin/env python3
"""API-сервер «Ирфан».

Роли (basic-auth, учётки в /etc/irfan/auth.json — вне репозитория):
  admin — публикация в live (courses.json/news.json/azkar.json), реестр
          студентов, коды выкупа;
  ustaz — только заявки на модерацию (*_pending.json) и загрузка файлов.

GET  — всем, кроме путей с ПДн (users.json, redemptions.json) — только admin.
PUT  — по ролям (см. _put_role_for).
POST /comments   — чат эфира от студентов (без пароля);
POST /users      — студент сообщает профиль/активность (без пароля);
POST /redeem     — обмен коинов на награду: баланс и код выдаёт СЕРВЕР.
"""
import base64
import http.server
import json
import os
import secrets
import threading
import time

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'api')
AUTH_FILE = '/etc/irfan/auth.json'
COMMENTS = os.path.join(ROOT, 'comments.json')
USERS = os.path.join(ROOT, 'users.json')
REDEMPTIONS = os.path.join(ROOT, 'redemptions.json')
_MAX_COMMENTS = 200
_MAX_USERS = 10000
_MAX_REDEMPTIONS = 20000

# Пути с ПДн — GET только для админа.
_PROTECTED_GET = ('/users.json', '/redemptions.json')

# Что можно писать устазу: только заявки на модерацию и загрузки.
_USTAZ_WRITABLE = ('/courses_pending.json', '/news_pending.json',
                   '/azkar_pending.json')
_USTAZ_WRITABLE_PREFIX = ('/uploads/',)

# Каталог наград — источник истины для стоимости (клиенту не доверяем).
SHOP_ITEMS = {
    'tasbih': 500,
    'book': 700,
    'course': 1000,
}
MAX_COINS = 1000
COINS_PER_PRAYER = 5
# Потолок за сутки: 5 намазов по 5 коинов + запас на зикры.
MAX_COINS_PER_DAY = 55

_lock = threading.Lock()
os.chdir(ROOT)


def _load_auth():
    """Учётки ролей. Формат: {"admin": "пароль", "ustaz": "пароль"}."""
    try:
        with open(AUTH_FILE, 'r', encoding='utf-8') as f:
            raw = json.load(f)
    except (FileNotFoundError, ValueError):
        return {}
    out = {}
    for role in ('admin', 'ustaz'):
        pw = raw.get(role)
        if isinstance(pw, str) and pw:
            hdr = 'Basic ' + base64.b64encode(
                f'{role}:{pw}'.encode()).decode()
            out[hdr] = role
    return out


_AUTH = _load_auth()


def _role(headers):
    """Роль запроса: 'admin' | 'ustaz' | None. Сравнение — постоянного времени."""
    got = headers.get('Authorization', '')
    for hdr, role in _AUTH.items():
        if secrets.compare_digest(got, hdr):
            return role
    return None


def _put_role_for(path):
    """Какая роль нужна, чтобы писать в этот путь."""
    p = path.split('?')[0]
    if p in _USTAZ_WRITABLE or p.startswith(_USTAZ_WRITABLE_PREFIX):
        return 'ustaz'      # устазу можно; админу — тоже (он выше по правам)
    return 'admin'          # всё остальное, включая live-файлы, — только админ


def _read_json(path, default):
    try:
        with open(path, 'r', encoding='utf-8') as f:
            v = json.load(f)
        return v
    except (FileNotFoundError, ValueError):
        return default


def _add_comment(name, text):
    """Добавляет комментарий зрителя в comments.json, возвращает его или None."""
    name = (name or '').strip()[:40] or 'Гость'
    text = (text or '').strip()[:300]
    if not text:
        return None
    now = int(time.time() * 1000)
    item = {'id': now, 'name': name, 'text': text, 'ts': now}
    with _lock:
        items = _read_json(COMMENTS, [])
        if not isinstance(items, list):
            items = []
        # гарантируем строго возрастающий id даже при совпадении миллисекунд
        if items and int(items[-1].get('id', 0)) >= item['id']:
            item['id'] = int(items[-1]['id']) + 1
        items.append(item)
        items = items[-_MAX_COMMENTS:]
        with open(COMMENTS, 'w', encoding='utf-8') as f:
            json.dump(items, f, ensure_ascii=False)
    return item


def _load_users():
    u = _read_json(USERS, [])
    return u if isinstance(u, list) else []


def _save_users(users):
    with open(USERS, 'w', encoding='utf-8') as f:
        json.dump(users, f, ensure_ascii=False, indent=2)


# Раньше этой даты аккаунтов не существовало — нижняя граница для createdAt.
_EPOCH_MS = 1735689600000  # 2025-01-01


def _max_plausible_prayers(rec, now):
    """Потолок «прочитано намазов» — 5 в сутки за всё время жизни аккаунта.

    Клиент считает статистику сам (SharedPreferences), поэтому число можно
    накрутить. Сервер режет заведомо невозможный рост: за сутки физически
    нельзя прочитать больше пяти намазов.

    Отсчёт идёт от даты создания аккаунта В ПРИЛОЖЕНИИ (её присылает клиент),
    а не от момента, когда сервер впервые увидел студента: люди пользовались
    приложением локально задолго до появления реестра, и их честную
    статистику обрезать нельзя. Дата зажата снизу [_EPOCH_MS] и сверху `now`,
    так что «состарить» аккаунт ради лишних коинов не выйдет.
    """
    started = int(rec.get('accountCreatedAt')
                  or rec.get('registeredAt') or now)
    days = max(1, (now - started) // 86400000 + 2)
    return int(days * 5)


def _earned_coins(rec, now=None):
    """Заработанные коины: столько, сколько насчитал клиент, но не больше
    физически возможного.

    Клиент считает и намазы (5 коинов), и зикры (1 коин за 33 повтора).
    Считать на сервере только намазы нельзя — приложение показывало бы один
    баланс, а выкуп срывался бы по другому. Поэтому берём клиентское число,
    но зажимаем его потолком: за сутки нельзя получить больше, чем 5 намазов
    (25 коинов) плюс разумный запас на зикры.
    """
    now = now or int(time.time() * 1000)
    reported = int(rec.get('coins') or 0)
    by_prayers = int(rec.get('prayersRead') or 0) * COINS_PER_PRAYER
    days = _max_plausible_prayers(rec, now) // 5
    ceiling = days * MAX_COINS_PER_DAY
    return max(0, min(MAX_COINS, ceiling, max(reported, by_prayers)))


def _upsert_user(data):
    """Заводит/обновляет запись студента по email (без пароля). Возвращает
    запись (с флагом blocked, который мог поставить админ) или None."""
    email = (data.get('email') or '').strip().lower()[:120]
    if '@' not in email or '.' not in email:
        return None
    name = (data.get('name') or '').strip()[:60] or 'Без имени'
    gender = data.get('gender') if data.get('gender') in ('male', 'female') else ''
    try:
        age = int(data.get('age') or 0)
    except (ValueError, TypeError):
        age = 0
    age = max(0, min(150, age))
    now = int(time.time() * 1000)

    def _stat(v, hi):
        try:
            return max(0, min(hi, int(v)))
        except (ValueError, TypeError):
            return None

    with _lock:
        users = _load_users()
        rec = next((x for x in users if x.get('email') == email), None)
        if rec is None:
            rec = {'email': email, 'blocked': False, 'registeredAt': now,
                   'spent': 0}
            users.append(rec)
            users = users[-_MAX_USERS:]
        # Дата создания аккаунта в приложении — база для анти-накрутки.
        # Ставится один раз и только в допустимом диапазоне.
        if 'accountCreatedAt' not in rec:
            try:
                created = int(data.get('createdAt') or 0)
            except (ValueError, TypeError):
                created = 0
            rec['accountCreatedAt'] = (created if _EPOCH_MS <= created <= now
                                       else now)
        rec['name'] = name
        rec['gender'] = gender
        rec['age'] = age
        rec['lastSeen'] = now
        # Активность студента (необязательные поля — для дашборда устаза).
        for key, hi in (('prayersRead', 10**7), ('streak', 100000),
                        ('coins', 10**7)):
            val = _stat(data.get(key), hi)
            if val is not None:
                rec[key] = val
        # Анти-накрутка: режем невозможный рост прочитанных намазов.
        cap = _max_plausible_prayers(rec, now)
        if int(rec.get('prayersRead') or 0) > cap:
            rec['prayersRead'] = cap
            rec['capped'] = True
        rec.setdefault('spent', 0)
        rec['balance'] = max(0, _earned_coins(rec, now) - int(rec.get('spent') or 0))
        _save_users(users)
        return dict(rec)


def _redeem(data):
    """Обмен коинов на награду. Баланс считает и код выдаёт сервер.

    Возвращает (код_ответа, тело).
    """
    email = (data.get('email') or '').strip().lower()[:120]
    item_id = (data.get('itemId') or '').strip()[:40]
    if '@' not in email:
        return 400, {'error': 'bad email'}
    cost = SHOP_ITEMS.get(item_id)
    if cost is None:
        return 400, {'error': 'unknown item'}
    now = int(time.time() * 1000)
    with _lock:
        users = _load_users()
        rec = next((x for x in users if x.get('email') == email), None)
        if rec is None:
            return 404, {'error': 'no user'}
        if rec.get('blocked'):
            return 403, {'error': 'blocked'}
        balance = max(0, _earned_coins(rec, now) - int(rec.get('spent') or 0))
        if balance < cost:
            return 409, {'error': 'not enough', 'balance': balance}
        rec['spent'] = int(rec.get('spent') or 0) + cost
        rec['balance'] = balance - cost
        code = 'IRF-' + secrets.token_hex(3).upper()
        entry = {'code': code, 'email': email, 'name': rec.get('name', ''),
                 'itemId': item_id, 'cost': cost, 'ts': now, 'used': False}
        items = _read_json(REDEMPTIONS, [])
        if not isinstance(items, list):
            items = []
        items.append(entry)
        items = items[-_MAX_REDEMPTIONS:]
        with open(REDEMPTIONS, 'w', encoding='utf-8') as f:
            json.dump(items, f, ensure_ascii=False, indent=2)
        _save_users(users)
    return 201, entry


def _mark_used(code):
    """Устаз/админ гасит код после выдачи награды."""
    code = (code or '').strip().upper()[:20]
    with _lock:
        items = _read_json(REDEMPTIONS, [])
        if not isinstance(items, list):
            return 404, {'error': 'no code'}
        for it in items:
            if it.get('code') == code:
                if it.get('used'):
                    return 409, {'error': 'already used', 'entry': it}
                it['used'] = True
                it['usedAt'] = int(time.time() * 1000)
                with open(REDEMPTIONS, 'w', encoding='utf-8') as f:
                    json.dump(items, f, ensure_ascii=False, indent=2)
                return 200, it
    return 404, {'error': 'no code'}


class Handler(http.server.SimpleHTTPRequestHandler):
    # Правильные типы для HLS (ABR-транскод отдаётся отсюда же).
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        '.m3u8': 'application/vnd.apple.mpegurl',
        '.ts': 'video/mp2t',
    }

    def end_headers(self):
        self.send_header('Cache-Control', 'no-cache')
        self.send_header('Access-Control-Allow-Origin', '*')
        super().end_headers()

    def _send_json(self, code, obj):
        body = json.dumps(obj, ensure_ascii=False).encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _deny(self, code=401):
        self.send_response(code)
        self.end_headers()

    def do_GET(self):
        # Реестр аккаунтов и коды выкупа (ПДн) — только админ.
        if self.path.split('?')[0].rstrip('/') in _PROTECTED_GET:
            if _role(self.headers) != 'admin':
                self._deny()
                return
        return super().do_GET()

    def do_POST(self):
        p = self.path.rstrip('/')
        n = int(self.headers.get('Content-Length', 0) or 0)
        raw = self.rfile.read(n) if n else b''
        try:
            data = json.loads(raw.decode('utf-8')) if raw else {}
        except ValueError:
            self._send_json(400, {'error': 'bad json'})
            return
        if p == '/comments':
            item = _add_comment(data.get('name'), data.get('text'))
            if item is None:
                self._send_json(400, {'error': 'empty'})
                return
            self._send_json(201, item)
            return
        if p == '/users':
            rec = _upsert_user(data)
            if rec is None:
                self._send_json(400, {'error': 'bad email'})
                return
            self._send_json(201, rec)
            return
        if p == '/redeem':
            code, body = _redeem(data)
            self._send_json(code, body)
            return
        if p == '/redeem/use':
            # Гашение кода — только персонал.
            if _role(self.headers) is None:
                self._deny()
                return
            code, body = _mark_used(data.get('code'))
            self._send_json(code, body)
            return
        self.send_response(404)
        self.end_headers()

    def do_PUT(self):
        role = _role(self.headers)
        if role is None:
            self._deny()
            return
        need = _put_role_for(self.path)
        # admin может всё; ustaz — только то, что помечено 'ustaz'.
        if need == 'admin' and role != 'admin':
            self._send_json(403, {'error': 'admin only'})
            return
        path = self.translate_path(self.path)
        if not os.path.abspath(path).startswith(ROOT):
            self._deny(403)
            return
        os.makedirs(os.path.dirname(path), exist_ok=True)
        n = int(self.headers.get('Content-Length', 0))
        remaining, chunk = n, 1 << 20
        with open(path, 'wb') as f:
            while remaining > 0:
                data = self.rfile.read(min(chunk, remaining))
                if not data:
                    break
                f.write(data)
                remaining -= len(data)
        self.send_response(201)
        self.end_headers()


if __name__ == '__main__':
    http.server.ThreadingHTTPServer(('0.0.0.0', 8090), Handler).serve_forever()
