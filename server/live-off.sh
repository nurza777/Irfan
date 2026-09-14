#!/bin/sh
# Вызывается MediaMTX (runOnNotReady), когда публикация прекратилась.
# Боевая копия лежит на сервере: /opt/irfan-server/live-off.sh
#
# Флаг hls.stop ставится ПЕРВЫМ и до всяких kill. В live-on.sh транскод
# крутится в цикле с перезапуском (он страхует от смерти ffmpeg посреди
# эфира), и без флага этот цикл принял бы штатное завершение эфира за
# сбой и поднял бы ffmpeg заново.
touch /opt/irfan-server/hls.stop

[ -f /opt/irfan-server/hls.pid ] && kill "$(cat /opt/irfan-server/hls.pid)" 2>/dev/null
rm -f /opt/irfan-server/hls.pid
pkill -f "rtmp://127.0.0.1:1935/live/" 2>/dev/null   # транскод; ключ эфира в скрипте не пишем
sleep 1
rm -f /opt/irfan-server/api/hls/*
echo "{\"live\": false, \"title\": \"\", \"url\": \"\"}" > /opt/irfan-server/api/status.json

# Момент окончания. По нему live-on.sh решает, стирать ли чат: если эфир
# начнётся снова в ближайшие десять минут, это переподключение после
# обрыва, а не новая трансляция, и переписку учеников надо сохранить.
NOW=$(date +%s)
echo "$NOW" > /opt/irfan-server/last-live-end

# ── Сводка эфира ──────────────────────────────────────────────────────────
#
# Раньше после трансляции нельзя было узнать ничего: ни сколько было
# зрителей, ни падал ли транскод. Считаем по access-логу nginx от отметки,
# сделанной в live-on.sh: зритель — уникальный адрес, запросивший
# master.m3u8. Это не точная аналитика (общий Wi-Fi считается за одного,
# NAT оператора тоже), но порядок величины даёт.
# Сводку пишем только если есть отметка старта. Без этой проверки повторный
# вызов live-off.sh (MediaMTX зовёт его сам, а руками его запускают при
# отладке) добавлял в журнал пустую строку «длительность 0:00».
if [ ! -s /opt/irfan-server/live-start ]; then
  rm -f /opt/irfan-server/hls.stop
  exit 0
fi

LOG=/var/log/nginx/access.log
START=$(cat /opt/irfan-server/live-start)
MARK=0
[ -s /opt/irfan-server/live-logmark ] && MARK=$(cat /opt/irfan-server/live-logmark)
CUR=$(wc -l < "$LOG" 2>/dev/null || echo 0)
# Лог провернулся посреди эфира — смещение больше не значит ничего,
# считаем по всему файлу, иначе tail отрезал бы вообще всё.
[ "$CUR" -lt "$MARK" ] && MARK=0

VIEWERS=$(tail -n +$((MARK + 1)) "$LOG" 2>/dev/null \
  | grep "hls/master.m3u8" | awk '{print $1}' | sort -u | wc -l)
REQUESTS=$(tail -n +$((MARK + 1)) "$LOG" 2>/dev/null | grep -c "/hls/")
# Без `|| echo 0`: grep -c при нуле совпадений сам печатает 0, но выходит
# с ненулевым кодом, и запасной echo дописал бы второй ноль.
RESTARTS=$(grep -c "транскод упал" /opt/irfan-server/logs/ffmpeg.log 2>/dev/null)
[ -z "$RESTARTS" ] && RESTARTS=0
DUR=0
[ "$START" -gt 0 ] && DUR=$((NOW - START))

# Пик зрителей по УСТРОЙСТВАМ — главное число. Считается apiserver-ом по
# сердцебиениям приложения; забираем до того, как записи протухнут (45 с).
PEAK=$(curl -s -m 5 http://127.0.0.1:8090/live/viewers 2>/dev/null \
  | python3 -c "import json,sys; print(json.load(sys.stdin).get('peak', 0))" 2>/dev/null)
[ -z "$PEAK" ] && PEAK=0

# Уникальные адреса оставлены рядом НАМЕРЕННО, а не как дубль: разрыв между
# двумя числами показывает, насколько операторы прячут абонентов за общим
# адресом. Если адресов вдвое меньше устройств — счёт по логам врал бы вдвое.
printf '%s эфир завершён: длительность %d:%02d, зрителей (пик, по устройствам) %s, уникальных адресов %s, запросов к HLS %s, перезапусков транскода %s\n' \
  "$(date '+%F %T')" "$((DUR / 60))" "$((DUR % 60))" "$PEAK" "$VIEWERS" "$REQUESTS" "$RESTARTS" \
  >> /opt/irfan-server/logs/live-history.log

rm -f /opt/irfan-server/live-start /opt/irfan-server/live-logmark

# Флаг снимаем последним: пока он лежит, следующий live-on.sh вышел бы
# из цикла сразу и эфир не запустился бы вовсе.
rm -f /opt/irfan-server/hls.stop
