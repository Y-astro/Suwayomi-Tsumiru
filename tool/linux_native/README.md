# App-local Linux engine

This opt-in build replaces Flutter's GTK GL presentation path with a Wayland EGL
subsurface. GTK continues to handle windows, input, accessibility and plugins.
Frame requests follow GTK's compositor-paced Cairo clock. The standard engine
and installed application are not modified.

The source patch is pinned to Flutter 3.47.9, engine
`89c39edfdfae2949f6806e4a315c0c08522238b7`. Updating Flutter requires reviewing
and retesting the patch. This is a custom embedder, not an upstream Flutter fix.

## Develop with hot reload

Install the pinned SDK and the repository's normal dependencies/code generation.
Additional native build tools are Python 3, Git, CMake, Ninja, patch, pkg-config,
wayland-scanner, and the development packages for GTK3, EGL, epoxy, X11,
wayland-client, wayland-egl and wayland-protocols.

```sh
export FLUTTER_ROOT=/path/to/flutter-3.47.9
export PATH="$FLUTTER_ROOT/bin:$PATH"
python3 tool/linux_native/build.py
export TSUMIRU_NATIVE_ENGINE_DIR="$PWD/build/linux_native/debug"
flutter run -d linux
```

The initial native build downloads the official standalone debug engine and
checks its SHA256. RapidJSON is fetched at Flutter's pinned Git revision. All
downloaded and generated files remain under `build/linux_native/`.

Edit Dart code and press `r` for hot reload. Use `R` when a change requires a
restart. After changing the native patch, stop the application, rebuild the
native engine and restart `flutter run`. Native changes cannot be hot reloaded.
Changed-library reloads with this shell took 1113 ms and 163 ms in two smoke
observations; those timings are not a performance guarantee.

Unset `TSUMIRU_NATIVE_ENGINE_DIR` to use the standard engine. The build rejects
mixing a debug native engine with a profile/release application.

## Check actual presentation

Run this inside the Wayland session:

```sh
python3 tool/linux_native/check.py
python3 tool/linux_native/check.py --lifecycle
```

The check uses the real `ZoomView` with local content. It bypasses normal app
startup, credentials, server calls and reading-progress writes. It checks native
FFI initialization, opaque output pixels, successful GL swaps and compositor
presentation feedback after ten seconds of warmup. It stops its own test process
and saves evidence in `build/linux_native/check.log`.
The lifecycle variant recreates the native presentation target five times while
rendering and checks that retained surfaces survive until their last reference.
This exercises surface ownership; it does not reparent GTK widgets or create a
second Flutter view.

On a high-refresh display, the acceptance threshold is over 100 displayed frames
per second. On slower displays it is 80% of the reported refresh rate. Lack of
presentation feedback is a failed verification, not evidence of success.

`TSUMIRU_NATIVE_TRACE=1` enables the native presentation diagnostics. Production
frame counters, successful swaps and compositor presentation timestamps describe
different stages; do not substitute one for another.

## Profile and release cores

The official archive used above contains a debug/JIT core. Profile and release
builds require a standalone AOT core built from the matching Flutter source.
Keep that checkout separate from the installed SDK. Follow Flutter's
[engine setup instructions](https://github.com/flutter/flutter/blob/main/docs/engine/contributing/Setting-up-the-Engine-development-environment.md).
For this revision, the Linux host release configuration is:

```sh
# From the separate Flutter checkout after gclient sync and gclient runhooks:
cd engine/src
python3 flutter/tools/gn --runtime-mode release --target-dir tsumiru_release \
  --enable-fontconfig --no-lto --no-rbe --no-goma
ninja -C out/tsumiru_release -j4 libflutter_engine.so
```

Use the host configuration above; adding `--target-os linux` currently hits an
ANGLE `wayland_dir` configuration error at this revision. Add depot_tools to PATH
for build actions, while retaining working system `python3` and `ninja` commands.
Fontconfig is enabled to retain system-font discovery in the desktop core.

Then, from Tsumiru:

```sh
export TSUMIRU_ENGINE_CORE=/path/to/engine/src/out/tsumiru_release/libflutter_engine.so
python3 tool/linux_native/build.py --mode release
TSUMIRU_NATIVE_ENGINE_DIR="$PWD/build/linux_native/release" flutter build linux --release
# Optional isolated AOT/FFI/presentation check with the same core:
python3 tool/linux_native/check.py --mode release --lifecycle
```

Use an independently built profile core with `--mode profile` for profiling.
The engine license is copied into the application bundle with the native core.

## Current verification boundary

The initial debug reader harness reached approximately 145–149 displayed FPS
across three runs on a 165Hz Hyprland display. After lifecycle fixes, the debug
check measured 161.69 displayed FPS. Three release AOT runs measured
159.51–164.61 displayed FPS, including window resize and normal-close checks.
Both passed five surface recreations and the native-to-Dart callback check.
These results do not establish full-reader image/network performance,
large-chapter behavior, or a universal 165 FPS guarantee. Multi-view and full GTK
reparenting behavior remain unverified; the current app uses one pacing view.
See [the investigation](../../docs/architecture/linux-frame-pacing.md) for the
baseline and remaining verification.
