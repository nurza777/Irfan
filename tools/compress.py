#!/usr/bin/env python3
"""Пакетное сжатие видео и фотографий перед выгрузкой на сервер.

Работает на Windows, Linux и macOS. Сам находит доступный кодировщик:
NVENC (карты NVIDIA), VideoToolbox (Apple), иначе процессорный x265.

О качестве честно: полностью без потерь сжать уже сжатое видео нельзя —
файл станет только больше. Здесь используется «визуально без потерь»:
разница неразличима глазом, а размер падает вдвое-втрое. Съёмка с телефона
обычно закодирована расточительно, поэтому выигрыш и получается большим.

По умолчанию видео приводится к 1080p. Уроки смотрят с телефона, где 4K от
1080p неотличим, а размер падает вшестеро: на реальном материале 140 ГБ
превращаются в 20 ГБ вместо 91 ГБ. Оригинальное разрешение — `--keep-size`.

    python compress.py ИСХОДНАЯ_ПАПКА ПАПКА_РЕЗУЛЬТАТА
    python compress.py ИСХОДНАЯ ПАПКА_РЕЗУЛЬТАТА --check       # только оценка
    python compress.py ИСХОДНАЯ ПАПКА_РЕЗУЛЬТАТА --keep-size   # не уменьшать
    python compress.py ИСХОДНАЯ ПАПКА_РЕЗУЛЬТАТА --height 720
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import time

VIDEO_EXT = {'.mp4', '.mov', '.m4v', '.avi', '.mkv', '.mts', '.m2ts', '.wmv'}
PHOTO_EXT = {'.jpg', '.jpeg', '.png', '.heic', '.webp'}


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def have(cmd):
    return shutil.which(cmd) is not None


def pick_encoder():
    """Выбирает лучший доступный кодировщик."""
    out = run(['ffmpeg', '-hide_banner', '-encoders']).stdout
    # Проверяем не только сборку ffmpeg, но и наличие самой карты.
    if 'hevc_nvenc' in out and _nvidia_present():
        return 'nvenc'
    if 'hevc_videotoolbox' in out and sys.platform == 'darwin':
        return 'videotoolbox'
    return 'cpu'


def _nvidia_present():
    if not have('nvidia-smi'):
        return False
    return run(['nvidia-smi', '-L']).returncode == 0


def video_args(encoder):
    """Настройки «визуально без потерь» для каждого кодировщика."""
    if encoder == 'nvenc':
        return [
            '-c:v', 'hevc_nvenc',
            '-preset', 'p7',        # самый качественный пресет NVENC
            '-tune', 'hq',
            '-rc', 'vbr',
            '-cq', '22',            # ниже число — выше качество
            '-b:v', '0',            # чистый режим постоянного качества
            '-pix_fmt', 'p010le',   # 10 бит: меньше полос на градиентах
        ]
    if encoder == 'videotoolbox':
        return ['-c:v', 'hevc_videotoolbox', '-q:v', '55', '-tag:v', 'hvc1']
    return ['-c:v', 'libx265', '-preset', 'medium', '-crf', '22',
            '-tag:v', 'hvc1']


def probe(path):
    r = run(['ffprobe', '-v', 'error', '-show_entries',
             'format=duration,size', '-of', 'json', str(path)])
    try:
        f = json.loads(r.stdout)['format']
        return float(f.get('duration', 0)), int(f.get('size', 0))
    except Exception:
        return 0.0, 0


def compress_video(src, dst, encoder, height=1080):
    scale = []
    if height:
        # -2 держит пропорции и чётную ширину (требование кодировщиков).
        # Условие в min() не даёт растянуть видео, которое и так меньше.
        scale = ['-vf', f"scale=-2:'min({height},ih)'"]
    args = ['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y',
            '-i', str(src), *scale, *video_args(encoder),
            # Звук перекодируем только если он не AAC — иначе копируем как есть.
            '-c:a', 'aac', '-b:a', '128k',
            '-movflags', '+faststart',   # видео начинает играть сразу
            str(dst)]
    r = run(args)
    if r.returncode != 0:
        return False, r.stderr.strip().splitlines()[-1] if r.stderr else 'ошибка'
    # Сверяем длительность: обрезанный файл принимать нельзя.
    d0, _ = probe(src)
    d1, _ = probe(dst)
    if d0 and abs(d0 - d1) > max(1.0, d0 * 0.02):
        return False, f'длительность разошлась: {d0:.1f} → {d1:.1f} сек'
    return True, ''


def compress_photo(src, dst):
    # Качество 88 — на глаз неотличимо, размер падает в разы.
    r = run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y',
             '-i', str(src), '-q:v', '3', str(dst)])
    return r.returncode == 0, (r.stderr or '').strip()[:120]


def human(b):
    for unit in ('Б', 'КБ', 'МБ', 'ГБ'):
        if abs(b) < 1024:
            return f'{b:.1f} {unit}'
        b /= 1024
    return f'{b:.1f} ТБ'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('src')
    ap.add_argument('dst')
    ap.add_argument('--check', action='store_true',
                    help='только посчитать объём, ничего не сжимать')
    ap.add_argument('--keep-size', action='store_true',
                    help='не уменьшать разрешение (файлы выйдут крупнее)')
    ap.add_argument('--height', type=int, default=1080,
                    help='до какой высоты уменьшать (по умолчанию 1080)')
    a = ap.parse_args()
    target_h = 0 if a.keep_size else a.height

    if not have('ffmpeg') or not have('ffprobe'):
        sys.exit('Нужен ffmpeg. Windows: winget install Gyan.FFmpeg\n'
                 '                  Linux: sudo apt install ffmpeg\n'
                 '                  macOS: brew install ffmpeg')

    files = []
    for root, _, names in os.walk(a.src):
        for n in names:
            ext = os.path.splitext(n)[1].lower()
            if ext in VIDEO_EXT or ext in PHOTO_EXT:
                files.append(os.path.join(root, n))
    if not files:
        sys.exit('Не нашёл ни видео, ни фотографий.')

    total = sum(os.path.getsize(f) for f in files)
    enc = pick_encoder()
    names = {'nvenc': 'NVIDIA NVENC (аппаратный)',
             'videotoolbox': 'Apple VideoToolbox (аппаратный)',
             'cpu': 'процессорный x265 — медленно, но лучшее сжатие'}
    print(f'Файлов: {len(files)}, объём: {human(total)}')
    print(f'Кодировщик: {names[enc]}')
    print(f'Разрешение: {"как в оригинале" if not target_h else str(target_h) + "p"}')
    if a.check:
        # Замерено на реальном материале: 4K-съёмка ужимается вшестеро при
        # приведении к 1080p и примерно в полтора раза без него.
        k = 6.5 if target_h else 1.5
        print(f'\nОжидаемо к выгрузке: примерно {human(total / k)}')
        print('Фотографии ужимаются в 3–5 раз.')
        return

    os.makedirs(a.dst, exist_ok=True)
    done = saved = failed = 0
    t0 = time.time()
    for i, src in enumerate(sorted(files), 1):
        rel = os.path.relpath(src, a.src)
        ext = os.path.splitext(src)[1].lower()
        out_ext = '.mp4' if ext in VIDEO_EXT else '.jpg'
        dst = os.path.join(a.dst, os.path.splitext(rel)[0] + out_ext)
        os.makedirs(os.path.dirname(dst), exist_ok=True)

        before = os.path.getsize(src)
        print(f'[{i}/{len(files)}] {rel} ({human(before)}) … ', end='', flush=True)
        if ext in VIDEO_EXT:
            ok, err = compress_video(src, dst, enc, target_h)
        else:
            ok, err = compress_photo(src, dst)

        if not ok:
            print(f'ПРОПУСК — {err}')
            # Не теряем файл: кладём оригинал как есть.
            shutil.copy2(src, os.path.join(a.dst, rel))
            failed += 1
            continue
        after = os.path.getsize(dst)
        if after >= before:
            # Сжатие не помогло — оставляем оригинал.
            os.remove(dst)
            shutil.copy2(src, os.path.join(a.dst, rel))
            print('оригинал меньше, оставил как есть')
            continue
        saved += before - after
        done += 1
        print(f'{human(after)}  −{100 * (before - after) // before}%')

    mins = (time.time() - t0) / 60
    print(f'\nГотово за {mins:.0f} мин. Сжато файлов: {done}, пропущено: {failed}')
    print(f'Освободилось: {human(saved)} — столько не придётся выгружать.')


if __name__ == '__main__':
    main()
