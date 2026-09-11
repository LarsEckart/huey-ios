# HueCore test loop timing

Measured on Lars's machine (Apple Silicon, Swift 6.3.3, Xcode 26.6) on `main`
with the headless HueCore package in place.

## Commands

| Command | Wall time | What it does |
|---|---|---|
| `just test` | ~0.4 s (warm) | headless HueCore suite on macOS |
| `swift test` (warm) | ~0.43 s | full 44-test suite, cache warm |
| `swift test --filter GroupSelectionTests` (warm) | ~0.42 s | focused edit-test loop |
| cold build + full suite | several seconds | SwiftPM compile from a clean `.build` |

The edit-test loop is the warm `swift test --filter <RuleTest>` path at under
half a second of wall time — no simulator, device, app host, or live network is
involved.

## Test-body time (wall, warm)

The whole host-native suite (44 tests across `GroupSelection`, `Brightness`,
`HueGroupUpdater`, `HueBridgeHTTPClient`, and `HueDiscoveryClient`) executes
its test bodies in **~0.010 s total** (`swift test` reports `Executed 44 tests
... in 0.007 (0.010) seconds`). Individual rule test bodies run in
milliseconds (most report `0.000 s`), comfortably under the issue's
"milliseconds" bar.

The concurrent/optimistic behavior is covered deterministically with a
suspended fake bridge client (`SuspendingBridgeClient`): tests inspect the
updater's optimistic state *while* a request is pending, then complete
overlapping updates/refreshes in a chosen order. These tests use no sleeps or
live waits — they run in milliseconds with the rest of the suite.

## Coverage boundaries

Not claimed as fully covered:

- Suspended-fake concurrency is exercised for the specific scenarios tested
  (overlapping group success/failure in both completion orders, refresh
  overlap, same-group rapid edits). It is not a proof of every interleaving.
- No iOS UI/simulator/device test target exists. App-shell wiring (`RootView`,
  `SetupView`, `LampsViewModel`'s stream subscription) and SwiftUI behavior
  are not covered by tests in this deliverable.
- HTTP mapping tests assert request URL/headers/timeout/body and mutation
  errors against the fake transport; they are not live-network tests.

## iOS testing scope

This repository had no test target and no existing tests before this change, so
business-rule coverage is hosted in the headless `HueCore` package rather than
in an iOS test target. All product rules that were previously inside
`LampsViewModel` now live in `HueCore` and are covered by deterministic
host-native tests (`swift test`), which need no app host, simulator, device, or
live network.

The issue calls for iOS tests that stay focused on dependency wiring and
SwiftUI behaviour. That wiring is thin: the composition root (`AppDependencies`)
builds a `URLSessionHTTPTransport`, `HueBridgeHTTPClient`, `HueDiscoveryClient`,
and UserDefaults-backed `HueGroupCache`; `LampsView`/`SetupView` receive
ready-made, replaceable dependencies. `LampsViewModel` subscribes to the
updater's snapshot stream and maps outcomes into `@Published` state. Because
the non-UI behaviour is covered headlessly, no new iOS/xcodebuild test target
was added. An Xcode UI/integration test target for shell wiring and SwiftUI
rendering remains an optional follow-up; this deliverable does not claim to
have run such tests.
