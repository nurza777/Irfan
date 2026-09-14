#!/usr/bin/env python3
"""Ставит запись азана звуком уведомления о намазе.

Запуск:  python3 tools/add_azan.py <файл с азаном>

Почему нужен отдельный скрипт, а не просто «положить mp3 в assets».
iOS берёт звук уведомления НЕ из ресурсов Flutter, а из корня бандла
приложения, и предъявляет к файлу два жёстких требования:

  * формат — Linear PCM, MA4 (IMA4), µ-law или a-law в контейнере
    .caf/.aiff/.wav. MP3 система не проигрывает вообще;
  * длительность — не больше 30 секунд. Файл длиннее система молча
    заменяет стандартным звуком: ни ошибки, ни предупреждения.

Полный азан длится минуты, поэтому берём первые 29 секунд. Так делают
все известные приложения намаза — обойти ограничение нельзя, оно в самой
системе, а не в приложении.

Скрипт кладёт файл в оба проекта и прописывает его в Xcode-проект
(Runner → Resources). Повторный запуск просто заменяет звук.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import uuid

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PBX = os.path.join(ROOT, 'ios/Runner.xcodeproj/project.pbxproj')
IOS_SOUND = os.path.join(ROOT, 'ios/Runner/Sounds/azan.caf')
AND_SOUND = os.path.join(ROOT, 'android/app/src/main/res/raw/azan.mp3')

RUNNER_GROUP = '97C146F01CF9000F007C117D'      # группа Runner
RUNNER_RESOURCES = '97C146EC1CF9000F007C117D'  # фаза Resources цели Runner
MAX_SECONDS = 29


def die(msg):
    print('✗ ' + msg, file=sys.stderr)
    sys.exit(1)


def pbx_uuid():
    """Опознаватель в формате Xcode: 24 шестнадцатеричных знака."""
    return uuid.uuid4().hex[:24].upper()


def _loudnorm(src):
    """Строит фильтр выравнивания громкости по замеру самой записи.

    Выравнивание — не косметика: записи с открытых площадок различаются
    по уровню втрое. Тихая при звонке на улице просто не слышна, громкая
    бьёт по ушам ночью.

    Проход ДВА, а не один. Однопроходный loudnorm идёт «на слух» по мере
    чтения файла и промахивается: на первой же записи он дал −18,7 LUFS
    вместо заказанных −16. Сначала меряем, потом применяем замер.
    """
    target = 'I=-16:TP=-1.5:LRA=11'
    # Свести в моно ОБЯЗАТЕЛЬНО до замера. Громкость по EBU R128 у стерео
    # считается по сумме каналов, у моно — по одному, и одна и та же запись
    # в моно измеряется примерно на 3 дБ тише. Если мерить стерео, а писать
    # моно (как и делаем — звук уведомления моно), файл выходит тише
    # заказанного ровно на эту разницу: проверено, вышло −18,5 вместо −16.
    mono = 'aformat=channel_layouts=mono,'
    try:
        r = subprocess.run(
            ['ffmpeg', '-hide_banner', '-i', src, '-t', str(MAX_SECONDS),
             '-af', f'{mono}loudnorm={target}:print_format=json',
             '-f', 'null', '-'],
            capture_output=True, text=True, check=True)
        raw = r.stderr[r.stderr.rindex('{'):]
        m = json.loads(raw[:raw.index('}') + 1] if '}' in raw else raw)
        return (f'{mono}loudnorm={target}:measured_I={m["input_i"]}'
                f':measured_TP={m["input_tp"]}:measured_LRA={m["input_lra"]}'
                f':measured_thresh={m["input_thresh"]}'
                f':offset={m["target_offset"]}:linear=true')
    except Exception as e:
        # Замер не удался — выравниваем в один проход. Хуже по точности,
        # но лучше, чем оставить запись как есть.
        print('• замер громкости не удался (%s), один проход' % e)
        return mono + 'loudnorm=' + target


def convert(src):
    os.makedirs(os.path.dirname(IOS_SOUND), exist_ok=True)
    os.makedirs(os.path.dirname(AND_SOUND), exist_ok=True)
    tmp = os.path.join(ROOT, 'build', 'azan-trim.wav')
    os.makedirs(os.path.dirname(tmp), exist_ok=True)

    # Сначала обрезка и приведение к WAV: afconvert не умеет ни резать,
    # ни читать всё подряд, а ffmpeg не умеет писать IMA4 в CAF.
    norm = _loudnorm(src)
    subprocess.run(
        ['ffmpeg', '-y', '-loglevel', 'error', '-i', src,
         '-t', str(MAX_SECONDS), '-af', norm, '-ac', '1', '-ar', '44100', tmp],
        check=True)
    subprocess.run(
        ['afconvert', '-f', 'caff', '-d', 'ima4', tmp, IOS_SOUND], check=True)
    subprocess.run(
        ['ffmpeg', '-y', '-loglevel', 'error', '-i', src,
         '-t', str(MAX_SECONDS), '-af', norm, '-ac', '1', '-b:a', '96k',
         AND_SOUND], check=True)
    os.remove(tmp)


def wire_xcode():
    """Прописывает azan.caf в ресурсы цели Runner. Идемпотентно."""
    s = open(PBX, encoding='utf-8').read()
    if 'Sounds/azan.caf' in s:
        print('• в Xcode-проекте звук уже прописан')
        return
    ref, build = pbx_uuid(), pbx_uuid()

    s = s.replace(
        '/* Begin PBXBuildFile section */',
        '/* Begin PBXBuildFile section */\n'
        f'\t\t{build} /* azan.caf in Resources */ = {{isa = PBXBuildFile; '
        f'fileRef = {ref} /* azan.caf */; }};', 1)
    s = s.replace(
        '/* Begin PBXFileReference section */',
        '/* Begin PBXFileReference section */\n'
        f'\t\t{ref} /* azan.caf */ = {{isa = PBXFileReference; '
        'lastKnownFileType = file; name = azan.caf; path = Sounds/azan.caf; '
        'sourceTree = "<group>"; };', 1)

    # Якоримся на ОБЪЯВЛЕНИЕ группы («= {»), а не на первое упоминание
    # опознавателя: тот же опознаватель стоит и в списке детей родительской
    # группы, и поиск «ближайшего children» от него уводил файл в Products.
    m = re.search(re.escape(RUNNER_GROUP) + r'[^\n]*= \{.*?children = \(\n',
                  s, re.S)
    if not m:
        die('не найдено объявление группы Runner')
    s = s[:m.end()] + f'\t\t\t\t{ref} /* azan.caf */,\n' + s[m.end():]

    m = re.search(re.escape(RUNNER_RESOURCES) + r'[^\n]*= \{.*?files = \(\n',
                  s, re.S)
    if not m:
        die('не найдена фаза Resources')
    s = s[:m.end()] + f'\t\t\t\t{build} /* azan.caf in Resources */,\n' + s[m.end():]

    shutil.copy(PBX, PBX + '.bak')
    open(PBX, 'w', encoding='utf-8').write(s)
    print('• звук прописан в Xcode-проект (копия прежнего — project.pbxproj.bak)')


def main():
    if len(sys.argv) != 2:
        die('нужен один довод: путь к записи азана')
    src = sys.argv[1]
    if not os.path.isfile(src):
        die('файл не найден: ' + src)
    if not shutil.which('ffmpeg'):
        die('нет ffmpeg (brew install ffmpeg)')
    convert(src)
    wire_xcode()
    print('✓ азан установлен:')
    print('  iOS     ' + os.path.relpath(IOS_SOUND, ROOT))
    print('  Android ' + os.path.relpath(AND_SOUND, ROOT))
    print('Дальше: включить звук в lib/services/notification_service.dart —')
    print('  iOS     DarwinNotificationDetails(sound: \'azan.caf\', ...)')
    print('  Android канал prayer_times_azan с RawResourceAndroidNotificationSound')
    print('Канал Android обязан быть НОВЫМ: звук у существующего канала')
    print('система менять не даёт, он задаётся раз и навсегда при создании.')


if __name__ == '__main__':
    main()
