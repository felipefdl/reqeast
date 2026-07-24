#!/bin/bash
# Validate marketing screenshot raws (and optionally finals) before compose/upload.
# Exit 1 on any hard failure so agents cannot ship wrong-device or empty-demo frames.
#
# Usage:
#   bash scripts/validate-screenshots.sh              # raws + finals if present
#   bash scripts/validate-screenshots.sh --raws-only
#   bash scripts/validate-screenshots.sh --finals-only
#   LANGS=en DEVICES=mac,iphone,ipad,ipad11 bash scripts/validate-screenshots.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RAW_DIR="$PROJECT_DIR/screenshots/raw"
FINAL_DIR="$PROJECT_DIR/screenshots/final"

RAWSONLY=0
FINALSONLY=0
for arg in "$@"; do
    case "$arg" in
        --raws-only) RAWSONLY=1 ;;
        --finals-only) FINALSONLY=1 ;;
        -h|--help)
            sed -n '2,12p' "$0"
            exit 0
            ;;
    esac
done

# Default: all marketing locales / devices. Override with comma lists.
IFS=',' read -r -a LANG_ARR <<< "${LANGS:-en,zh-Hans,zh-Hant,ja,fr,pt-BR,es,ko,de}"
IFS=',' read -r -a DEVICE_ARR <<< "${DEVICES:-mac,iphone,ipad,ipad11}"

errors=0
warnings=0

fail() {
    echo "ERROR: $*" >&2
    errors=$((errors + 1))
}

warn() {
    echo "WARNING: $*" >&2
    warnings=$((warnings + 1))
}

ok() {
    echo "  OK  $*"
}

png_wh() {
    python3 - "$1" <<'PY'
import struct, sys
path = sys.argv[1]
with open(path, "rb") as f:
    f.read(8)
    f.read(4)
    if f.read(4) != b"IHDR":
        sys.exit(2)
    w, h = struct.unpack(">II", f.read(8))
print(f"{w} {h}")
PY
}

# --- Raw validation ----------------------------------------------------------

validate_raws() {
    echo "=== Raws ($RAW_DIR) ==="
    local lang device path w h ratio size

    for device in "${DEVICE_ARR[@]}"; do
        for lang in "${LANG_ARR[@]}"; do
            local dir="$RAW_DIR/$device/$lang"
            if [ ! -d "$dir" ]; then
                # ipad11 only required when multi collage is in scope
                if [ "$device" = "ipad11" ]; then
                    fail "missing $device/$lang (multi collage needs raw/ipad11/)"
                else
                    fail "missing $device/$lang"
                fi
                continue
            fi

            case "$device" in
                mac)
                    for base in 01_ProjectSidebar 02_HttpRequest 03_ProtocolMenu 04_SocketView; do
                        path="$dir/${base}.png"
                        if [ ! -f "$path" ]; then
                            fail "missing $device/$lang/${base}.png"
                            continue
                        fi
                        read -r w h < <(png_wh "$path") || { fail "unreadable $path"; continue; }
                        ratio=$(python3 -c "print(round($w/$h, 3))")
                        size=$(stat -f%z "$path" 2>/dev/null || stat -c%s "$path")
                        # Normal app window 1100×800 (@2x = 2200×1600, ratio 1.375).
                        # Reject portrait. Prefer landscape ~1.3–1.6 (not phone frames).
                        if python3 -c "import sys; sys.exit(0 if 1.25 <= $w/$h <= 1.70 else 1)"; then
                            :
                        else
                            fail "$device/$lang/${base}.png wrong aspect ${w}x${h} (ratio $ratio; need landscape ~1.4 app window)"
                        fi
                        if [ "$w" -lt 1000 ]; then
                            fail "$device/$lang/${base}.png too narrow (${w}px) — expect ~1100 or ~2200"
                        fi
                        if [ "$base" = "01_ProjectSidebar" ] && [ "$size" -lt 180000 ]; then
                            fail "$device/$lang/${base}.png too small ($size bytes) — likely empty / wrong window"
                        fi
                        ok "$device/$lang/${base}.png ${w}x${h} (${size}B)"
                    done
                    ;;
                iphone)
                    for base in 01_ProjectSidebar 02_HttpRequest 03_ProtocolMenu 04_SocketView; do
                        path="$dir/${base}.png"
                        if [ ! -f "$path" ]; then
                            fail "missing $device/$lang/${base}.png"
                            continue
                        fi
                        read -r w h < <(png_wh "$path") || { fail "unreadable $path"; continue; }
                        size=$(stat -f%z "$path" 2>/dev/null || stat -c%s "$path")
                        # Portrait phone (~0.46). Reject landscape / iPad frames.
                        if python3 -c "import sys; sys.exit(0 if $w/$h < 0.7 else 1)"; then
                            :
                        else
                            fail "$device/$lang/${base}.png wrong aspect ${w}x${h} — looks like tablet/mac (never put mac screencapture in iphone/)"
                        fi
                        # 01 is intentionally empty welcome; still must be a full frame
                        if [ "$size" -lt 80000 ]; then
                            fail "$device/$lang/${base}.png too small ($size bytes)"
                        fi
                        ok "$device/$lang/${base}.png ${w}x${h} (${size}B)"
                    done
                    ;;
                ipad)
                    for base in 01_ProjectSidebar 02_HttpRequest 03_ProtocolMenu 04_SocketView; do
                        path="$dir/${base}.png"
                        if [ ! -f "$path" ]; then
                            fail "missing $device/$lang/${base}.png"
                            continue
                        fi
                        read -r w h < <(png_wh "$path") || { fail "unreadable $path"; continue; }
                        size=$(stat -f%z "$path" 2>/dev/null || stat -c%s "$path")
                        ratio=$(python3 -c "print(round($w/$h, 3))")
                        # Landscape 13" ~1.33. Portrait = forgot rotate. ~1.45 = wrong device (11").
                        if python3 -c "import sys; r=$w/$h; sys.exit(0 if 1.25 <= r <= 1.40 else 1)"; then
                            :
                        else
                            fail "$device/$lang/${base}.png aspect ${w}x${h} (ratio $ratio) — need 13\" landscape ~1.33 (portrait=forgot sips -r 270; ~1.45=11\" multi raw)"
                        fi
                        # Demo sidebar must be painted (empty white column was ~218–230k on smaller plates)
                        if [ "$base" = "01_ProjectSidebar" ] && [ "$size" -lt 250000 ]; then
                            fail "$device/$lang/${base}.png too small ($size bytes) — empty demo sidebar? Wait 8s after simctl launch"
                        fi
                        ok "$device/$lang/${base}.png ${w}x${h} ratio=$ratio (${size}B)"
                    done
                    ;;
                ipad11)
                    # Multi collage only: 01 (project list) + 02 (HTTP) required.
                    for base in 01_ProjectSidebar 02_HttpRequest; do
                        path="$dir/${base}.png"
                        if [ ! -f "$path" ]; then
                            fail "missing $device/$lang/${base}.png (multi slot 03 needs this)"
                            continue
                        fi
                        read -r w h < <(png_wh "$path") || { fail "unreadable $path"; continue; }
                        size=$(stat -f%z "$path" 2>/dev/null || stat -c%s "$path")
                        ratio=$(python3 -c "print(round($w/$h, 3))")
                        # Landscape 11" ~1.45. Reject 13" (~1.33) and portrait.
                        if python3 -c "import sys; r=$w/$h; sys.exit(0 if 1.40 <= r <= 1.55 else 1)"; then
                            :
                        else
                            fail "$device/$lang/${base}.png aspect ${w}x${h} (ratio $ratio) — need 11\" landscape ~1.45. NEVER use 13\" raw here or stretch in compose"
                        fi
                        if [ "$base" = "01_ProjectSidebar" ] && [ "$size" -lt 230000 ]; then
                            fail "$device/$lang/${base}.png too small ($size bytes) — empty demo sidebar on multi plate. Recapture: 8s settle + prepare_sim_for_marketing"
                        fi
                        ok "$device/$lang/${base}.png ${w}x${h} ratio=$ratio (${size}B)"
                    done
                    ;;
                *)
                    fail "unknown device '$device'"
                    ;;
            esac
        done
    done
}

