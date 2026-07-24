#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RAW_DIR="$PROJECT_DIR/screenshots/raw"
FINAL_DIR="$PROJECT_DIR/screenshots/final"
TITLES_FILE="$SCRIPT_DIR/screenshot-titles.json"
TEMPLATES_DIR="$SCRIPT_DIR/templates"

if ! command -v jq &>/dev/null; then
    echo "jq not found. Install with: brew install jq"
    exit 1
fi

# Partial: LANGS=en  or  LANGUAGES=en  or  LANGS=en,ja
if [ -n "${LANGS:-}" ]; then
    LANGUAGES="${LANGS//,/ }"
fi
LANGUAGES="${LANGUAGES:-en zh-Hans zh-Hant ja fr pt-BR es ko de}"

# Scale factor per device (Mac shows a window inside the display, iPhone/iPad are full-screen)
scale_for_device() {
    case "$1" in
        mac) echo "0.805" ;;
        *)   echo "1.0" ;;
    esac
}

mkdir -p "$FINAL_DIR"

# Refuse to compose bad raws (wrong device, empty iPad11 sidebar, etc.)
echo "Validating raws before compose..."
LANGS="${LANGS:-${LANGUAGES// /,}}" \
    bash "$SCRIPT_DIR/validate-screenshots.sh" --raws-only

# ============================================================
# Compose a single-device screenshot
# ============================================================
compose_single() {
    local doc_name="$1" group_name="$2" device_group="$3"
    local screenshot="$4" title="$5" subtitle="$6"
    local title_layer="$7" subtitle_layer="$8" output="$9" scale="${10}"

    mkdir -p "$(dirname "$output")"

    osascript <<EOF
tell application "Pixelmator Pro"
    tell document "$doc_name"
        -- Hide all top-level groups, show target
        set allLayers to every layer
        repeat with l in allLayers
            if class of l is group layer then
                if name of l is "$group_name" then
                    set visible of l to true
                else
                    set visible of l to false
                end if
            end if
        end repeat

        tell layer "$group_name"
            set text content of text layer "$title_layer" to "$title"
            set text content of text layer "$subtitle_layer" to "$subtitle"
            -- Keep long headlines inside safe margins (template text box is full-bleed).
            try
                tell text content of text layer "$title_layer"
                    set sz to size
                    if (count of characters) > 28 then set size to sz * 0.88
                    if (count of characters) > 34 then set size to sz * 0.82
                end tell
            end try

            tell layer "$device_group"
                -- Find screenshot layer (skip Status Bar group)
                set p to missing value
                repeat with il in (every layer)
                    if class of il is image layer then
                        set n to name of il
                        if n contains "Media Placeholder" or n contains "ProjectSidebar" or n contains "HttpRequest" or n contains "ProtocolMenu" or n contains "SocketView" then
                            set p to il
                            exit repeat
                        end if
                    end if
                end repeat
                if p is missing value then set p to image layer 1
                set file of p to POSIX file "$screenshot"
                set d to layer "Display"
                set dW to width of d
                set dH to height of d
                set dPos to position of d
                -- Uniform scale only (never non-uniform stretch). Stretching warps app chrome
                -- (sidebar looks wrong). Mac captures should already match Display aspect (~1.54).
                set constrain proportions of p to true
                set boxW to dW * $scale
                set boxH to dH * $scale
                set sW to width of p
                set sH to height of p
                set fit to boxW / sW
                if (boxH / sH) < fit then set fit to boxH / sH
                set width of p to sW * fit
                set newW to width of p
                set newH to height of p
                set newX to (item 1 of dPos) + (dW - newW) / 2
                set newY to (item 2 of dPos) + (dH - newH) / 2
                set position of p to {newX, newY}
            end tell
        end tell

        set thePath to POSIX file "$output"
        export for web to thePath as PNG
    end tell
end tell
EOF
}

