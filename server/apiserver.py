#!/usr/bin/env python3
"""API-сервер «Ирфан».

Роли (basic-auth, учётки в /etc/irfan/auth.json — вне репозитория):
  admin — публикация в live (courses.json/news.json/azkar.json), реестр
          студентов, коды выкупа;
  ustaz — только заявки на модерацию (*_pending.json) и загрузка файлов.

Персональные учётки устазов (/etc/irfan/staff.json, заводит админ) —
вход по POST /auth/token, дальше `Authorization: Bearer <токен>`. Нужны
потому, что приложение стало публичным: зашитый в сборку общий пароль
вытаскивается из бинарника любым скачавшим. Токен привязан к своему
teacherId — устаз пишет только собственную заявку на каталог.

GET  — всем, кроме путей с ПДн (users.json, redemptions.json) — только admin.
PUT  — по ролям (см. _put_role_for).
POST /comments   — чат эфира от студентов (без пароля);
POST /users      — студент сообщает профиль/активность (без пароля);
POST /redeem     — обмен коинов на награду: баланс и код выдаёт СЕРВЕР;
POST /verify/request, /verify/confirm — подтверждение телефона кодом;
POST /backup     — ученик сохраняет слепок своего прогресса (см. _put_snapshot);
POST /account/restore — перенос аккаунта на новый телефон (см. _restore_account);
POST /teachers   — устаз заводит себя в реестре (статус pending);
POST /teachers/flag, /teachers/delete (admin) — модерация устазов;
POST /access/grant, /access/revoke (admin) — доступ к направлению/курсу
                   на срок в днях или бессрочно.
"""
import base64
import hashlib
import hmac
import http.server
import json
import os
import secrets
import re
import shutil
import subprocess
import threading
import time
import urllib.parse

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'api')
AUTH_FILE = os.environ.get('IRFAN_AUTH_FILE', '/etc/irfan/auth.json')
# Персональные учётки устазов и данные публикации эфира — рядом с auth.json,
# вне репозитория и вне раздаваемого каталога. Пути переопределяются через
# окружение, чтобы прогонять сервер локально, не трогая боевые файлы.
STAFF_FILE = os.environ.get('IRFAN_STAFF_FILE', '/etc/irfan/staff.json')
STREAM_FILE = os.environ.get('IRFAN_STREAM_FILE', '/etc/irfan/stream.json')
# Секрет подписи ссылок на уроки и выключатель проверки.
MEDIA_CFG = os.environ.get('IRFAN_MEDIA_CFG', '/etc/irfan/media.json')
COMMENTS = os.path.join(ROOT, 'comments.json')
USERS = os.path.join(ROOT, 'users.json')
REDEMPTIONS = os.path.join(ROOT, 'redemptions.json')
ACCESS = os.path.join(ROOT, 'access.json')
TEACHERS = os.path.join(ROOT, 'teachers.json')
# Каталог версий — СОСЕДНИЙ с api/, а не внутри: всё, что лежит в ROOT,
# раздаётся по HTTP, и копия users.json стала бы публичной.
VERSIONS = os.path.join(os.path.dirname(ROOT), 'versions')
VERIFY = os.path.join(ROOT, 'verifications.json')
REPORTS = os.path.join(ROOT, 'reports.json')
CRASHES = os.path.join(ROOT, 'crashes.json')
# Выданные токены — тоже СОСЕДНИЙ файл: внутри api/ он раздавался бы по HTTP.
TOKENS = os.path.join(os.path.dirname(ROOT), 'tokens.json')
# Слепки прогресса учеников. Каталог СОСЕДНИЙ с api/ и это здесь не мелочь:
# имя файла выводится из номера телефона, то есть внутри ROOT любой желающий
# скачивал бы чужую историю, просто перебирая номера. Имя всё равно хешируем —
# чтобы номера не светились и в листинге каталога на самом сервере.
# Каталог `backups` рядом уже занят архивами backup.sh, отсюда другое имя.
SNAPSHOTS = os.path.join(os.path.dirname(ROOT), 'snapshots')
_MAX_COMMENTS = 200
_MAX_REPORTS = 2000
# Сбоев храним по видам, а не по случаям: одна и та же ошибка у
# сотни человек — это одна строка со счётчиком, иначе список
# забивается и в нём ничего не видно.
_MAX_CRASHES = 300
# Потолок тела POST-запроса: там всегда небольшой JSON (анкета, комментарий,
# заявка). Загрузка уроков идёт через PUT и этим потолком не ограничена.
_MAX_POST_BYTES = 256 * 1024
# Потолки для PUT: урок — большой файл (самый тяжёлый из залитых 787 МБ),
# JSON-документы каталога и новостей — заведомо мелкие.
_MAX_UPLOAD_BYTES = 4 * 1024 ** 3
# Сколько живёт подписанная ссылка на урок. Урок длинный, а
# перемотка открывает соединение заново — с коротким сроком
# видео обрывалось бы на середине.
MEDIA_LINK_TTL_S = 6 * 3600
_MAX_JSON_PUT_BYTES = 8 * 1024 * 1024
# Слепок прогресса одного ученика. Реальный размер — единицы килобайт:
# день трекера это пять коротких пометок, а зикры — счётчик на день. Потолок
# взят с большим запасом (примерно на тридцать лет ежедневных записей) и
# нужен только чтобы никто не занял диск под видом истории намазов.
_MAX_SNAPSHOT_BYTES = 192 * 1024

# Корни грубой брани. Первая группа ловится с приставками («нахуй»,
# «заебал»), вторая — только с начала слова: иначе «барсука» и «сукно»
# попадали бы под «сука». Список заведомо неполный, см. _mask_profanity.
_PROFANITY_RE = re.compile(
    r'\w*(?:хуй|хуё|хуе|пизд|ебат|ебал|ебан|еблан|бляд|блять|мудак|мудил'
    r'|гандон|долбоёб|долбоеб|пидор|пидар|ублюд|шлюх|fuck|cunt)\w*'
    r'|\b(?:сука|сучка|говно|shit|bitch)\w*', re.IGNORECASE)
_MAX_USERS = 10000
_MAX_REDEMPTIONS = 20000
_MAX_TEACHERS = 500

# Пути с ПДн — GET только для админа.
#
# admin.json (хеш пароля админа) раньше был доступен ЛЮБОЙ роли: приложение
# устаза читало его, чтобы проверить скрытый вход админа у себя на телефоне.
# Того приложения больше нет, а хеш брутфорсится офлайн — то есть любой устаз
# мог унести его и спокойно подбирать пароль. Теперь только админ; сам файл
# ничем уже не читается и его можно удалить с сервера.
_PROTECTED_GET = ('/users.json', '/redemptions.json', '/access.json',
                  '/verifications.json', '/media.json', '/pending.json',
                  '/staff.json', '/reports.json', '/admin.json',
                  '/crashes.json')
# Данные публикации эфира — любому вошедшему устазу, это его рабочий ключ.
_AUTHED_GET = ('/stream.json',)

# Что можно писать устазу: только заявки на модерацию и загрузки.
_USTAZ_WRITABLE = ('/courses_pending.json', '/news_pending.json',
                   '/azkar_pending.json')
_USTAZ_WRITABLE_PREFIX = ('/uploads/',)
# Заявка на каталог — у каждого устаза своя: с общим courses_pending.json
# двое публикующих затирали бы работу друг друга.
_PENDING_RE = re.compile(r'^/courses_pending_[0-9a-f]{6,32}\.json$')

