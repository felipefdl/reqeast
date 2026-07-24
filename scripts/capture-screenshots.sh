#!/bin/bash
# App Store marketing capture. Full playbook: scripts/SCREENSHOTS.md
#
# Never `source` this file — it runs a long loop. Always:
#   bash scripts/capture-screenshots.sh
#
# Partial re-runs (comma lists):
#   LANGS=en DEVICES=ipad11 bash scripts/capture-screenshots.sh
#   LANGS=en,ja DEVICES=mac,iphone bash scripts/capture-screenshots.sh

# Refuse accidental `source` (must run before set -u; works in bash).
if (return 0 2>/dev/null); then
    echo "ERROR: do not source capture-screenshots.sh (it runs the full capture loop)." >&2
    echo "Run: bash scripts/capture-screenshots.sh   or   LANGS=en DEVICES=ipad11 bash scripts/..." >&2
    return 1
fi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PROJECT_DIR/screenshots/raw"
# Shared config path readable by the sandboxed UITest runner (not $TMPDIR / container tmp).
LANG_CONFIG="/tmp/reqeast-screenshot-config"

IPHONE_SIM="iPhone 17 Pro Max"
# Standalone App Store iPad frames (13"). Multi-device collage plates are 11" — separate pass.
IPAD_SIM="iPad Pro 13-inch (M5)"
IPAD11_SIM="iPad Pro 11-inch (M5)"

# LANGS=en,ja  DEVICES=mac,iphone,ipad,ipad11
if [ -n "${LANGS:-}" ]; then
    IFS=',' read -r -a LANGUAGES <<< "$LANGS"
else
    LANGUAGES=("en" "zh-Hans" "zh-Hant" "ja" "fr" "pt-BR" "es" "ko" "de")
fi

build_devices() {
    DEVICES=()
    local want="${DEVICES_FILTER:-mac,iphone,ipad,ipad11}"
    # Prefer DEVICES env (user-facing); fall back to internal name.
    if [ -n "${DEVICES:-}" ] && [[ "${DEVICES}" != *"|"* ]]; then
        # User passed comma list of short names (mac,iphone,...) — not the internal array yet.
        want="$DEVICES"
    fi
    IFS=',' read -r -a _want_arr <<< "$want"
    local d
    for d in "${_want_arr[@]}"; do
        d="${d// /}"
        case "$d" in
            mac) DEVICES+=("mac|platform=macOS") ;;
            iphone) DEVICES+=("iphone|platform=iOS Simulator,name=$IPHONE_SIM") ;;
            ipad) DEVICES+=("ipad|platform=iOS Simulator,name=$IPAD_SIM") ;;
            ipad11) DEVICES+=("ipad11|platform=iOS Simulator,name=$IPAD11_SIM") ;;
            *)
                echo "ERROR: unknown device '$d' (use mac,iphone,ipad,ipad11)" >&2
                exit 1
                ;;
        esac
    done
}
# Capture DEVICES env before we rebuild the array (bash name clash).
DEVICES_FILTER="${DEVICES:-mac,iphone,ipad,ipad11}"
unset DEVICES 2>/dev/null || true
build_devices

mkdir -p "$OUTPUT_DIR"
echo "Capture plan: devices=${DEVICES_FILTER} langs=${LANGUAGES[*]}"

# Map project lang code → Apple locale + xcodebuild -testLanguage / -testRegion
apple_locale_for_lang() {
    case "$1" in
        en) echo "en_US" ;;
        zh-Hans) echo "zh_CN" ;;
        zh-Hant) echo "zh_TW" ;;
        ja) echo "ja_JP" ;;
        fr) echo "fr_FR" ;;
        pt-BR) echo "pt_BR" ;;
        es) echo "es_ES" ;;
        ko) echo "ko_KR" ;;
        de) echo "de_DE" ;;
        *) echo "$1" ;;
    esac
}

test_language_for_lang() {
    case "$1" in
        zh-Hans) echo "zh-Hans" ;;
        zh-Hant) echo "zh-Hant" ;;
        pt-BR) echo "pt-BR" ;;
        *) echo "$1" ;;
    esac
}

