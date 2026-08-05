#!/usr/bin/env bash
#
# Ставит ежедневную резервную копию (см. backup.sh). Запускать НА СЕРВЕРЕ:
#
#   bash /opt/irfan-server/install-backup.sh
#
# Копия делается раз в сутки ночью и ещё раз при загрузке — если сервер
# перезапустили, свежий срез появляется сразу.
set -euo pipefail

cat > /etc/systemd/system/irfan-backup.service <<'UNIT'
[Unit]
Description=Irfan: резервная копия данных
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/env bash /opt/irfan-server/backup.sh
Nice=10
IOSchedulingClass=idle
UNIT

cat > /etc/systemd/system/irfan-backup.timer <<'UNIT'
[Unit]
Description=Irfan: ежедневная резервная копия

[Timer]
OnCalendar=*-*-* 03:30:00
OnBootSec=10min
Persistent=true

[Install]
WantedBy=timers.target
UNIT

systemctl daemon-reload
systemctl enable --now irfan-backup.timer

echo "==> таймер включён:"
systemctl list-timers irfan-backup.timer --no-pager | head -3
echo
echo "==> Копии лежат на ТОМ ЖЕ диске — это защита от ошибки, но не от"
echo "    смерти диска. Забирать наружу: tools/pull-backup.sh с вашего мака."
