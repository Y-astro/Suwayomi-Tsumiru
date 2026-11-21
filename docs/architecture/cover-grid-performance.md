# Cached cover-grid performance

Follow-up to main-app scrolling on the 165 Hz Linux/Wayland display. The user
reported that Library remained slow, Updates was less affected, and History's
touchpad behavior was good. Loading covers added lag, but the loaded grid also
looked slow. The reader was to remain unchanged.

## Reproduction

An isolated release AOT harness scrolls 120 locally cached covers with fake
captions, the real `MangaCoverGridTile`, Tsumiru's theme and a fixed desktop window.
It warms each workload for five seconds and measures eight seconds of animation.
It does not call the server or use production account state. Compositor
`wp_presentation_feedback` measures displayed frames; Flutter frame counts are
not used as presentation-rate proof.

The original grid displayed **84.85 FPS**. Its median raster time was 8.85 ms and
95th percentile was 29.53 ms. An image-only grid was much cheaper. Temporarily
hiding titles or removing the gradient isolated the expensive title/scrim path.

## Experiments

| Experiment | Decision |
| --- | --- |
| Remove text shadow | Discarded: no reliable improvement; original styling restored. |
| Replace title ListTile with a simpler row | Discarded: no reliable improvement; original controls/layout restored. |
| Remove gradient | Diagnostic only: faster, but changes appearance. |
| Paint gradient only in its visible bottom third | Improved, but still missed the frame budget often. Superseded. |
| Use Flutter's raster-cache hint | Discarded: no improvement on this renderer. |
| Draw the scrim from one shared 1x256 alpha texture | Kept: preserves appearance and improves repeated presentation measurements. |

The retained texture replaces repeated gradient shading with image drawing.
Its painter retains the border, uses the original gradient while the texture is
unavailable, and guards asynchronous invalidation after disposal. The shared
texture has process lifetime; individual cover painters do not dispose it.
The optimization applies to overlaid cover titles without the separate dark
overlay, including Library and Updates grids. Reader source and native-engine
code are unchanged.

Repeated retained runs displayed **146.81 FPS** and **143.96 FPS**, approximately
70% above the baseline. Median raster times were 5.41 and 5.38 ms; 95th
percentiles were 9.63 and 9.52 ms. This is a cached-widget workload, not a claim
of sustained 165 FPS in every full-app workload. Some frames still exceed the
6.06 ms refresh budget; cold image loading is outside these measurements.

Pixel comparisons against the original decoration differ by at most one channel
value across integer/fractional geometry and light/dark backgrounds. Separate
tests preserve title and continue-button interaction at normal and doubled text
scale. Visual inspection checked the rendered cover grid.

## Related user-requested behavior

Desktop main-app sections now omit pull-to-refresh wrappers. Overscrolling the
top no longer refreshes or starts a library update. Explicit update controls are
unchanged, and the mobile pull gesture remains available. Input tests observe
the refresh callback before the change and verify it stays uncalled on desktop.

Main-navigation mouse-wheel distance increases from 1.0 to 1.7, matching the
reader's existing default. History and other sections retain their touchpad
path. This does not change reader settings or its scrolling implementation.

Raw run logs, discarded experiments and the local-data harness remain in ignored
`.superpowers/main-app-scrolling/`; no cached covers or screenshots are committed.

Final verification: all 997 Flutter tests passed, scoped Dart analysis found no
issues, and the full native release build passed. Isolated startup, resize and
normal-close smoke checks passed without production server or account state.