# ============================================================
# Compose a multi-device screenshot (slot 3)
# ============================================================
compose_multi() {
    local doc_name="$1" group_name="$2"
    local title="$3" subtitle="$4"
    local title_layer="$5" subtitle_layer="$6"
    local output="$7" scale="$8"
    shift 8
    # Remaining args: triplets of "device_group:scale:screenshot_path"
    local device_pairs=("$@")

    mkdir -p "$(dirname "$output")"

    # Build the AppleScript for each device
    local device_script=""
    for pair in "${device_pairs[@]}"; do
        local dg="${pair%%:*}"
        local rest="${pair#*:}"
        local dev_scale="${rest%%:*}"
        local sf="${rest#*:}"
        device_script="$device_script
            tell layer \"$dg\"
                -- Screenshots already include a real status bar; hide template overlays.
                repeat with il in (every layer)
                    try
                        if name of il is \"Status Bar\" then set visible of il to false
                    end try
                end repeat
                -- Find screenshot layer (skip Status Bar group)
                set p to missing value
                repeat with il in (every layer)
                    if class of il is image layer then
                        set n to name of il
                        if n contains \"Media Placeholder\" or n contains \"ProjectSidebar\" or n contains \"HttpRequest\" or n contains \"ProtocolMenu\" or n contains \"SocketView\" then
                            set p to il
                            exit repeat
                        end if
                    end if
                end repeat
                if p is missing value then set p to image layer 1
                set file of p to POSIX file \"$sf\"
                set d to layer \"Display\"
                set dW to width of d
                set dH to height of d
                set dPos to position of d
                set constrain proportions of p to true
                set boxW to dW * $dev_scale
                set boxH to dH * $dev_scale
                set sW to width of p
                set sH to height of p
                set fit to boxW / sW
                if (boxH / sH) < fit then set fit to boxH / sH
                set width of p to sW * fit
                set newW to width of p
                set newH to height of p
                set newX to (item 1 of dPos) + (dW - newW) / 2
                set newY to (item 2 of dPos) + (dH - newH) / 2
                set position of p to {newX, newY}
            end tell
"
    done

    osascript <<EOF
tell application "Pixelmator Pro"
    tell document "$doc_name"
        set allLayers to every layer
        repeat with l in allLayers
            if class of l is group layer then
                if name of l is "$group_name" then
                    set visible of l to true
                else
                    set visible of l to false
                end if
            end if
        end repeat

        tell layer "$group_name"
            set text content of text layer "$title_layer" to "$title"
            set text content of text layer "$subtitle_layer" to "$subtitle"
            try
                tell text content of text layer "$title_layer"
                    set sz to size
                    if (count of characters) > 28 then set size to sz * 0.88
                    if (count of characters) > 34 then set size to sz * 0.82
                end tell
            end try
$device_script
        end tell

        set thePath to POSIX file "$output"
        export for web to thePath as PNG
    end tell
end tell
EOF
}

# ============================================================
# Open templates
# ============================================================
echo "Opening templates..."
for tpl in mac.pxd iphone.pxd ipad.pxd; do
    osascript -e "tell application \"Pixelmator Pro\" to open POSIX file \"$TEMPLATES_DIR/$tpl\"" 2>/dev/null || true
done
sleep 2

