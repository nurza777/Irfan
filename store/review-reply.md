# Ответ на Guideline 2.1 — Information Needed

Составлено 04.09.2026. Пункты 2–6 готовы к вставке; пункт 1 (видео) снимаете
вы, ниже — покадровый список того, что Apple обязательно должна увидеть.

Отвечать двумя местами, как просит Apple: сообщением в App Store Connect
И тем же текстом в поле Notes раздела App Review Information — тогда при
следующих подачах вопросов не будет.

---

# Что записать на видео (пункт 1)

**Снимать на настоящем телефоне, не на симуляторе.** Начинать с запуска
приложения с домашнего экрана. Один непрерывный дубль, 3–5 минут.

## Подготовка (5 минут, до записи)

**1. Номер для съёмки — НЕ `⟨НОМЕР_РЕВЬЮЕРА⟩`.**
Снимайте на `⟨НОМЕР_ДЛЯ_СЪЁМКИ⟩`. Причина простая и жёсткая: на сервере запись
закрепляется за первым устройством, которое с ней пришло. Зарегистрируете
`⟨НОМЕР_РЕВЬЮЕРА⟩` на своём телефоне — и ревьюер, зарегистрировав тот же номер
у себя, получит отказ, а вместе с ним не увидит курсов. Этот номер должен
остаться нетронутым до проверки.

**2. Выдать номеру съёмки доступ к курсам.**
Панель → Доступы → выдать `⟨НОМЕР_ДЛЯ_СЪЁМКИ⟩` направление «Куран кыргызча»,
бессрочно. Без этого в шаге «Курсы» будет пусто, а Apple смотрит именно на
работающее приложение. У `⟨НОМЕР_РЕВЬЮЕРА⟩` такой доступ уже выдан.

**3. Заполнить контакты поддержки** (панель → Коды → «Поддержка: контакты
в приложении»), если хотите, чтобы на экране подтверждения номера была
видна кнопка «Позвонить».

**4. Сборка на телефоне должна быть 1.0.0 (2)** — та же, что уйдёт в Apple.

Обязательный порядок — Apple перечислила это прямо:

1. **Запуск с домашнего экрана**, главный экран с временем намаза.
2. **Обычный путь пользователя без регистрации**: Коран (открыть суру,
   показать перевод), азкары, компас киблы, счётчик зикров, Рамадан.
   Это доказывает, что приложение полезно и без аккаунта.
3. **Регистрация**: значок человека слева вверху → вкладка «Регистрация» →
   телефон `⟨НОМЕР_ДЛЯ_СЪЁМКИ⟩` (см. подготовку — не номер ревьюера!), любое имя,
   пароль от 6 знаков. На предложении подтвердить номер нажать
   **«Подтвердить позже»** — автоотправка кодов не подключена.
4. **Вход** — выйти и войти обратно тем же номером.
5. **Трекер намазов** — отметить намаз, показать серию и статистику.
6. **Курсы** — открыть направление, показать список уроков (доступ этому
   номеру уже выдан).
7. **Прямой эфир с чатом** — это пользовательский контент, Apple смотрит
   на него внимательнее всего:
   - написать сообщение в чат;
   - **долгим нажатием** на сообщение открыть меню и показать
     **«Пожаловаться»**;
   - там же показать **«Скрыть этого пользователя»**.
   ⚠️ Чат виден только во время эфира. Скажите заранее — включу тестовую
   трансляцию на сервере, пока вы записываете.
8. **Кабинет устаза**: Настройки → **долгое нажатие на «О приложении»**
   → вход `review` / `⟨ПАРОЛЬ_РЕВЬЮ⟩` → вкладка «Эфир».
   ⚠️ Строки «Кабинет устаза» в настройках больше НЕТ, пока не вошли:
   она показывается только тем, кто уже авторизован. Обязательно снимите
   само долгое нажатие — иначе ревьюер не найдёт вход и вернёт заявку.
   Дальше показать, что камера включается только по кнопке «Включить
   камеру». Это объясняет, зачем приложению камера и микрофон.
9. **Удаление аккаунта**: значок человека → «Удалить аккаунт» →
   подтверждение. Apple требует это показать, раз есть регистрация.

Платного содержимого в приложении нет — этот пункт списка пропускается.

---

# 2. Purpose and target audience

```
Irfan is a free daily-practice companion for Muslims, made for the community
of the Irfan religious organisation in Kyrgyzstan and for Kyrgyz speakers
abroad.

The problem it solves: practising Muslims need several separate tools every
day — accurate prayer times for their exact location, a way to keep track of
which prayers they performed, the Quran with a translation they trust, and
the lessons of their own teacher. Irfan puts these in one place, in Russian
and Kyrgyz, and works offline for everything that does not need the network.

Main audience: adults in Kyrgyzstan and the Kyrgyz diaspora. Secondary
audience: students of the organisation's teachers, who follow video courses
and live lessons inside the app.

The app is free, has no advertising, no in-app purchases and no tracking.
```

# 3. Setup and access instructions

