#!/usr/bin/env bash
# HiFi Send 0.2.2 — automatic dependencies, fresh setup and upgrades.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
[[ $EUID != 0 ]] || { echo 'Run as the normal Norns user, without sudo.'; exit 1; }
project_dir="$PWD"
[[ "$project_dir" == "$HOME/dust/code/hifi-send" ]] || {
 echo 'Norns mod folders cannot contain dots. Install this project as ~/dust/code/hifi-send.'
 exit 1
}
# A leftover invalid mod directory can break Norns' mod scanner even when disabled.
for mod_file in "$HOME"/dust/code/*/lib/mod.lua; do
 [[ -f "$mod_file" ]] || continue
 mod_dir="${mod_file%/lib/mod.lua}"
 mod_name="${mod_dir##*/}"
 [[ "$mod_name" =~ ^[a-zA-Z0-9_-]+$ ]] || {
  echo "Invalid Norns mod folder: $mod_name"
  echo 'Move this folder outside dust/code, reboot Norns, and rerun setup.'
  exit 1
 }
done
account="$(id -un)"
[[ "$account" =~ ^[a-zA-Z0-9_-]+$ && "$HOME" =~ ^/[a-zA-Z0-9_./-]+$ ]] || { echo 'Unsupported username or home path.'; exit 1; }
# Resolve dependencies automatically; fresh repository setup is Bullseye-only.
sudo -v
installed_version="$(dpkg-query -W -f='${Version}' owntone 2>/dev/null || true)"
need_owntone=0
if ! command -v owntone >/dev/null || ! dpkg --compare-versions "$installed_version" ge 29; then
 need_owntone=1
fi
missing_tools=0
for executable in python3 ffmpeg jack_lsp jack_connect jack_disconnect; do
 command -v "$executable" >/dev/null || missing_tools=1
done
if [[ "$need_owntone" == 1 ]]; then
 . /etc/os-release
 [[ "${VERSION_CODENAME:-}" == bullseye ]] || {
  echo 'Automatic OwnTone installation currently supports Bullseye only.'
  echo 'Install OwnTone 29+ for your OS from its official instructions, then rerun setup.'
  exit 1
 }
 sudo apt-get update
 sudo apt-get install -y --no-remove --no-install-recommends wget gnupg ca-certificates
 transfer_dir="$(mktemp -d)"
 trap 'rm -rf -- "$transfer_dir"' EXIT
 wget -q -O "$transfer_dir/owntone.gpg" https://raw.githubusercontent.com/owntone/owntone-apt/refs/heads/master/repo/rpi/owntone.gpg
 gpg --batch --yes --dearmor --output "$transfer_dir/owntone-archive-keyring.gpg" "$transfer_dir/owntone.gpg"
 wget -q -O "$transfer_dir/owntone.list" https://raw.githubusercontent.com/owntone/owntone-apt/refs/heads/master/repo/rpi/owntone-bullseye.list
 sudo install -m 644 "$transfer_dir/owntone-archive-keyring.gpg" /usr/share/keyrings/owntone-archive-keyring.gpg
 sudo install -m 644 "$transfer_dir/owntone.list" /etc/apt/sources.list.d/owntone.list
 rm -rf -- "$transfer_dir"
 trap - EXIT
 sudo apt-get update
 # Do not interrupt a pre-existing default server silently.
 if sudo systemctl is-active --quiet owntone.service; then
  echo 'A default OwnTone server is already active. Stop it deliberately before continuing.'
  exit 1
 fi
 sudo systemctl mask --runtime owntone.service
 trap 'sudo systemctl unmask --runtime owntone.service >/dev/null || true' EXIT
 sudo apt-get install -y --no-remove --no-install-recommends owntone ffmpeg jack-tools python3
 sudo systemctl disable owntone.service
 sudo systemctl unmask --runtime owntone.service
 trap - EXIT
elif [[ "$missing_tools" == 1 ]]; then
 sudo apt-get update
 sudo apt-get install -y --no-remove --no-install-recommends ffmpeg jack-tools python3
fi

for executable in owntone python3 ffmpeg jack_lsp jack_connect jack_disconnect; do
  command -v "$executable" >/dev/null || { echo "Missing $executable — see INSTALL.md."; exit 1; }
done
installed_version="$(dpkg-query -W -f='${Version}' owntone 2>/dev/null || true)"
dpkg --compare-versions "$installed_version" ge 29 || { echo 'OwnTone 29 or newer is required.'; exit 1; }
ffmpeg -hide_banner -devices 2>&1 | awk '$2 == "jack" { found=1 } END { exit !found }' || { echo 'FFmpeg needs JACK input support.'; exit 1; }
sudo -v
sudo systemctl stop norns-hifi-worker.service 2>/dev/null || true
# Stop a worker launched by an older mod, without signalling an unrelated PID.
python3 - <<'PY'
from pathlib import Path
import os, signal, time
p=Path.home()/'dust/data/hifi-send/worker.pid'
if p.exists():
    pid=int(p.read_text()); proc=Path('/proc')/str(pid)/'cmdline'
    if proc.exists() and b'hifi-send/backend/bridge.py' in proc.read_bytes():
        os.kill(pid,signal.SIGTERM)
        for _ in range(100):
            if not proc.exists(): break
            time.sleep(.1)
        else: raise SystemExit('Old worker has not stopped; retry setup shortly.')