# ============================================================
# Mac screenshots
# ============================================================
echo ""
echo "=== Mac ==="
for lang in $LANGUAGES; do
    # Slot 01: ProjectSidebar
    title=$(jq -r ".mac.\"01\".\"${lang}\".title" "$TITLES_FILE")
    subtitle=$(jq -r ".mac.\"01\".\"${lang}\".subtitle" "$TITLES_FILE")
    raw="$RAW_DIR/mac/$lang/01_ProjectSidebar.png"
    [ -f "$raw" ] && {
        echo "mac/$lang/01"
        compose_single "mac.pxd" "First" "MacBook Air (M2)" "$raw" "$title" "$subtitle" "Headline" "Headline copy" "$FINAL_DIR/mac/$lang/01.png" 0.805
    }

    # Slot 02: ProtocolMenu
    title=$(jq -r ".mac.\"02\".\"${lang}\".title" "$TITLES_FILE")
    subtitle=$(jq -r ".mac.\"02\".\"${lang}\".subtitle" "$TITLES_FILE")
    raw="$RAW_DIR/mac/$lang/03_ProtocolMenu.png"
    [ -f "$raw" ] && {
        echo "mac/$lang/02"
        compose_single "mac.pxd" "second" "MacBook Air (M2)" "$raw" "$title" "$subtitle" "Headline" "Headline copy" "$FINAL_DIR/mac/$lang/02.png" 0.805
    }

    # Slot 03: Multi-device
    # Mac = HTTP editor; iPad = project list (11" multi plate); iPhone = empty welcome.
    # Do not put the same 02_HttpRequest on Mac and iPad — looks like a duplicated screen.
    title=$(jq -r ".mac.\"03\".\"${lang}\".title" "$TITLES_FILE")
    subtitle=$(jq -r ".mac.\"03\".\"${lang}\".subtitle" "$TITLES_FILE")
    mac_raw="$RAW_DIR/mac/$lang/02_HttpRequest.png"
    # Multi collage plate is iPad Pro 11-in. Capture on 11" sim into raw/ipad11/.
    ipad_raw="$RAW_DIR/ipad11/$lang/01_ProjectSidebar.png"
    if [ ! -f "$ipad_raw" ]; then
        ipad_raw="$RAW_DIR/ipad/$lang/01_ProjectSidebar.png"
        echo "  WARNING: missing ipad11/$lang; falling back to 13\" ipad raw (will look wrong)"
    fi
    iphone_raw="$RAW_DIR/iphone/$lang/01_ProjectSidebar.png"
    if [ -f "$mac_raw" ] && [ -f "$ipad_raw" ] && [ -f "$iphone_raw" ]; then
        echo "mac/$lang/03 (multi-device)"
        compose_multi "mac.pxd" "3" "$title" "$subtitle" "Headline" "Headline copy" "$FINAL_DIR/mac/$lang/03.png" 0.805 \
            "MacBook Air (M2) copy:0.805:$mac_raw" \
            "iPad Pro 11-in. (M4) copy:1.0:$ipad_raw" \
            "iPhone 16 Pro copy:1.0:$iphone_raw"
    fi
done

# ============================================================
# iPhone screenshots
# ============================================================
echo ""
echo "=== iPhone ==="
for lang in $LANGUAGES; do
    title=$(jq -r ".iphone.\"01\".\"${lang}\".title" "$TITLES_FILE")
    subtitle=$(jq -r ".iphone.\"01\".\"${lang}\".subtitle" "$TITLES_FILE")
    raw="$RAW_DIR/iphone/$lang/01_ProjectSidebar.png"
    [ -f "$raw" ] && {
        echo "iphone/$lang/01"
        compose_single "iphone.pxd" "1" "iPhone 16 Pro" "$raw" "$title" "$subtitle" "Headline copy 3" "Headline copy" "$FINAL_DIR/iphone/$lang/01.png" 1.0
    }

    title=$(jq -r ".iphone.\"02\".\"${lang}\".title" "$TITLES_FILE")
    subtitle=$(jq -r ".iphone.\"02\".\"${lang}\".subtitle" "$TITLES_FILE")
    raw="$RAW_DIR/iphone/$lang/03_ProtocolMenu.png"
    [ -f "$raw" ] && {
        echo "iphone/$lang/02"
        compose_single "iphone.pxd" "2" "iPhone 16 Pro" "$raw" "$title" "$subtitle" "Headline copy 2" "Headline copy" "$FINAL_DIR/iphone/$lang/02.png" 1.0
    }

    title=$(jq -r ".iphone.\"03\".\"${lang}\".title" "$TITLES_FILE")
    subtitle=$(jq -r ".iphone.\"03\".\"${lang}\".subtitle" "$TITLES_FILE")
    iphone_raw="$RAW_DIR/iphone/$lang/01_ProjectSidebar.png"
    mac_raw="$RAW_DIR/mac/$lang/01_ProjectSidebar.png"
    # Multi collage plate is iPad Pro 11-in (Display ~1.45). Capture on 11" sim → raw/ipad11/.
    ipad_raw="$RAW_DIR/ipad11/$lang/01_ProjectSidebar.png"
    if [ ! -f "$ipad_raw" ]; then
        ipad_raw="$RAW_DIR/ipad/$lang/01_ProjectSidebar.png"
        echo "  WARNING: missing ipad11/$lang; falling back to 13\" ipad raw (will look wrong)"
    fi
    if [ -f "$iphone_raw" ] && [ -f "$mac_raw" ] && [ -f "$ipad_raw" ]; then
        echo "iphone/$lang/03 (multi-device)"
        compose_multi "iphone.pxd" "3" "$title" "$subtitle" "Headline copy 2" "Headline copy" "$FINAL_DIR/iphone/$lang/03.png" 1.0 \
            "iPhone 16 Pro:1.0:$iphone_raw" \
            "MacBook Air (M2):0.805:$mac_raw" \
            "iPad Pro 11-in. (M4):1.0:$ipad_raw"
    fi