```
No account is required to use most of the app. Prayer times, the Quran
reader, the qibla compass, azkar and duas, the Ramadan screen, the 99 Names
of Allah, the dhikr counter, community news and watching a live broadcast
all work immediately after installation.

An account is only needed for features that cannot exist without one:
the prayer tracker, coins and rewards, the course catalogue, certificates,
and posting in the live chat.

HOW TO CREATE AN ACCOUNT
Tap the person icon in the top-left corner of the home screen, switch to
the "Регистрация" tab and register with:

  phone:    ⟨НОМЕР_РЕВЬЮЕРА⟩
  name:     any
  password: any (minimum 6 characters)

We have pre-granted this phone number full access to the course catalogue,
so the "Курсы" section is unlocked right after registration.

PHONE VERIFICATION
After registration the app offers to confirm the number with a code.
Automatic SMS delivery is not connected yet, so please tap "Подтвердить
позже". Verification is optional and no feature is locked behind it.

TEACHER CABINET (this is why the app asks for camera and microphone)
The app contains a teachers-only section where teachers publish video
lessons and run live broadcasts. It is deliberately not advertised to
students: the menu entry appears only after a teacher has signed in.

HOW TO OPEN IT:
  1. Open Settings (gear icon, top right of the main screen).
  2. LONG-PRESS the last row, "О приложении" ("About").
  3. A sign-in screen appears. Use:

       login:    review
       password: ⟨ПАРОЛЬ_РЕВЬЮ⟩

  4. After signing in, a "Кабинет устаза" row also appears in Settings.

The camera is started only after the teacher taps "Включить камеру"
("Turn on camera"). Regular users never see a camera or microphone prompt.
This account is for review only.

LIVE BROADCASTS
A broadcast is only on when a teacher starts it, so the "Прямой эфир"
screen will usually show "Сейчас эфира нет". This is the normal idle state,
not an error. If you would like to see a live broadcast and its chat during
review, please tell us and we will start one.

ACCOUNT DELETION
Person icon → "Удалить аккаунт". Deletes the profile, prayer statistics,
coins and granted course access.
```

# 4. External services used

```
The app relies on very few external services.

1. Our own backend at https://api.irfan.kg (a server we operate, hosted at
   Hetzner, Germany). It serves the course catalogue and lesson videos,
   community news, live broadcast status and HLS stream, the live chat,
   student accounts and course access. Live video is ingested over RTMP and
   transcoded with MediaMTX and ffmpeg on the same server. No third-party
   video platform is involved.

2. Apple Push Notification service (APNs) — used only to tell students that
   a live broadcast has started. It is turned on together with notification
   permission, only after the user allows notifications in the system
   prompt, and can be switched off at any time in Settings.

3. https://cdn.islamic.network — public CDN that streams Quran recitation
   audio. Nothing is bundled in the app; audio is fetched on demand when the
   user taps play.

4. Azan.ru — the Russian meaning-based translation of the Quran and its
   tafsir. This text is bundled offline inside the app. The source is
   credited on every tafsir page with a link to the corresponding azan.ru
   page, and the translation is labelled "Azan.ru" in the translation list.

Apple system services are used for location (CoreLocation) and for turning
coordinates into a city name; prayer times themselves are calculated on the
device and work offline.

There are NO analytics SDKs, NO advertising networks, NO payment processors
and NO AI services in the app.
```

# 5. Regional differences

```
The app behaves identically in every region. There is no geographic
restriction, no region-specific content and no feature that is enabled or
disabled by country.

The only thing that depends on location is the prayer timetable itself: it
is calculated from the device's coordinates, or from a city the user picks
manually from a list. The calculation runs entirely on the device.

The interface and the store listing are available in Russian and Kyrgyz.
The user can switch the language at any time in Settings, independently of
the device region.
```

# 6. Regulated industry and third-party material

⚠️ **Здесь важно не сказать лишнего.** Разрешение Azan.ru пока устное,
подписанного письма нет. Ниже формулировка, которая это не скрывает.
Если письмо к моменту ответа будет получено — приложите скан, и абзац про
устное согласие можно убрать.

```
The app is not part of a regulated industry. It provides no medical,
financial or legal services, and it takes no payments.

Regarding third-party material, the app contains religious texts and
streams religious audio:

1. Quran translation and tafsir by Azan.ru, bundled offline. We use this
   text with the permission of the portal, given to us directly. The source
   is credited on every tafsir page with a link back to azan.ru, and the
   translation is attributed to Azan.ru in the app. We are in the process
   of obtaining that permission in writing and can provide it on request.

2. Quran recitation audio is not distributed by us. It is streamed on
   demand from the public CDN cdn.islamic.network, which serves these
   recordings openly; the reciter's name is shown in the app.

3. The Arabic text of the Quran itself is scripture and is not subject to
   copyright.

4. The app carries the name and logo of the Irfan religious organisation,
   with whose knowledge and consent it is published; the video lessons and
   the dhikr audio inside the app are that organisation's own material,
   recorded by its teachers.

If any of this requires formal documentation, we will provide it.
```