test_region_for_lang() {
    case "$1" in
        en) echo "US" ;;
        zh-Hans) echo "CN" ;;
        zh-Hant) echo "TW" ;;
        ja) echo "JP" ;;
        fr) echo "FR" ;;
        pt-BR) echo "BR" ;;
        es) echo "ES" ;;
        ko) echo "KR" ;;
        de) echo "DE" ;;
        *) echo "US" ;;
    esac
}

# Extract screenshots from xcresult bundle using xcresulttool (Xcode 16+ manifest shape)
extract_from_xcresult() {
    local result_path="$1" device_name="$2" lang="$3"
    local dst="$OUTPUT_DIR/$device_name/$lang"
    local tmp_dir
    tmp_dir=$(mktemp -d)

    if [ ! -d "$result_path" ]; then
        echo "  WARNING: missing result bundle $result_path"
        rm -rf "$tmp_dir"
        return
    fi

    xcrun xcresulttool export attachments \
        --path "$result_path" \
        --output-path "$tmp_dir" 2>/dev/null || {
        echo "  WARNING: failed to extract attachments"
        rm -rf "$tmp_dir"
        return
    }

    local manifest="$tmp_dir/manifest.json"
    if [ ! -f "$manifest" ]; then
        echo "  WARNING: no manifest found in $tmp_dir"
        ls -la "$tmp_dir" || true
        rm -rf "$tmp_dir"
        return
    fi

    mkdir -p "$dst"
    python3 - "$manifest" "$tmp_dir" "$dst" <<'PY'
import json, shutil, os, sys, re, struct

manifest_path, tmp_dir, dst = sys.argv[1:4]
with open(manifest_path, encoding="utf-8") as f:
    manifest = json.load(f)

copied = 0
entries = manifest if isinstance(manifest, list) else []
for entry in entries:
    # New Xcode format: { attachments: [{ exportedFileName, suggestedHumanReadableName }] }
    attachments = entry.get("attachments")
    if attachments is None:
        # Legacy flat entry
        attachments = [entry]

    for att in attachments:
        suggested = (
            att.get("suggestedHumanReadableName")
            or att.get("suggestedName")
            or ""
        )
        file_name = (
            att.get("exportedFileName")
            or att.get("fileName")
            or ""
        )
        if not file_name:
            continue
        src = os.path.join(tmp_dir, file_name)
        if not os.path.isfile(src):
            # Sometimes files land next to manifest without nested path
            alt = os.path.join(tmp_dir, os.path.basename(file_name))
            if os.path.isfile(alt):
                src = alt
            else:
                print(f"  WARNING: missing attachment file {file_name}", file=sys.stderr)
                continue

        # 01_ProjectSidebar_0_UUID.png → 01_ProjectSidebar.png
        base = os.path.basename(suggested) if suggested else os.path.basename(file_name)
        m = re.match(r"^(\d{2}_[A-Za-z0-9]+)", base)
        dst_name = f"{m.group(1)}.png" if m else base
        if not dst_name.endswith(".png"):
            dst_name += ".png"

        out = os.path.join(dst, dst_name)

        def png_wh(path):
            try:
                with open(path, "rb") as f:
                    f.read(8)
                    f.read(4)
                    if f.read(4) != b"IHDR":
                        return None
                    return struct.unpack(">II", f.read(8))
            except OSError:
                return None

        # Prefer correct device geometry over raw byte size. A large portrait leftover
        # from a failed simctl path must not beat a smaller upright landscape UITest 01.
        # Among same geometry class, prefer larger (filled demo sidebar vs empty white).
        if os.path.isfile(out):
            try:
                cur = png_wh(out)
                new = png_wh(src)
                if cur and new:
                    cw, ch = cur
                    nw, nh = new
                    cur_land = cw > ch
                    new_land = nw > nh
                    # iPad marketing wants landscape; never keep portrait over landscape.
                    if new_land and not cur_land:
                        pass  # replace portrait with landscape
                    elif cur_land and not new_land:
                        print(f"  keep existing {dst_name} (landscape beats portrait attachment)")
                        copied += 1
                        continue
                    elif dst_name == "01_ProjectSidebar.png" and cur_land and new_land:
                        if os.path.getsize(out) > os.path.getsize(src) + 8000:
                            print(f"  keep existing {dst_name} (larger landscape demo)")
                            copied += 1
                            continue
            except OSError:
                pass
        shutil.copy2(src, out)
        print(f"  {dst_name}")
        copied += 1

if copied == 0:
    print("  WARNING: no attachments copied", file=sys.stderr)
    sys.exit(1)
PY
    local py_status=$?
    if [ "$py_status" -ne 0 ]; then
        echo "  WARNING: failed to parse/copy attachments"
    fi

    # macOS only: prefer screencapture files (transparent window corners).
    # Prefer latest/mac/<lang>/ (per-device path). Never use bare latest/<lang>/ for
    # non-mac devices. When multiple copies exist, keep the largest pixel area that is
    # landscape ~1.5 (1540×1000 @2x = 3080×2000). Older 2200×1768 wrong-window captures
    # must not overwrite good marketing chrome.
    if [ "$device_name" = "mac" ]; then
        python3 - "$dst" "$lang" <<'PY'
import os, struct, sys
from pathlib import Path

dst, lang = sys.argv[1:3]
home = Path.home() / "Library" / "Containers"
candidates: dict[str, list[tuple[int, int, int, Path]]] = {}

def png_wh(path: Path):
    with path.open("rb") as f:
        f.read(8)
        f.read(4)
        if f.read(4) != b"IHDR":
            return None
        w, h = struct.unpack(">II", f.read(8))
        return w, h

roots = []
if home.is_dir():
    for p in home.rglob(f"reqeast-screenshots/latest/mac/{lang}/*.png"):
        roots.append(p)

for shot in roots:
    base = shot.name
    if not (base.startswith("0") and base[1].isdigit() and "_" in base and base.endswith(".png")):
        continue
    wh = png_wh(shot)
    if not wh:
        continue
    w, h = wh
    if w < h:
        continue  # portrait
    ratio = w / h if h else 0
    # Prefer near 1.54 marketing window; demote squat 1.24 wrong windows
    area = w * h
    score = area
    if 1.45 <= ratio <= 1.65:
        score += 10_000_000  # prefer correct aspect
    candidates.setdefault(base, []).append((score, w, h, shot))

for base, opts in sorted(candidates.items()):
    opts.sort(key=lambda t: t[0], reverse=True)
    score, w, h, shot = opts[0]
    out = Path(dst) / base
    # Only replace if better or missing
    if out.is_file():
        cur = png_wh(out)
        if cur:
            cw, ch = cur
            cr = cw / ch if ch else 0
            if 1.45 <= cr <= 1.65 and cw * ch >= w * h:
                print(f"  keep existing {base} ({cw}x{ch})")
                continue
    import shutil
    shutil.copy2(shot, out)
    print(f"  {base} (screencapture {w}x{h})")
PY
    fi

    # Sanity: flag wrong device geometry in the destination folder
    python3 - "$device_name" "$dst" <<'PY'
import os, struct, sys
device, dst = sys.argv[1:3]

def png_size(path):
    with open(path, "rb") as f:
        f.read(8)
        f.read(4)
        assert f.read(4) == b"IHDR"
        w, h = struct.unpack(">II", f.read(8))
        return w, h

for name in sorted(os.listdir(dst)):
    if not name.endswith(".png"):
        continue
    path = os.path.join(dst, name)
    try:
        w, h = png_size(path)
    except Exception:
        continue
    ratio = w / h if h else 0
    bad = False
    if device == "iphone" and ratio > 0.7:
        bad = True  # expect tall phone (~0.46)
    if device in ("ipad", "ipad11") and ratio < 1.0:
        # Landscape only. 13" ~1.33, 11" multi plate ~1.45. Never feed 13" into 11" plates.
        bad = True
    if device == "mac" and ratio < 1.0:
        bad = True
    if bad:
        print(f"  WARNING: {name} looks wrong for {device}: {w}x{h} (ratio {ratio:.2f})", file=sys.stderr)
PY

    rm -rf "$tmp_dir"
}

