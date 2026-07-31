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
POST /redeem     — обмен коинов на награду: баланс и код выдаёт СЕРВЕР;
POST /verify/request, /verify/confirm — подтверждение телефона кодом;
POST /access/grant, /access/revoke (admin) — доступ к направлению/курсу
                   на срок в днях или бессрочно.
"""
import base64
import http.server
import json
import os
import secrets
import re
import shutil
import threading
import time
import urllib.parse

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'api')
AUTH_FILE = '/etc/irfan/auth.json'
COMMENTS = os.path.join(ROOT, 'comments.json')
USERS = os.path.join(ROOT, 'users.json')
REDEMPTIONS = os.path.join(ROOT, 'redemptions.json')
ACCESS = os.path.join(ROOT, 'access.json')
# Каталог версий — СОСЕДНИЙ с api/, а не внутри: всё, что лежит в ROOT,
# раздаётся по HTTP, и копия users.json стала бы публичной.
VERSIONS = os.path.join(os.path.dirname(ROOT), 'versions')
VERIFY = os.path.join(ROOT, 'verifications.json')
_MAX_COMMENTS = 200
_MAX_USERS = 10000
_MAX_REDEMPTIONS = 20000

# Пути с ПДн — GET только для админа.
_PROTECTED_GET = ('/users.json', '/redemptions.json', '/access.json',
                  '/verifications.json', '/media.json')
# Хеш пароля админа: не ПДн, но и не для публики — брутфорсится офлайн.
# Достаточно любой роли: приложение устаза читает его до входа админом.
_AUTHED_GET = ('/admin.json',)

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

# Подтверждение телефона кодом.
CODE_TTL_MS = 10 * 60 * 1000     # код живёт 10 минут
CODE_MAX_ATTEMPTS = 5            # неверных попыток на код
CODE_RESEND_MS = 60 * 1000       # не чаще одного кода в минуту
_MAX_VERIFY = 5000

# Ограничение частоты: сколько запросов с одного адреса за окно.
RATE_WINDOW_S = 60
RATE_ANON = 20          # анонимные POST (/users, /comments, /verify/request)
RATE_AUTH_FAIL = 10     # неудачные попытки авторизации

_hits = {}              # (ключ, ip) -> [метки времени]
_rate_lock = threading.Lock()


def _rate_ok(key, ip, limit):
    """Пускать ли запрос. Скользящее окно в памяти — сбрасывается при
    перезапуске, но своё дело (спам и перебор пароля) делает."""
    now = time.time()
    with _rate_lock:
        hits = [t for t in _hits.get((key, ip), []) if now - t < RATE_WINDOW_S]
        if len(hits) >= limit:
            _hits[(key, ip)] = hits
            return False
        hits.append(now)
        _hits[(key, ip)] = hits
        # Не даём словарю расти бесконечно.
        if len(_hits) > 10000:
            for k in [k for k, v in _hits.items()
                      if not v or now - v[-1] > RATE_WINDOW_S]:
                _hits.pop(k, None)
        return True


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


# Куда вообще можно писать. Раньше админский PUT принимал любой путь внутри
# api/ и создавал произвольные файлы и каталоги — в том числе .html, который
# отдавался бы браузеру с нашего же адреса. Теперь список закрытый.
_PUT_ALLOWED = ('/courses.json', '/news.json', '/azkar.json',
                '/courses_pending.json', '/news_pending.json',
                '/azkar_pending.json', '/users.json', '/admin.json',
                '/status.json', '/live-title.txt')


def _put_allowed(path):
    p = path.split('?')[0]
    return p in _PUT_ALLOWED or p.startswith('/uploads/')


def _put_role_for(path):
    """Какая роль нужна, чтобы писать в этот путь."""
    p = path.split('?')[0]
    if p in _USTAZ_WRITABLE or p.startswith(_USTAZ_WRITABLE_PREFIX):
        return 'ustaz'      # устазу можно; админу — тоже (он выше по правам)
    return 'admin'          # всё остальное, включая live-файлы, — только админ


# Сколько прошлых версий каждого файла держим.
_BACKUPS = 5


def _keep_backup(path):
    """Сохраняет копию файла перед перезаписью, храня последние [_BACKUPS]."""
    if not os.path.isfile(path) or not path.endswith('.json'):
        return
    try:
        d = VERSIONS
        os.makedirs(d, exist_ok=True)
        base = os.path.basename(path)
        # Метка с миллисекундами: два PUT в одну секунду не затрут копию.
        stamp = int(time.time() * 1000)
        shutil.copy2(path, os.path.join(d, f'{base}.{stamp}'))
        old = sorted(f for f in os.listdir(d) if f.startswith(base + '.'))
        for f in old[:-_BACKUPS]:
            os.remove(os.path.join(d, f))
    except OSError as e:
        print(f'[backup] не удалось сохранить {path}: {e}', flush=True)


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


def _identity(data):
    """Опознаватель студента — номер телефона.

    Приложение перешло с почты на номер: люди помнят его, и код подтверждения
    всё равно уходит туда. Поле email принимаем ради записей, заведённых
    старыми сборками, — иначе их статистика и доступы осиротели бы.
    """
    phone = _norm_phone(data.get('phone'))
    if phone:
        return phone
    legacy = (data.get('email') or '').strip().lower()[:120]
    return legacy


def _find_user(users, ident):
    """Ищет запись по телефону или по прежнему опознавателю-почте."""
    for u in users:
        if u.get('phone') == ident or u.get('email') == ident:
            return u
    return None


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


def _norm_phone(v):
    """Телефон к виду +996XXXXXXXXX. Пустая строка, если не похоже на номер."""
    raw = ''.join(ch for ch in str(v or '') if ch.isdigit() or ch == '+')
    digits = ''.join(ch for ch in raw if ch.isdigit())
    if len(digits) < 9 or len(digits) > 15:
        return ''
    if raw.startswith('+'):
        return '+' + digits
    # Локальный кыргызский формат: 0555123456 → +996555123456.
    if digits.startswith('0') and len(digits) == 10:
        return '+996' + digits[1:]
    if len(digits) == 9:
        return '+996' + digits
    return '+' + digits


# ——— Доступ к курсам ———

def _load_access():
    a = _read_json(ACCESS, [])
    return a if isinstance(a, list) else []


def _access_active(rec, now=None):
    """Действует ли запись доступа: until=None — бессрочно."""
    now = now or int(time.time() * 1000)
    if rec.get('revoked'):
        return False
    until = rec.get('until')
    return until is None or int(until) > now


def _access_for(ident):
    """Действующие доступы студента — то, что видит его приложение."""
    now = int(time.time() * 1000)
    return [
        {'scope': r.get('scope'), 'key': r.get('key'), 'until': r.get('until')}
        for r in _load_access()
        if r.get('student') == ident and _access_active(r, now)
    ]


def _same_student(rec, ident):
    """Записи, созданные до перехода на телефон, хранят почту в `email`."""
    return rec.get('student') == ident or rec.get('email') == ident


def _grant_access(data):
    """Выдаёт доступ. days=None/0 → бессрочно, иначе срок в днях."""
    ident = _identity(data)
    scope = data.get('scope')
    key = (data.get('key') or '').strip()[:200]
    if not ident or scope not in ('direction', 'course') or not key:
        return 400, {'error': 'bad request'}
    try:
        days = int(data.get('days') or 0)
    except (ValueError, TypeError):
        days = 0
    now = int(time.time() * 1000)
    until = None if days <= 0 else now + days * 86400000
    entry = {'student': ident, 'scope': scope, 'key': key, 'until': until,
             'grantedAt': now, 'days': days or None}
    with _lock:
        items = _load_access()
        # Повторная выдача на тот же курс продлевает, а не плодит записи.
        for r in items:
            if (_same_student(r, ident) and r.get('scope') == scope
                    and r.get('key') == key):
                r.update(entry)
                r.pop('revoked', None)
                break
        else:
            items.append(entry)
        with open(ACCESS, 'w', encoding='utf-8') as f:
            json.dump(items, f, ensure_ascii=False, indent=2)
    return 201, entry


def _revoke_access(data):
    ident = _identity(data)
    scope = data.get('scope')
    key = (data.get('key') or '').strip()[:200]
    with _lock:
        items = _load_access()
        found = False
        for r in items:
            if (_same_student(r, ident) and r.get('scope') == scope
                    and r.get('key') == key):
                r['revoked'] = True
                r['revokedAt'] = int(time.time() * 1000)
                found = True
        if not found:
            return 404, {'error': 'no grant'}
        with open(ACCESS, 'w', encoding='utf-8') as f:
            json.dump(items, f, ensure_ascii=False, indent=2)
    return 200, {'ok': True}


# ——— Подтверждение телефона кодом ———

def _load_verify():
    v = _read_json(VERIFY, [])
    return v if isinstance(v, list) else []


def _save_verify(items):
    with open(VERIFY, 'w', encoding='utf-8') as f:
        json.dump(items[-_MAX_VERIFY:], f, ensure_ascii=False, indent=2)


def _send_code(phone, code):
    """Отправка кода студенту.

    Провайдер (WhatsApp Business API / Twilio / SMS-шлюз) не подключён —
    для этого нужен платный аккаунт. Пока код пишется в лог и виден админу
    в приложении устаза (GET /verifications.json). Чтобы включить реальную
    отправку, достаточно заменить тело этой функции: остальной поток —
    срок жизни, лимит попыток, антиспам — уже работает.
    """
    print(f'[verify] код для {phone}: {code}', flush=True)
    return False   # False = «доставлено не было», админ выдаёт код вручную


def _request_code(data):
    """Создаёт код подтверждения и пытается его отправить."""
    phone = _norm_phone(data.get('phone'))
    if not phone:
        return 400, {'error': 'bad phone'}
    now = int(time.time() * 1000)
    with _lock:
        items = _load_verify()
        last = next((x for x in reversed(items)
                     if x.get('phone') == phone), None)
        # Антиспам: не чаще одного кода в минуту на аккаунт.
        if last and now - int(last.get('createdAt') or 0) < CODE_RESEND_MS:
            wait = (CODE_RESEND_MS - (now - int(last['createdAt']))) // 1000
            return 429, {'error': 'too soon', 'retryAfter': wait}
        code = f'{secrets.randbelow(1000000):06d}'
        entry = {'phone': phone, 'code': code,
                 'createdAt': now, 'expiresAt': now + CODE_TTL_MS,
                 'attempts': 0, 'used': False, 'delivered': False}
        entry['delivered'] = _send_code(phone, code)
        items.append(entry)
        _save_verify(items)
    # Сам код в ответ НЕ отдаём: иначе подтверждение не значит ничего.
    return 201, {'sent': True, 'delivered': entry['delivered'],
                 'expiresAt': entry['expiresAt']}


def _confirm_code(data):
    phone = _norm_phone(data.get('phone'))
    code = ''.join(ch for ch in str(data.get('code') or '') if ch.isdigit())
    if not phone:
        return 400, {'error': 'bad phone'}
    now = int(time.time() * 1000)
    with _lock:
        items = _load_verify()
        entry = next((x for x in reversed(items)
                      if x.get('phone') == phone and not x.get('used')), None)
        if entry is None:
            return 404, {'error': 'no code'}
        if now > int(entry.get('expiresAt') or 0):
            return 410, {'error': 'expired'}
        if int(entry.get('attempts') or 0) >= CODE_MAX_ATTEMPTS:
            return 429, {'error': 'too many attempts'}
        if not secrets.compare_digest(code, str(entry.get('code'))):
            entry['attempts'] = int(entry.get('attempts') or 0) + 1
            _save_verify(items)
            left = CODE_MAX_ATTEMPTS - entry['attempts']
            return 403, {'error': 'wrong code', 'attemptsLeft': max(0, left)}
        entry['used'] = True
        entry['confirmedAt'] = now
        _save_verify(items)
        users = _load_users()
        rec = _find_user(users, phone)
        if rec is not None:
            rec['verified'] = True
            _save_users(users)
    return 200, {'verified': True}


def _upsert_user(data):
    """Заводит/обновляет запись студента по email (без пароля). Возвращает
    запись (с флагом blocked, который мог поставить админ) или None."""
    ident = _identity(data)
    if not ident:
        return None
    name = (data.get('name') or '').strip()[:60] or 'Без имени'
    gender = data.get('gender') if data.get('gender') in ('male', 'female') else ''
    try:
        age = int(data.get('age') or 0)
    except (ValueError, TypeError):
        age = 0
    age = max(0, min(150, age))
    city = (data.get('city') or '').strip()[:60]
    now = int(time.time() * 1000)

    def _stat(v, hi):
        try:
            return max(0, min(hi, int(v)))
        except (ValueError, TypeError):
            return None

    with _lock:
        users = _load_users()
        rec = _find_user(users, ident)
        if rec is None:
            # Раньше здесь стояло users[-_MAX_USERS:] — при переполнении
            # вылетали САМЫЕ СТАРЫЕ, то есть настоящие первые ученики,
            # а мусорные записи оставались. Теперь новые просто не заводим.
            if len(users) >= _MAX_USERS:
                return {'error': 'registry full'}
            rec = {'phone': ident, 'blocked': False, 'registeredAt': now,
                   'spent': 0}
            users.append(rec)
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
        # Номер — он же опознаватель, менять его через этот вызов нельзя.
        rec.setdefault('phone', ident)
        if city:
            rec['city'] = city
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
        rec.setdefault('verified', False)
        _save_users(users)
        out = dict(rec)
    # Свои доступы к курсам — чтобы приложение сразу знало, что открыто.
    out['access'] = _access_for(ident)
    return out


UPLOADS = os.path.join(ROOT, 'uploads')

# Адрес, по которому уроки забирает ПРИЛОЖЕНИЕ СТУДЕНТА.
#
# Он не совпадает с тем, откуда зашёл администратор: панель открывают и по
# защищённой ссылке Tailscale, и по прямому IP. Если складывать ссылку урока
# из адреса админа, ученикам достанется ссылка на Funnel — а это канал
# служебного доступа, не предназначенный для раздачи видео.
MEDIA_BASE = os.environ.get(
    'IRFAN_MEDIA_BASE', 'http://178.104.206.100:8090').rstrip('/')

# Что разрешаем заливать. Расширение проверяем, потому что каталог раздаётся
# всем: html/js оттуда исполнялись бы в браузере с нашего же адреса.
MEDIA_EXT = ('.mp4', '.mov', '.m4v', '.mp3', '.m4a', '.aac', '.pdf',
             '.jpg', '.jpeg', '.png', '.webp')
_SAFE_NAME = re.compile(r'[^A-Za-z0-9._-]+')

# Кириллицу переводим в латиницу, иначе имя «урок 1.mp4» после вырезания
# небезопасных символов превращалось в нечитаемый набор процентов и цифр.
_TRANSLIT = {
    'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ё': 'e',
    'ж': 'zh', 'з': 'z', 'и': 'i', 'й': 'y', 'к': 'k', 'л': 'l', 'м': 'm',
    'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u',
    'ф': 'f', 'х': 'h', 'ц': 'c', 'ч': 'ch', 'ш': 'sh', 'щ': 'sch',
    'ъ': '', 'ы': 'y', 'ь': '', 'э': 'e', 'ю': 'yu', 'я': 'ya',
    'ң': 'n', 'ө': 'o', 'ү': 'u',           # кыргызские
}


def _translit(text):
    out = []
    for ch in text:
        low = ch.lower()
        if low in _TRANSLIT:
            t = _TRANSLIT[low]
            out.append(t.upper() if ch.isupper() and t else t)
        else:
            out.append(ch)
    return ''.join(out)


def safe_upload_name(raw):
    """Приводит имя файла к безопасному виду или возвращает ''."""
    # Путь приходит percent-encoded — сперва раскодируем, иначе кириллица
    # осталась бы вида %D1%83 и превратилась в мусор.
    name = urllib.parse.unquote(str(raw or '')).strip()
    name = os.path.basename(name)
    stem, ext = os.path.splitext(name)
    ext = ext.lower()
    if ext not in MEDIA_EXT:
        return ''
    stem = _SAFE_NAME.sub('-', _translit(stem)).strip('-.')[:80]
    if not stem:
        stem = f'file-{int(time.time())}'
    return stem + ext


# ——— Папки для загруженных файлов ———
#
# Папки — РАЗМЕТКА, а не каталоги на диске: файлы как лежали в uploads/, так и
# лежат. Иначе перекладывание урока в папку меняло бы его адрес и ломало уже
# опубликованные ссылки в courses.json (а их на сервере больше двухсот).
# Указатель держим РЯДОМ с api/, а не внутри: всё, что в ROOT, раздаётся по
# HTTP, и список файлов стал бы публичным — листинги мы как раз закрыли.
MEDIA_INDEX = os.path.join(os.path.dirname(ROOT), 'media-folders.json')
_MAX_FOLDERS = 200
_FOLDER_NAME_MAX = 60


def _load_index():
    idx = _read_json(MEDIA_INDEX, {})
    if not isinstance(idx, dict):
        idx = {}
    folders = idx.get('folders')
    files = idx.get('files')
    return {
        'folders': folders if isinstance(folders, list) else [],
        'files': files if isinstance(files, dict) else {},
    }


def _save_index(idx):
    with open(MEDIA_INDEX, 'w', encoding='utf-8') as f:
        json.dump(idx, f, ensure_ascii=False, indent=2)


def _folder_name(raw):
    name = ' '.join(str(raw or '').split())      # схлопываем переносы и табы
    return name[:_FOLDER_NAME_MAX]


def _folder_op(data):
    """Создание, переименование и удаление папки. Файлы при удалении папки
    остаются на месте и просто становятся «без папки»."""
    op = data.get('op')
    fid = str(data.get('id') or '')[:40]
    name = _folder_name(data.get('name'))
    with _lock:
        idx = _load_index()
        folders = idx['folders']
        if op == 'create':
            if not name:
                return 400, {'error': 'empty name'}
            if len(folders) >= _MAX_FOLDERS:
                return 507, {'error': 'too many folders'}
            folder = {
                'id': f'f{int(time.time() * 1000)}-{secrets.token_hex(3)}',
                'name': name,
                'created': int(time.time() * 1000),
            }
            folders.append(folder)
            _save_index(idx)
            return 201, folder
        found = next((f for f in folders if f.get('id') == fid), None)
        if found is None:
            return 404, {'error': 'no folder'}
        if op == 'rename':
            if not name:
                return 400, {'error': 'empty name'}
            found['name'] = name
            _save_index(idx)
            return 200, found
        if op == 'delete':
            folders.remove(found)
            idx['files'] = {k: v for k, v in idx['files'].items() if v != fid}
            _save_index(idx)
            return 200, {'id': fid, 'deleted': True}
    return 400, {'error': 'bad op'}


def _media_move(data):
    """Раскладывает файлы по папкам. Пустой folder — вынуть из папки."""
    names = data.get('names')
    if isinstance(names, str):
        names = [names]
    if not isinstance(names, list) or not names:
        return 400, {'error': 'no names'}
    fid = str(data.get('folder') or '')[:40]
    with _lock:
        idx = _load_index()
        if fid and not any(f.get('id') == fid for f in idx['folders']):
            return 404, {'error': 'no folder'}
        moved = 0
        for raw in names[:2000]:
            name = safe_upload_name(raw)
            if not name or not os.path.isfile(os.path.join(UPLOADS, name)):
                continue
            if fid:
                idx['files'][name] = fid
            else:
                idx['files'].pop(name, None)
            moved += 1
        _save_index(idx)
    return 200, {'moved': moved, 'folder': fid}


def _assign_folder(name, fid):
    """Кладёт только что загруженный файл в папку (тихо, без ответа)."""
    if not fid:
        return
    with _lock:
        idx = _load_index()
        if any(f.get('id') == fid for f in idx['folders']):
            idx['files'][name] = fid
            _save_index(idx)


def _media_list():
    """Загруженные файлы + папки + сколько места осталось на диске."""
    idx = _load_index()
    by_file = idx['files']
    items = []
    try:
        for name in sorted(os.listdir(UPLOADS)):
            full = os.path.join(UPLOADS, name)
            if not os.path.isfile(full):
                continue
            st = os.stat(full)
            items.append({
                'name': name,
                'size': st.st_size,
                'mtime': int(st.st_mtime * 1000),
                'url': f'/uploads/{name}',
                # Абсолютная ссылка для каталога — всегда на публичный адрес.
                'publicUrl': f'{MEDIA_BASE}/uploads/{name}',
                'folder': by_file.get(name, ''),
            })
    except OSError:
        pass
    items.sort(key=lambda x: x['mtime'], reverse=True)
    counts = {}
    for it in items:
        counts[it['folder']] = counts.get(it['folder'], 0) + 1
    folders = [dict(f, count=counts.get(f.get('id'), 0)) for f in idx['folders']]
    try:
        du = shutil.disk_usage(ROOT)
        disk = {'free': du.free, 'total': du.total}
    except OSError:
        disk = {}
    # Где файл используется — чтобы не удалить урок, который смотрят.
    used = {}
    catalog = _read_json(os.path.join(ROOT, 'courses.json'), {})
    for d in (catalog.get('directions') or []):
        for c in (d.get('courses') or []):
            for l in (c.get('lessons') or []):
                url = l.get('url') or ''
                key = url.rsplit('/', 1)[-1]
                if key:
                    used.setdefault(key, []).append(
                        f"{d.get('title','')} / {c.get('title','')} / "
                        f"{l.get('title','')}")
    for it in items:
        it['usedIn'] = used.get(it['name'], [])
    return {'items': items, 'folders': folders, 'disk': disk,
            'mediaBase': MEDIA_BASE}


def _delete_media(data):
    name = safe_upload_name(data.get('name'))
    if not name:
        return 400, {'error': 'bad name'}
    full = os.path.join(UPLOADS, name)
    if not os.path.abspath(full).startswith(os.path.abspath(UPLOADS)):
        return 403, {'error': 'forbidden'}
    if not os.path.isfile(full):
        return 404, {'error': 'no file'}
    try:
        os.remove(full)
    except OSError as e:
        return 500, {'error': str(e)}
    # Метку папки убираем следом, иначе указатель копил бы записи о том,
    # чего уже нет, и счётчики папок врали бы.
    with _lock:
        idx = _load_index()
        if idx['files'].pop(name, None) is not None:
            _save_index(idx)
    return 200, {'name': name, 'deleted': True}


def _set_blocked(data):
    """Блокирует/разблокирует одного ученика.

    Раньше и панель, и приложение устаза перезаписывали ВЕСЬ users.json
    снимком, загруженным при открытии списка. Пока админ смотрел на экран,
    ученики успевали отметиться (lastSeen, намазы, коины), а кто-то —
    зарегистрироваться; запись поверх затирала и то, и другое. Точечная
    операция под замком это исключает.
    """
    ident = _identity(data)
    blocked = bool(data.get('blocked'))
    with _lock:
        users = _load_users()
        rec = _find_user(users, ident)
        if rec is None:
            return 404, {'error': 'no user'}
        rec['blocked'] = blocked
        _save_users(users)
        return 200, {'student': ident, 'blocked': blocked}


def _delete_user(data):
    """Убирает ученика из реестра (аккаунт на его устройстве остаётся)."""
    ident = _identity(data)
    with _lock:
        users = _load_users()
        rest = [x for x in users
                if x.get('phone') != ident and x.get('email') != ident]
        if len(rest) == len(users):
            return 404, {'error': 'no user'}
        _save_users(rest)
        return 200, {'student': ident, 'deleted': True}


def _redeem(data):
    """Обмен коинов на награду. Баланс считает и код выдаёт сервер.

    Возвращает (код_ответа, тело).
    """
    ident = _identity(data)
    item_id = (data.get('itemId') or '').strip()[:40]
    if not ident:
        return 400, {'error': 'bad phone'}
    cost = SHOP_ITEMS.get(item_id)
    if cost is None:
        return 400, {'error': 'unknown item'}
    now = int(time.time() * 1000)
    with _lock:
        users = _load_users()
        rec = _find_user(users, ident)
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
        entry = {'code': code, 'student': ident, 'name': rec.get('name', ''),
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


_RANGE_RE = re.compile(r'^bytes=(\d*)-(\d*)$')
_CHUNK = 1 << 16


class Handler(http.server.SimpleHTTPRequestHandler):
    # Keep-alive: плеер шлёт десятки Range-запросов подряд, и открывать под
    # каждый новое соединение — заметная задержка при перемотке.
    # Обязательное условие: Content-Length есть у любого ответа (см. ниже).
    protocol_version = 'HTTP/1.1'

    # Правильные типы для HLS (ABR-транскод отдаётся отсюда же).
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        '.m3u8': 'application/vnd.apple.mpegurl',
        '.ts': 'video/mp2t',
    }

    def end_headers(self):
        self.send_header('Cache-Control', 'no-cache')
        self.send_header('Access-Control-Allow-Origin', '*')
        # Без этого плеер не знает, что можно запрашивать куски файла.
        self.send_header('Accept-Ranges', 'bytes')
        super().end_headers()

    def _serve_range(self):
        """Отдаёт кусок файла по заголовку Range. True — запрос обработан.

        Базовый SimpleHTTPRequestHandler заголовок Range игнорирует и всегда
        шлёт файл целиком: перемотка в уроке не работала, а iOS-плееру
        приходилось тянуть весь ролик перед стартом. Для видео это
        обязательная вещь, поэтому обрабатываем сами.
        """
        rng = (self.headers.get('Range') or '').strip()
        if not rng:
            return False
        path = self.translate_path(self.path.split('?')[0])
        if not os.path.isfile(path):
            return False

        size = os.path.getsize(path)
        m = _RANGE_RE.match(rng)
        if not m:
            self._range_not_satisfiable(size)
            return True
        start_s, end_s = m.group(1), m.group(2)
        if not start_s:
            # «bytes=-N» — последние N байт.
            n = int(end_s or 0)
            if n <= 0:
                self._range_not_satisfiable(size)
                return True
            start, end = max(0, size - n), size - 1
        else:
            start = int(start_s)
            end = int(end_s) if end_s else size - 1
        if start >= size or end < start:
            self._range_not_satisfiable(size)
            return True
        end = min(end, size - 1)
        length = end - start + 1

        self.send_response(206)
        self.send_header('Content-Type', self.guess_type(path))
        self.send_header('Content-Length', str(length))
        self.send_header('Content-Range', f'bytes {start}-{end}/{size}')
        self.send_header('Last-Modified',
                         self.date_time_string(os.stat(path).st_mtime))
        self.end_headers()
        try:
            with open(path, 'rb') as f:
                f.seek(start)
                left = length
                while left > 0:
                    buf = f.read(min(_CHUNK, left))
                    if not buf:
                        break
                    self.wfile.write(buf)
                    left -= len(buf)
        except (BrokenPipeError, ConnectionResetError):
            # Плеер перемотал или закрыл урок — это норма, не ошибка.
            pass
        return True

    def _range_not_satisfiable(self, size):
        self.send_response(416)
        self.send_header('Content-Range', f'bytes */{size}')
        self.send_header('Content-Length', '0')
        self.end_headers()

    def _send_json(self, code, obj):
        body = json.dumps(obj, ensure_ascii=False).encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    @property
    def _ip(self):
        # nginx впереди пока нет, поэтому адрес берём с сокета. Когда
        # появится прокси, здесь понадобится X-Forwarded-For (и доверять
        # ему можно будет только от самого прокси).
        return self.client_address[0]

    def _role_checked(self):
        """Роль запроса с защитой от перебора пароля."""
        role = _role(self.headers)
        if role is None and self.headers.get('Authorization'):
            # Считаем только неудачные попытки — успешные не наказываем.
            if not _rate_ok('authfail', self._ip, RATE_AUTH_FAIL):
                return 'ratelimited'
        return role

    def _deny(self, code=401):
        self.send_response(code)
        self.send_header('Content-Length', '0')
        self.end_headers()

    def _too_many(self):
        self._send_json(429, {'error': 'too many requests'})

    def list_directory(self, path):
        # Листинги перечисляли все файлы данных и загруженные уроки —
        # незачем облегчать перебор. Отдаём 403.
        self.send_error(403, 'Forbidden')
        return None

    def do_GET(self):
        p = self.path.split('?')[0].rstrip('/')
        # Реестр аккаунтов, доступы и коды (ПДн) — только админ.
        if p in _PROTECTED_GET or p in _AUTHED_GET:
            role = self._role_checked()
            if role == 'ratelimited':
                self._too_many()
                return
            need_admin = p in _PROTECTED_GET
            if role is None or (need_admin and role != 'admin'):
                self._deny()
                return
        if p == '/media.json':
            self._send_json(200, _media_list())
            return
        if self._serve_range():
            return
        return super().do_GET()

    # Ручки без пароля: любой может засыпать реестр, чат и коды.
    _ANON_POST = ('/users', '/comments', '/verify/request', '/verify/confirm',
                  '/redeem')

    def do_POST(self):
        p = self.path.rstrip('/')
        if p in self._ANON_POST and not _rate_ok('anon', self._ip, RATE_ANON):
            self._too_many()
            return
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
            if rec.get('error'):
                self._send_json(507, rec)
                return
            self._send_json(201, rec)
            return
        if p == '/redeem':
            code, body = _redeem(data)
            self._send_json(code, body)
            return
        if p == '/auth/check':
            role = self._role_checked()
            if role == 'ratelimited':
                self._too_many()
                return
            if role is None:
                self._deny()
                return
            self._send_json(200, {'role': role})
            return
        if p == '/verify/request':
            code, body = _request_code(data)
            self._send_json(code, body)
            return
        if p == '/verify/confirm':
            code, body = _confirm_code(data)
            self._send_json(code, body)
            return
        if p in ('/media/delete', '/media/folder', '/media/move'):
            if self._role_checked() != 'admin':
                self._deny()
                return
            code, body = (
                _delete_media(data) if p == '/media/delete'
                else _folder_op(data) if p == '/media/folder'
                else _media_move(data))
            self._send_json(code, body)
            return
        if p in ('/users/flag', '/users/delete'):
            if self._role_checked() != 'admin':
                self._deny()
                return
            code, body = (_set_blocked(data) if p == '/users/flag'
                          else _delete_user(data))
            self._send_json(code, body)
            return
        if p == '/access/grant':
            if self._role_checked() != 'admin':
                self._deny()
                return
            code, body = _grant_access(data)
            self._send_json(code, body)
            return
        if p == '/access/revoke':
            if self._role_checked() != 'admin':
                self._deny()
                return
            code, body = _revoke_access(data)
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
        self._send_json(404, {'error': 'not found'})

    def do_PUT(self):
        if not _put_allowed(self.path):
            self._send_json(403, {'error': 'path not writable'})
            return
        role = self._role_checked()
        if role == 'ratelimited':
            self._too_many()
            return
        if role is None:
            self._deny()
            return
        need = _put_role_for(self.path)
        # admin может всё; ustaz — только то, что помечено 'ustaz'.
        if need == 'admin' and role != 'admin':
            self._send_json(403, {'error': 'admin only'})
            return
        # Имя файла в uploads чистим сами: каталог раздаётся всем, и
        # заливать туда что попало (или уходить вверх по дереву) нельзя.
        raw = self.path.split('?')[0]
        upload = raw.startswith('/uploads/')
        if upload:
            name = safe_upload_name(raw[len('/uploads/'):])
            if not name:
                self._send_json(415, {'error': 'unsupported file type'})
                return
            os.makedirs(UPLOADS, exist_ok=True)
            path = os.path.join(UPLOADS, name)
        else:
            path = self.translate_path(self.path)
        if not os.path.abspath(path).startswith(ROOT):
            self._deny(403)
            return
        os.makedirs(os.path.dirname(path), exist_ok=True)
        # Перед перезаписью откладываем предыдущую версию: одобрение
        # модерации затирает live-файл целиком, и ошибочная публикация
        # иначе безвозвратно уносит то, что было опубликовано раньше.
        _keep_backup(path)
        n = int(self.headers.get('Content-Length', 0))
        remaining, chunk = n, 1 << 20
        with open(path, 'wb') as f:
            while remaining > 0:
                data = self.rfile.read(min(chunk, remaining))
                if not data:
                    break
                f.write(data)
                remaining -= len(data)
        if upload:
            # Имя после чистки отличается от присланного (транслитерация,
            # замена символов) — панели оно нужно, чтобы сразу положить файл
            # в открытую папку и показать его без перезагрузки списка.
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            _assign_folder(name, (q.get('folder') or [''])[0][:40])
            self._send_json(201, {
                'name': name,
                'url': f'/uploads/{name}',
                'publicUrl': f'{MEDIA_BASE}/uploads/{name}',
            })
            return
        self.send_response(201)
        self.send_header('Content-Length', '0')
        self.end_headers()


if __name__ == '__main__':
    http.server.ThreadingHTTPServer(('0.0.0.0', 8090), Handler).serve_forever()
