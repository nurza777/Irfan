#!/bin/bash
# Разогрев кадров-превью для панели.
#
# Кадры делаются лениво, при первом показе файла. На двух сотнях уроков
# это значит, что панель какое-то время стоит с пустыми клетками. Скрипт
# проходит по всем роликам заранее — по одному, с самым низким приоритетом,
# чтобы не мешать эфиру и выгрузке.
#
# Запуск на сервере:  nohup nice -n 19 /opt/irfan-server/warm-thumbs.sh &
cd /opt/irfan-server/api/uploads || exit 1
for f in *.mp4 *.mov *.m4v; do
  [ -e "$f" ] || continue
  curl -s -o /dev/null --get --data-urlencode "name=$f" \
    http://127.0.0.1:8090/media/thumb
done
