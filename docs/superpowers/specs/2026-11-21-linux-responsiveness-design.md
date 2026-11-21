# Linux responsiveness design

Status: approved by the user on 2026-11-21.

## Intent

Make Tsumiru feel responsive and smooth on this laptop. Prioritize touchpad
scrolling in the reader, then scrolling and navigation in the main app. New
features and unrelated correctness fixes are deferred.

## Verified baseline

- Source checkout: `v1.6.5`, commit `c01ad2562fbc124d4f63a49664c6e3018c14616c`.
- Installed application: v1.6.5 AppImage, build 5006.
- Display: 1920x1200 at 165.004 Hz, scale 1, VRR enabled.
- Repository pins Flutter 3.47.9 in `.fvmrc`; Flutter and Dart are absent from PATH.
- Installed engine exports `fl_dart_project_set_enable_impeller`; the app runner
  does not import that function. Earlier `--no-enable-impeller` launch still
  reported Impeller.
- Reader code already includes mouse-wheel smoothing, a separate trackpad gesture
  path, image decode limits, and page-size anchoring. Their runtime behavior has
  not been measured.

## Approaches

1. **Measure input and presentation, then make targeted changes (recommended).**
   Establish a baseline in a profile build. Separate input handling, image/layout
   work, and actual GTK/Wayland presentation pacing. Change the narrowest proven
   bottleneck and compare the same workload. This takes initial setup but avoids
   treating source-code hypotheses as established causes.
2. **Change the engine or GTK integration first.** This may address a confirmed
   presentation cap, but requires native rebuilds and adds maintenance. Reserve
   it for measurements showing the app-level path cannot meet the refresh goal.

The user approved the recommended staged approach.

## Development workflow

Use the pinned SDK and an initial Linux debug build for development. Keep the
process running and hot reload ordinary Dart changes. Native runner/engine
changes require rebuilding; some Dart initialization changes require restart.
Generate localization and Dart sources initially, then regenerate only when
their inputs change. Use profile/release builds to judge performance, since
debug-mode timings do not represent shipped performance.

Use an isolated development profile for preferences, cache, and local reading
state. Do not replace the installed AppImage or its desktop launcher. Check
server-write behavior before reader benchmarks so automated runs do not change
reading progress. Server and compositor configuration remain unchanged.

## Measurements and acceptance

Record repeated runs with the same chapter, window size, device, build, and cache
state. Separate cached-image scrolling from image-loading runs. Capture input
classification, frame-time distributions, long frames, presentation cadence,
CPU and memory. At 165.004 Hz, refresh intervals are approximately 6.06 ms;
confirm actual presentation independently of Flutter's reported frame rate.

Preserve direct touchpad tracking, pinch-to-zoom, direction reversal, fling
interruption, page/chapter boundaries, layout anchoring, and reading progress.
Check mouse behavior after shared changes. Use focused existing tests and add
regression coverage only for changed behavior. Keep an optimization only when
repeatable measurements improve its target beyond noise without these
regressions. Establish numerical improvement thresholds after the baseline and
before editing the affected code.

## Limits at design approval

No performance improvement or 165 FPS result is proven yet. GTK/Flutter upstream
reports suggest a presentation limit worth testing; changing scroll physics or
renderers alone does not establish a fix. Prepare the implementation plan and
set up the development/profile workflow.

## Delivery

Push verified changes to `https://github.com/Y-astro/Suwayomi-Tsumiru` on
`perf/linux-touchpad`. Do not create a pull request unless the user explicitly
requests one. Preserve the installed application and workstation defaults.

## Approved native investigation

The user selected native high-refresh support after GTK GL controls reproduced
the 16667 us clock interval on the 165 Hz display. Investigate an app-local Linux
embedder using the exact official standalone engine core and a rebuilt GTK shell
before considering a full Dart/Skia rebuild. Preserve plugin/FFI compatibility,
the normal-engine fallback, and hot reload. No global GTK or compositor changes.
Keep custom source patches and build inputs reproducible in the app fork; do not
commit downloaded libraries or SDKs. Measure frame production, renderer output,
and compositor presentation separately before claiming a high-refresh result.


## Execution result

The approved native path now has an opt-in build, release AOT verification and
compositor presentation evidence. See
[the investigation](../../architecture/linux-frame-pacing.md) for results and
remaining limits. The installed AppImage and workstation defaults are preserved.