# Каталог наград — источник истины для стоимости (клиенту не доверяем).
SHOP_ITEMS = {
    'tasbih': 500,
    'book': 700,
    'mat': 1000,
    # Скидка на курсы убрана из приложения (цифровой товар мимо встроенных
    # покупок Apple), но id оставлен: по нему приходят уже выданные коды.
    'course': 1000,
}
MAX_COINS = 1000
COINS_PER_PRAYER = 5
# Потолок за сутки: 5 намазов по 5 коинов + запас на зикры.
MAX_COINS_PER_DAY = 55

# Персональные учётки устазов и токены входа.
PBKDF2_ITER = 120_000
TOKEN_TTL_MS = 30 * 24 * 3600 * 1000   # месяц, продлевается при обращении
_MAX_TOKENS = 500
_MAX_STAFF = 200
_LOGIN_RE = re.compile(r'^[a-z0-9._-]{3,32}$')

# Подтверждение телефона кодом.
#
# Код живёт час, а не десять минут, как было бы при автоотправке. Канал
# доставки — человек: ученик просит код у устаза, тот смотрит его в панели.
# С десятиминутным сроком код успевал истечь до того, как устаз вообще
# заметил запрос, и ученик крутился по кругу «запросить снова».
CODE_TTL_MS = 60 * 60 * 1000
CODE_MAX_ATTEMPTS = 5            # неверных попыток на код
CODE_RESEND_MS = 60 * 1000       # не чаще одного кода в минуту
_MAX_VERIFY = 5000
# Разрешение на перенос аккаунта, выдаётся после верного кода. Отдельная
# одноразовая бумажка, а не сам код: код ученик мог продиктовать вслух,
# а перенос забирает аккаунт у прежнего телефона.
RESTORE_TICKET_TTL_MS = 15 * 60 * 1000

# Ограничение частоты: сколько запросов с одного адреса за окно.
RATE_WINDOW_S = 60
RATE_ANON = 20          # анонимные POST (/users, /comments, /verify/request)
RATE_AUTH_FAIL = 10     # неудачные попытки авторизации
# Кадры-превью: панель открывает список из двух сотен файлов, и браузер
# просит их пачками. Дорогая часть всё равно упирается в очередь ffmpeg.
RATE_THUMB = 300

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


def _pw_hash(password, salt=None, iters=PBKDF2_ITER):
    """PBKDF2-HMAC-SHA256. Формат строки — `pbkdf2$итерации$соль$хеш`."""
    salt = salt or secrets.token_bytes(16)
    dk = hashlib.pbkdf2_hmac('sha256', password.encode('utf-8'), salt, iters)
    return 'pbkdf2${}${}${}'.format(
        iters, base64.b64encode(salt).decode(), base64.b64encode(dk).decode())


def _pw_verify(password, stored):
    try:
        algo, iters, salt_b64, dk_b64 = str(stored).split('$')
        if algo != 'pbkdf2':
            return False
        want = base64.b64decode(dk_b64)
        got = hashlib.pbkdf2_hmac('sha256', password.encode('utf-8'),
                                  base64.b64decode(salt_b64), int(iters))
    except (ValueError, TypeError):
        return False
    return secrets.compare_digest(got, want)


def _write_private(path, obj):
    """Пишет JSON так, чтобы файл не читался никем, кроме владельца."""
    tmp = path + '.tmp'
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, 'w', encoding='utf-8') as f:
        json.dump(obj, f, ensure_ascii=False)
    os.replace(tmp, path)


def _load_staff():
    v = _read_json(STAFF_FILE, [])
    return [s for s in v if isinstance(s, dict)] if isinstance(v, list) else []


def _save_staff(items):
    _write_private(STAFF_FILE, items)


def _find_staff(items, login):
    return next((s for s in items if s.get('login') == login), None)


def _load_tokens():
    v = _read_json(TOKENS, {})
    return v if isinstance(v, dict) else {}


def _save_tokens(items):
    _write_private(TOKENS, items)


def _token_key(token):
    """В файле лежит только хеш: утечка tokens.json не даёт войти."""
    return hashlib.sha256(('irfan-token:' + token).encode()).hexdigest()


def _issue_token(rec):
    now = int(time.time() * 1000)
    token = secrets.token_urlsafe(32)
    with _lock:
        items = _load_tokens()
        # Заодно чистим протухшие, иначе файл растёт до бесконечности.
        items = {k: v for k, v in items.items()
                 if isinstance(v, dict) and (v.get('exp') or 0) > now}
        if len(items) >= _MAX_TOKENS:
            oldest = sorted(items.items(), key=lambda kv: kv[1].get('exp') or 0)
            for k, _ in oldest[:len(items) - _MAX_TOKENS + 1]:
                items.pop(k, None)
        items[_token_key(token)] = {
            'login': rec.get('login'),
            'role': rec.get('role') or 'ustaz',
            'teacherId': rec.get('teacherId'),
            'name': rec.get('name'),
            'created': now,
            'exp': now + TOKEN_TTL_MS,
        }
        _save_tokens(items)
    return token, now + TOKEN_TTL_MS


def _token_principal(token):
    """Кто стоит за токеном, либо None. Просроченный токен не пускает."""
    if not token:
        return None
    key = _token_key(token)
    now = int(time.time() * 1000)
    items = _load_tokens()
    rec = items.get(key)
    if not isinstance(rec, dict) or (rec.get('exp') or 0) <= now:
        return None
    # Учётку могли отключить или удалить уже после выдачи токена.
    staff = _find_staff(_load_staff(), rec.get('login'))
    if staff is None or staff.get('disabled'):
        return None
    return {'role': rec.get('role') or 'ustaz', 'login': rec.get('login'),
            'teacherId': rec.get('teacherId'), 'name': rec.get('name'),
            'exp': rec.get('exp')}


def _revoke_token(token):
    key = _token_key(token or '')
    with _lock:
        items = _load_tokens()
        if items.pop(key, None) is None:
            return False
        _save_tokens(items)
        return True


def _auth_token(data):
    """Вход устаза по логину и паролю. Возвращает (код, тело)."""
    login = str(data.get('login') or '').strip().lower()
    password = str(data.get('password') or '')
    if not login or not password:
        return 400, {'error': 'no credentials'}
    rec = _find_staff(_load_staff(), login)
    # Пароль проверяем даже для несуществующего логина: иначе по времени
    # ответа видно, какие логины заведены.
    stored = (rec or {}).get('pass') or _pw_hash('-')
    ok = _pw_verify(password, stored)
    if rec is None or not ok or rec.get('disabled'):
        return 401, {'error': 'bad credentials'}
    token, exp = _issue_token(rec)
    return 200, {
        'token': token,
        'login': login,
        'role': rec.get('role') or 'ustaz',
        'teacherId': rec.get('teacherId'),
        'name': rec.get('name') or login,
        'expiresAt': exp,
    }


