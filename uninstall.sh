#!/usr/bin/env bash
set -euo pipefail
# Ask the running worker to terminate its own capture child cleanly.
python3 - <<'PY'
from pathlib import Path
import time
p = Path.home() / 'dust/data/hifi-send/commands'
if p.is_dir():
    temp = p / '9999999999-quit.tmp'
    temp.write_text('quit\n')
    temp.replace(p / '9999999999-quit.cmd')
time.sleep(3)
PY
sudo systemctl disable --now norns-hifi-worker.service
sudo rm -f /etc/systemd/system/norns-hifi-worker.service /etc/sudoers.d/norns-hifi-send
sudo systemctl disable --now norns-hifi-owntone.service
sudo rm -f /etc/systemd/system/norns-hifi-owntone.service
sudo rm -f /etc/systemd/logind.conf.d/90-hifi-send.conf
sudo systemctl daemon-reload
printf 'Disable hifi-send in MODS and restart. Code and diagnostic files retained.\n'
