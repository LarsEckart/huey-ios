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
- Includes refresh + reset pairing

## Build & Test

Requires Xcode 16+, iOS 18.0+, and Homebrew-installed tooling.

```bash
just generate   # regenerate Xcode project from project.yml
just build      # generate, format/lint, and build for device
just install    # build + install to device
just uninstall  # uninstall app from the device
just format     # format Swift sources in place
just lint       # format + strict swift-format + SwiftLint + file length check
just clean      # clean build artifacts
```

## Notes

- The app talks to the Hue bridge over local HTTP (`http://<bridge-ip>/api`).
- During setup, it may call Philips Hue's discovery service at `https://discovery.meethue.com/` to find your bridge IP address.
- It requests Local Network access on iOS.
- Pairing credentials are stored in `UserDefaults`.
