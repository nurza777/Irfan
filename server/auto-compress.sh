#!/usr/bin/env bash
#
# Фоновое сжатие уроков, загруженных на сервер.
#
# Страховка на случай, если файл залили без предварительного сжатия. Основной
# путь всё же — сжимать на ноутбуке перед выгрузкой (tools/compress.py):
# здесь всего 4 ядра без видеокарты, и кодирование идёт медленно.
#
# Что делает:
#   • раз в запуск берёт по одному необработанному видео из uploads/
#   • приводит к 1080p и HEVC — на телефоне это неотличимо от 4K,
#     а размер падает в разы
#   • ЗАМЕНЯЕТ файл только если новый меньше и длительность совпала;
#     иначе оставляет оригинал нетронутым
#   • не запускается, если на диске мало места или сервер занят эфиром
#
# Ставится таймером systemd (см. install-auto-compress.sh).
set -uo pipefail

UPLOADS=/opt/irfan-server/api/uploads
STATE=/opt/irfan-server/compressed.list      # что уже обработано
LOG=/opt/irfan-server/logs/compress.log
MIN_FREE_GB=15          # ниже этого порога не начинаем
HEIGHT=1080
MAX_PER_RUN=3           # файлов за один запуск, чтобы не занимать сервер надолго

mkdir -p "$(dirname "$LOG")"
touch "$STATE"

log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

# Во время эфира процессор нужен транскодеру — не мешаем.
if pgrep -f "ffmpeg.*rtmp://127.0.0.1" >/dev/null 2>&1; then
  log "пропуск: идёт эфир"
  exit 0
fi

FREE_GB=$(df -BG --output=avail "$UPLOADS" | tail -1 | tr -dc '0-9')
if (( FREE_GB < MIN_FREE_GB )); then
  log "пропуск: свободно ${FREE_GB} ГБ, нужно минимум ${MIN_FREE_GB}"
  exit 0
fi

processed=0
shopt -s nullglob nocaseglob
for f in "$UPLOADS"/*.{mp4,mov,m4v,avi,mkv}; do
  (( processed >= MAX_PER_RUN )) && break
  name=$(basename "$f")
  grep -Fxq "$name" "$STATE" && continue          # уже смотрели

  before=$(stat -c%s "$f")
  dur_before=$(ffprobe -v error -show_entries format=duration \
                 -of csv=p=0 "$f" 2>/dev/null | cut -d. -f1)
  [[ -z "${dur_before:-}" ]] && { echo "$name" >> "$STATE"; continue; }

  # Не трогаем то, что уже сжато толково.
  #
  # Сюда заливают и материал, прошедший обработку на стороне (например,
  # пересобранный из HLS). Повторное кодирование таких файлов — это второе
  # поколение сжатия: качество теряется безвозвратно, а выигрыш по размеру
  # не стоит того. Признаки «уже готово»: современный кодек либо низкий
  # битрейт на мегапиксель.
  # ffprobe отдаёт «hevc,1280,720» — читаем через IFS, без возни с кавычками.
  IFS=, read -r vcodec vw vh < <(ffprobe -v error -select_streams v:0 \
      -show_entries stream=codec_name,width,height -of csv=p=0 "$f" 2>/dev/null)
  brate=$(ffprobe -v error -show_entries format=bit_rate \
            -of csv=p=0 "$f" 2>/dev/null)

  if [[ "$vcodec" == "hevc" || "$vcodec" == "av1" || "$vcodec" == "vp9" ]]; then
    log "пропуск $name: уже $vcodec, повторное сжатие только испортит"
    echo "$name" >> "$STATE"; continue
  fi

  if [[ -n "${brate:-}" && -n "${vw:-}" && -n "${vh:-}" ]] \
     && (( vw > 0 && vh > 0 )); then
    # Кбит/с на мегапиксель. Съёмка с телефона даёт 4000+, уже сжатый
    # материал — около 1500–2000.
    per_mp=$(( brate / 1000 * 1000000 / (vw * vh) ))
    if (( per_mp < 2500 )); then
      log "пропуск $name: ${per_mp} кбит/с на мегапиксель — уже сжато"
      echo "$name" >> "$STATE"; continue
    fi
  fi

  tmp="${f}.compressing.mp4"
  # nice/ionice — чтобы API и раздача видео не тормозили из-за кодирования.
  nice -n 19 ionice -c3 ffmpeg -hide_banner -loglevel error -y \
    -i "$f" \
    -vf "scale=-2:'min(${HEIGHT},ih)'" \
    -c:v libx265 -preset medium -crf 24 -tag:v hvc1 \
    -c:a aac -b:a 128k \
    -movflags +faststart \
    "$tmp" 2>>"$LOG"

  if [[ ! -s "$tmp" ]]; then
    log "ОШИБКА кодирования: $name — оригинал не тронут"
    rm -f "$tmp"; echo "$name" >> "$STATE"; continue
  fi

  after=$(stat -c%s "$tmp")
  dur_after=$(ffprobe -v error -show_entries format=duration \
                -of csv=p=0 "$tmp" 2>/dev/null | cut -d. -f1)

  # Принимаем результат только если он меньше и не обрезан.
  if (( after < before )) && [[ -n "${dur_after:-}" ]] \
     && (( dur_after >= dur_before - 2 )); then
    mv -f "$tmp" "$f"
    saved=$(( (before - after) / 1048576 ))
    log "сжат $name: $((before/1048576)) МБ → $((after/1048576)) МБ (−${saved} МБ)"
  else
    rm -f "$tmp"
    log "оставлен как есть: $name (сжатие не дало выигрыша или обрезало)"
  fi

  echo "$name" >> "$STATE"
  (( processed++ ))
done

(( processed > 0 )) && log "обработано за запуск: $processed"
exit 0
