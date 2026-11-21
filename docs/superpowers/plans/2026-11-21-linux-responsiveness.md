# Linux responsiveness implementation plan

> **For agentic workers:** Use the requested AGY worker for bounded setup and implementation, with Codex acceptance. Follow superpowers:executing-plans for task order and verification. Steps use checkboxes for tracking.

**Goal:** Improve reader touchpad responsiveness and frame presentation, then main-app scrolling, using measured changes.

**Architecture:** Keep Tsumiru's Flutter reader, existing image caching, and current server interfaces. Separate input handling from rendering and presentation measurements. Retain only targeted changes supported by a reproducible baseline.

**Tech stack:** Dart/Flutter 3.47.9, GTK3 Linux runner, existing Flutter tests.

**Spec:** `docs/superpowers/specs/2026-11-21-linux-responsiveness-design.md`

## Global constraints

- Prioritize reader touchpad behavior; defer features and unrelated fixes.
- Preserve installed AppImage, desktop entry, server settings, compositor settings, and reading progress.
- Use branch `perf/linux-touchpad` in this freshly cloned checkout.
- Push verified changes only to `https://github.com/Y-astro/Suwayomi-Tsumiru`; never create a PR without a specific request.
- Do not commit SDKs, generated Dart files, workstation paths, credentials, caches, traces, or unrelated formatting.
- Record commands, evidence, resource paths, and deviations in ignored `.superpowers/linux-responsiveness/progress.md`.

## Review focus

- Trackpad pan/zoom input must retain fractional movement and correct direction, independent of mouse-wheel smoothing.
- Pinch anchoring and fling interruption must work at scale 1 and when zoomed.
- Chapter boundaries, image-size corrections, and reversed/horizontal modes must retain position.
- Frame production counters must not be reported as actual presentation-rate proof.
- Development and performance runs must not mutate production preferences, library data, or reading progress.

## Task 1: Establish the development and measurement baseline

**Files:** Existing `.fvmrc`, `pubspec.yaml`, build workflows, `linux/my_application.cc`; ignored setup/profile artifacts only.

**Interfaces:** Produces the exact SDK command, reproducible build/test commands, isolated runtime environment, and baseline report consumed by Task 2.

- [x] Install the pinned Linux Flutter SDK in a user-owned directory; verify official archive checksum. Existing native dependencies are available through pkg-config. Do not upgrade system packages or substitute an incompatible SDK silently.
- [x] Run dependency resolution, localization generation, and build_runner using the checked-in workflow. Verify Linux build availability.
- [x] Run existing zoom, wheel, gesture, and continuous-reader regression tests before edits. Record failures by name.
- [x] Verify debug hot reload with a temporary visible Dart change, restore it, and leave the development command reproducible.
- [ ] Build a profile target. Isolate local data and prevent server writes; use existing fixture/provider overrides for a local reader workload if necessary.
- [ ] Capture repeated touchpad-input and GTK presentation traces under the current compositor. Also capture cached reader scrolling versus page/image loading. Label proxies and limitations explicitly.
- [ ] Record baseline frame-time distribution, presentation cadence where observable, CPU/memory, exact environment and workload. Choose target thresholds before changing product code.
- [ ] Stop this task with the exact blocker if the SDK or trustworthy measurement path is unavailable. Do not invent performance findings.

## Task 2: Fix the first demonstrated bottleneck

**Candidate files:** `lib/src/widgets/zoom/zoom_view.dart`, `lib/src/features/manga_book/presentation/reader/widgets/reader_mode/infinity_continuous/multichapter_continuous_reader_mode.dart`, `lib/src/features/manga_book/presentation/reader/widgets/mouse_wheel_speed.dart`, `linux/my_application.cc`. These are candidates, not permission to change every file.

**Tests:** Extend the closest existing file in `test/src/widgets/zoom/` or `test/src/features/manga_book/reader/`; use a native runtime regression check for a demonstrated runner issue.

**Interfaces:** Consumes Task 1's workload and measured cause. Preserves existing reader settings, provider contracts, server calls, and public widget interfaces.

- [x] Trace the measured cause through all callers. Write the narrow failing behavior test and observe the expected failure before a non-trivial fix.
- [x] Apply one minimal fix. Preserve touchpad direct tracking, pinch, fractional input, boundaries, and mouse behavior. Do not add generic smoothing or caching already present.
- [x] Re-run the focused test, related reader/zoom tests, analyzer for touched paths, and applicable build. Compare exactly the baseline workload in repeated runs.
- [x] Keep only a change exceeding the predeclared target without regression. Revert only owned experiment changes if it fails. Document the result and any native-presentation limit.
- [x] Measure the next bottleneck before another experiment; pursue main-app scrolling only after the reader result is established.

## Task 3: Verify and deliver

**Files:** Retained source/test diff and concise reusable development instructions, if needed. Keep local profiles and machine-specific setup in ignored artifacts.

**Interfaces:** Produces a verified commit on the user's fork and a transparent evidence ledger.

- [x] Run `flutter test` and the Linux build on the final state. Record any baseline failures separately and do not claim a green suite if failures remain.
- [x] Review the complete diff for correctness, five review-focus cases, secret leakage, generated churn, and scope. Use one independent review when code changes warrant it.
- [ ] Verify input-driven reader behavior, native presentation where claimed, main-app mouse/touchpad behavior after shared changes, and detached runtime survival.
- [x] Commit retained work with the configured user identity. Push `perf/linux-touchpad` to `origin` without force; verify the remote commit. Do not create a PR.
- [x] Report measured before/after results, development/hot-reload command, commit/branch link, skipped checks, and residual limits. Do not claim perfect optimization or 165 FPS without measurement.


## Execution notes

The confirmed bottleneck was native GTK GL presentation. The user approved an
app-local embedder after the 60 Hz cap was reproduced with independent controls.
The retained code changes the shared presentation path; no speculative reader
smoothing, cache wrapper or new feature was added.

The safe local-content `ZoomView` harness replaces automated production chapter
runs because normal startup can access the shared system keyring. Release AOT
verification supersedes the initial profile-only step. Compositor presentation
feedback provides the decisive measurement: 159.51–164.61 displayed FPS in three
release runs on the 165 Hz panel. Five surface recreations, native-to-Dart FFI,
resize requests and normal closes passed. The full app also built, displayed
onboarding and closed normally with isolated XDG directories and a private DBus
session without service activation. That session intentionally lacks the secret
service and logs related plugin warnings; it does not verify credential access.

Final Dart analysis passed and all 981 Flutter tests passed. The native hardware
check failed under a temporary blank-buffer fault and passed after restoration.
One independent native review was completed; surface lifetime and idle-source
ownership findings were fixed and verified locally.

Unchecked workload items remain explicit limits, not implied acceptance:
physical touchpad gestures, image/network-heavy chapters, finger-to-display
latency, full GTK reparenting, multiple views/monitors and suspend/resume. No
production server or reading-progress data was used for the automated runs.
See `docs/architecture/linux-frame-pacing.md` for the evidence and
`tool/linux_native/README.md` for reproducible development and build commands.