# Select the Simulator window for a given device via Window menu, then Landscape Left.
# Multiple booted sims: Device > Orientation applies only to the frontmost device window.
# Window menu titles look like "iPad Pro 13-inch (M5) – iOS 26.5" (en dash); match on sim name.
# IMPORTANT: iterate menu items by index. `repeat with mi in (every menu item)` yields dead
# refs so name is missing value and device rows never match.
force_sim_landscape() {
    local sim_name="$1"
    local attempt
    for attempt in 1 2 3 4 5; do
        osascript - "$sim_name" <<'APPLESCRIPT' 2>/dev/null || true
on run argv
    set simName to item 1 of argv
    tell application "Simulator" to activate
    delay 0.2
    tell application "System Events"
        tell process "Simulator"
            set frontmost to true
            try
                set winMenu to menu 1 of menu bar item "Window" of menu bar 1
                set cnt to count of menu items of winMenu
                repeat with i from 1 to cnt
                    try
                        set mi to menu item i of winMenu
                        set n to name of mi as text
                        if n contains simName then
                            click mi
                            exit repeat
                        end if
                    end try
                end repeat
            end try
            delay 0.3
            try
                click menu item "Landscape Left" of menu 1 of menu item "Orientation" of menu "Device" of menu bar 1
            end try
        end tell
    end tell
end run
APPLESCRIPT
        sleep 0.5
    done
}