# --- Final validation --------------------------------------------------------

validate_finals() {
    echo "=== Finals ($FINAL_DIR) ==="
    local lang platform path size
    # Finals only for store platforms (no raw/ipad11 final dir)
    local platforms=(mac iphone ipad)
    for platform in "${platforms[@]}"; do
        # Skip platform if not relevant to current DEVICES filter
        local want=0
        for d in "${DEVICE_ARR[@]}"; do
            if [ "$d" = "$platform" ] || { [ "$platform" = "iphone" ] && [ "$d" = "ipad11" ]; } \
                || { [ "$platform" = "mac" ] && [ "$d" = "ipad11" ]; }; then
                want=1
            fi
            if [ "$d" = "$platform" ]; then want=1; fi
        done
        # If user only asked for ipad11, still check iphone/mac finals that consume it when present
        if [ "$want" -eq 0 ] && [ "$platform" != "iphone" ] && [ "$platform" != "mac" ]; then
            continue
        fi

        for lang in "${LANG_ARR[@]}"; do
            for slot in 01 02 03; do
                path="$FINAL_DIR/$platform/$lang/${slot}.png"
                if [ ! -f "$path" ]; then
                    # Only require finals when directory exists (partial compose)
                    if [ -d "$FINAL_DIR/$platform/$lang" ]; then
                        fail "missing final $platform/$lang/${slot}.png"
                    fi
                    continue
                fi
                size=$(stat -f%z "$path" 2>/dev/null || stat -c%s "$path")
                if [ "$size" -lt 200000 ]; then
                    fail "final $platform/$lang/${slot}.png too small ($size bytes)"
                else
                    ok "final $platform/$lang/${slot}.png (${size}B)"
                fi
            done
        done
    done
}

if [ "$FINALSONLY" -eq 0 ]; then
    validate_raws
fi
if [ "$RAWSONLY" -eq 0 ]; then
    if [ -d "$FINAL_DIR" ]; then
        validate_finals
    fi
fi

echo ""
if [ "$errors" -gt 0 ]; then
    echo "FAILED: $errors error(s), $warnings warning(s)."
    echo "Read scripts/SCREENSHOTS.md (HARD RULE + known pain). Recapture correct device — never stretch/paint."
    exit 1
fi
echo "PASSED: raw/final checks clean ($warnings warning(s))."
exit 0
