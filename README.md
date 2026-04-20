# Huey iOS

Minimal iOS app for toggling Philips Hue rooms and zones.

Built from the same Hue bridge API behavior used in:
- `~/GitHub/huey` (CLI)
- `~/GitHub/huey-win` (Windows GUI)

## What it does

- First-run setup: enter bridge IP and pair via bridge button press
- Fetches all Hue **groups** of type `Room` or `Zone`
- Shows one toggle per room/zone and toggles the whole group on/off
- Includes refresh + reset pairing

## Build

```bash
cd ~/GitHub/huey-ios
xcodegen generate
open HueyIOS.xcodeproj
```

Or build from CLI:

```bash
xcodebuild \
  -project HueyIOS.xcodeproj \
  -scheme HueyIOS \
  -destination 'generic/platform=iOS Simulator' \
  build
```

## Notes

- The app talks to the Hue bridge over local HTTP (`http://<bridge-ip>/api`).
- It requests Local Network access on iOS.
- Pairing credentials are stored in `UserDefaults`.
