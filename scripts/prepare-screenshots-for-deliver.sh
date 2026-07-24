#!/bin/bash
set -euo pipefail

# Copies composited screenshots from screenshots/final/ into fastlane/screenshots/
# organized by Fastlane locale codes. Deliver detects device type by image dimensions.
# Outputs two directories: screenshots for iOS (iPhone + iPad) and screenshots-mac for macOS.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SOURCE_DIR="$PROJECT_DIR/screenshots/final"
IOS_DIR="$PROJECT_DIR/fastlane/screenshots"
MAC_DIR="$PROJECT_DIR/fastlane/screenshots-mac"

# project_lang → fastlane_locale pairs
LOCALE_PAIRS=(
  "en:en-US"
  "de:de-DE"
  "es:es-ES"
  "fr:fr-FR"
  "ja:ja"
  "ko:ko"
  "pt-BR:pt-BR"
  "zh-Hans:zh-Hans"
  "zh-Hant:zh-Hant"
)

if [ ! -d "$SOURCE_DIR" ]; then
  echo "No screenshots found at $SOURCE_DIR"
  echo "Run 'just screenshots' first to generate them."
  exit 1
fi

rm -rf "$IOS_DIR" "$MAC_DIR"

count=0

for pair in "${LOCALE_PAIRS[@]}"; do
  lang="${pair%%:*}"
  locale="${pair#*:}"

  for device in iphone ipad mac; do
    src_dir="$SOURCE_DIR/$device/$lang"
    if [ ! -d "$src_dir" ]; then
      echo "WARNING: missing $src_dir"
      continue
    fi

    if [ "$device" = "mac" ]; then
      dest_dir="$MAC_DIR/$locale"
    else
      dest_dir="$IOS_DIR/$locale"
    fi
    mkdir -p "$dest_dir"

    for file in "$src_dir"/*.png; do
      [ -f "$file" ] || continue
      fname=$(basename "$file")
      cp "$file" "$dest_dir/${device}_${fname}"
      count=$((count + 1))
    done
  done
done

echo "Prepared $count screenshots (iOS: $IOS_DIR, Mac: $MAC_DIR)"
