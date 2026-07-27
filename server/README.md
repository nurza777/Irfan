# Сервер прямых эфиров «Ирфан»

Схема: устаз стримит по **RTMP** со своего телефона → nginx-rtmp
конвертирует в **HLS** → все приложения смотрят по HTTP. Файл
`status.json` переключается автоматически при старте/окончании эфира —
приложение опрашивает его каждые 15 секунд.

```
Телефон устаза (RTMP) ──▶ nginx-rtmp ──▶ HLS (/var/www/irfan-live/hls)
                              │
                              └─▶ status.json (live: true/false)
                                        ▲
                     Приложения зрителей опрашивают каждые 15 с
```

## Установка на Ubuntu-droplet (159.89.38.67)

```bash
apt update && apt install -y libnginx-mod-rtmp apache2-utils
mkdir -p /var/www/irfan-live/hls /var/www/irfan-api/uploads
cp irfan-live-on.sh irfan-live-off.sh /usr/local/bin/ && chmod +x /usr/local/bin/irfan-live-*.sh
/usr/local/bin/irfan-live-off.sh   # создать начальный status.json
echo '{"updated":"","courses":[]}' > /var/www/irfan-api/courses.json
htpasswd -bc /etc/nginx/.irfan-htpasswd ustaz 'ПАРОЛЬ_УСТАЗА'   # пароль публикации
chown -R www-data:www-data /var/www/irfan-live /var/www/irfan-api
# rtmp-блок (rtmp.conf) добавить в САМЫЙ КОНЕЦ /etc/nginx/nginx.conf (вне http{}),
# location-блоки (http-location.conf) — внутрь server{} сайта.
ufw allow 1935/tcp
nginx -t && systemctl reload nginx
```

## Приложение устаза («Ирфан Устаз»)

- Эфир: вкладка «Эфир» — камера, название, кнопка «Начать эфир»
  (RTMP на `rtmp://159.89.38.67/live`, ключ из настроек).
- Курсы: вкладка «Курсы» — создание/редактирование, загрузка видео,
  кнопка «Опубликовать» кладёт `courses.json` в `/irfan-api/`
  (PUT c basic-auth `ustaz:<пароль>`); студенческое приложение
  читает его в разделе «Курсы».

## Как устазу вести эфир (уже сейчас, до отдельного приложения)

1. Установить бесплатный **Larix Broadcaster** (iOS/Android).
2. Добавить соединение: `rtmp://<сервер>/live/<КЛЮЧ_ПОТОКА>`
   (ключ потока — длинная случайная строка, её знает только устаз;
   задаётся на сервере в `/etc/irfan/stream.key`, см. `irfan-live-on.sh`).
3. Нажать запись — через ~10 секунд эфир появится у всех в приложении.
4. Остановить запись — приложения снова покажут «эфира нет».

Заголовок эфира можно поменять в `/usr/local/bin/irfan-live-on.sh`.

## Проверка

```bash
curl http://159.89.38.67/irfan-live/status.json
# в эфире: {"live": true, "title": "…", "url": "hls/stream.m3u8"}
```

Позже сделаем отдельное приложение устаза — оно будет стримить RTMP на
тот же адрес, ничего на сервере менять не придётся.
