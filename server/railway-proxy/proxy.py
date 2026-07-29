#!/usr/bin/env python3
"""HTTPS-обёртка над сервером «Ирфан» для Railway.

Зачем: админка отдаётся по HTTP с голого IP, и пароль идёт по сети открытым
текстом. Railway даёт бесплатный адрес с сертификатом, но положить туда одну
страницу нельзя — HTTPS-страница не имеет права ходить на HTTP-адрес, браузер
блокирует такие запросы. Поэтому здесь стоит прокси: браузер общается с
Railway по HTTPS, Railway с Hetzner — по HTTP.

ЧЕСТНАЯ ОГОВОРКА: участок Railway → Hetzner идёт по открытому интернету
без шифрования. Это защищает от соседа по кафе, но не от того, кто слушает
магистраль. Полное решение — домен и сертификат на самом сервере
(server/enable-https.sh), тогда прокси не нужен вовсе.

Переменные окружения:
    ORIGIN — адрес сервера «Ирфан» (по умолчанию http://178.104.206.100:8090)
    PORT   — подставляет Railway
"""
import os

from aiohttp import ClientSession, ClientTimeout, web

ORIGIN = os.environ.get('ORIGIN', 'http://178.104.206.100:8090').rstrip('/')
PORT = int(os.environ.get('PORT', '8080'))

# Заголовки, которые нельзя пересылать как есть: их выставляет уже сам прокси.
_SKIP = {'host', 'content-length', 'transfer-encoding', 'connection',
         'keep-alive', 'upgrade'}

# Видео не гоняем через прокси: трафик пойдёт вдвое дальше и упрётся в лимиты
# Railway. Панель показывает прямые ссылки на origin — их и открываем.
_HEAVY = ('/uploads/', '/hls/')


async def handle(request: web.Request) -> web.StreamResponse:
    path = request.rel_url.path
    # Перенаправляем только ЧТЕНИЕ видео. Загрузку пропускаем через себя:
    # редирект увёл бы браузер на http-адрес, а страница открыта по https —
    # такой запрос он заблокирует как смешанный контент.
    if path.startswith(_HEAVY) and request.method in ('GET', 'HEAD'):
        raise web.HTTPFound(ORIGIN + str(request.rel_url))

    url = ORIGIN + str(request.rel_url)
    headers = {k: v for k, v in request.headers.items()
               if k.lower() not in _SKIP}
    body = await request.read() if request.can_read_body else None

    session: ClientSession = request.app['session']
    try:
        async with session.request(
            request.method, url, headers=headers, data=body,
            allow_redirects=False,
        ) as upstream:
            out = web.StreamResponse(status=upstream.status)
            for k, v in upstream.headers.items():
                if k.lower() not in _SKIP:
                    out.headers[k] = v
            await out.prepare(request)
            async for chunk in upstream.content.iter_chunked(1 << 16):
                await out.write(chunk)
            await out.write_eof()
            return out
    except Exception as e:                     # сервер лежит или не отвечает
        return web.json_response(
            {'error': 'origin unavailable', 'detail': str(e)}, status=502)


async def _startup(app: web.Application) -> None:
    # Загрузка видеоурока может идти долго — таймаут щедрый.
    app['session'] = ClientSession(timeout=ClientTimeout(total=900))


async def _cleanup(app: web.Application) -> None:
    await app['session'].close()


def build() -> web.Application:
    app = web.Application(client_max_size=1 << 30)   # 1 ГБ на загрузку урока
    app.on_startup.append(_startup)
    app.on_cleanup.append(_cleanup)
    app.router.add_route('*', '/{tail:.*}', handle)
    return app


if __name__ == '__main__':
    web.run_app(build(), port=PORT)
