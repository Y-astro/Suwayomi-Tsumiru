#!/usr/bin/env python3
"""Check real Wayland presentation and FFI using local content and isolated data."""

import json
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

from build import HERE, REPO


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode', choices=['debug', 'profile', 'release'], default='debug')
    parser.add_argument('--lifecycle', action='store_true', help='Recreate native surfaces during rendering')
    args = parser.parse_args()
    if not os.environ.get('WAYLAND_DISPLAY'):
        raise SystemExit('This hardware check requires a Wayland session')
    subprocess.run([sys.executable, str(HERE / 'build.py'), '--mode', args.mode, '--testing'], check=True)
    flutter = shutil.which('flutter')
    sdk = Path(os.environ['FLUTTER_ROOT']) if os.environ.get('FLUTTER_ROOT') else Path(flutter).resolve().parents[1]
    cache = REPO / 'build/linux_native'
    env = dict(os.environ, TSUMIRU_NATIVE_ENGINE_DIR=str(cache / args.mode),
               TSUMIRU_APPLICATION_ID='io.github.aaronbamblett.tsumiru.nativeprobe',
               TSUMIRU_NATIVE_TRACE='1')
    for variable, directory in [('XDG_CONFIG_HOME', 'config'), ('XDG_DATA_HOME', 'data'), ('XDG_CACHE_HOME', 'cache')]:
        location = cache / 'check-data' / directory
        location.mkdir(parents=True, exist_ok=True)
        env[variable] = str(location)
    command = [str(sdk / 'bin/flutter'), 'build', 'linux', f'--{args.mode}', '--no-pub',
               '-t', 'tool/linux_native/probe.dart']
    if args.lifecycle:
        command.append('--dart-define=TSUMIRU_NATIVE_CYCLE_TEST=true')
    subprocess.run(command, cwd=REPO, env=env, check=True)
    log_path = cache / 'check.log'
    with log_path.open('w') as log:
        child = subprocess.Popen([str(REPO / f'build/linux/x64/{args.mode}/bundle/tsumiru')],
                                 cwd=REPO, env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            time.sleep(20)
        finally:
            child.terminate()
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
    text = log_path.read_text()
    if args.lifecycle:
        assert text.count('Native surface cycle complete') == 5, f'Surface recreation failed: {log_path}'
        assert text.count('Native Wayland surface released') >= 5, f'Old surfaces were not released: {log_path}'
    assert 'FFI IsolateScope verification passed' in text, f'Native FFI check failed: {log_path}'
    pixels = re.findall(r'Native output RGBA (\d+) (\d+) (\d+) (\d+)', text)
    assert pixels and all(int(p[3]) == 255 for p in pixels), f'Window buffer is blank: {log_path}'
    assert 'Subsurface frame failed' not in text, f'GL presentation failed: {log_path}'
    samples = [tuple(map(int, m)) for m in re.findall(
        r'PRESENTED count=(\d+) time_ns=(\d+) refresh_ns=(\d+).*discarded=(\d+)', text)]
    assert samples, f'No compositor presentation feedback: {log_path}'
    warm = [s for s in samples if s[1] >= samples[0][1] + 10_000_000_000]
    assert len(warm) >= 3, f'Not enough presentation samples after warmup: {log_path}'
    first, last = warm[0], warm[-1]
    fps = (last[0] - first[0]) * 1e9 / (last[1] - first[1])
    refresh_hz = 1e9 / last[2] if last[2] else 60
    assert fps > min(100, refresh_hz * 0.8), f'Presentation too slow: {fps:.2f} FPS; {log_path}'
    print(json.dumps({'displayed_fps': round(fps, 2), 'refresh_hz': round(refresh_hz, 2),
                      'discarded': last[3], 'evidence': str(log_path)}, indent=2))


if __name__ == '__main__':
    main()
