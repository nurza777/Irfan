#!/usr/bin/env bash
# Ставит фоновое сжатие уроков таймером systemd. Запускать на сервере от root.
set -euo pipefail

# Скрипт может уже лежать по назначению (закинули через scp) — тогда просто
# выставляем права, а не копируем сам в себя.
if [[ "$(readlink -f auto-compress.sh)" != "/opt/irfan-server/auto-compress.sh" ]]; then
  install -m 755 auto-compress.sh /opt/irfan-server/auto-compress.sh
else
  chmod 755 /opt/irfan-server/auto-compress.sh
fi

cat > /etc/systemd/system/irfan-compress.service <<'UNIT'
[Unit]
Description=Сжатие загруженных уроков «Ирфан»
After=network.target

[Service]
Type=oneshot
ExecStart=/opt/irfan-server/auto-compress.sh
# Кодирование не должно мешать API и раздаче видео.
Nice=19
IOSchedulingClass=idle
CPUQuota=200%
UNIT

cat > /etc/systemd/system/irfan-compress.timer <<'UNIT'
[Unit]
Description=Проверять новые уроки для сжатия

[Timer]
OnBootSec=10min
OnUnitActiveSec=15min
Persistent=true

[Install]
WantedBy=timers.target
UNIT

systemctl daemon-reload
systemctl enable --now irfan-compress.timer
echo "Готово. Проверить:  systemctl list-timers irfan-compress"
echo "Лог:                tail -f /opt/irfan-server/logs/compress.log"
echo "Запустить сразу:    systemctl start irfan-compress"
