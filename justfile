# Reqeast build tasks

# Build the Rust library and generate Swift bindings (XCFramework for macOS + iOS)
build-rust:
    cd rust && ./build-xcframework.sh

# Clean Rust build artifacts
clean-rust:
    cd rust && cargo clean
    rm -rf ReqeastCore

# Check Rust code
check-rust:
    cd rust && cargo check

# Run Rust tests
test-rust:
    cd rust && cargo test

# Regenerate spec import golden fixtures from parse_spec output
update-spec-goldens:
    cd rust && UPDATE_SPEC_GOLDENS=1 cargo test update_spec_goldens -- --ignored --nocapture

# Regenerate Swift mapper project.json goldens from normalized fixtures
update-spec-project-goldens:
    python3 scripts/generate_spec_project_goldens.py

# Run spec import criterion benchmarks
bench-spec-import:
    cd rust && cargo bench --bench spec_import

# Run spec import performance gate (AC4; opt-in — not part of test-all)
test-spec-perf:
    xcodebuild test -project Reqeast.xcodeproj -scheme Reqeast -only-testing:ReqeastTests/SpecImportPerformanceTests -destination 'platform=macOS' -parallel-testing-enabled NO SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) RUN_SPEC_PERF' -quiet

# Refresh stress-500 Swift performance baseline (writes fixture JSON when sandbox allows)
update-spec-perf-baseline:
    UPDATE_SPEC_PERF_BASELINE=1 just test-spec-perf

# Run CKAsset validation harness (T39 spike; opt-in — not part of test-all)
test-ckasset-harness:
    xcodebuild test -project Reqeast.xcodeproj -scheme Reqeast -only-testing:ReqeastTests/CKAssetValidationHarnessTests -destination 'platform=macOS' -parallel-testing-enabled NO SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) RUN_CKASSET_HARNESS' -quiet

# Record CKAsset harness timings to fixture JSON (non-gating spike)
record-ckasset-harness:
    RECORD_CKASSET_HARNESS=1 just test-ckasset-harness

# Format Rust code
fmt-rust:
    cd rust && cargo fmt

# Lint Rust code
lint-rust:
    cd rust && cargo clippy -- -D warnings

# Run Swift unit tests (macOS)
test-swift:
    xcodebuild test -project Reqeast.xcodeproj -scheme Reqeast -only-testing:ReqeastTests -destination 'platform=macOS' -quiet

# Run Swift unit tests (iOS Simulator)
test-swift-ios:
    xcodebuild test -project Reqeast.xcodeproj -scheme Reqeast -only-testing:ReqeastTests -destination 'platform=iOS Simulator,name=iPhone 17' -quiet

# Run UI tests (macOS); screenshot capture is opt-in (see test-ui-screenshots)
test-ui:
    xcodebuild test -project Reqeast.xcodeproj -scheme Reqeast -only-testing:ReqeastUITests -skip-testing:ReqeastUITests/ScreenshotTests -destination 'platform=macOS' -parallel-testing-enabled NO -quiet

# Run UI tests (iOS Simulator); screenshot capture is opt-in
test-ui-ios:
    xcodebuild test -project Reqeast.xcodeproj -scheme Reqeast -only-testing:ReqeastUITests -skip-testing:ReqeastUITests/ScreenshotTests -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO -quiet

# Run marketing screenshot UITests only (slow; used by screenshots-capture)
test-ui-screenshots:
    xcodebuild test -project Reqeast.xcodeproj -scheme Reqeast -only-testing:ReqeastUITests/ScreenshotTests -destination 'platform=macOS' -parallel-testing-enabled NO SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) RUN_SCREENSHOT_TESTS' -quiet

# Run all non-network tests
test-all: test-rust test-swift

# Build for iOS (generic device)
build-ios:
    xcodebuild build -project Reqeast.xcodeproj -scheme Reqeast -destination 'generic/platform=iOS' -quiet

# Build for iOS Simulator
build-ios-sim:
    xcodebuild build -project Reqeast.xcodeproj -scheme Reqeast -destination 'platform=iOS Simulator,name=iPhone 17' -quiet

# Generate open source license bundle from Rust dependencies
generate-licenses:
    cd rust && cargo bundle-licenses --format json --output ../Reqeast/Resources/licenses.json

# Bundle curlconverter JS for JavaScriptCore
bundle-curlconverter:
    cd scripts/curlconverter && npm install && npm run bundle