PY
umask 077
data_dir="$HOME/dust/data/hifi-send"
mkdir -p "$data_dir/audio" "$data_dir/cache" "$data_dir/commands"
if [[ ! -e "$data_dir/audio/norns.pipe" ]]; then mkfifo -m 600 "$data_dir/audio/norns.pipe"; fi
[[ -p "$data_dir/audio/norns.pipe" ]] || { echo 'audio/norns.pipe must be a FIFO.'; exit 1; }
# OwnTone reads now-playing info (script, author, screen) from this pipe.
if [[ ! -e "$data_dir/audio/norns.pipe.metadata" ]]; then mkfifo -m 600 "$data_dir/audio/norns.pipe.metadata"; fi
python3 - <<'PY'
from pathlib import Path
import re, secrets
p=Path.home()/'dust/data/hifi-send/owntone.conf';d=p.parent
if p.exists():
    s=p.read_text()
    backup=p.with_name('owntone.conf.before-v021')
    if not backup.exists(): backup.write_text(s)
    s=re.sub(r'(?m)^\s*cache_path\s*=.*$', ' cache_dir = "'+str(d/'cache')+'"',s)
    setting=re.compile(r'(?m)^(\s*start_buffer_ms\s*=\s*)(\d+)')
    found=setting.findall(s)
    if len(found)>1: raise SystemExit('Multiple buffer settings; inspect owntone.conf.')
    if found:
        if int(found[0][1])<=250:
            s=setting.sub(lambda m:m[1]+'500',s)
    elif 'general {' in s:
        s=s.replace('general {','general {\n start_buffer_ms = 500',1)
    else: raise SystemExit('Missing general section; inspect owntone.conf.')
else:
    import getpass
    s='''general {
 uid = "%s"
 db_path = "%s/cache/songs-own29.db"
 cache_dir = "%s/cache"
 logfile = "%s/owntone.log"
 loglevel = warning
 admin_password = "%s"
 trusted_networks = { "localhost" }
 websocket_port = 0
 speaker_autoselect = false
 start_buffer_ms = 500
}
library {
 name = "Norns HiFi Send"
 port = 3691
 directories = { "%s/audio" }
 pipe_autostart = true
}
audio { type = "disabled" }
mpd { port = 0 }
''' % (getpass.getuser(),d,d,d,secrets.token_hex(32),d)
p.write_text(s)
c=d/'config.json'
if not c.exists(): c.write_text('{"source_ports": null}\n')
PY
server_binary="$(command -v owntone)"
cat > "$data_dir/norns-hifi-owntone.service" <<EOF
[Unit]
Description=Norns HiFi Send network audio
After=network.target avahi-daemon.service
Wants=avahi-daemon.service
[Service]
Type=simple
User=$account
Group=$(id -gn)
ExecStart=$server_binary -f -c $data_dir/owntone.conf
Restart=on-failure
RestartSec=5
UMask=0077
[Install]
WantedBy=multi-user.target
EOF
cat > "$data_dir/norns-hifi-worker.service" <<EOF
[Unit]
Description=Norns HiFi Send controller
After=norns-jack.service norns-hifi-owntone.service
[Service]
Type=simple
User=$account
Group=$(id -gn)
LimitRTPRIO=90
LimitMEMLOCK=infinity
Environment=JACK_NO_START_SERVER=1
ExecStart=/usr/bin/python3 $project_dir/backend/bridge.py --data $data_dir
Restart=on-failure
RestartSec=3
UMask=0077
[Install]
WantedBy=multi-user.target
EOF
printf '%s ALL=(root) NOPASSWD: /usr/bin/systemctl restart norns-hifi-owntone.service\n' "$account" > "$data_dir/sudoers"
sudo visudo -cf "$data_dir/sudoers"
sudo install -m 440 "$data_dir/sudoers" /etc/sudoers.d/norns-hifi-send
for service in norns-hifi-owntone norns-hifi-worker; do
 sudo install -m 644 "$data_dir/$service.service" "/etc/systemd/system/$service.service"
done
# Preserve JACK IPC across the last SSH logout; applied at next reboot.
printf '[Login]\nRemoveIPC=no\n' > "$data_dir/logind.conf"
sudo mkdir -p /etc/systemd/logind.conf.d
sudo install -m 644 "$data_dir/logind.conf" /etc/systemd/logind.conf.d/90-hifi-send.conf
sudo systemctl daemon-reload
sudo systemctl enable norns-hifi-owntone.service norns-hifi-worker.service
sudo systemctl restart norns-hifi-owntone.service
sudo systemctl restart norns-hifi-worker.service
sudo systemctl --no-pager --full status norns-hifi-owntone.service norns-hifi-worker.service
printf '\nSetup complete. Enable hifi-send in SYSTEM > MODS, then reboot Norns.\n'
