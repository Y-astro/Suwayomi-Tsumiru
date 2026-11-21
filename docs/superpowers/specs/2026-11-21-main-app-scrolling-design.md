# Main-app scrolling design

## Scope

Implement backlog item 1 only. The user clarified that touchpad scrolling feels
bad in Library, while Updates and History touchpad behavior is fine. Mouse-wheel
scrolling feels rigid throughout the main app. The reader is perfect and must
not change. Items 2–5 remain queued.

## Evidence

Root independently reproduced instantaneous 53-pixel wheel jumps under
`AppScrollBehavior`. A standalone list starts a synthetic trackpad pan after
0.5 logical pixels; the same list inside `TouchTabPager` starts after 19 pixels.
Nested drag recognizers defer recognition until Flutter's touch-slop threshold.
This is synthetic routing evidence, not a physical-device latency measurement.

## Approach

Reuse the existing `MouseWheelSpeed` widget unchanged at the main navigation
scope, with speed 1. Resolve the innermost eligible vertical scroll target under
each wheel event, preserving nested routing and normal boundaries. Scope target
metadata to main navigation so reader routes retain their existing behavior.
Horizontal scrolling and non-mouse events retain their normal handling.

Lower the gesture threshold only inside desktop Library tab bodies. Keep the
horizontal tab pager outside that override, preserving deliberate horizontal tab
navigation. Do not tune touchpad physics in Updates or History.

Replacing controllers throughout the app or patching Flutter gesture recognition
would require wider changes. Global bouncing physics would neither solve wheel
jumps nor respect the user's request to preserve working touchpad behavior.

## Acceptance and delivery

Test multi-frame wheel motion, accumulated distance, reversal, nested targets,
boundaries, keyboard/scrollbar interruption, Shift/horizontal handling and reduced
motion. Reproduce small trackpad movement on the actual Library fixture and
preserve horizontal tab navigation. Reader source must be unchanged; run its
existing regression tests. Build the native release app and use an isolated
local-data runtime smoke. Push verified changes to the user's fork without a PR.
Preserve the running app and deploy the completed build for its next launch.

## Verification

All 992 Flutter tests passed. The final focused run passed 18 tests, including
the actual Library fixture with scrollable content, horizontal trackpad paging,
nested wheel target selection and boundary propagation, small wheel bursts,
interruption/disposal, Shift/horizontal input, reduced motion, mobile fallback,
unmodified behavior outside main navigation and direct fractional trackpad input.
Scoped Dart analysis found no issues.

Disabling the wheel scope makes the easing regression fail at 53 pixels on the
first frame. Restoring the Library's old gesture threshold makes its actual
screen regression fail at 19 pixels, exceeding the new 3-pixel acceptance bound.
Both temporary faults were restored before final verification.

An isolated release AOT harness with the real main-app scope and tab pager also
passed injected input checks: wheel offset was initially 0, approximately 23.56
pixels after 24 ms and 53 pixels after settling. A 2-pixel trackpad gesture moved
the inner Library-style list. The window rendered, resized and closed normally.
The private DBus session intentionally lacks accessibility/secret services and
logs related startup warnings; it is not a credential or accessibility audit.

The wheel follower targets ordinary downward vertical scrollables. Coordinated
`NestedScrollView` positions, reversed axes and horizontal scrolling keep their
existing platform wheel handling. The reader and native-engine sources are
unchanged. Physical touchpad/mouse feel still needs the user's check.

The full `lib/main.dart` release build also passed. Its isolated onboarding
startup rendered, resized and exited normally. Production credentials and library
state were not used in either runtime smoke.
