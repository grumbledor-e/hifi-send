#!/usr/bin/env bash
set -u
printf 'HiFi Send 0.2.2 diagnostics\n'
uname -m
cat /etc/os-release
printf '\nOwnTone service\n'
systemctl --no-pager --full status norns-hifi-owntone.service || true
systemctl --no-pager --full status norns-hifi-worker.service || true
printf '\nFFmpeg JACK support\n'
ffmpeg -hide_banner -devices 2>&1 | sed -n '/jack/p'
printf '\nJACK graph\n'
jack_lsp -c || true
printf '\nWorker status\n'
cat "$HOME/dust/data/hifi-send/status.tsv" 2>/dev/null || true
printf '\nRecent capture messages\n'
tail -n 30 "$HOME/dust/data/hifi-send/capture.log" 2>/dev/null || true
printf '\nRecent sender messages\n'
tail -n 30 "$HOME/dust/data/hifi-send/owntone.log" 2>/dev/null || true
printf '\nRecent worker messages\n'
tail -n 20 "$HOME/dust/data/hifi-send/worker.log" 2>/dev/null || true
