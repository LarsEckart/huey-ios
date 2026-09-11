[![Certified Shovelware](https://justin.searls.co/img/shovelware.svg)](https://justin.searls.co/shovelware/)

# Huey iOS

Minimal iOS app for toggling Philips Hue rooms and zones.

Built from the same Hue bridge API behavior used in:
- `~/GitHub/huey` (CLI)
- `~/GitHub/huey-win` (Windows GUI)

## What it does

- First-run setup: auto-detect bridge IP and pair via bridge button press
- Fetches all Hue **groups** of type `Room` or `Zone`
- Shows one toggle per room/zone and toggles the whole group on/off
- Includes brightness sliders, refresh, and reset pairing
- Toggles and brightness edits apply optimistically and roll back on failure

## Architecture

The business behaviour lives in the **HueCore** Swift package (`HueCore/`), an
iOS + macOS library with no SwiftUI, UIKit, URLSession, or UserDefaults. It
owns the Hue domain values, room/zone selection and ordering, brightness
clamping, and the optimistic update/rollback workflow, plus the small effect
interfaces those workflows depend on (`HueBridgeClient`, `HueGroupCaching`,
`HueDiscovering`, `HTTPTransport`).

`HueGroupUpdater` is the single owner of the current group list. It reads the
list, applies each optimistic edit per group *before* the network call
suspends, publishes every snapshot (optimistic, resolved, refresh) through an
`AsyncStream`, and reconciles concurrent completions by group-ownership token
and revision — so toggling one room never overwrites another's change, and a
failed request never undoes an unrelated success or a fresher refresh. The UI
subscriptes to the snapshot stream, so it sees the intent immediately and can
restore a locally edited slider on rollback.

The iOS app (`Sources/App/`) is a thin shell: SwiftUI views render state and
send intent, `LampsViewModel` maps workflow outcomes into observable
presentation state, and the composition root (`AppDependencies` +
`URLSessionHTTPTransport`) builds the concrete URLSession/UserDefaults
adapters. Views receive ready-made, replaceable dependencies (a
`HueGroupUpdater`, or an injected discovery client and bridge-client factory in
`SetupView`) and never construct bridge, discovery, or cache clients.

```text
iOS shell (SwiftUI views, LampsViewModel, composition root)
        ↓
HueCore package (domain values, group selection, brightness,
                optimistic update/rollback workflow, effect interfaces)
        ↑
Platform adapters (URLSession transport, UserDefaults group cache)
```

## Build & Test

Requires Xcode 16+, iOS 18.0+, and Homebrew-installed tooling.

```bash
just generate   # regenerate Xcode project from project.yml
just build      # generate + compile for device
just test       # run headless HueCore tests on macOS (no simulator/device/network)
just install    # build + install to device
just uninstall  # uninstall app from the device
just format     # format Swift sources in place
just lint       # format + strict swift-format + SwiftLint + file length check
just clean      # clean build artifacts
```

`just test` runs `swift test` inside `HueCore/` and is the tight edit-test
loop for business rules: it needs no iOS host, simulator, device, or live
network, and focused rule tests run in milliseconds. A suspended fake bridge
client drives deterministic concurrent-update and optimistic-state tests with
no sleeps or live waits. Test fixtures and a fake HTTP transport cover
request/response mapping (including exact URLs, headers, timeouts, and bodies)
without calling the bridge.

## Notes

- The app talks to the Hue bridge over local HTTP (`http://<bridge-ip>/api`).
- Registration always posts to `http://<bridge-ip>/api` (username-independent);
  authenticated calls use `/api/<username>`.
- During setup, it may call Philips Hue's discovery service at
  `https://discovery.meethue.com/` to find your bridge IP address.
- It requests Local Network access on iOS.
- Pairing credentials are stored in `UserDefaults`.
- `HueGroupCache` persists the group list to `UserDefaults` per
  bridge/username pairing.
