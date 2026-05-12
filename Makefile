DEVICE = platform=iOS,name=tubli poisi iPhone
DEVICE_ID = 00008110-001119C83CE1801E
SCHEME = HueyIOS
PROJECT = HueyIOS.xcodeproj
BUNDLE_ID = com.larseckart.hueyios
SWIFT_SOURCES = Sources

.PHONY: generate compile build deploy uninstall test clean format lint

generate:
	xcodegen generate

compile:
	bash -o pipefail -lc "xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'generic/platform=iOS' -allowProvisioningUpdates build | xcbeautify"

build: generate compile

deploy: build
	@APP_PATH=$$(ls -td ~/Library/Developer/Xcode/DerivedData/HueyIOS-*/Build/Products/Debug-iphoneos/HueyIOS.app 2>/dev/null | head -1); \
	if [ -z "$$APP_PATH" ]; then echo "Error: App not found in DerivedData"; exit 1; fi; \
	xcrun devicectl device install app --device "$(DEVICE_ID)" "$$APP_PATH"

uninstall:
	xcrun devicectl device uninstall app --device "$(DEVICE_ID)" $(BUNDLE_ID)

test:
	bash -o pipefail -lc "xcodebuild test -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEVICE)' -allowProvisioningUpdates | xcbeautify"

clean:
	bash -o pipefail -lc "xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean 2>&1 | xcbeautify" || true

format:
	swift-format format --in-place --recursive $(SWIFT_SOURCES)

lint: format
	swift-format lint --strict --recursive $(SWIFT_SOURCES)
	swiftlint lint --strict --config .swiftlint.yml
	@# File length check (max 200 lines)
	@failed=0; for f in $$(find $(SWIFT_SOURCES) -name '*.swift'); do \
		lines=$$(wc -l < "$$f"); \
		if [ $$lines -gt 200 ]; then \
			echo "$$f: $$lines lines (max 200) - ask Lars"; failed=1; \
		fi; \
	done; exit $$failed