done

# ============================================================
# iPad screenshots (exact pixel placement from template)
# ============================================================
echo ""
echo "=== iPad ==="

compose_ipad_single() {
    local group="$1" title="$2" subtitle="$3" title_layer="$4" subtitle_layer="$5"
    local device1="$6" device2="$7" screenshot="$8" output="$9"

    osascript <<EOF
tell application "Pixelmator Pro"
    tell document "ipad.pxd"
        set allLayers to every layer
        repeat with l in allLayers
            if class of l is group layer then
                set visible of l to (name of l is "$group")
            end if
        end repeat

        tell layer "$group"
            set text content of text layer "$title_layer" to "$title"
            set text content of text layer "$subtitle_layer" to "$subtitle"

            -- iPad Pro 11-in: 2041x1533 at (347, 352)
            tell layer "$device1"
                set p to missing value
                repeat with il in (every layer)
                    if class of il is image layer then
                        set n to name of il
                        if n contains "Media Placeholder" or n contains "ProjectSidebar" or n contains "HttpRequest" or n contains "ProtocolMenu" or n contains "SocketView" then
                            set p to il
                            exit repeat
                        end if
                    end if
                end repeat
                if p is missing value then set p to image layer 1
                set file of p to POSIX file "$screenshot"
                set constrain proportions of p to false
                set width of p to 2041
                set height of p to 1533
                set position of p to {347, 352}
            end tell

            -- iPad Pro 13-in: same dimensions
            tell layer "$device2"
                set p to missing value
                repeat with il in (every layer)
                    if class of il is image layer then
                        set n to name of il
                        if n contains "Media Placeholder" or n contains "ProjectSidebar" or n contains "HttpRequest" or n contains "ProtocolMenu" or n contains "SocketView" then
                            set p to il
                            exit repeat
                        end if
                    end if
                end repeat
                if p is missing value then set p to image layer 1
                set file of p to POSIX file "$screenshot"
                set constrain proportions of p to false
                set width of p to 2041
                set height of p to 1533
                set position of p to {347, 352}
            end tell
        end tell

        set thePath to POSIX file "$output"
        export for web to thePath as PNG
    end tell
end tell
EOF
}

# Fit screenshot image into device group's Display layer (uniform scale, centered).
# mac_scale < 1 leaves a window chrome margin on Mac (same idea as mac.pxd multi).
compose_ipad_multi_device_script() {
    local device_group="$1" scale="$2" screenshot="$3"
    cat <<EOS
            tell layer "$device_group"
                set p to missing value
                repeat with il in (every layer)
                    if class of il is image layer then
                        set n to name of il
                        if n contains "Media Placeholder" or n contains "ProjectSidebar" or n contains "HttpRequest" or n contains "ProtocolMenu" or n contains "SocketView" then
                            set p to il
                            exit repeat
                        end if
                    end if
                end repeat
                if p is missing value then set p to image layer 1
                set file of p to POSIX file "$screenshot"
                set d to layer "Display"
                set dW to width of d
                set dH to height of d
                set dPos to position of d
                set constrain proportions of p to true
                set boxW to dW * $scale
                set boxH to dH * $scale
                set sW to width of p
                set sH to height of p
                set fit to boxW / sW
                if (boxH / sH) < fit then set fit to boxH / sH
                set width of p to sW * fit
                set newW to width of p
                set newH to height of p
                set newX to (item 1 of dPos) + (dW - newW) / 2
                set newY to (item 2 of dPos) + (dH - newH) / 2
                set position of p to {newX, newY}
            end tell
EOS
}

