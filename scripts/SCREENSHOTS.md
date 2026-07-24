# App Store screenshot pipeline

**Read this entire file before any screenshot work.** Wrong-device “fixes” and painting system chrome cost hours. The scripts encode the rules; this doc is the agent playbook.

## Agent checklist (do not skip)

1. **Never fight the image.** Recapture on the correct simulator. Do not stretch, crop, or non-uniform-scale a wrong-device raw into a plate. Do not paint out banners in the PNG.
2. **Devices are not interchangeable** (table below). Multi collage iPad is **11"**, standalone iPad is **13"**.
3. **Validate before compose:** `just screenshots-validate` (also runs automatically after capture and before compose).
4. **Partial re-runs only:** use `LANGS=` + `DEVICES=` (see recipes). Never `source` capture scripts.
5. **Accept criteria per slot** (below) before opening Preview or uploading ASC.

## HARD RULE: capture the right device

| Plate / slot | Capture on | Raw dir | Aspect |
|--------------|------------|---------|--------|
| Mac standalone 01–03 | **normal** app chrome (see `references/mac-1.png`) — no forced toolbar hacks | `raw/mac/` | ~1.4 landscape |
| iPhone standalone 01–03 | `iPhone 17 Pro Max` | `raw/iphone/` | portrait (~0.46) |
| iPad standalone 01–03 | **`iPad Pro 13-inch (M5)`** | `raw/ipad/` | **~1.33 landscape** |
| Multi collage iPad bezel (Mac/iPhone final **03**) | **`iPad Pro 11-inch (M5)`** | **`raw/ipad11/`** | **~1.45 landscape** |

**Do:**

1. Recapture on the simulator that matches the Pixelmator plate.
2. Compose with **uniform scale only** (preserve UI proportions).
3. Status bar 9:41 + no “Ready for Apple Intelligence” CFU (`prepare_sim_for_marketing`).
4. iPad/Mac **demo sidebars** must show Weather / Stripe / Chat / IoT (not empty white).

**Do not:**

1. Stretch/crop 13" into 11" plates (or phone↔iPad↔Mac).
2. “Fix” aspect in Pixelmator / sips as a substitute for recapture.
3. Paint over the Apple Intelligence banner. Clear CFU + re-capture.
4. Share one `latest/<lang>/` path across devices (Mac screencapture must never land in `iphone/` or `ipad*`).
5. `source scripts/capture-screenshots.sh` (it refuses; still never do it).

Root short form: [`Agents.md`](../Agents.md) → **Marketing screenshots**. UITest notes: [`ReqeastUITests/AGENTS.md`](../ReqeastUITests/AGENTS.md).

---

## Commands (happy path + partial)

```sh
# Full pipeline (all 9 locales × mac + iphone + ipad + ipad11 → compose)
just screenshots

# Steps
just screenshots-capture          # raws → screenshots/raw/
just screenshots-validate         # hard fail on bad geometry / empty demos / missing multi
just screenshots-compose          # validates raws, Pixelmator → screenshots/final/, validates finals
just deliver-prepare-screenshots  # → fastlane/screenshots{,-mac}/
just deliver-screenshots          # ASC: iOS + Mac (not iOS-only)
```

### Partial re-runs (always prefer these)

```sh
# English only, multi iPad + iPhone (typical after multi plate fix)
LANGS=en DEVICES=ipad11,iphone bash scripts/capture-screenshots.sh
LANGS=en bash scripts/compose-screenshots.sh
open -a Preview screenshots/final/iphone/en/0{1,2,3}.png

# One language, all devices
LANGS=ja bash scripts/capture-screenshots.sh

# Mac only after window chrome change
LANGS=en DEVICES=mac bash scripts/capture-screenshots.sh

# Validate only
LANGS=en just screenshots-validate
# or
LANGS=en DEVICES=ipad11 bash scripts/validate-screenshots.sh --raws-only
```

| Env | Values | Effect |
|-----|--------|--------|
| `LANGS` | `en`, `en,ja`, … | Subset of locales |
| `DEVICES` | `mac`, `iphone`, `ipad`, `ipad11` (comma list) | Subset of capture cells |
| `LANGUAGES` | space-separated (compose only) | Same as `LANGS` for compose |

Locales: `en`, `zh-Hans`, `zh-Hant`, `ja`, `fr`, `pt-BR`, `es`, `ko`, `de`.

---

## What each raw is + compose map

