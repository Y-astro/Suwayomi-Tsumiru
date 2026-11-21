# Linux frame-pacing investigation

## Scope and result

Investigated Tsumiru v1.6.5 on a 1920x1200, 165.004 Hz, scale-1 display under
Hyprland/Wayland, using Flutter 3.47.9 and GTK 3.24.52. The bundled engine is
`89c39edfdfae2949f6806e4a315c0c08522238b7`.

The isolated reader-input harness uses the application's real `ZoomView` around
a local list. It avoids normal startup, storage, credentials, and server calls.
Three five-second Wayland runs reported a steady GTK clock interval of 16667 us
and matching draw callbacks. Samples were logged initially and every 30 ticks;
these logs are not a complete frame-time distribution. One Xwayland run reported
the same interval.

An independent native control reproduced the distinction:

| Control | Observed steady clock interval | Approximate cadence |
| --- | --- | --- |
| Cairo drawing area on Wayland | 6060 us | 165 Hz |
| Drawing area after creating a GDK GL context | 16667 us | 60 Hz |
| Flutter GL view with continuous GTK redraws | 16667 us | 60 Hz |

These measurements establish a GTK scheduling limitation on this machine.
They do not measure physical presentation timestamps, full-reader image loading,
or end-to-end finger-to-display latency. They do not prove this is the only
source of reader stutter.

## What the source already does

- `fl_scrolling_manager.cc` in the matching engine classifies a
  `GDK_SOURCE_TOUCHPAD` as pan/zoom input, preserving floating-point deltas.
- `ZoomView` has a trackpad gesture path.
- `MouseWheelSpeed` smooths mouse scroll events and leaves trackpad events alone.
- `ServerImage` already implements decode dimensions and resize debouncing.

The source supports the expected routing. Capturing a real device gesture is
still necessary to verify the complete input route on a particular machine.
Adding another smoothing layer or another image-resize wrapper is not justified
by this investigation.

## Development versus performance measurement

Ordinary Dart changes can be hot reloaded after an initial Linux debug build.
An actual text change in the isolated harness reloaded one library in 323 ms;
restoring it reloaded one library in 274 ms. Those are individual development
smoke observations, not a speed guarantee.
With the custom shell, a changed-library reload took 1113 ms and restoring the
text took 163 ms. Both reloaded one library while the native process stayed live.

Use profile/release builds for performance comparisons. A normal application
launch can initialize secure storage and migrate data; changing XDG paths alone
does not isolate a shared system keyring. Diagnostic harnesses should bypass
normal startup entirely and use local content without server writes.

## Native work required for high refresh

Flutter's Linux embedder does not install `FlutterProjectArgs.vsync_callback`
in the inspected revision. GTK's GL presentation clock and the engine's fallback
scheduler both need attention. Increasing a Flutter frame-production counter
alone can render extra frames that never reach the display.

Any native solution must be app-scoped, follow display/compositor timing, handle
resize and shutdown safely, preserve the standard-engine fallback, and measure
the last presentation stage it changes. Do not patch system GTK or hard-code
165 Hz globally. An official prebuilt standalone embedder archive exists for
this engine revision. Rebuilding only the GTK shell works with that debug core;
the release core must be built separately from matching engine source.

Relevant upstream evidence:

- [Flutter high-refresh investigation](https://github.com/flutter/flutter/issues/183703)
- [Linux frame-pacing tracking issue](https://github.com/flutter/flutter/issues/191245)
- [Custom embedder documentation](https://github.com/flutter/flutter/blob/master/docs/engine/Custom-Flutter-Engine-Embedders.md)

## Verification ledger

Verified: SDK/engine version, existing debug/profile build artifacts, 69 focused
reader/zoom tests, changed-library hot reload, and native Cairo/GL clock controls.
At the initial baseline no performance patch had been retained. The native
candidate results below record subsequent presentation and test verification.
Profile-mode reader metrics, real-device touchpad traces, and the complete-app
workload remain outside the initial baseline.

## Native candidate results

A custom GTK shell now links against the exact official standalone engine core.
It initializes Dart's public dynamic API before using native isolate callbacks,
keeps GTK input handling, schedules engine frame requests from GTK's Cairo clock,
and presents GL frames through a desynchronized Wayland child surface. The
standard-engine path remains the default unless explicitly selected at build
time. Source patches and build/check commands live in `tool/linux_native/`.

The first candidate produced successful EGL swaps with blank output. Reading
back the source and output buffers showed opaque source pixels and transparent
output pixels. Selecting `GL_BACK` explicitly for the window framebuffer fixed
the surfaceless-context draw-buffer state. Removing that fix makes the real
native hardware check fail with `Window buffer is blank`; restoring it enables
visible output. Screenshot inspection also checked text orientation and layout.

Wayland `wp_presentation_feedback` then confirmed the following displayed-frame
rates after warmup, independently of engine tick and swap counters:

| Run | Displayed FPS | Measured interval | Discarded updates by final sample |
| --- | ---: | ---: | ---: |
| 1 | 149.15 | 13.28 s | 29 |
| 2 | 145.87 | 8.64 s | 17 |
| 3 | 145.03 | 7.86 s | 12 |

A separate run through the portable build/check commands measured 147.87
displayed FPS. Feedback reported a 6060459 ns refresh interval, approximately
165 Hz. These measurements use the debug/JIT core and a local-content `ZoomView`
harness; they do not establish full-reader or release performance. Some updates
were discarded rather than displayed, so this is not a sustained 165 FPS claim.

An independent review found native surface-lifetime, unrealize cleanup,
presentation-object ownership, and cancelled-idle-source reference problems.
The retained fix uses reference-counted presentation targets: in-flight EGL work
keeps its surface alive without holding the GTK mutex across a blocking swap.
Unrealize detaches the target, each target owns its presentation object, and the
vsync idle source has a destroy notifier. The compositor remains stable across
target recreation.

After these fixes, the debug lifecycle check measured 161.69 displayed FPS.
A matching release AOT core built with desktop Fontconfig support also passed
the real native-to-Dart callback check and five surface recreations during
animation. Repeated release measurements were:

| Run | Displayed FPS | Measured interval | Discarded updates by final sample |
| --- | ---: | ---: | ---: |
| Lifecycle check | 159.51 | 9.40 s | 58 |
| Resize and close 1 | 164.61 | 8.75 s | 10 |
| Resize and close 2 | 164.61 | 8.75 s | 10 |

The resize runs requested 480x360, 320x240 and 960x700 windows and closed normally
with exit status 0. Screenshot inspection verified visible text and orientation.
Shutdown still logs the stock embedder's rejection of removing the implicit
view; no crash or failed surface presentation accompanied it.

The final full Flutter suite passed 981 tests. Targeted Dart analysis found no
issues. Both custom-engine and standard-engine full release builds passed.
The custom full app displayed onboarding, resized and exited normally in an
isolated XDG profile on a private DBus session without service activation.
That session intentionally lacks the secret service, producing libsecret/plugin
warnings; credential access was not tested. The installed AppImage and desktop
launcher stayed unchanged.

Performance checks cover a local-content reader harness, not real device
input, image/network-heavy chapters or finger-to-display latency. Multiple
Flutter views, full GTK widget reparenting/re-realization, multi-monitor movement,
and suspend/resume remain unverified. One pacing view per engine is the current
app-scoped limit.