compose_ipad_multi() {
    local title="$1" subtitle="$2" mac_raw="$3" iphone_raw="$4" ipad_raw="$5" output="$6"
    # iPad multi plate iPad bezel is 11-in. Display ~1.45 — use raw/ipad11, never 13" (1.33).
    # Hardcoded 1590×1193 was 13" aspect and stretched content in the 11" hole (Display 1589×1095).
    local mac_script iphone_script ipad_script
    mac_script=$(compose_ipad_multi_device_script "MacBook Air (M2)" "0.805" "$mac_raw")
    iphone_script=$(compose_ipad_multi_device_script "iPhone 16 Pro" "1.0" "$iphone_raw")
    ipad_script=$(compose_ipad_multi_device_script "iPad Pro 11-in. (M4)" "1.0" "$ipad_raw")

    osascript <<EOF
tell application "Pixelmator Pro"
    tell document "ipad.pxd"
        set allLayers to every layer
        repeat with l in allLayers
            if class of l is group layer then
                set visible of l to (name of l is "3")
            end if
        end repeat

        tell layer "3"
            set text content of text layer "Headline copy 3" to "$title"
            set text content of text layer "Headline copy" to "$subtitle"
$mac_script
$iphone_script
$ipad_script
        end tell

        set thePath to POSIX file "$output"
        export for web to thePath as PNG
    end tell
end tell
EOF
}

for lang in $LANGUAGES; do
    # Slot 01
    title=$(jq -r ".ipad.\"01\".\"${lang}\".title" "$TITLES_FILE")
    subtitle=$(jq -r ".ipad.\"01\".\"${lang}\".subtitle" "$TITLES_FILE")
    raw="$RAW_DIR/ipad/$lang/01_ProjectSidebar.png"
    [ -f "$raw" ] && {
        echo "ipad/$lang/01"
        compose_ipad_single "1" "$title" "$subtitle" "Headline copy 4" "Headline copy" \
            "iPad Pro 11-in. (M4)" "iPad Pro 13-in. (M4)" "$raw" "$FINAL_DIR/ipad/$lang/01.png"
    }

    # Slot 02
    title=$(jq -r ".ipad.\"02\".\"${lang}\".title" "$TITLES_FILE")
    subtitle=$(jq -r ".ipad.\"02\".\"${lang}\".subtitle" "$TITLES_FILE")
    raw="$RAW_DIR/ipad/$lang/03_ProtocolMenu.png"
    [ -f "$raw" ] && {
        echo "ipad/$lang/02"
        compose_ipad_single "2" "$title" "$subtitle" "Headline copy 3" "Headline copy 2" \
            "iPad Pro 11-in. (M4)" "iPad Pro 13-in. (M4)" "$raw" "$FINAL_DIR/ipad/$lang/02.png"
    }

    # Slot 03: Multi-device — iPad bezel is 11-in. (Display ~1.45). Use raw/ipad11/, not 13".
    title=$(jq -r ".ipad.\"03\".\"${lang}\".title" "$TITLES_FILE")
    subtitle=$(jq -r ".ipad.\"03\".\"${lang}\".subtitle" "$TITLES_FILE")
    iphone_raw="$RAW_DIR/iphone/$lang/01_ProjectSidebar.png"
    mac_raw="$RAW_DIR/mac/$lang/01_ProjectSidebar.png"
    ipad_raw="$RAW_DIR/ipad11/$lang/01_ProjectSidebar.png"
    if [ ! -f "$ipad_raw" ]; then
        ipad_raw="$RAW_DIR/ipad/$lang/01_ProjectSidebar.png"
        echo "  WARNING: missing ipad11/$lang for multi; falling back to 13\" (will look wrong in 11\" bezel)"
    fi
    if [ -f "$iphone_raw" ] && [ -f "$ipad_raw" ] && [ -f "$mac_raw" ]; then
        echo "ipad/$lang/03 (multi-device, ipad11 raw)"
        compose_ipad_multi "$title" "$subtitle" "$mac_raw" "$iphone_raw" "$ipad_raw" "$FINAL_DIR/ipad/$lang/03.png"
    fi
done

# ============================================================
# Close templates without saving
# ============================================================
echo ""
echo "Closing templates..."
for doc in "mac.pxd" "iphone.pxd" "ipad.pxd"; do
    osascript -e "tell application \"Pixelmator Pro\" to tell document \"$doc\" to close without saving" 2>/dev/null || true
done

echo "Done. Final screenshots in $FINAL_DIR"
echo ""
echo "Validating finals..."
LANGS="${LANGS:-${LANGUAGES// /,}}" \
    bash "$SCRIPT_DIR/validate-screenshots.sh" --finals-only
