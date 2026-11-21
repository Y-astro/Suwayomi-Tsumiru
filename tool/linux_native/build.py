#!/usr/bin/env python3
"""Build Tsumiru's pinned, app-local Linux engine without modifying the SDK."""

import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import urllib.request
import zipfile

ENGINE = '89c39edfdfae2949f6806e4a315c0c08522238b7'
EMBEDDER_SHA256 = 'e84427cd4a660ffbb572e0b2b6c7f03bc2d21b9d95d75b6d71c382546698c093'
RAPIDJSON_REVISION = '47253cab97e9cfe99dbd6b90836fc11589d7d802'
HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]


def download(url, destination, checksum):
    if not destination.exists():
        temporary = destination.with_suffix('.download')
        try:
            with urllib.request.urlopen(url, timeout=60) as response, temporary.open('wb') as output:
                shutil.copyfileobj(response, output)
            temporary.replace(destination)
        finally:
            temporary.unlink(missing_ok=True)
    if hashlib.sha256(destination.read_bytes()).hexdigest() != checksum:
        raise RuntimeError(f'Checksum mismatch: {destination}; remove it before retrying')


def cmake_quote(path):
    value = str(path)
    if ']]' in value:
        raise ValueError('CMake paths cannot contain ]]')
    return f'[[{value}]]'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode', choices=['debug', 'profile', 'release'], default='debug')
    parser.add_argument('--testing', action='store_true', help='Include the native FFI smoke probe')
    args = parser.parse_args()
    flutter = shutil.which('flutter')
    sdk = Path(os.environ['FLUTTER_ROOT']).resolve() if os.environ.get('FLUTTER_ROOT') else (
        Path(flutter).resolve().parents[1] if flutter else None)
    if sdk is None:
        parser.error('Set FLUTTER_ROOT to the Flutter SDK or add flutter to PATH')
    version = json.loads(subprocess.check_output([str(sdk / 'bin/flutter'), '--version', '--machine'], text=True))
    expected = json.loads((REPO / '.fvmrc').read_text())['flutter']
    if version['frameworkVersion'] != expected or version['engineRevision'] != ENGINE:
        parser.error(f'This patch requires Flutter {expected}, engine {ENGINE}')
    for command in ['cmake', 'ninja', 'patch', 'git', 'pkg-config', 'wayland-scanner']:
        if not shutil.which(command):
            parser.error(f'Missing build tool: {command}')

    cache = REPO / 'build/linux_native'
    cache.mkdir(parents=True, exist_ok=True)
    rapidjson = cache / 'rapidjson'
    if not (rapidjson / '.git').exists():
        subprocess.run(['git', 'init', '--quiet', str(rapidjson)], check=True)
        subprocess.run(['git', '-C', str(rapidjson), 'fetch', '--quiet', '--depth', '1',
                        'https://flutter.googlesource.com/third_party/rapidjson', RAPIDJSON_REVISION], check=True)
        subprocess.run(['git', '-C', str(rapidjson), 'checkout', '--quiet', '--detach', 'FETCH_HEAD'], check=True)
    revision = subprocess.check_output(['git', '-C', str(rapidjson), 'rev-parse', 'HEAD'], text=True).strip()
    if revision != RAPIDJSON_REVISION:
        raise RuntimeError(f'Unexpected RapidJSON revision in {rapidjson}')

    output = cache / args.mode
    output.mkdir(exist_ok=True)
    core = output / 'libflutter_engine.so'
    temporary_core = output / 'libflutter_engine.so.staging'
    supplied = os.environ.get('TSUMIRU_ENGINE_CORE')
    if supplied:
        source = Path(supplied).resolve(strict=True)
        if source != core.resolve():
            shutil.copy2(source, temporary_core)
    elif args.mode == 'debug':
        archive_path = cache / 'embedder.zip'
        download(f'https://storage.googleapis.com/flutter_infra_release/flutter/{ENGINE}/linux-x64/linux-x64-embedder.zip',
                 archive_path, EMBEDDER_SHA256)
        with zipfile.ZipFile(archive_path) as archive:
            with archive.open('libflutter_engine.so') as source, temporary_core.open('wb') as target:
                shutil.copyfileobj(source, target)
    else:
        parser.error('Profile/release require TSUMIRU_ENGINE_CORE pointing to a matching locally built standalone engine')

    candidate = temporary_core if temporary_core.exists() else core
    library = ctypes.CDLL(str(candidate))
    aot = library.FlutterEngineRunsAOTCompiledDartCode
    aot.argtypes = []
    aot.restype = ctypes.c_bool
    if aot() != (args.mode != 'debug'):
        temporary_core.unlink(missing_ok=True)
        parser.error('The supplied engine core does not match the requested JIT/AOT build mode')
    if temporary_core.exists():
        temporary_core.replace(core)

    source_root = cache / 'src'
    patch = HERE / 'flutter.patch'
    patch_hash = hashlib.sha256(patch.read_bytes()).hexdigest()
    stamp = cache / 'source-patch.sha256'
    if not source_root.exists() or not stamp.exists() or stamp.read_text() != patch_hash:
        if source_root.exists():
            shutil.rmtree(source_root)
        shutil.copytree(sdk / 'engine/src', source_root, dirs_exist_ok=True)
        subprocess.run(['patch', '--batch', '-p1', '-i', str(patch)], cwd=source_root, check=True)
        stamp.write_text(patch_hash)

    engine = source_root / 'flutter'
    build_definition = (engine / 'shell/platform/linux/BUILD.gn').read_text()
    block = build_definition.split('source_set("flutter_linux_sources")', 1)[1]
    block = block.split('  sources = [', 1)[1].split('\n  ]', 1)[0]
    names = re.findall(r'"([^"\n]+\.cc)"', block)
    if not 60 <= len(names) <= 100 or 'fl_engine.cc' not in names:
        raise RuntimeError('Unexpected GTK source manifest in pinned SDK')
    sources = [engine / 'shell/platform/linux' / name for name in names]
    sources.append(engine / 'shell/platform/linux/fl_wayland_surface.cc')
    sources += [engine / 'shell/platform/common' / name for name in
                ['engine_switches.cc', 'isolate_scope.cc', 'text_editing_delta.cc', 'text_input_model.cc']]
    sources += [engine / 'fml' / name for name in
                ['logging.cc', 'log_settings.cc', 'log_settings_state.cc', 'string_conversion.cc']]
    sources.append(sdk / 'bin/cache/dart-sdk/include/dart_api_dl.c')
    manifest = cache / 'sources.cmake'
    manifest.write_text('set(FLUTTER_LINUX_SOURCES\n' + '\n'.join(cmake_quote(p) for p in sources) + '\n)\n')
    cmake_mode = {'debug': 'Debug', 'profile': 'RelWithDebInfo', 'release': 'Release'}[args.mode]
    build = cache / f'cmake-{args.mode}'
    subprocess.run(['cmake', '-S', str(HERE), '-B', str(build), '-G', 'Ninja',
                    f'-DCMAKE_BUILD_TYPE={cmake_mode}', f'-DENGINE_SRC={source_root}',
                    f'-DDART_INCLUDE={sdk / "bin/cache/dart-sdk/include"}',
                    f'-DRAPIDJSON_SRC={rapidjson}', f'-DENGINE_CORE={core}',
                    f'-DNATIVE_OUTPUT={output}', f'-DSOURCE_MANIFEST={manifest}',
                    f'-DBUILD_TESTING={"ON" if args.testing else "OFF"}'], check=True)
    subprocess.run(['cmake', '--build', str(build), '--parallel', '2'], check=True)
    app_mode = {'debug': 'Debug', 'profile': 'Profile', 'release': 'Release'}[args.mode]
    (output / 'build-mode.cmake').write_text(f'set(TSUMIRU_NATIVE_BUILD_MODE {app_mode})\n')
    shutil.copy2(sdk / 'bin/cache/pkg/sky_engine/LICENSE', output / 'ENGINE_LICENSE')
    print(f'Native engine ready: {output}')
    print(f'TSUMIRU_NATIVE_ENGINE_DIR={output} {sdk / "bin/flutter"} run -d linux --{args.mode}')


if __name__ == '__main__':
    main()