| Raw file | Scene | Content rules |
|----------|--------|----------------|
| `01_ProjectSidebar` | Project list / welcome | **iPhone:** empty welcome (`-screenshotEmpty`) on purpose. **iPad 13" / iPad 11" / Mac:** demo projects **must** be visible (Weather, Stripe, Chat, IoT). |
| `02_HttpRequest` | HTTP editor | Weather API → GET Current Weather |
| `03_ProtocolMenu` | New request menu open | Must show **gRPC** (+ all protocols). Becomes final **02**. |
| `04_SocketView` | TCP session | IoT Gateway → TCP Telemetry Stream (not always in final 01–03) |

| Final | Source raw(s) |
|-------|----------------|
| `01` | `01_ProjectSidebar` + titles |
| `02` | `03_ProtocolMenu` (“Six Protocols”) |
| `03` multi | **iPhone multi:** iPhone `01` (empty OK) + Mac `01` (**demos**) + **iPad11 `01` (**demos**)** |
| | **Mac multi:** Mac `02` HTTP + **iPad11 `01` project list** + iPhone `01` empty (not the same HTTP on Mac and iPad) |
| | **iPad multi:** Mac + iPhone `01` + **iPad11 `01` (11" bezel ~1.45)** — never 13" raw in multi |

Titles: **`scripts/screenshot-titles.json`**. Update when protocol count / gRPC / copy changes. Never ship “Five Protocols” if the app has six.

### iPad demo settle (empty sidebar trap)

- simctl `01`: **8s** after launch (3s produced empty white columns while a11y still saw rows).
- UITest: **3s** after Weather is hittable.
- **iPad11 `01`:** prefer **simctl** (8s). Do not let empty UITest `01` overwrite a larger good simctl frame (extract keeps larger file).

---

## Accept criteria (open Preview only after these)

| Check | Pass |
|-------|------|
| Geometry | iPhone portrait; iPad 13" landscape ~1.33; iPad11 ~1.45; Mac landscape ~1.5 |
| Multi iPad | From `raw/ipad11/`, not stretched 13" |
| Demo sidebars | Mac + iPad11 (+ standalone iPad) show 4 demo projects on `01` |
| iPhone 01 / multi phone | Empty welcome is OK |
| System chrome | No “Ready for Apple Intelligence”; prefer 9:41 |
| Mac title bar | Traffic lights → chips → detail title “Reqeast” (see `screenshots/references/mac-1.png`). Not: gap after lights, chips floating mid-bar, missing nav title. |
| Final 02 | Protocol menu includes **gRPC** |
| Locale | Non-EN chrome localized; demo **names** stay English |

`just screenshots-validate` enforces geometry + file size proxies for empty demos.

---

## Hard requirements (do not skip)

### 1. Window must exist under `xcodebuild` (macOS)

CLI often launches **menu bar, zero windows**. Mitigation: `AppDelegate.ensureFallbackMainWindowIfNeeded()` (delayed so WindowGroup can win), `.defaultLaunchBehavior(.presented)`, `app.activate()`, largest **named** layer-0 window for `screencapture -l`. Screenshot mode loads demo data only — **never** force `title` / `titleVisibility` / `toolbarStyle` (that breaks the menu bar).

### 2. Language must reach the UITest process

Write **`/tmp/reqeast-screenshot-config`** (not shell `$TMPDIR`):

```text
lang=ja
appleLocale=ja_JP
platform=ipad11
```

Plus env `SCREENSHOT_LANG` / `SCREENSHOT_APPLE_LOCALE` / `SCREENSHOT_PLATFORM`, and `-testLanguage` / `-testRegion`.

| lang | AppleLocale | testRegion |
|------|-------------|------------|
| en | en_US | US |
| zh-Hans | zh_CN | CN |
| zh-Hant | zh_TW | TW |
| ja | ja_JP | JP |
| fr | fr_FR | FR |
| pt-BR | pt_BR | BR |
| es | es_ES | ES |
| ko | ko_KR | KR |
| de | de_DE | DE |

### 3. xcresult extract (Xcode 16+)

Use `exportedFileName` + `suggestedHumanReadableName`. Mac-only screencapture overlay from `latest/mac/<lang>/` — **never** into iphone/ipad.

### 3b. iPad landscape (framebuffer stays portrait)

UI is landscape; PNG often portrait until **CW 270°** (`sips -r 270` / UITest rotate). Geometry check fails portrait iPad raws.

### 3c. Pixelmator constrain proportions

Default constrain rewrites width when setting height → Mac collapses. Prefer **uniform scale**. Never non-uniform stretch of app chrome.

### 3d. iPad 13" vs 11"

| Use | Sim | Raw | Aspect |
|-----|-----|-----|--------|
| Standalone iPad 01–03 | 13" M5 | `raw/ipad/` | ~1.33 |
| Multi iPad bezel | **11" M5** | **`raw/ipad11/`** | **~1.45** |

### 3e. Apple Intelligence CFU banner

Not TipKit alone. Domain: `com.apple.generativeexperiences.corefollowup` / `DateOfLastAppleIntelligenceReadinessCFU`.

`prepare_sim_for_marketing udid lang apple_locale [reboot]`:

- Writes `AppleLanguages` + `AppleLocale` for **this** cell (status bar date language follows SpringBoard locale)
- **`reboot=1` (default):** full `simctl shutdown` + `boot` so SpringBoard reloads GlobalPreferences. `kickstart` alone leaves “Fr. 10. Juli” on EN after a `de` cell.
- **`reboot=0`:** locale + CFU + status bar only. Use after the app is running (reboot kills it).
- Deletes CFU domain; TipKit / Siri / GMS overrides
- `simctl status_bar override` → time `9:41` only (this Xcode rejects ISO date strings), wifi, full battery. Date *language* comes from locale, not the override.

### iPad 01 capture path (UITest landscape + simctl demos)

1. **UITest** (`test01`–`04` on 13", `test01`–`02` on 11"): `XCUIDevice` landscape + CFU dismiss + correct geometry. List paint is often empty white while a11y is hittable.
2. **simctl demo fill** after the UITest cell: `capture_simctl_test01 … reboot=0` (no SpringBoard reboot, keep UITest landscape), 8s settle, overwrite `01_ProjectSidebar.png`.
3. **Do not** prefer a larger portrait leftover over a smaller landscape attachment (extract prefers landscape geometry).
4. **Simulator Window menu:** when forcing orientation from AppleScript, iterate Window menu items **by index** (not `repeat with mi in every menu item`; dead refs yield `missing value`).

**Status bar date language must match the capture locale** (EN → English Fri/Jul, not German Fr./Juli). Inspect every locale after capture before ASC.

UITest: `dismissSystemChromeTips()` swipe/close retries. **Re-capture if still visible; never paint.**

### 3f. Mac menu bar (match `screenshots/references/mac-1.png` and real `open -a`)

**Correct:** traffic lights → toolbar chips (cloud / + / sidebar) → detail title **“Reqeast”** (or request/project name).  
**Wrong:** any AppDelegate mutation of `window.title` / `titleVisibility` / `toolbarStyle` — that reorders the menu bar (title between lights and chips, or chips with no title).

Screenshot mode loads demo data only. **Do not re-skin the title bar.** `applyMarketingScreenshotWindowChrome` is a no-op for chrome. Capture the real WindowGroup window via `screencapture -l`.

### 4–6. Pixelmator / compile / MCP

- Templates: **`mac.pxd` / `iphone.pxd` / `ipad.pxd`**. Needs Pixelmator Pro + Automation permission.
- `RUN_SCREENSHOT_TESTS` in UITest Debug; `just test-ui` skips ScreenshotTests.
- MCP export skipped in screenshot mode.

---

## Scripts and just recipes

| Command | Role |
|---------|------|
| `scripts/capture-screenshots.sh` | Capture loop; `LANGS`/`DEVICES`; refuse `source`; validate raws at end |
| `scripts/compose-screenshots.sh` | Pixelmator compose; validate raws first + finals after |
| `scripts/validate-screenshots.sh` | Geometry + size gates (empty demo / wrong aspect) |
| `scripts/prepare-screenshots-for-deliver.sh` | → fastlane dirs |
| `scripts/screenshot-titles.json` | Titles (9 langs) |
| `scripts/templates/*.pxd` | Device frames |

```sh
just screenshots              # capture + compose
just screenshots-capture
just screenshots-compose
just screenshots-validate
just screenshots-quick        # compose only (still validates raws)
just deliver-prepare-screenshots
just deliver-screenshots      # iOS + Mac
```

Sim names hardcoded: `IPHONE_SIM` / `IPAD_SIM` / `IPAD11_SIM` in capture script. Rename when Apple renames devices.

---

## Upload / ASC

```sh
just deliver-screenshots   # prepare + iOS screenshots + Mac screenshots + Mac prune
just deliver-metadata
just deliver               # metadata + screenshots (iOS then Mac)
```

**Counts per language (not bugs):**

| Platform | Files on ASC | Why |
|----------|--------------|-----|
| iOS | **6** (3 iPhone + 3 iPad) | Same locale folder; deliver sorts by pixel size |
| Mac | **3** (`mac_01`…`mac_03`) | Single `APP_DESKTOP` set |

Local layout: `fastlane/screenshots/{locale}/iphone_*.png` + `ipad_*.png`, and `fastlane/screenshots-mac/{locale}/mac_*.png`.

**Mac double-upload (6 instead of 3):** deliver can re-upload after a false "missing" verify while ASC is still processing the first batch. Prune extra `APP_DESKTOP` shots with maintainer-only ASC tooling (not in this public tree). Keep one of each `mac_01` / `mac_02` / `mac_03` per locale.

**Titles / margins:** long iPhone slot-03 headlines overflow the template (edge-to-edge). Keep copy short in `screenshot-titles.json` (e.g. “Data never leaves your iPhone.”). Compose also shrinks title font when character count is high. Prefer template text-box insets for permanent padding.

Target editable ASC version (e.g. 1.2). Auth: Spaceship 2FA or API key. ASC 500s during screenshot finalize: wait or re-run; do not leave deliver spinning forever.

**ASC tools (current stack):** fastlane 2.237.0+ (deliver), Xcode `exportArchive` for binaries (`just deploy`), notarytool/altool/iTMSTransporter via Xcode/Transporter. Keep brew `fastlane` on latest stable.

---

## Smoke before a long full run

```sh
# EN multi path only (~minutes, not hours)
LANGS=en DEVICES=mac,iphone,ipad11 bash scripts/capture-screenshots.sh
LANGS=en bash scripts/compose-screenshots.sh
open -a Preview screenshots/final/iphone/en/0{1,2,3}.png
# Visual: multi 03 iPad has demos + no AI tip; phone empty OK; protocol menu has gRPC
```

---

## File map

| Path | Role |
|------|------|
| `scripts/capture-screenshots.sh` | Capture, locale map, simctl 01, CFU clear, extract |
| `scripts/compose-screenshots.sh` | Pixelmator |
| `scripts/validate-screenshots.sh` | Hard gate |
| `scripts/prepare-screenshots-for-deliver.sh` | fastlane layout |
| `scripts/screenshot-titles.json` | Marketing copy |
| `scripts/templates/{mac,iphone,ipad}.pxd` | Frames |
| `ReqeastUITests/ScreenshotTests.swift` | UITest capture |
| `Reqeast/ReqeastApp.swift` | Window fallback, landscape, demo load, chrome |
| `Reqeast/Models/StorageEnvironment.swift` | `screenshot.` prefix wins over `test.`/`debug.` |
| `Reqeast/Services/MCPExportService.swift` | Skip export in screenshot mode |

---

## Known pain (fixed once; do not regress)

1. Menu bar, no window under CLI UITest → AppKit fallback window  
2. All locales English → `/tmp/reqeast-screenshot-config` + `-testLanguage` + real `AppleLocale`  
3. Extract copies nothing / IsADirectoryError → new xcresult manifest keys  
4. Compose “Can’t get document mac” → use `mac.pxd` names  
5. “Five Protocols” after gRPC → update `screenshot-titles.json`  
6. Demo names English → expected; check chrome localization  
7. **Mac shot on iPhone** → per-device `latest/{mac,iphone,ipad,ipad11}/` only  
8. **13" raw in 11" multi plate** → capture `ipad11`, never stretch  
9. **Empty iPad sidebar** with hittable Weather → wait **8s** simctl; keep larger 01 over empty UITest  
10. **“Ready for Apple Intelligence”** → CFU delete + status_bar; not TipKit alone; never paint PNG  
11. **Portrait iPad raw** → CW 270° rotate  
12. **Mac tiny / squashed** → uniform scale in compose; capture normal WindowGroup size  
13. **Mac menu bar wrong** → do not force title/titleVisibility/toolbarStyle. Native chrome only (`references/mac-1.png`: lights → chips → “Reqeast”). Detail stays in `NavigationStack` so nav titles show.  
14. **Status bar date wrong language** (EN shows “Fr. 10. Juli”) → `prepare_sim_for_marketing` must rewrite locale + **simctl shutdown/boot** per cell; date language is SpringBoard, not `-testLanguage` alone.  
15. **iPad 01 empty demos** after UITest landscape → simctl `-screenshotMode` + 8s with `reboot=0` after UITest (keep landscape). Extract: landscape PNG beats larger portrait leftover.  
17. **iPhone privacy title flush to edge** → shorter copy in `screenshot-titles.json` (+ compose font shrink for long titles).  



14. **`source capture-screenshots.sh`** → starts full loop; script refuses; never source  
15. **Constrain proportions** in Pixelmator → non-uniform collapse of Mac chrome  
16. **iPad multi 03 stretched iPad** → plate bezel is 11" (Display ~1.45); use `raw/ipad11/` + uniform fit to Display. Hardcoded 1590×1193 was 13" aspect and broke the frame.  