# Generate missing dSYM for CodeLanguages_Container in macOS Reqeast archives (skip iOS)
fix-dsym:
    #!/bin/sh
    set -e
    # Paths contain spaces; use find + sort by mtime, not unquoted ls/glob expansion.
    find "$HOME/Library/Developer/Xcode/Archives" -name 'Reqeast*.xcarchive' -type d -print0 2>/dev/null \
      | xargs -0 stat -f '%m %N' \
      | sort -rn \
      | head -4 \
      | while read -r _mtime archive; do
          binary="$archive/Products/Applications/Reqeast.app/Contents/Frameworks/CodeLanguages_Container.framework/Versions/A/CodeLanguages_Container"
          if [ ! -f "$binary" ]; then
            echo "Skip (no CodeLanguages_Container): $(basename "$archive")"
            continue
          fi
          echo "Archive: $(basename "$archive")"
          xcrun dsymutil "$binary" -o "$archive/dSYMs/CodeLanguages_Container.framework.dSYM"
          echo "dSYM generated. UUIDs:"
          xcrun dwarfdump --uuid "$archive/dSYMs/CodeLanguages_Container.framework.dSYM"
        done

# Archive, fix dSYM, and upload to App Store Connect
deploy: _archive fix-dsym _upload

_archive:
    xcodebuild archive \
      -project Reqeast.xcodeproj \
      -scheme Reqeast \
      -destination 'generic/platform=macOS'
    xcodebuild archive \
      -project Reqeast.xcodeproj \
      -scheme Reqeast \
      -destination 'generic/platform=iOS'

_upload:
    #!/bin/sh
    set -e
    find "$HOME/Library/Developer/Xcode/Archives" -name 'Reqeast*.xcarchive' -type d -print0 2>/dev/null \
      | xargs -0 stat -f '%m %N' \
      | sort -rn \
      | head -2 \
      | while read -r _mtime archive; do
          echo "Uploading: $(basename "$archive")"
          xcodebuild -exportArchive \
            -archivePath "$archive" \
            -exportOptionsPlist ExportOptions.plist \
            -allowProvisioningUpdates
        done

# Build the MCP server npm package
build-mcp:
    cd reqeast-mcp && npm install && npm run build

# Publish MCP server to npm
publish-mcp:
    cd reqeast-mcp && npm publish

# Marketing screenshots — full playbook: scripts/SCREENSHOTS.md
# Partial: LANGS=en DEVICES=ipad11,iphone just screenshots-capture
#          LANGS=en just screenshots-compose

# Capture raw screenshots (all langs/devices unless LANGS=/DEVICES= set)
screenshots-capture:
    bash scripts/capture-screenshots.sh

# Hard gate: geometry, empty demo sidebars, missing ipad11 multi raws
screenshots-validate:
    bash scripts/validate-screenshots.sh

# Compose final marketing images (validates raws first, finals after)
screenshots-compose:
    bash scripts/compose-screenshots.sh

# Full screenshot pipeline: capture + compose (+ validate in both scripts)
screenshots: screenshots-capture screenshots-compose

# Compose only (skip capture; still validates raws)
screenshots-quick: screenshots-compose

# Download existing metadata from App Store Connect into fastlane/metadata/
deliver-download:
    fastlane deliver download_metadata --metadata_path ./fastlane/metadata

# Prepare screenshots for fastlane deliver (copies from screenshots/final/ to fastlane/screenshots/)
deliver-prepare-screenshots:
    bash scripts/prepare-screenshots-for-deliver.sh

# Upload metadata only to App Store Connect
deliver-metadata:
    fastlane metadata

# Upload screenshots only to App Store Connect (iOS + Mac)
# Note: `fastlane screenshots` alone is iOS-only (default_platform). Always run both.
# Mac: deliver can double-upload (ASC verify race). prune drops extra APP_DESKTOP shots.
deliver-screenshots: deliver-prepare-screenshots
    fastlane ios screenshots
    fastlane mac screenshots

# Mac screenshot prune against ASC lives in the private maintainer tooling repo.
# Public tree does not ship ASC credentials or prune scripts.

# Upload metadata and screenshots to App Store Connect (iOS + Mac)
deliver: deliver-prepare-screenshots
    fastlane ios release_metadata
    fastlane mac release_metadata

# Preview metadata without uploading (opens HTML report)
deliver-preview:
    fastlane preview

# Full rebuild
rebuild: clean-rust build-rust