def _staff_op(data):
    """Управление учётками устазов из веб-панели (только админ)."""
    op = str(data.get('op') or '').strip()
    login = str(data.get('login') or '').strip().lower()
    if op not in ('create', 'password', 'disable', 'enable', 'delete'):
        return 400, {'error': 'bad op'}
    if not _LOGIN_RE.match(login):
        return 400, {'error': 'логин: 3–32 символа, латиница, цифры, . _ -'}
    password = str(data.get('password') or '')
    if op in ('create', 'password') and len(password) < 8:
        return 400, {'error': 'пароль — минимум 8 символов'}
    now = int(time.time() * 1000)
    with _lock:
        items = _load_staff()
        rec = _find_staff(items, login)
        if op == 'create':
            if rec is not None:
                return 409, {'error': 'логин занят'}
            if len(items) >= _MAX_STAFF:
                return 507, {'error': 'staff full'}
            rec = {
                'login': login,
                'name': (str(data.get('name') or '').strip()[:60] or login),
                'role': 'ustaz',
                'teacherId': _teacher_id(login),
                'pass': _pw_hash(password),
                'createdAt': now,
            }
            items.append(rec)
        elif rec is None:
            return 404, {'error': 'no staff'}
        elif op == 'password':
            rec['pass'] = _pw_hash(password)
            rec['passwordChangedAt'] = now
        elif op in ('disable', 'enable'):
            rec['disabled'] = (op == 'disable')
        elif op == 'delete':
            items = [s for s in items if s.get('login') != login]
        _save_staff(items)
    # Отключение и удаление должны гасить уже выданные токены немедленно.
    if op in ('disable', 'delete', 'password'):
        with _lock:
            toks = {k: v for k, v in _load_tokens().items()
                    if not (isinstance(v, dict) and v.get('login') == login)}
            _save_tokens(toks)
    if op == 'create':
        # Заводим и запись в реестре устазов, сразу одобренную: логин выдал
        # админ, отдельная модерация здесь ничего не добавляет.
        _upsert_teacher({'login': login, 'name': rec.get('name')})
        _set_teacher_status({'id': rec.get('teacherId'), 'status': 'approved'})
        return 201, {'login': login, 'teacherId': rec.get('teacherId'),
                     'name': rec.get('name')}
    return 200, {'login': login, 'op': op}


def _staff_list():
    """Список учёток для панели — без хешей паролей."""
    return {'staff': [{
        'login': s.get('login'),
        'name': s.get('name'),
        'teacherId': s.get('teacherId'),
        'disabled': bool(s.get('disabled')),
        'createdAt': s.get('createdAt'),
    } for s in _load_staff()]}


def _stream_config():
    """Адрес и учётка публикации эфира — отдаются только вошедшему персоналу.

    Раньше ключ потока был константой в сборке приложения устаза. В публичном
    приложении так нельзя: узнав ключ, посторонний вклинится в эфир.
    """
    cfg = _read_json(STREAM_FILE, {})
    if not isinstance(cfg, dict):
        cfg = {}
    key = cfg.get('key')
    if not key:
        # Файла с настройками эфира нет. Раньше здесь стоял прежний ключ
        # потока — в репозитории ему не место, да и молча подставлять
        # нерабочую учётку хуже, чем честно сказать «не настроено».
        return None
    user, password = cfg.get('user'), cfg.get('pass')
    # MediaMTX принимает учётку прямо в RTMP-URL, а плагин на телефоне
    # умеет только «адрес + ключ» — поэтому логин едет хвостом ключа.
    if user and password:
        key = '{}?user={}&pass={}'.format(
            key, urllib.parse.quote(user), urllib.parse.quote(password))
    return {
        'rtmpUrl': cfg.get('rtmpUrl') or 'rtmp://178.104.206.100/live',
        'streamKey': key,
    }


def _principal(headers):
    """Кто делает запрос: dict с role/login/teacherId, либо None.

    Поддерживаются оба способа: общий basic-auth (веб-панель, заливка с
    ноутбука) и персональный bearer-токен устаза из приложения.
    """
    got = headers.get('Authorization', '')
    if got.startswith('Bearer '):
        return _token_principal(got[len('Bearer '):].strip())
    for hdr, role in _AUTH.items():
        if secrets.compare_digest(got, hdr):
            return {'role': role, 'login': role, 'teacherId': None,
                    'name': role}
    return None


def _role(headers):
    """Роль запроса: 'admin' | 'ustaz' | None. Сравнение — постоянного времени."""
    return (_principal(headers) or {}).get('role')


# Куда вообще можно писать. Раньше админский PUT принимал любой путь внутри
# api/ и создавал произвольные файлы и каталоги — в том числе .html, который
# отдавался бы браузеру с нашего же адреса. Теперь список закрытый.
_PUT_ALLOWED = ('/courses.json', '/news.json', '/azkar.json',
                '/courses_pending.json', '/news_pending.json',
                '/azkar_pending.json', '/users.json', '/admin.json',
                '/status.json', '/live-title.txt', '/teachers.json',
                '/support.json')


def _put_allowed(path):
    p = path.split('?')[0]
    return (p in _PUT_ALLOWED or p.startswith('/uploads/')
            or bool(_PENDING_RE.match(p)))


def _put_role_for(path):
    """Какая роль нужна, чтобы писать в этот путь."""
    p = path.split('?')[0]
    if (p in _USTAZ_WRITABLE or p.startswith(_USTAZ_WRITABLE_PREFIX)
            or _PENDING_RE.match(p)):
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


def _mask_profanity(text):
    """Закрывает звёздочками грубую брань в чате эфира.

    Список заведомо неполный — обойти его несложно. Он и не задуман как
    защита: это обязательный для App Store фильтр очевидного (Guideline 1.2),
    работающий вместе с жалобой на сообщение и блокировкой автора. Убирает
    самое грубое до того, как его увидят дети на уроке.
    """
    def cover(m):
        w = m.group(0)
        return w[0] + '*' * (len(w) - 1)
    return _PROFANITY_RE.sub(cover, text)


def _is_teacher_name(name):
    """Совпадает ли имя с кем-то из реестра преподавателей."""
    n = (name or '').strip().lower()
    if not n:
        return False
    return any((t.get('name') or '').strip().lower() == n
               for t in _load_teachers())


