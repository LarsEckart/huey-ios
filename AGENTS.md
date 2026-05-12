# huey-ios

Minimal iOS app for toggling Hue rooms and zones.

## Commands

Use these Make targets for all routine work:

- Generate project: `make generate`
- Compile app (generic iOS): `make compile`
- Build (generate + lint + compile): `make build`
- Deploy to Lars's iPhone: `make deploy`
- Uninstall from device: `make uninstall`
- Run tests on device: `make test`
- Format Swift sources: `make format`
- Lint Swift sources: `make lint` (formats first, then runs swift-format, SwiftLint, and the 200-line file length check)
- Clean build artifacts: `make clean`