# PNG edge ink: top vs left non-white pixel counts (status bar / chrome).
# Prints: width height top_ink left_ink
png_edge_ink() {
    python3 - "$1" <<'PY'
import struct, sys, zlib
from pathlib import Path
path = Path(sys.argv[1])
data = path.read_bytes()
assert data[:8] == b"\x89PNG\r\n\x1a\n"
i = 8
w = h = None
idat = b""
while i < len(data):
    ln = struct.unpack(">I", data[i : i + 4])[0]
    i += 4
    typ = data[i : i + 4]
    i += 4
    chunk = data[i : i + ln]
    i += ln + 4
    if typ == b"IHDR":
        w, h = struct.unpack(">II", chunk[:8])
    elif typ == b"IDAT":
        idat += chunk
    elif typ == b"IEND":
        break
raw = zlib.decompress(idat)
stride = w * 4
rows = []
prev = bytearray(stride)
p = 0
for _y in range(h):
    f = raw[p]
    p += 1
    row = bytearray(raw[p : p + stride])
    p += stride
    if f == 1:
        for x in range(stride):
            left = row[x - 4] if x >= 4 else 0
            row[x] = (row[x] + left) & 255
    elif f == 2:
        for x in range(stride):
            row[x] = (row[x] + prev[x]) & 255
    elif f == 3:
        for x in range(stride):
            left = row[x - 4] if x >= 4 else 0
            row[x] = (row[x] + ((left + prev[x]) // 2)) & 255
    elif f == 4:
        for x in range(stride):
            a = row[x - 4] if x >= 4 else 0
            b = prev[x]
            c = prev[x - 4] if x >= 4 else 0
            p0 = a + b - c
            pa, pb, pc = abs(p0 - a), abs(p0 - b), abs(p0 - c)
            pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
            row[x] = (row[x] + pr) & 255
    rows.append(bytes(row))
    prev = row

def ink_row(row, x0, x1):
    n = 0
    for x in range(x0 * 4, x1 * 4, 4):
        r, g, b = row[x], row[x + 1], row[x + 2]
        if r < 240 or g < 240 or b < 240:
            n += 1
    return n

band = min(40, h)
top = sum(ink_row(rows[y], 0, w) for y in range(band))
left = sum(ink_row(rows[y], 0, min(40, w)) for y in range(h))
print(w, h, top, left)
PY
}

# Normalize iPad simctl PNG to upright landscape (status bar on top).
# Portrait buffer + landscape UI → CW 270. Never 270-rotate upright portrait (→ sideways).
normalize_ipad_marketing_png() {
    local png="$1"
    local w h top left
    read -r w h top left < <(png_edge_ink "$png")
    if [ -z "$w" ] || [ -z "$h" ]; then
        return 1
    fi
    # Already upright landscape: chrome on top edge, not left.
    if [ "$w" -gt "$h" ] && [ "$top" -gt $((left * 2)) ]; then
        return 0
    fi
    # Landscape dims but status bar on left: bad 270 of upright portrait → reverse with CW 90
    # then fail (caller must re-force landscape). Or CW 270 again? CW90 → upright portrait.
    if [ "$w" -gt "$h" ] && [ "$left" -gt $((top * 2)) ]; then
        echo "  WARNING: sideways landscape (top=$top left=$left); recovering via CW 90 → portrait then fail path"
        sips -r 90 "$png" --out "$png" >/dev/null
        read -r w h top left < <(png_edge_ink "$png")
    fi
    # Portrait buffer: only rotate 270 when content is sideways (left chrome >> top).
    if [ "$h" -gt "$w" ]; then
        if [ "$left" -gt $((top * 2)) ]; then
            sips -r 270 "$png" --out "$png" >/dev/null
            read -r w h top left < <(png_edge_ink "$png")
            if [ "$w" -gt "$h" ] && [ "$top" -gt $((left * 2)) ]; then
                return 0
            fi
            echo "  WARNING: after CW 270 still wrong (top=$top left=$left)"
            return 1
        fi
        # Upright portrait: landscape never took. Do not rotate.
        echo "  WARNING: upright portrait (top=$top left=$left); landscape not applied"
        return 1
    fi
    return 0
}

# Capture test01 (ProjectSidebar) via simctl for iOS devices.
# Args: sim_name device_name lang mode [reboot]
#   reboot=1 (default): full prepare_sim locale reboot.
#   reboot=0: keep current device orientation (use after UITest left iPad landscape).
capture_simctl_test01() {
    local sim_name="$1" device_name="$2" lang="$3" mode="$4"
    local do_reboot="${5:-1}"
    local dst="$OUTPUT_DIR/$device_name/$lang"
    local app_path
    local apple_locale
    apple_locale=$(apple_locale_for_lang "$lang")

    # Prefer newest Debug-iphonesimulator build
    app_path=$(find ~/Library/Developer/Xcode/DerivedData/Reqeast-*/Build/Products/Debug-iphonesimulator \
        -name "Reqeast.app" -type d 2>/dev/null | while read -r p; do
            stat -f '%m %N' "$p"
        done | sort -rn | head -1 | cut -d' ' -f2-)

    if [ -z "$app_path" ]; then
        echo "  WARNING: could not find built app"
        return
    fi

    local sim_udid
    sim_udid=$(xcrun simctl list devices available --json 2>/dev/null | \
        python3 -c "
import sys, json
d = json.load(sys.stdin)
for rt, devs in d['devices'].items():
    for dev in devs:
        if dev.get('name') == '$sim_name' and dev.get('isAvailable', False):
            print(dev['udid'])
            sys.exit(0)
" 2>/dev/null)

    if [ -z "$sim_udid" ]; then
        echo "  WARNING: simulator '$sim_name' not found"
        return
    fi

    xcrun simctl boot "$sim_udid" 2>/dev/null || true
    xcrun simctl install "$sim_udid" "$app_path" 2>/dev/null
    xcrun simctl terminate "$sim_udid" app.reqeast 2>/dev/null || true

    # Locale + marketing status bar / CFU. reboot=0 after UITest keeps landscape.
    prepare_sim_for_marketing "$sim_udid" "$lang" "$apple_locale" "$do_reboot"

    # Only force orientation via Simulator menu when we rebooted (orientation reset).
    # After UITest, XCUIDevice already left the device landscape; menu automation can hang
    # or flip the wrong window and is not needed.
    if [ "$do_reboot" = "1" ] && { [ "$device_name" = "ipad" ] || [ "$device_name" = "ipad11" ]; }; then
        force_sim_landscape "$sim_name"
        xcrun simctl spawn "$sim_udid" notifyutil -p com.apple.SpringBoard.orientationChanged 2>/dev/null || true
    fi

    xcrun simctl launch "$sim_udid" app.reqeast \
        "$mode" \
        -AppleLanguages "($lang)" \
        -AppleLocale "$apple_locale" \
        2>/dev/null

    # Demo list paint needs more than a couple of seconds on iPad (esp. 11").
    # 3s produced empty sidebars while a11y already reported rows. UITest a11y is often
    # empty-white while simctl 8s settles pixels.
    if [ "$device_name" = "ipad" ] || [ "$device_name" = "ipad11" ]; then
        sleep 8
    else
        sleep 3
    fi
    # CFU / tips can reappear after launch; re-stamp status bar only (no reboot — kills app).
    prepare_sim_for_marketing "$sim_udid" "$lang" "$apple_locale" 0
    sleep 0.5

    mkdir -p "$dst"
    local shot="$dst/01_ProjectSidebar.png"
    xcrun simctl io "$sim_udid" screenshot "$shot" 2>/dev/null

    if { [ "$device_name" = "ipad" ] || [ "$device_name" = "ipad11" ]; } && [ -f "$shot" ]; then
        if ! normalize_ipad_marketing_png "$shot"; then
            echo "  WARNING: $device_name/$lang 01 not upright landscape after simctl (reboot=$do_reboot)" >&2
        fi
    fi
    xcrun simctl terminate "$sim_udid" app.reqeast 2>/dev/null || true
    echo "  01_ProjectSidebar.png (simctl reboot=$do_reboot)"
}

# Write SpringBoard / Global Domain language + locale on a booted sim.
write_sim_locale() {
    local udid="$1" l="$2" al="$3"
    if [ -n "$l" ]; then
        # Prefer primary language code SpringBoard expects (en, de, ja, zh-Hans, …)
        xcrun simctl spawn "$udid" defaults write "Apple Global Domain" AppleLanguages -array "$l" 2>/dev/null || true
    fi
    if [ -n "$al" ]; then
        xcrun simctl spawn "$udid" defaults write "Apple Global Domain" AppleLocale -string "$al" 2>/dev/null || true
        xcrun simctl spawn "$udid" defaults write "Apple Global Domain" AppleLocaleIdentifier -string "$al" 2>/dev/null || true
    fi
}

# Apply per-locale system language + marketing status bar + CFU suppression.
# Status bar *date* language follows SpringBoard locale. If the sim was left on de_DE,
# EN frames show "Fr. 10. Juli". Always rewrite locale and restart SpringBoard.
# Args: udid [lang] [apple_locale] [reboot]
#   reboot=1 (default): shutdown+boot so SpringBoard reloads date language.
#   reboot=0: locale + status bar only (use after app is already running; reboot kills it).
prepare_sim_for_marketing() {
    local sim_udid="$1"
    local lang="${2:-}"
    local apple_locale="${3:-}"
    local do_reboot="${4:-1}"

    write_sim_locale "$sim_udid" "$lang" "$apple_locale"

    # TipKit / tips daemon
    xcrun simctl spawn "$sim_udid" defaults write com.apple.tipsd TipsDisabled -bool true 2>/dev/null || true
    xcrun simctl spawn "$sim_udid" defaults write com.apple.TipKit displayFrequency -string never 2>/dev/null || true
    # Core Follow Up that posts "Ready for Apple Intelligence" over the status bar
    xcrun simctl spawn "$sim_udid" defaults delete com.apple.generativeexperiences.corefollowup \
        DateOfLastAppleIntelligenceReadinessCFU 2>/dev/null || true
    xcrun simctl spawn "$sim_udid" defaults delete com.apple.generativeexperiences.corefollowup 2>/dev/null || true
    xcrun simctl spawn "$sim_udid" defaults delete com.apple.generativeexperiences 2>/dev/null || true
    # Siri / Apple Intelligence eligibility overrides (best-effort; keys move across OS versions)
    xcrun simctl spawn "$sim_udid" defaults write com.apple.assistant.support "Assistant Enabled" -bool false 2>/dev/null || true
    xcrun simctl spawn "$sim_udid" defaults write com.apple.CloudSubscriptionFeatures.gm eligibilityOverride -int 0 2>/dev/null || true
    xcrun simctl spawn "$sim_udid" defaults write com.apple.gms.availability override -int 0 2>/dev/null || true
    xcrun simctl spawn "$sim_udid" defaults write com.apple.gms.availability "com.apple.gms.availability.wasAvailable" -bool false 2>/dev/null || true
    xcrun simctl spawn "$sim_udid" defaults write com.apple.CloudSubscriptionFeatures.gm.engagement engagementSeen -bool true 2>/dev/null || true
    # Mark readiness CFU as already handled (best-effort; key names drift across iOS versions)
    xcrun simctl spawn "$sim_udid" defaults write com.apple.generativeexperiences.corefollowup \
        DateOfLastAppleIntelligenceReadinessCFU -date "2001-01-01 00:00:00 +0000" 2>/dev/null || true

    if [ "$do_reboot" = "1" ]; then
        # SpringBoard caches locale hard. kickstart alone leaves "Fr. 10. Juli" on EN.
        # Shutdown + boot reloads GlobalPreferences for status bar date language.
        xcrun simctl shutdown "$sim_udid" 2>/dev/null || true
        sleep 1
        xcrun simctl boot "$sim_udid" 2>/dev/null || true
        local i
        for i in $(seq 1 40); do
            if xcrun simctl list devices | grep -q "$sim_udid.*(Booted)"; then
                break
            fi
            sleep 0.5
        done
        sleep 2
        # Re-apply locale after boot (device may merge defaults again)
        write_sim_locale "$sim_udid" "$lang" "$apple_locale"
    fi

    # Clock only (this Xcode rejects ISO date strings). Date *language* comes from locale.
    xcrun simctl status_bar "$sim_udid" override \
        --time "9:41" \
        --dataNetwork wifi \
        --wifiBars 3 \
        --cellularBars 4 \
        --batteryState charged \
        --batteryLevel 100 \
        --operatorName "" \
        2>/dev/null || true
}

total=$((${#LANGUAGES[@]} * ${#DEVICES[@]}))
current=0
failures=0

for device_entry in "${DEVICES[@]}"; do
    device_name="${device_entry%%|*}"
    destination="${device_entry#*|}"

    for lang in "${LANGUAGES[@]}"; do
        current=$((current + 1))
        apple_locale=$(apple_locale_for_lang "$lang")
        test_lang=$(test_language_for_lang "$lang")
        test_region=$(test_region_for_lang "$lang")
        echo "[$current/$total] $device_name / $lang (locale=$apple_locale test=$test_lang-$test_region)"

        # Absolute path so sandboxed UITest runner can read it (not container tmp).
        # platform is required: UITest runner can mis-report iPad as iPhone via UIDevice.idiom.
        printf 'lang=%s\nappleLocale=%s\nplatform=%s\n' "$lang" "$apple_locale" "$device_name" > "$LANG_CONFIG"
        # Also write host TMPDIR for any non-sandboxed readers.
        printf 'lang=%s\nappleLocale=%s\nplatform=%s\n' "$lang" "$apple_locale" "$device_name" > "$TMPDIR/reqeast-screenshot-config"

        # iPhone empty welcome: simctl is enough (no landscape matrix).
        # iPad 01: use UITest (XCUIDevice landscape + CFU dismiss). simctl AppleScript
        # orientation is unreliable with multiple booted sims and often yields portrait.
        if [ "$device_name" = "iphone" ]; then
            capture_simctl_test01 "$IPHONE_SIM" "$device_name" "$lang" "-screenshotEmpty"
        fi

        # Pre-boot sim and strip system tips before UITest screenshots
        if [ "$device_name" = "iphone" ] || [ "$device_name" = "ipad" ] || [ "$device_name" = "ipad11" ]; then
            sim_for_device="$IPHONE_SIM"
            [ "$device_name" = "ipad" ] && sim_for_device="$IPAD_SIM"
            [ "$device_name" = "ipad11" ] && sim_for_device="$IPAD11_SIM"
            sim_udid=$(xcrun simctl list devices available --json 2>/dev/null | \
                python3 -c "
import sys, json
d = json.load(sys.stdin)
for rt, devs in d['devices'].items():
    for dev in devs:
        if dev.get('name') == '$sim_for_device' and dev.get('isAvailable', False):
            print(dev['udid']); sys.exit(0)
" 2>/dev/null || true)
            if [ -n "${sim_udid:-}" ]; then
                xcrun simctl boot "$sim_udid" 2>/dev/null || true
                prepare_sim_for_marketing "$sim_udid" "$lang" "$apple_locale"
            fi
        fi

        local_result="/tmp/reqeast-screenshots-${device_name}-${lang}.xcresult"
        rm -rf "$local_result"

        if [ "$device_name" = "mac" ]; then
            test_filter="-only-testing:ReqeastUITests/ScreenshotTests"
        elif [ "$device_name" = "ipad11" ]; then
            # Multi collage: 01 project list + 02 HTTP (Mac multi uses ipad11/02).
            # UITest test01: XCUIDevice landscape + 8s demo settle + CFU dismiss.
            test_filter="-only-testing:ReqeastUITests/ScreenshotTests/test01_ProjectSidebar -only-testing:ReqeastUITests/ScreenshotTests/test02_HttpRequest"
        elif [ "$device_name" = "ipad" ]; then
            # 13" standalone: full set via UITest (landscape + locale + CFU).
            test_filter="-only-testing:ReqeastUITests/ScreenshotTests/test01_ProjectSidebar -only-testing:ReqeastUITests/ScreenshotTests/test02_HttpRequest -only-testing:ReqeastUITests/ScreenshotTests/test03_ProtocolMenu -only-testing:ReqeastUITests/ScreenshotTests/test04_SocketView"
        else
            # iPhone: 01 from simctl empty; UITest 02–04.
            test_filter="-only-testing:ReqeastUITests/ScreenshotTests/test02_HttpRequest -only-testing:ReqeastUITests/ScreenshotTests/test03_ProtocolMenu -only-testing:ReqeastUITests/ScreenshotTests/test04_SocketView"
        fi

        # -testLanguage / -testRegion constrain the app + test host localization.
        # SCREENSHOT_LANG is also read by ScreenshotTests for launchArguments.
        # shellcheck disable=SC2086
        if ! SCREENSHOT_LANG="$lang" \
            SCREENSHOT_APPLE_LOCALE="$apple_locale" \
            SCREENSHOT_PLATFORM="$device_name" \
            xcodebuild test \
            -project "$PROJECT_DIR/Reqeast.xcodeproj" \
            -scheme Reqeast \
            $test_filter \
            -destination "$destination" \
            -resultBundlePath "$local_result" \
            -parallel-testing-enabled NO \
            -testLanguage "$test_lang" \
            -testRegion "$test_region" \
            2>&1 | tail -12; then
            echo "  FAILED ($device_name / $lang)"
            failures=$((failures + 1))
        fi

        extract_from_xcresult "$local_result" "$device_name" "$lang" || true
        rm -rf "$local_result"

        # iPad multi + standalone 01: UITest forces landscape/locale/CFU, but list paint is
        # often empty white while a11y is hittable. simctl -screenshotMode + 8s settles demos.
        # reboot=0 keeps the XCUIDevice landscape from the UITest cell above.
        if [ "$device_name" = "ipad11" ] || [ "$device_name" = "ipad" ]; then
            fill_sim="$IPAD_SIM"
            [ "$device_name" = "ipad11" ] && fill_sim="$IPAD11_SIM"
            echo "  $device_name 01: simctl demo fill (no reboot, keep landscape)"
            capture_simctl_test01 "$fill_sim" "$device_name" "$lang" "-screenshotMode" "0"
        fi
    done
done

echo "Done. Raw screenshots in $OUTPUT_DIR"
if [ "$failures" -gt 0 ]; then
    echo "WARNING: $failures capture cell(s) failed. Inspect logs and re-run those device/lang pairs."
    echo "Partial re-run: LANGS=<lang> DEVICES=<mac|iphone|ipad|ipad11> bash scripts/capture-screenshots.sh"
    exit 1
fi

# Hard gate: wrong aspect / empty demo / missing ipad11 must fail before compose.
echo ""
echo "Validating raws..."
LANGS="$(IFS=','; echo "${LANGUAGES[*]}")" \
DEVICES="$DEVICES_FILTER" \
    bash "$SCRIPT_DIR/validate-screenshots.sh" --raws-only