def _add_comment(name, text):
    """Добавляет комментарий зрителя в comments.json, возвращает его или None."""
    name = (name or '').strip()[:40] or 'Гость'
    text = _mask_profanity((text or '').strip()[:300])
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
        # Имя из реестра — чтобы в панели было видно, КОГО спрашивают. Код
        # выдаёт человек, и один номер в столбце ему ничего не говорит.
        rec = _find_user(_load_users(), phone)
        entry = {'phone': phone, 'code': code,
                 'name': (rec or {}).get('name', ''),
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
        # Разрешение на перенос аккаунта. Выдаём всегда, а не только когда
        # запись есть: иначе ответ сервера говорил бы постороннему, заведён
        # ли аккаунт на этом номере.
        ticket = secrets.token_urlsafe(24)
        entry['ticket'] = ticket
        entry['ticketExpires'] = now + RESTORE_TICKET_TTL_MS
        _save_verify(items)
        users = _load_users()
        rec = _find_user(users, phone)
        if rec is not None:
            rec['verified'] = True
            _save_users(users)
    return 200, {'verified': True, 'restoreTicket': ticket}


# ——— Перенос аккаунта на другой телефон ———
#
# Аккаунт ученика живёт на телефоне: пароля на сервере нет, вся история
# (трекер намазов, зикры, обеты, закладки Корана) лежит в SharedPreferences.
# Пока этого раздела не было, смена телефона означала потерю серии, коинов и
# всей истории без всякой возможности вернуть их — и это была самая частая
# настоящая потеря у людей, которые пользуются приложением каждый день.
#
# Устроено так: приложение само присылает сюда слепок своего хранилища, а на
# новом телефоне забирает его обратно. Сервер в содержимое не смотрит и не
# считает по нему ничего — это непрозрачный ящик, который вернут владельцу.
# Заработанное считается по-прежнему по полям реестра (prayersRead/coins) с
# теми же потолками, поэтому подложным слепком коинов себе не прибавить.


def _snapshot_path(phone):
    name = hashlib.sha256(('irfan-snap:' + phone).encode()).hexdigest()[:32]
    return os.path.join(SNAPSHOTS, name + '.json')


def _load_snapshot(phone):
    return _read_json(_snapshot_path(phone), None)


def _drop_snapshot(phone):
    """Снести слепок — вместе с аккаунтом. Без этого удаление аккаунта
    оставляло бы на сервере всю историю человека (App Store 5.1.1(v))."""
    try:
        os.remove(_snapshot_path(phone))
        return True
    except OSError:
        return False


def _put_snapshot(data):
    """Ученик сохраняет слепок своего прогресса.

    Право на запись — тот же ключ устройства, что и у остальных ученических
    ручек: иначе знающий номер затирал бы чужую историю пустым слепком.
    """
    ident = _identity(data)
    if not ident:
        return 400, {'error': 'bad phone'}
    blob = data.get('data')
    if not isinstance(blob, dict):
        return 400, {'error': 'bad data'}
    raw = json.dumps(blob, ensure_ascii=False, separators=(',', ':'))
    if len(raw.encode('utf-8')) > _MAX_SNAPSHOT_BYTES:
        return 413, {'error': 'too large'}
    now = int(time.time() * 1000)
    with _lock:
        users = _load_users()
        rec = _find_user(users, ident)
        if rec is None:
            # Слепок без записи в реестре осиротеет: восстанавливать будет
            # некуда и некому. Приложение всё равно первым делом шлёт профиль.
            return 404, {'error': 'no user'}
        if not _student_ok(rec, data):
            return 403, {'error': 'forbidden'}
        # _student_ok мог закрепить запись за этим устройством — сохраняем.
        _save_users(users)
        os.makedirs(SNAPSHOTS, exist_ok=True)
        os.chmod(SNAPSHOTS, 0o700)
        path = _snapshot_path(ident)
        # Через временный файл: оборванная запись оставила бы обрезанный JSON,
        # то есть человек лишился бы истории ровно в тот момент, когда она
        # ему и понадобилась.
        tmp = path + '.tmp'
        with open(tmp, 'w', encoding='utf-8') as f:
            json.dump({'phone': ident, 'updatedAt': now, 'data': blob}, f,
                      ensure_ascii=False, separators=(',', ':'))
        os.replace(tmp, path)
        os.chmod(path, 0o600)
    return 201, {'ok': True, 'updatedAt': now}


def _ticket_ok(phone, ticket, now):
    """Гасит одноразовое разрешение на перенос. Вызывать под _lock."""
    if len(ticket) < 16:
        return False
    items = _load_verify()
    for e in reversed(items):
        if e.get('phone') != phone or e.get('ticketUsed'):
            continue
        have = e.get('ticket')
        if not have or now > int(e.get('ticketExpires') or 0):
            continue
        if secrets.compare_digest(ticket, str(have)):
            e['ticketUsed'] = True
            e['ticketUsedAt'] = now
            _save_verify(items)
            return True
    return False


def _restore_account(data):
    """Отдаёт аккаунт новому телефону.

    Два пути внутрь:
      * ключ устройства уже записан в реестре — это тот же телефон после
        переустановки (Keychain её переживает, а SharedPreferences нет), и
        код тут спрашивать не за что;
      * одноразовое разрешение после подтверждения номера — это новый
        телефон, и запись переезжает на него.

    Переезд забирает право писать у прежнего устройства: два телефона с одной
    историей разошлись бы, и чей слепок последний, тот и затёр бы остальные.
    """
    ident = _identity(data)
    if not ident:
        return 400, {'error': 'bad phone'}
    got = _auth_key(data.get('secret'))
    ticket = str(data.get('ticket') or '')[:64]
    now = int(time.time() * 1000)
    with _lock:
        users = _load_users()
        rec = _find_user(users, ident)
        if rec is None:
            return 404, {'error': 'no account'}
        if rec.get('blocked'):
            return 403, {'error': 'blocked'}
        have = rec.get('authKey')
        same_device = bool(got) and bool(have) and \
            secrets.compare_digest(got, have)
        if not same_device:
            if not got:
                # Без ключа запись не за кем закреплять, а отдавать историю
                # неизвестно кому — тем более. Проверяем ДО разрешения:
                # _ticket_ok его гасит, и заведомо безнадёжная попытка
                # сжигала бы бумажку, за которой человек ходил к устазу.
                return 400, {'error': 'no device key'}
            if not _ticket_ok(ident, ticket, now):
                return 403, {'error': 'forbidden'}
            rec['authKey'] = got
            rec['movedAt'] = now
            _save_users(users)
        snap = _load_snapshot(ident)
        rec = dict(rec)     # дальше читаем уже вне замка
    return 200, {
        'profile': {k: rec.get(k) for k in (
            'name', 'gender', 'age', 'city', 'verified', 'accountCreatedAt',
            'prayersRead', 'streak', 'coins', 'spent', 'balance')},
        'access': _access_for(ident),
        # Потраченное берётся из реестра, а не из слепка: слепок мог быть
        # снят до выкупа награды, и восстановление вернуло бы уже потраченные
        # коины в кошелёк.
        'spent': int(rec.get('spent') or 0),
        'data': (snap or {}).get('data'),
        'updatedAt': (snap or {}).get('updatedAt'),
    }


# ── Устазы ───────────────────────────────────────────────────────────────
#
# Приложение студента показывает список устазов и уроки выбранного. Устаз
# заводится сам из своего приложения и до одобрения админом студентам не
# виден — это та же модерация, что и у курсов, только на уровне человека.


def _teacher_id(ident):
    """Опознаватель устаза — хеш его логина (почты или номера).

    teachers.json читает приложение студента, то есть файл публичный. Класть
    туда почту или номер нельзя, а связывать заявки с автором чем-то надо —
    берём необратимый хеш: устаз считает его у себя тем же способом и
    попадает в свою же запись.
    """
    p = _norm_phone(ident) or str(ident or '').strip().lower()
    if not p:
        return ''
    return hashlib.sha256(('irfan-ustaz:' + p).encode()).hexdigest()[:16]


def _load_teachers():
    v = _read_json(TEACHERS, {})
    items = v.get('teachers') if isinstance(v, dict) else v
    return [t for t in items if isinstance(t, dict)] if isinstance(items, list) else []


def _save_teachers(items):
    _keep_backup(TEACHERS)
    with open(TEACHERS, 'w', encoding='utf-8') as f:
        json.dump({'updated': int(time.time() * 1000), 'teachers': items},
                  f, ensure_ascii=False)


def _find_teacher(items, tid):
    return next((t for t in items if t.get('id') == tid), None)


def _upsert_teacher(data):
    """Устаз сообщает о себе: имя и описание. Новый — со статусом pending."""
    tid = _teacher_id(data.get('login') or data.get('phone'))
    if not tid:
        return None
    name = (data.get('name') or '').strip()[:60] or 'Устаз'
    bio = (data.get('bio') or '').strip()[:300]
    now = int(time.time() * 1000)
    with _lock:
        items = _load_teachers()
        rec = _find_teacher(items, tid)
        if rec is None:
            if len(items) >= _MAX_TEACHERS:
                return {'error': 'registry full'}
            rec = {'id': tid, 'status': 'pending', 'registeredAt': now}
            items.append(rec)
        rec['name'] = name
        if bio:
            rec['bio'] = bio
        rec['lastSeen'] = now
        _save_teachers(items)
        return dict(rec)


def _set_teacher_status(data):
    """Модерация устаза. approved — виден студентам, остальное — нет."""
    tid = str(data.get('id') or '').strip()
    status = data.get('status')
    if status not in ('approved', 'pending', 'blocked'):
        return 400, {'error': 'bad status'}
    with _lock:
        items = _load_teachers()
        rec = _find_teacher(items, tid)
        if rec is None:
            return 404, {'error': 'no teacher'}
        rec['status'] = status
        rec['moderatedAt'] = int(time.time() * 1000)
        _save_teachers(items)
        return 200, dict(rec)


def _delete_teacher(data):
    """Удаляет устаза из реестра вместе с его неразобранной заявкой.

    Опубликованные уроки не трогаем: они лежат в live courses.json, и решение
    убрать их оттуда — отдельное действие админа в разделе курсов.
    """
    tid = str(data.get('id') or '').strip()
    if not _PENDING_RE.match(f'/courses_pending_{tid}.json'):
        return 400, {'error': 'bad id'}
    with _lock:
        items = _load_teachers()
        rest = [t for t in items if t.get('id') != tid]
        if len(rest) == len(items):
            return 404, {'error': 'no teacher'}
        _save_teachers(rest)
    try:
        os.remove(os.path.join(ROOT, f'courses_pending_{tid}.json'))
    except OSError:
        pass
    return 200, {'deleted': tid}


def _pending_list():
    """Неразобранные заявки на каталог — по файлу на устаза."""
    names = {t.get('id'): t.get('name') for t in _load_teachers()}
    out = []
    try:
        files = sorted(os.listdir(ROOT))
    except OSError:
        files = []
    for fn in files:
        if not (fn.startswith('courses_pending_') and fn.endswith('.json')):
            continue
        tid = fn[len('courses_pending_'):-len('.json')]
        data = _read_json(os.path.join(ROOT, fn), {})
        if not isinstance(data, dict):
            continue
        dirs = data.get('directions')
        out.append({
            'teacherId': tid,
            'teacherName': names.get(tid) or data.get('author') or '',
            'status': data.get('status') or 'pending',
            'updated': data.get('updated') or '',
            'author': data.get('author') or '',
            'directions': len(dirs) if isinstance(dirs, list) else 0,
            'lessons': sum(len(c.get('lessons') or [])
                           for d in (dirs or []) if isinstance(d, dict)
                           for c in (d.get('courses') or [])
                           if isinstance(c, dict)),
        })
    return {'pending': out}


def _auth_key(secret):
    """Хеш секрета устройства. В файле лежит только он — утечка users.json
    не даёт писать от имени ученика."""
    s = str(secret or '')
    if len(s) < 16:
        return ''
    return hashlib.sha256(('irfan-device:' + s).encode()).hexdigest()


def _student_ok(rec, data):
    """Имеет ли запрос право менять эту запись ученика.

    Пароля у ученика нет: аккаунт живёт на телефоне, а сервер знает только
    номер. Поэтому приложение заводит секрет устройства (Keychain) и шлёт
    его при каждом обращении; сервер хранит хеш.

    Записи, заведённые до этого (у них нет `authKey`), забираются по точной
    дате создания аккаунта: её знает только само приложение, а по номеру
    её не угадать. Совсем старые записи без `accountCreatedAt` достаются
    первому, кто пришёл с ключом, — иначе их владельцы не смогли бы
    пользоваться приложением после обновления.
    """
    got = _auth_key(data.get('secret'))
    have = rec.get('authKey')
    if have:
        return bool(got) and secrets.compare_digest(got, have)
    if not got:
        return True          # старое приложение без ключа — пускаем как раньше
    created = rec.get('accountCreatedAt')
    try:
        claimed = int(data.get('createdAt') or 0)
    except (ValueError, TypeError):
        claimed = 0
    if created and claimed != created:
        # Дату создания знает только само приложение. Требуем её и когда её
        # в запросе нет вовсе: иначе запись забирал бы кто угодно через
        # ручку, где эта дата не передаётся (например, /redeem). Настоящее
        # приложение всё равно первым делом шлёт профиль в POST /users.
        return False
    rec['authKey'] = got     # запись закрепляется за этим устройством
    return True


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
            # Первый пришедший закрепляет запись за своим устройством.
            _student_ok(rec, data)
        elif not _student_ok(rec, data):
            # Чужая попытка переписать анкету: раньше это удавалось любому,
            # кто знал номер (менялись имя, город, возраст).
            return {'error': 'forbidden'}
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
    # Ключ устройства наружу не отдаём — он нужен только серверу.
    out.pop('authKey', None)
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
    titles = idx.get('titles')
    return {
        'folders': folders if isinstance(folders, list) else [],
        'files': files if isinstance(files, dict) else {},
        # Подпись к файлу. Имя вроде tajweed-37isuopz.mp4 не говорит ни о чём,
        # а переименовать файл нельзя — по имени на него ссылаются уроки.
        'titles': titles if isinstance(titles, dict) else {},
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


_TITLE_MAX = 120


def _media_title(data):
    """Подпись к файлу: чем он является. Пустая — снять подпись."""
    name = safe_upload_name(data.get('name'))
    if not name or not os.path.isfile(os.path.join(UPLOADS, name)):
        return 404, {'error': 'no file'}
    title = ' '.join(str(data.get('title') or '').split())[:_TITLE_MAX]
    with _lock:
        idx = _load_index()
        if title:
            idx['titles'][name] = title
        else:
            idx['titles'].pop(name, None)
        _save_index(idx)
    return 200, {'name': name, 'title': title}


def _assign_upload(name, fid, title):
    """Раскладывает только что загруженный файл: папка и подпись.

    Подпись особенно важна при загрузке: имя файла на диске проходит
    транслитерацию, и «Урок 1 — Омовение.mp4» превращается в
    Urok-1-Omovenie.mp4. Исходное название сохраняем как подпись.
    """
    title = ' '.join(str(title or '').split())[:_TITLE_MAX]
    if not fid and not title:
        return
    with _lock:
        idx = _load_index()
        if fid and any(f.get('id') == fid for f in idx['folders']):
            idx['files'][name] = fid
        if title:
            idx['titles'][name] = title
        _save_index(idx)


# ——— Кадр-превью ———
#
# Двести уроков с именами вида tajweed-38.mp4 глазом не различить, поэтому
# панель показывает по кадру из каждого ролика. Кадры складываем РЯДОМ с api/
# (в api/ всё раздаётся списком-невидимкой, но лишнего там держать незачем) и
# отдаём отдельной ручкой.
THUMBS = os.path.join(os.path.dirname(ROOT), 'thumbs')
_THUMB_EXT = ('.mp4', '.mov', '.m4v')
# Больше двух ffmpeg разом не запускаем: на сервере 4 ядра, и на них же идут
# эфир и выгрузка уроков.
_thumb_sem = threading.Semaphore(2)


def _thumb_path(name):
    return os.path.join(THUMBS, name + '.jpg')


def _thumb_fresh(dst, src):
    try:
        return os.path.getmtime(dst) >= os.path.getmtime(src)
    except OSError:
        return False


def _make_thumb(name):
    """Кадр из ролика. Возвращает путь к jpeg или None."""
    src = os.path.join(UPLOADS, name)
    dst = _thumb_path(name)
    if _thumb_fresh(dst, src):
        return dst
    os.makedirs(THUMBS, exist_ok=True)
    with _thumb_sem:
        # Пока стояли в очереди, кадр мог сделать соседний запрос.
        if _thumb_fresh(dst, src):
            return dst
        tmp = f'{dst}.{os.getpid()}.{threading.get_ident()}.part'
        # -ss ДО -i — быстрая перемотка по ключевым кадрам, иначе ffmpeg
        # честно декодирует ролик с начала. Пятая секунда: в начале урока
        # часто заставка или чёрный кадр. Не вышло — берём самый первый кадр.
        for seek in ('5', '0'):
            # -f image2 обязателен: пишем во временный файл с расширением
            # .part, по которому ffmpeg формат не угадывает и молча падает.
            cmd = ['nice', '-n', '19', 'ffmpeg', '-v', 'error', '-y',
                   '-ss', seek, '-i', src, '-frames:v', '1',
                   '-vf', 'scale=320:-2', '-q:v', '6', '-f', 'image2', tmp]
            try:
                subprocess.run(cmd, timeout=30,
                               stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL)
            except (OSError, subprocess.SubprocessError):
                break
            if os.path.isfile(tmp) and os.path.getsize(tmp) > 0:
                os.replace(tmp, dst)
                return dst
        try:
            os.remove(tmp)
        except OSError:
            pass
    return None


def _media_list():
    """Загруженные файлы + папки + сколько места осталось на диске."""
    idx = _load_index()
    by_file = idx['files']
    titles = idx['titles']
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
                'title': titles.get(name, ''),
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
    # Где файл используется — чтобы не удалить урок, который смотрят, и
    # чтобы в панели было видно, чем файл является.
    used = {}
    lesson_titles = {}

    def _scan(dirs, prefix):
        for d in (dirs or []):
            if not isinstance(d, dict):
                continue
            for c in (d.get('courses') or []):
                for l in (c.get('lessons') or []):
                    # Совпадение ищем по имени файла: ссылка урока абсолютная
                    # и может вести хоть на публичный адрес, хоть на служебный.
                    key = (l.get('url') or '').split('?')[0].rsplit('/', 1)[-1]
                    if not key:
                        continue
                    used.setdefault(key, []).append(
                        f"{prefix}{d.get('title','')} / {c.get('title','')} / "
                        f"{l.get('title','')}")
                    lesson_titles.setdefault(key, l.get('title') or '')

    catalog = _read_json(os.path.join(ROOT, 'courses.json'), {})
    # Каталог хранится по устазам; общий блок directions остался от старых
    # публикаций. Пока живут обе формы, обходим обе — иначе связка
    # «файл ↔ урок» теряется и все уроки выглядят непривязанными.
    _scan(catalog.get('directions'), '')
    for t in (catalog.get('teachers') or []):
        if not isinstance(t, dict):
            continue
        name = (t.get('name') or '').strip()
        _scan(t.get('directions'), f'{name} · ' if name else '')
    for it in items:
        it['usedIn'] = used.get(it['name'], [])
        # Название урока — запасная подпись: файл уже опубликован, значит
        # известно, что это, и подписывать вручную незачем.
        it['lessonTitle'] = lesson_titles.get(it['name'], '')
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
    # Метку папки и подпись убираем следом, иначе указатель копил бы записи
    # о том, чего уже нет, и счётчики папок врали бы.
    with _lock:
        idx = _load_index()
        gone = [idx['files'].pop(name, None), idx['titles'].pop(name, None)]
        if any(v is not None for v in gone):
            _save_index(idx)
    try:
        os.remove(_thumb_path(name))
    except OSError:
        pass
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
        # Слепок прогресса без записи в реестре восстановить всё равно
        # некуда (_restore_account требует запись) — оставлять его значило бы
        # копить на диске историю людей, которых админ уже убрал.
        _drop_snapshot(ident)
        return 200, {'student': ident, 'deleted': True}


def _media_cfg():
    """Настройки раздачи уроков. Секрет подписи заводится при первом обращении.

    `require_signed` намеренно выключен по умолчанию: на телефонах учеников
    ещё стоят прежние сборки, которые ходят за уроком по голой ссылке, и
    включение вслепую оборвало бы им занятия. Включать, когда новая сборка
    разъедется по устройствам.
    """
    cfg = _read_json(MEDIA_CFG, {})
    if not isinstance(cfg, dict):
        cfg = {}
    if not cfg.get('secret'):
        cfg['secret'] = secrets.token_urlsafe(32)
        cfg.setdefault('require_signed', False)
        try:
            _write_private(MEDIA_CFG, cfg)
        except OSError as e:
            print(f'[media] не удалось записать {MEDIA_CFG}: {e}', flush=True)
    return cfg


def _media_sign(name, exp):
    key = _media_cfg().get('secret', '')
    msg = f'{name}|{exp}'.encode()
    return hmac.new(key.encode(), msg, hashlib.sha256).hexdigest()[:32]


def _media_sig_ok(name, exp_raw, sig):
    """Верна ли подпись ссылки на урок и не истекла ли она."""
    if not sig or not exp_raw:
        return False
    try:
        exp = int(exp_raw)
    except (TypeError, ValueError):
        return False
    if exp < time.time():
        return False
    return secrets.compare_digest(sig, _media_sign(name, exp))


def _media_link(data, staff):
    """Выдаёт временную ссылку на урок.

    Файлы в uploads/ раздавались всем, кто знает имя: ссылку достаточно было
    один раз переслать, и урок смотрел кто угодно. Теперь приложение просит
    ссылку, а сервер подписывает её на несколько часов.

    Сам файл на диске не трогается и не переименовывается — иначе поехали бы
    и опубликованные уроки, и раскладка по папкам.
    """
    name = safe_upload_name(
        (data.get('name') or '').strip() or
        (data.get('url') or '').strip().rsplit('/', 1)[-1].split('?')[0])
    if not name:
        return 400, {'error': 'bad name'}
    if not os.path.isfile(os.path.join(UPLOADS, name)):
        return 404, {'error': 'no file'}
    # Персонал получает ссылку по своей авторизации, ученик — по ключу
    # устройства (тому же, которым подписывает анкету).
    if not staff:
        users = _load_users()
        ident = _identity(data)
        rec = _find_user(users, ident) if ident else None
        if rec is None or rec.get('blocked') or not _student_ok(rec, data):
            return 403, {'error': 'forbidden'}
    exp = int(time.time()) + MEDIA_LINK_TTL_S
    return 200, {
        'url': f'{MEDIA_BASE}/uploads/{name}?exp={exp}&sig={_media_sign(name, exp)}',
        'expiresIn': MEDIA_LINK_TTL_S,
    }


def _crash_report(data):
    """Сбой в приложении. Складываем по видам: одинаковые ошибки — одна
    запись со счётчиком и датой последнего случая.

    Личных данных здесь нет и быть не должно: только текст ошибки, стек,
    версия приложения и система. Ни номера, ни имени приложение не шлёт.
    """
    error = (data.get('error') or '').strip()[:400]
    if not error:
        return 400, {'error': 'empty'}
    stack = (data.get('stack') or '').strip()[:4000]
    version = (data.get('version') or '').strip()[:40]
    platform = (data.get('platform') or '').strip()[:40]
    fatal = bool(data.get('fatal'))
    now = int(time.time() * 1000)
    # Вид сбоя: текст ошибки плюс первая строка стека — этого хватает,
    # чтобы одинаковые падения слиплись, а разные не смешались.
    head = stack.split('\n', 1)[0][:200]
    kind = hashlib.sha256(f'{error}|{head}'.encode()).hexdigest()[:16]

    with _lock:
        items = _read_json(CRASHES, [])
        if not isinstance(items, list):
            items = []
        rec = next((c for c in items
                    if isinstance(c, dict) and c.get('kind') == kind), None)
        if rec is None:
            if len(items) >= _MAX_CRASHES:
                # Вытесняем самый давний по последнему случаю, а не по
                # порядку добавления: старая, но живая ошибка важнее.
                items.sort(key=lambda c: c.get('lastSeen') or 0)
                items = items[1:]
            rec = {'kind': kind, 'error': error, 'stack': stack,
                   'firstSeen': now, 'count': 0}
            items.append(rec)
        rec['count'] = int(rec.get('count') or 0) + 1
        rec['lastSeen'] = now
        if version:
            rec['version'] = version
        if platform:
            rec['platform'] = platform
        rec['fatal'] = fatal or bool(rec.get('fatal'))
        _keep_backup(CRASHES)
        with open(CRASHES, 'w', encoding='utf-8') as f:
            json.dump(items, f, ensure_ascii=False)
    return 201, {'ok': True}


def _report_comment(data):
    """Жалоба ученика на сообщение в чате эфира (Guideline 1.2).

    Копится в reports.json; читает его только админ — в панели видно, на что
    жалуются, и можно закрыть автору вход. Сообщение при этом СРАЗУ прячется
    у пожаловавшегося: блокировка хранится на его устройстве и не ждёт
    разбора.
    """
    author = (data.get('author') or '').strip()[:40]
    text = (data.get('text') or '').strip()[:300]
    reason = (data.get('reason') or '').strip()[:80]
    if not text:
        return 400, {'error': 'empty'}
    now = int(time.time() * 1000)
    item = {'id': now, 'author': author, 'text': text, 'reason': reason,
            'ts': now, 'by': (data.get('by') or '').strip()[:40]}
    with _lock:
        items = _read_json(REPORTS, [])
        if not isinstance(items, list):
            items = []
        items.append(item)
        items = items[-_MAX_REPORTS:]
        _keep_backup(REPORTS)
        with open(REPORTS, 'w', encoding='utf-8') as f:
            json.dump(items, f, ensure_ascii=False)
    return 201, {'ok': True}


def _delete_account(data):
    """Ученик удаляет свой аккаунт из приложения (требование App Store 5.1.1).

    Убирает запись из реестра, выданные доступы и коды подтверждения. Коды
    выкупа остаются: это финансовые следы уже полученных наград, и по ним
    не опознать человека (в них только код и товар).

    Удалять может только владелец записи — тот, чей ключ устройства в ней
    записан (см. [_student_ok]): иначе знающий номер стирал бы чужие
    аккаунты вместе с оплаченными доступами к курсам.
    """
    ident = _norm_phone(data.get('phone')) or str(
        data.get('phone') or '').strip().lower()
    if not ident:
        return 400, {'error': 'no phone'}
    removed = False
    with _lock:
        users = _load_users()
        rec = _find_user(users, ident)
        if rec is not None and not _student_ok(rec, data):
            return 403, {'error': 'forbidden'}
        # У записи ученика опознаватель лежит в `phone` (или в `email` у
        # заведённых старыми сборками) — не в `student`, как у доступов.
        rest = [u for u in users
                if u.get('phone') != ident and u.get('email') != ident]
        removed = len(rest) != len(users)
        if removed:
            _save_users(rest)
        # Доступы к курсам и коды подтверждения — вместе с записью.
        grants = _load_access()
        keep = [g for g in grants if not _same_student(g, ident)]
        if len(keep) != len(grants):
            _keep_backup(ACCESS)
            with open(ACCESS, 'w', encoding='utf-8') as f:
                json.dump(keep, f, ensure_ascii=False)
        codes = _load_verify()
        left = [c for c in codes if _norm_phone(c.get('phone')) != ident]
        if len(left) != len(codes):
            _save_verify(left)
        # Слепок прогресса — это вся история человека; без этой строки
        # «удалить аккаунт» оставляло бы её лежать на сервере.
        _drop_snapshot(ident)
    return 200, {'deleted': removed}


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
        # Тратить коины может только владелец записи: без этого посторонний,
        # знающий номер, выкупал бы чужие награды себе.
        if not _student_ok(rec, data):
            return 403, {'error': 'forbidden'}
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

    def _serve_thumb(self):
        """Кадр-превью. Без пароля — как и сами файлы в uploads/: картинка
        из ролика, который и так раздаётся всем, кто знает имя. Тяжёлая
        часть (ffmpeg) закрыта очередью на два процесса и счётчиком запросов."""
        q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        name = safe_upload_name((q.get('name') or [''])[0])
        if not name or os.path.splitext(name)[1].lower() not in _THUMB_EXT:
            self._send_json(404, {'error': 'no preview'})
            return
        if not os.path.isfile(os.path.join(UPLOADS, name)):
            self._send_json(404, {'error': 'no file'})
            return
        if not _rate_ok('thumb', self._ip, RATE_THUMB):
            self._too_many()
            return
        path = _make_thumb(name)
        if not path:
            self._send_json(404, {'error': 'no preview'})
            return
        try:
            with open(path, 'rb') as f:
                body = f.read()
        except OSError:
            self._send_json(404, {'error': 'no preview'})
            return
        self.send_response(200)
        self.send_header('Content-Type', 'image/jpeg')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'max-age=86400')
        self.end_headers()
        self.wfile.write(body)

    def _send_json(self, code, obj):
        body = json.dumps(obj, ensure_ascii=False).encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    @property
    def _ip(self):
        """Адрес клиента с учётом обратного прокси.

        После включения HTTPS запросы приходят от nginx с localhost. Без
        этой поправки ВСЕ посетители слились бы в один счётчик: перебор
        пароля перестал бы ловиться, а чужой спам блокировал бы всех
        сразу. Заголовку доверяем только от самого прокси — иначе его
        подделает кто угодно и обойдёт ограничения.
        """
        peer = self.client_address[0]
        if peer not in ('127.0.0.1', '::1'):
            return peer
        # X-Real-IP прокси ставит сам, затирая присланное клиентом, — ему
        # верить можно.
        real = (self.headers.get('X-Real-IP') or '').strip()
        if real:
            return real
        # Запасной путь — X-Forwarded-For, и берём ПОСЛЕДНИЙ элемент: nginx
        # дописывает настоящий адрес в конец, а начало списка присылает сам
        # клиент. Если брать первый (как было сначала), любой подставит себе
        # новый адрес на каждый запрос — ограничение частоты перестанет
        # работать вовсе, и заодно можно испортить счётчик чужому.
        fwd = [p.strip() for p in
               (self.headers.get('X-Forwarded-For') or '').split(',')
               if p.strip()]
        return fwd[-1] if fwd else peer

    def _principal_checked(self):
        """Кто делает запрос, с защитой от перебора пароля.

        Возвращает dict, None (не авторизован) или строку 'ratelimited'.
        """
        who = _principal(self.headers)
        if who is None and self.headers.get('Authorization'):
            # Считаем только неудачные попытки — успешные не наказываем.
            if not _rate_ok('authfail', self._ip, RATE_AUTH_FAIL):
                return 'ratelimited'
        return who

    def _role_checked(self):
        """Роль запроса с защитой от перебора пароля."""
        who = self._principal_checked()
        if who == 'ratelimited':
            return 'ratelimited'
        return (who or {}).get('role')

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
        if p == '/staff.json':
            self._send_json(200, _staff_list())
            return
        if p == '/stream.json':
            cfg = _stream_config()
            self._send_json(200 if cfg else 503,
                            cfg or {'error': 'эфир не настроен на сервере'})
            return
        if p == '/media/thumb':
            self._serve_thumb()
            return
        if p == '/pending.json':
            self._send_json(200, _pending_list())
            return
        # Уроки: пускаем по подписанной ссылке (её выдаёт POST /media/link)
        # либо по авторизации персонала — панель и кабинет устаза смотрят
        # ролики напрямую. Пока require_signed выключен, прежние сборки на
        # телефонах работают как раньше.
        if p.startswith('/uploads/') and _media_cfg().get('require_signed'):
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            name = p[len('/uploads/'):]
            if not _media_sig_ok(name, (q.get('exp') or [''])[0],
                                 (q.get('sig') or [''])[0]) \
                    and self._role_checked() not in ('admin', 'ustaz'):
                self._deny(403)
                return
        if self._serve_range():
            return
        return super().do_GET()

    # Ручки без пароля: любой может засыпать реестр, чат и коды.
    _ANON_POST = ('/users', '/comments', '/verify/request', '/verify/confirm',
                  '/redeem', '/auth/token', '/account/delete',
                  '/account/restore', '/backup',
                  '/comments/report', '/media/link', '/crash')

    def do_POST(self):
        p = self.path.rstrip('/')
        if p in self._ANON_POST and not _rate_ok('anon', self._ip, RATE_ANON):
            self._too_many()
            return
        # Тело POST — это всегда небольшой JSON. Раньше оно читалось целиком
        # по заявленной длине: любой прохожий мог объявить Content-Length в
        # гигабайты и съесть память сервера, ничего не отправляя по существу.
        try:
            n = int(self.headers.get('Content-Length', 0) or 0)
        except ValueError:
            self._send_json(400, {'error': 'bad length'})
            return
        if n > _MAX_POST_BYTES:
            self._send_json(413, {'error': 'too large'})
            return
        raw = self.rfile.read(n) if n > 0 else b''
        try:
            data = json.loads(raw.decode('utf-8')) if raw else {}
        except (ValueError, UnicodeDecodeError):
            self._send_json(400, {'error': 'bad json'})
            return
        if not isinstance(data, dict):
            # Дальше везде вызывается data.get(...) — на списке или строке
            # это падало бы с 500 вместо внятного отказа.
            self._send_json(400, {'error': 'bad json'})
            return
        if p == '/comments':
            # Имя в чате приходит от клиента, и без проверки любой мог бы
            # писать от лица преподавателя. Имена из реестра устазов
            # разрешаем только вошедшему персоналу.
            if _is_teacher_name(data.get('name')) and \
                    self._role_checked() not in ('admin', 'ustaz'):
                self._send_json(403, {'error': 'имя занято преподавателем'})
                return
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
            if rec.get('error') == 'forbidden':
                self._send_json(403, rec)
                return
            if rec.get('error'):
                self._send_json(507, rec)
                return
            self._send_json(201, rec)
            return
        if p == '/teachers':
            # Раньше сюда мог писать кто угодно: так устаз заводил себя сам.
            # Учётки теперь выдаёт админ, а открытая ручка осталась дырой —
            # ею можно было засорить реестр и добить его до потолка в 500
            # записей, после чего настоящий устаз уже не заводился.
            if self._role_checked() != 'admin':
                self._deny()
                return
            rec = _upsert_teacher(data)
            if rec is None:
                self._send_json(400, {'error': 'bad phone'})
                return
            if rec.get('error'):
                self._send_json(507, rec)
                return
            self._send_json(201, rec)
            return
        if p in ('/teachers/flag', '/teachers/delete'):
            if self._role_checked() != 'admin':
                self._deny()
                return
            code, body = (_set_teacher_status(data) if p == '/teachers/flag'
                          else _delete_teacher(data))
            self._send_json(code, body)
            return
        if p == '/redeem':
            code, body = _redeem(data)
            self._send_json(code, body)
            return
        if p == '/media/link':
            role = self._role_checked()
            if role == 'ratelimited':
                self._too_many()
                return
            code, body = _media_link(data, staff=role in ('admin', 'ustaz'))
            self._send_json(code, body)
            return
        if p == '/crash':
            code, body = _crash_report(data)
            self._send_json(code, body)
            return
        if p == '/comments/report':
            code, body = _report_comment(data)
            self._send_json(code, body)
            return
        if p == '/account/delete':
            code, body = _delete_account(data)
            self._send_json(code, body)
            return
        if p == '/backup':
            code, body = _put_snapshot(data)
            self._send_json(code, body)
            return
        if p == '/account/restore':
            code, body = _restore_account(data)
            self._send_json(code, body)
            return
        if p == '/auth/token':
            # Неудачный вход тратит лимит перебора, удачный — нет.
            code, body = _auth_token(data)
            if code != 200 and not _rate_ok('authfail', self._ip,
                                            RATE_AUTH_FAIL):
                self._too_many()
                return
            self._send_json(code, body)
            return
        if p == '/auth/logout':
            got = self.headers.get('Authorization', '')
            if got.startswith('Bearer '):
                _revoke_token(got[len('Bearer '):].strip())
            self._send_json(200, {'ok': True})
            return
        if p == '/auth/check':
            who = self._principal_checked()
            if who == 'ratelimited':
                self._too_many()
                return
            if who is None:
                self._deny()
                return
            self._send_json(200, {'role': who.get('role'),
                                  'login': who.get('login'),
                                  'teacherId': who.get('teacherId'),
                                  'name': who.get('name'),
                                  'expiresAt': who.get('exp')})
            return
        if p == '/staff':
            if self._role_checked() != 'admin':
                self._deny()
                return
            code, body = _staff_op(data)
            self._send_json(code, body)
            return
        if p == '/verify/request':
            code, body = _request_code(data)
            self._send_json(code, body)
            return
        if p == '/verify/confirm':
            code, body = _confirm_code(data)
            self._send_json(code, body)
            return
        if p in ('/media/delete', '/media/folder', '/media/move', '/media/title'):
            if self._role_checked() != 'admin':
                self._deny()
                return
            code, body = (
                _delete_media(data) if p == '/media/delete'
                else _folder_op(data) if p == '/media/folder'
                else _media_title(data) if p == '/media/title'
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
        who = self._principal_checked()
        if who == 'ratelimited':
            self._too_many()
            return
        if who is None:
            self._deny()
            return
        role = who.get('role')
        need = _put_role_for(self.path)
        # admin может всё; ustaz — только то, что помечено 'ustaz'.
        if need == 'admin' and role != 'admin':
            self._send_json(403, {'error': 'admin only'})
            return
        # Устаз с персональным токеном пишет ТОЛЬКО свою заявку на каталог:
        # иначе, войдя под своей учёткой, он мог бы затереть чужую.
        if who.get('teacherId'):
            p = self.path.split('?')[0]
            own = '/courses_pending_{}.json'.format(who['teacherId'])
            if (_PENDING_RE.match(p) or p == '/courses_pending.json') \
                    and p != own:
                self._send_json(403, {'error': 'чужая заявка'})
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
        try:
            n = int(self.headers.get('Content-Length', 0))
        except ValueError:
            self._send_json(400, {'error': 'bad length'})
            return
        # Потолок на размер. Диск 150 ГБ и общий на всё: уроки, эфир, копии.
        # Без предела один запрос (свой по ошибке или чужой с утёкшим
        # токеном) забивает его целиком, и тогда встаёт и эфир, и раздача.
        limit = _MAX_UPLOAD_BYTES if upload else _MAX_JSON_PUT_BYTES
        if n > limit:
            self._send_json(413, {'error': 'too large'})
            return
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
            _assign_upload(name, (q.get('folder') or [''])[0][:40],
                           (q.get('title') or [''])[0])
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
    port = int(os.environ.get('IRFAN_PORT', '8090'))
    http.server.ThreadingHTTPServer(('0.0.0.0', port), Handler).serve_forever()
