# Reqeast Design System

## Brand Identity
- Theme: Retromodern
- Brand Accent: Blue #4091C3
- Vibe: Cool, modern, professional API tool

## Color Palette
| Role | Color | Hex | Usage |
|------|-------|-----|-------|
| System Accent | (system default) | — | All interactive controls: buttons, sidebar selections, toggles, pickers, focus rings |
| Brand Blue | Blue | #4091C3 | Identity elements only: app logo, paywall Subscribe button |
| Brand Dark | Dark Blue | #1A4D6B | Gradient start, depth elements |
| Brand Light | Light Blue | #82C4E8 | Gradient end, cool highlights |
| Success | Green | (system) | 2xx status codes |
| Warning | Orange | (system) | 4xx status codes, trial warnings |
| Error | Red | (system) | 5xx status codes, connection errors |
| Info | Blue | (system) | 3xx redirects, TCP/UDP badges |

### When to Use Each Palette
- **Brand Gradient (Dark Blue -> Blue -> Light Blue)**: Branding elements, logos, marketing visuals, hero sections
- **Brand Blue**: Identity elements only -- app logo and paywall Subscribe button. Never as a global AccentColor or on regular action buttons.
- **System Accent**: All interactive controls -- buttons, sidebar selections, toggles, pickers, focus rings. Respects the user's OS accent color choice.

## HTTP Method Badge Colors
- GET: Green (system)
- POST: Blue (#4091C3)
- PUT: Blue (system)
- PATCH: Purple (system)
- DELETE: Red (system)
- HEAD/OPTIONS: Gray (system)

## Typography
- Monospace for code, URLs, headers, response bodies
- System font for UI chrome
- SF Mono for JSON tree, syntax highlighting

## Liquid Glass Design
- .buttonStyle(.glass) for standard buttons
- .buttonStyle(.glassProminent) for primary actions (Send, Connect)
- NavigationSplitView with system sidebar styling
- No custom backgrounds on navigation elements
- Glass effect on toolbars and panels

## Animation
- Staggered entrance for list items
- Breathing effect on app logo
- Spring animations: snappy (0.3s, 0.2 bounce), gentle (0.5s, 0.15 bounce)
- Respect accessibilityReduceMotion

## Layout
- 3-column NavigationSplitView (macOS)
- Adaptive collapse (iPad: sidebar folds, iPhone: stack nav)
- Min window: 1050x500 (macOS)
- Default window: 1200x800 (macOS)

## Iconography
- SF Symbols throughout
- Protocol icons: arrow.up.arrow.down (HTTP), cable.connector (TCP), dot.radiowaves.up.forward (UDP)
- Method badges: inline colored text labels
