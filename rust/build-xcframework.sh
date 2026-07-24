#!/bin/bash
set -e

# MACOS_ONLY=1  Build only the macOS arm64 slice (for CI / CodeQL). Skips iOS
#               targets, x86_64 lipo, and license generation.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RUST_DIR="$SCRIPT_DIR"
OUTPUT_DIR="$PROJECT_DIR/ReqeastCore"
XCFRAMEWORK_DIR="$OUTPUT_DIR/reqeast_core.xcframework"
MACOS_ONLY="${MACOS_ONLY:-0}"

echo "=== Reqeast Core Rust Library Builder ==="
if [ "$MACOS_ONLY" = "1" ]; then
    echo "Mode: MACOS_ONLY (arm64 darwin, for CI/CodeQL)"
fi
echo ""

# Check for Rust installation
if ! command -v cargo &> /dev/null; then
    echo "Error: Rust is not installed."
    echo ""
    echo "Please install Rust using:"
    echo "  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
    echo ""
    echo "After installation, restart your terminal and run this script again."
    exit 1
fi

echo "Rust version: $(rustc --version)"
echo "Cargo version: $(cargo --version)"
echo ""

cd "$RUST_DIR"

# Ensure build targets are installed
echo "Ensuring build targets are installed..."
rustup target add aarch64-apple-darwin 2>/dev/null || true
if [ "$MACOS_ONLY" != "1" ]; then
    rustup target add x86_64-apple-darwin 2>/dev/null || true
    rustup target add aarch64-apple-ios 2>/dev/null || true
    rustup target add aarch64-apple-ios-sim 2>/dev/null || true
    rustup target add x86_64-apple-ios 2>/dev/null || true
fi

# Build for macOS arm64 (always)
echo ""
echo "Building for macOS arm64..."
cargo build --release --target aarch64-apple-darwin

if [ "$MACOS_ONLY" != "1" ]; then
    echo ""
    echo "Building for macOS x86_64..."
    cargo build --release --target x86_64-apple-darwin

    echo ""
    echo "Building for iOS arm64..."
    cargo build --release --target aarch64-apple-ios

    echo ""
    echo "Building for iOS Simulator arm64..."
    cargo build --release --target aarch64-apple-ios-sim

    echo ""
    echo "Building for iOS Simulator x86_64..."
    cargo build --release --target x86_64-apple-ios
fi

# Create output directories
mkdir -p "$OUTPUT_DIR/Sources"
mkdir -p "$OUTPUT_DIR/Headers"

# Create macOS library (universal or arm64-only)
echo ""
echo "Creating macOS library..."
MACOS_LIB_DIR="$OUTPUT_DIR/lib-macos"
mkdir -p "$MACOS_LIB_DIR"
if [ "$MACOS_ONLY" = "1" ]; then
    cp target/aarch64-apple-darwin/release/libreqeast_core.a "$MACOS_LIB_DIR/libreqeast_core.a"
else
    lipo -create \
        target/aarch64-apple-darwin/release/libreqeast_core.a \
        target/x86_64-apple-darwin/release/libreqeast_core.a \
        -output "$MACOS_LIB_DIR/libreqeast_core.a"
fi

if [ "$MACOS_ONLY" != "1" ]; then
    echo "Creating iOS Simulator universal binary..."
    IOS_SIM_LIB_DIR="$OUTPUT_DIR/lib-ios-sim"
    mkdir -p "$IOS_SIM_LIB_DIR"
    lipo -create \
        target/aarch64-apple-ios-sim/release/libreqeast_core.a \
        target/x86_64-apple-ios/release/libreqeast_core.a \
        -output "$IOS_SIM_LIB_DIR/libreqeast_core.a"

    IOS_DEVICE_LIB="target/aarch64-apple-ios/release/libreqeast_core.a"
fi

# Generate Swift bindings using uniffi-bindgen
echo ""
echo "Generating Swift bindings..."
cargo run --bin uniffi-bindgen generate \
    --library target/aarch64-apple-darwin/release/libreqeast_core.a \
    --language swift \
    --out-dir "$OUTPUT_DIR/Sources"

# Move the FFI header to Headers directory
if [ -f "$OUTPUT_DIR/Sources/reqeast_coreFFI.h" ]; then
    mv "$OUTPUT_DIR/Sources/reqeast_coreFFI.h" "$OUTPUT_DIR/Headers/"
fi

# Create module map
cat > "$OUTPUT_DIR/Headers/module.modulemap" << 'EOF'
module reqeast_coreFFI {
    header "reqeast_coreFFI.h"
    export *
}
EOF

# Build XCFramework
echo ""
echo "Creating XCFramework..."
rm -rf "$XCFRAMEWORK_DIR"
if [ "$MACOS_ONLY" = "1" ]; then
    xcodebuild -create-xcframework \
        -library "$MACOS_LIB_DIR/libreqeast_core.a" \
        -headers "$OUTPUT_DIR/Headers" \
        -output "$XCFRAMEWORK_DIR"
else
    xcodebuild -create-xcframework \
        -library "$MACOS_LIB_DIR/libreqeast_core.a" \
        -headers "$OUTPUT_DIR/Headers" \
        -library "$IOS_DEVICE_LIB" \
        -headers "$OUTPUT_DIR/Headers" \
        -library "$IOS_SIM_LIB_DIR/libreqeast_core.a" \
        -headers "$OUTPUT_DIR/Headers" \
        -output "$XCFRAMEWORK_DIR"
fi

# Clean up temporary directories (headers are now inside the xcframework)
rm -rf "$MACOS_LIB_DIR" "${IOS_SIM_LIB_DIR:-}" "$OUTPUT_DIR/Headers"

# Generate license bundle for App Store attribution (skip in MACOS_ONLY CI builds)
if [ "$MACOS_ONLY" != "1" ]; then
    echo ""
    echo "Generating license bundle..."
    mkdir -p "$PROJECT_DIR/Reqeast/Resources"
    if command -v cargo-bundle-licenses &> /dev/null || cargo bundle-licenses --help &> /dev/null; then
        cargo bundle-licenses --format json --output "$PROJECT_DIR/Reqeast/Resources/licenses.json"
    else
        echo "Warning: cargo-bundle-licenses not installed; skipping license bundle."
    fi
fi

echo ""
echo "=== Build Complete ==="
echo ""
echo "Output files:"
echo "  XCFramework:   $XCFRAMEWORK_DIR"
echo "  Swift sources: $OUTPUT_DIR/Sources/reqeast_core.swift"
echo ""
echo "XCFramework contents:"
ls -la "$XCFRAMEWORK_DIR/"
