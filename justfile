set dotenv-load

project := "HueyIOS.xcodeproj"
scheme := "HueyIOS"
derived_data := ".build/DerivedData"
team_id := env_var_or_default("DEVELOPMENT_TEAM", "5N98B42MGR")
device_udid := "00008110-001119C83CE1801E"
device := "platform=iOS,name=tubli poisi iPhone"
bundle_id := "com.larseckart.hueyios"
source_dirs := "Sources"

# Default recipe listing
_default:
	@just --list

# Regenerate the Xcode project from project.yml
@generate:
	#!/usr/bin/env bash
	set -euo pipefail
	xcodegen generate 2>&1 | xcagentify

# Build the app for a generic iOS device
@build: generate
	#!/usr/bin/env bash
	set -euo pipefail
	xcodebuild \
		-project "{{project}}" \
		-scheme "{{scheme}}" \
		-destination 'generic/platform=iOS' \
		-derivedDataPath "{{derived_data}}" \
		-allowProvisioningUpdates \
		DEVELOPMENT_TEAM="{{team_id}}" \
		build 2>&1 | xcagentify

# Build and install on Lars's iPhone
install: build
	#!/usr/bin/env bash
	set -euo pipefail
	APP_PATH=$(find "{{derived_data}}/Build/Products/Debug-iphoneos" -name 'HueyIOS.app' -type d | head -n 1)
	if [ -z "$APP_PATH" ]; then
		echo "Could not find HueyIOS.app in {{derived_data}}"
		exit 1
	fi
	echo "Installing $APP_PATH on device {{device_udid}}..."
	xcrun devicectl device install app --device "{{device_udid}}" "$APP_PATH"

# Uninstall from Lars's iPhone
@uninstall:
	xcrun devicectl device uninstall app --device "{{device_udid}}" "{{bundle_id}}"

# Format Swift code in place
@format:
	swift-format format --in-place --recursive {{source_dirs}}

# Lint Swift sources (format first, then fail if anything needs fixing)
@lint: format
	swift-format lint --strict --recursive {{source_dirs}}
	swiftlint lint --strict --config .swiftlint.yml
	# File length check (max 200 lines)
	failed=0; for f in $(find {{source_dirs}} -name '*.swift'); do \
		lines=$(wc -l < "$f"); \
		if [ $lines -gt 200 ]; then \
			echo "$f: $lines lines (max 200) - ask Lars"; failed=1; \
		fi; \
	done; exit $failed

# Clean build artifacts
clean:
	xcodebuild -project "{{project}}" -scheme "{{scheme}}" clean 2>&1 | xcagentify || true
	rm -rf "{{derived_data}}" .build
