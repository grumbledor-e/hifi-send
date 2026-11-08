#!/usr/bin/env python3
"""HiFi Send 0.2.2: local file IPC; audio/network work stays outside matron."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import signal
import re
import subprocess
import time
import urllib.request
import urllib.parse


def graph(text):
    ports = {}
    current = None
    for line in text.splitlines():
        if line and not line[0].isspace():
            current = line.strip()
            ports[current] = []
        elif current and line.strip():
            ports[current].append(line.strip())
    return ports


def sources(ports, explicit=None):
    if explicit:
        if len(explicit) != 2 or any(p not in ports for p in explicit):
            raise RuntimeError('Configured JACK source ports missing')
        return explicit
    result = []
    for n in (1, 2):
        links = ports.get('system:playback_' + str(n), [])
        if len(links) != 1:
            raise RuntimeError('Ambiguous main output; run diagnostics')
        result.append(links[0])
    return result


def clean(value):
    return str(value).replace('\t', ' ').replace('\n', ' ').replace('\r', ' ')


def atomic(path, text):
    temp = path.with_suffix('.tmp')
    temp.write_text(text)
    temp.replace(path)


class Bridge:
    def __init__(self, data):
        self.data = data
        self.proc = None
        self.log = None
        self.outputs = []
        self.target = ''
        self.volume = 20
        self.message = 'off'
        self.running = True
        self.started = 0
        self.config = json.loads((data / 'config.json').read_text())
        self.base = 'http://127.0.0.1:3691'
        self.buffer_ms = self.read_buffer()

    def read_buffer(self):
        match = re.search(r"(?m)^\s*start_buffer_ms\s*=\s*(\d+)", (self.data / 'owntone.conf').read_text())
        return int(match.group(1)) if match else 2250

    def set_buffer(self, value):
        value = int(value)
        if value < 100 or value > 2250 or value % 50:
            raise ValueError('Buffer must be 100..2250 ms in 50 ms steps')
        if self.proc:
            raise RuntimeError('Disconnect before changing buffer')
        path = self.data / 'owntone.conf'
        previous = path.read_text()
        text, count = re.subn(r'(?m)^(\s*start_buffer_ms\s*=\s*)\d+',
                              lambda m: m.group(1) + str(value), previous)
        if count != 1:
            raise RuntimeError('Expected exactly one buffer setting')
        atomic(path, text)
        result = subprocess.run(['sudo', '-n', '/usr/bin/systemctl', 'restart',
                                 'norns-hifi-owntone.service'], capture_output=True, text=True, timeout=20)
        if result.returncode:
            atomic(path, previous)
            raise RuntimeError('Buffer restart denied; rerun setup.sh')
        self.buffer_ms = value
        self.message = 'buffer applied; refresh devices'

    def api(self, path, body=None):
        payload = None if body is None else json.dumps(body).encode()
        request = urllib.request.Request(self.base + '/api/' + path, data=payload,
                    method='GET' if body is None else 'PUT',
                    headers={'Content-Type': 'application/json'})
        with urllib.request.urlopen(request, timeout=2) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}

    def refresh(self):
        self.outputs = sorted([o for o in self.api('outputs')['outputs']
                               if o['type'] in ('AirPlay', 'AirPlay 1', 'AirPlay 2', 'Chromecast')], key=lambda o: o['name'].lower())

    def stop(self):
        if self.proc:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait()
            self.proc = None
        if self.log:
            self.log.close()
            self.log = None
        self.target = ''
        try:
            self.api('player/stop', {})
            self.api('outputs/set', {'outputs': []})
        finally:
            self.message = 'off'

    def connect(self, ident):
        self.stop()
        self.refresh()
        output = next((o for o in self.outputs if str(o['id']) == ident), None)
        if not output:
            raise RuntimeError('Device unavailable; refresh list')
        if output['type'] != 'Chromecast' and self.buffer_ms <= 250:
            raise RuntimeError('AirPlay needs buffer above 250ms')
        if output.get('needs_auth_key') or output.get('requires_auth') or output.get('has_password'):
            raise RuntimeError('Device needs authentication; see README')
        # Validate before enabling a receiver. Preserve physical JACK connections.
        ports = graph(subprocess.check_output(['jack_lsp', '-c'], text=True, timeout=3))
        sources(ports, self.config.get('source_ports'))
        self.api('outputs/' + urllib.parse.quote(ident, safe=''), {'volume': self.volume})
        self.api('outputs/set', {'outputs': [ident]})
        logpath = self.data / 'capture.log'
        self.log = logpath.open('w')
        self.proc = subprocess.Popen(['ffmpeg', '-nostdin', '-hide_banner', '-loglevel', 'warning',
             '-f', 'jack', '-channels', '2', '-i', 'norns_hifi',
             '-ac', '2', '-ar', '44100', '-c:a', 'pcm_s16le', '-f', 's16le',
             '-flush_packets', '1', '-avioflags', 'direct', '-y', str(self.data / 'audio' / 'norns.pipe')],
             stdout=subprocess.DEVNULL, stderr=self.log)
        self.target = ident
        self.started = time.monotonic()
        self.message = 'starting'

    def route(self):
        if not self.proc:
            return
        if self.proc.poll() is not None:
            raise RuntimeError('Capture stopped; see capture.log')
        ports = graph(subprocess.check_output(['jack_lsp', '-c'], text=True, timeout=3))
        dests = sorted(p for p in ports if p.startswith('norns_hifi:'))
        if len(dests) != 2:
            if time.monotonic() - self.started > 10:
                raise RuntimeError('Capture ports missing; check FFmpeg JACK support')
            return
        for source, dest in zip(sources(ports, self.config.get('source_ports')), dests):
            for old in ports[dest]:
                if old != source:
                    subprocess.run(['jack_disconnect', old, dest], check=True, timeout=2,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
            if source not in ports[dest]:
                subprocess.run(['jack_connect', source, dest], check=True, timeout=2,
                               stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        output = next((o for o in self.outputs if str(o['id']) == self.target), None)
        if not output:
            raise RuntimeError('Receiver disappeared')
        if time.monotonic() - self.started > 12 and not output.get('selected'):
            raise RuntimeError('Output deselected; inspect owntone.log')
        # This describes reported server state, not proof of audible playback.
        state = self.api('player').get('state', '')
        self.message = 'sending' if output.get('selected') and state == 'play' else 'buffering'
        if time.monotonic() - self.started > 20 and self.message == 'buffering':
            raise RuntimeError('No playback confirmation; see logs')

    def command(self, text):
        fields = text.rstrip('\n').split('\t')
        if fields[0] == 'connect' and len(fields) == 2:
            self.connect(fields[1])
        elif fields[0] == 'stop':
            self.stop()
        elif fields[0] == 'refresh':
            self.refresh()
            if not self.proc:
                self.message = 'off'
        elif fields[0] == 'volume' and len(fields) == 2:
            self.volume = max(0, min(100, int(fields[1])))
            if self.target:
                self.api('outputs/' + urllib.parse.quote(self.target, safe=''), {'volume': self.volume})
        elif fields[0] == 'buffer' and len(fields) == 2:
            self.set_buffer(fields[1])
        elif fields[0] == 'quit':
            self.running = False
        else:
            raise ValueError('Unknown command')

    def status(self):
        rows = [['status', self.message], ['target', self.target], ['volume', self.volume],
                ['heartbeat', int(time.time())], ['buffer', self.buffer_ms]]
        rows += [['device', o['id'], o['name'] + (' [cast]' if o['type'] == 'Chromecast' else ' [air]')] for o in self.outputs]
        atomic(self.data / 'status.tsv', '\n'.join('\t'.join(map(clean, row)) for row in rows) + '\n')

    def run(self):
        # Discard commands from an earlier worker session; never auto-start audio.
        for path in (self.data / 'commands').glob('*.cmd'):
            path.unlink()
        last = 0
        initial = True
        last_route = 0
        try:
            while self.running:
                try:
                    if initial:
                        self.stop()
                        initial = False
                    for path in sorted((self.data / 'commands').glob('*.cmd')):
                        text = path.read_text()
                        path.unlink()
                        self.command(text)
                    if time.monotonic() - last > 2:
                        self.refresh()
                        last = time.monotonic()
                    if time.monotonic() - last_route > 1:
                        self.route()
                        last_route = time.monotonic()
                except Exception as error:
                    try:
                        self.stop()
                    except Exception:
                        pass
                    self.message = str(error)
                    atomic(self.data / 'last-error.txt', repr(error) + '\n')
                self.status()
                time.sleep(0.2)
        finally:
            try:
                self.stop()
            except Exception:
                pass
            self.status()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--data', type=Path, required=True)
    args = parser.parse_args()
    data = args.data.resolve()
    data.mkdir(parents=True, exist_ok=True)
    (data / 'commands').mkdir(exist_ok=True)
    with (data / 'worker.lock').open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        atomic(data / 'worker.pid', str(os.getpid()))
        bridge = Bridge(data)
        def shutdown(*_):
            bridge.running = False
        signal.signal(signal.SIGTERM, shutdown)
        signal.signal(signal.SIGINT, shutdown)
        bridge.run()

if __name__ == '__main__':
    main()
