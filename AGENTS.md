# huey-ios

Minimal iOS app for toggling Hue rooms and zones.

## Commands

Use these `just` recipes for all routine work:

- Generate project: `just generate`
- Build (generate + compile): `just build`
- Test headless HueCore on macOS: `just test` (runs `swift test`; no simulator or device)
- Install on Lars's iPhone: `just install`
- Uninstall from device: `just uninstall`
- Format Swift sources: `just format`
- Lint Swift sources: `just lint` (formats first, then `swift-format` strict,
  SwiftLint, and the 200-line file length check; each check fails the recipe)
- Clean build artifacts: `just clean`

## Architecture

- `HueCore/` is a Swift package (iOS + macOS) that holds the headless domain
  and workflows: Hue groups, room/zone selection and ordering, brightness
  clamping, and the optimistic update/rollback workflow. It has no SwiftUI,
  UIKit, URLSession, or UserDefaults; it depends only on injectable effect
  interfaces (`HueBridgeClient`, `HueGroupCaching`, `HueDiscovering`,
  `HTTPTransport`).
- `HueGroupUpdater` is the single owner of the current group list. It owns the
  state and the reconciliation rules, so the UI never passes whole-list
  snapshots in and replaces them (that lost concurrent changes). It applies an
  optimistic edit per group before the network call suspends, publishes each
  snapshot (optimistic, resolved, refresh) through an `AsyncStream`, and
  resolves completions by group-ownership token + revision so a later call
  can't roll back an unrelated one. Rules stay here, not in the view model.
- `Sources/App/` is the iOS shell: SwiftUI views, the `LampsViewModel`
  presentation adapter (subscribes to the updater's snapshot stream and maps
  outcomes into observable state), and the composition root (`AppDependencies`
  + `URLSessionHTTPTransport`). Views receive ready-made, replaceable
  dependencies (a `HueGroupUpdater` or injected discovery/bridge factory) and
  never construct bridge/cache/discovery clients themselves.

Change a business rule in `HueCore`, prove it with `just test` (deterministic,
host-native, millisecond test bodies), then wire it into the shell. Do not put
reconciliation or product rules back into the view model, and keep every file
under 200 lines.
