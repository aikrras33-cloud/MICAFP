# UnifiedShield Enterprise v9.0.0-enterprise — Quantum Enterprise RGB Design Language

> **Authoritative design-language reference for the Quantum Enterprise RGB UI**.
> This document is the single source of truth that the Flutter theme, the
> Next.js dashboard CSS, the browser-extension CSS, the Android Compose theme,
> and the iOS SwiftUI theme must all match. Token drift across surfaces is a
> bug; fix it here first, then mirror.

---

## 1. Design Philosophy

Five pillars, in priority order:

1. **Dark-first.** Every screen ships dark by default. The light variant exists but is opt-in and rarely used. Background `#050510` is the canvas; everything else sits *above* it in the depth-stack.
2. **RGB accents — animated sparingly.** The Quantum brand spectrum is a 9-stop gradient ring (`rgbSpectrum` in §2). It is used **only** on the connect button, the active-core chip, the license countdown, and the aurora background. Saturating the whole UI in RGB would trivially identify the app to a screenshotting DPI box.
3. **Glassmorphism.** Cards and modals are frosted-glass (`BackdropFilter` + `ImageFilter.blur(sigmaX: 12, sigmaY: 12)` over a translucent `bgSurface` overlay). Borders are 1-px `Color(0x14FFFFFF)`.
4. **Motion.** Every state transition animates over a curve from `QuantumCurves` and a duration from `QuantumDurations`. No instantaneous layout jumps. No `LinearAnimation` outside of progress bars.
5. **Depth.** A 4-layer elevation ladder (`bgDeep → bgSurface → bgElevated → bgTooltip`) plus shadow tokens `QuantumShadows.{sm, md, lg, glow}`. The glow layer is RGB-tinted and is reserved for the active/selected state.

---

## 2. Color Tokens — `QuantumPalette`

Source: `flutter_app/lib/theme/quantum_theme.dart`.

### 2.1 Background ladder (dark-first)
| Token | Hex | Role |
|-------|-----|------|
| `bgDeep` | `#050510` | Canvas behind everything |
| `bgSurface` | `#0A0A1F` | Card layer (`QuantumGlassCard`) |
| `bgElevated` | `#14142B` | Modal / sheet / dialog |
| `bgTooltip` | `#1F1F3D` | Tooltip / popover top layer |

### 2.2 Text
| Token | Hex | Role |
|-------|-----|------|
| `textPrimary` | `#F5F5FA` | Headlines + body |
| `textSecondary` | `#A0A0B8` | Subtitle + captions |
| `textTertiary` | `#6B6B85` | Tertiary metadata |
| `textDisabled` | `#3F3F5F` | Disabled-state text |

### 2.3 RGB brand spectrum
A 9-stop list. Index 0 and index 8 are equal so a sweep gradient loops seamlessly:

```
#FF006E  // magenta
#FB5607  // orange
#FFBE0B  // amber
#8338EC  // purple
#3A86FF  // blue
#06FFA5  // mint
#FF4D6D  // pink
#FFC436  // gold
#FF006E  // magenta (loop)
```

Reserved surfaces:
- **Connect button** ring sweep (§5.1).
- **Active core chip** border glow.
- **License countdown** separator dot.
- **Aurora background** blob palette (3-5 blobs sampled from the spectrum).

### 2.4 Status colors
| Token | Hex | Role |
|-------|-----|------|
| `success` | `#06FFA5` | Connected state |
| `warning` | `#FFBE0B` | Degraded / fallback-active state |
| `danger` | `#FF4D6D` | Disconnected / kill-switch-engaged state |
| `info` | `#3A86FF` | Neutral informational state |

### 2.5 Glass overlays
| Token | Hex | Use |
|-------|-----|-----|
| `glassFill` | `#0A0A1F` @ 70% | `QuantumGlassCard` background |
| `glassBorder` | `#FFFFFF` @ 8% | 1-px hairline border |
| `glassHighlight` | `#FFFFFF` @ 4% | Inner top-edge highlight |

---

## 3. Typography

Two font families, paired:

- **Inter** — Latin script (English UI, numerals in English locale).
- **Vazirmatn** — Arabic/Persian script (Farsi UI, Persian numerals).

`QuantumTypography` exposes 9 named styles:

| Style | Family | Size | Weight | Letter-spacing | Use |
|-------|--------|------|--------|----------------|-----|
| `displayLarge` | Inter / Vazirmatn | 32 | W700 | -0.5px | Headlines |
| `displayMedium` | Inter / Vazirmatn | 28 | W700 | -0.5px | Section titles |
| `displaySmall` | Inter / Vazirmatn | 24 | W700 | 0 | Card titles |
| `headlineLarge` | Inter / Vazirmatn | 22 | W600 | 0 | Screen titles |
| `headlineMedium` | Inter / Vazirmatn | 20 | W600 | 0 | Row titles |
| `bodyLarge` | Inter / Vazirmatn | 16 | W400 | 0 | Body |
| `bodyMedium` | Inter / Vazirmatn | 14 | W400 | 0 | Subtitle |
| `labelMedium` | JetBrains Mono | 11 | W500 | 0.5px | Port / code / serial |
| `labelSmall` | JetBrains Mono | 9 | W500 | 0.5px | Tabular figures in countdown |

JetBrains Mono is loaded as a third family for **numeric/code** runs (SOCKS5 ports, license serials, countdown cells).

---

## 4. Motion Library — `QuantumMotion`

Source: `flutter_app/lib/theme/quantum_motion.dart`.

### 4.1 Curves
| Token | Curve | Use |
|-------|-------|-----|
| `QuantumCurves.entrance` | `Curves.easeOutCubic` | Widgets entering the viewport |
| `QuantumCurves.exit` | `Curves.easeInCubic` | Widgets leaving the viewport |
| `QuantumCurves.emphasized` | `Curves.easeInOutEmphasized` (Material 3 spec, hand-rolled to avoid M3 import) | Major state transitions |
| `QuantumCurves.rgbSweep` | `Curves.linear` (with custom `AnimationController` rate) | RGB ring sweep |
| `QuantumCurves.bounce` | `Curves.easeOutBack` | Micro-delights (toggle on) |
| `QuantumCurves.spring` | `SpringDescription(mass:1, stiffness:340, damping:24)` | Physical interactions |

### 4.2 Durations
| Token | ms | Use |
|-------|----|-----|
| `QuantumDurations.instant` | 50 | Tooltip appear |
| `QuantumDurations.fast` | 100 | Toggle |
| `QuantumDurations.base` | 200 | Default |
| `QuantumDurations.slow` | 350 | Modal open |
| `QuantumDurations.glacial` | 600 | Aurora blob drift step |

### 4.3 Transitions
`QuantumTransitions` provides pre-built `AnimatedSwitcher.defaultTransitionBuilder` factories:
- `slideInFromBottom`
- `slideInFromRight`
- `scaleIn`
- `fadeThrough` (cross-fade with opacity → translate → opacity)

---

## 5. Component Specs — 10 Custom Components

Source: `flutter_app/lib/theme/quantum_components.dart`.

### 5.1 `QuantumConnectButton`
- **Shape**: circular, 88×88 dp, with a 3-dp-thick ring painted by a `SweepGradient` over `rgbSpectrum`.
- **Idle state**: ring rotates at 0.5 rev/s, label "اتصال" / "Connect" in `displaySmall`.
- **Connecting state**: ring spins at 2 rev/s, label morphs to "در حال اتصال..." / "Connecting…".
- **Connected state**: ring stops at a random offset (to avoid a recognizable static angle), center fills with `success` glow, label becomes "متصل" / "Connected" + duration timer in `labelSmall`.
- **Tap**: 100-ms `bounce` curve; on release triggers `DaemonBridge.connect()`.

### 5.2 `QuantumStatusCard`
- Glass card 320×148 dp. Top: row of status dots (`success`/`warning`/`danger`). Middle: `displayMedium` headline ("مِتریک‌های لحظه‌ای" / "Live metrics"). Bottom: `QuantumSparkline` showing 60-second history of bytes/sec.

### 5.3 `QuantumCoreSwitcher`
- Horizontal scrollable row of `QuantumCoreChip`s (140×96 dp). Active chip has 2-px `rgbSpectrum` border + 12-px `glow` shadow. Inactive chips have 1-px `glassBorder`. Tap triggers `DaemonBridge.switchCore(id)`.

### 5.4 `QuantumEnterpriseLicensePanel`
- Card with two rows. Top row: license serial in `labelMedium` mono. Bottom row: 4-cell `QuantumCountdownTimer` (days/hours/minutes/seconds).
- When expiry < 24 h, the separator dots pulse red and the entire card border switches to `danger`.

### 5.5 `QuantumSettingsRow`
- Standard 56-dp row. Left: icon in `QuantumPalette.textTertiary` (idle) or `rgbSpectrum[4]` (active). Right: `QuantumToggle` (5.6 below).

### 5.6 `QuantumToggle`
- Custom switch — **forbidden** to use Material's `Switch`. 44×24 dp pill. Off: `glassFill` background + 16-dp `textTertiary` dot on the left. On: `rgbSpectrum[4]` background + 16-dp white dot on the right. Animation: 200-ms `bounce`.

### 5.7 `QuantumResilienceChain`
- Vertical list of 8 rows (one per resilience step from §11 of ARCHITECTURE.md). Each row shows a 16-dp status dot, the step name in `bodyMedium`, and the budget timeout in `labelSmall`. The currently-executing step's dot pulses `info`; failed steps go `danger`; passed steps go `success`.

### 5.8 `QuantumAIAssistantSheet`
- Bottom-sheet modal with a chat UI. Top: `QuantumSpinner` while the on-device LLM is cold-starting. Body: streamed tokens via `EventChannel("unifiedshield/ai_stream")`. Bottom: text-field input with a microphone icon (`voice_command_service`).

### 5.9 `QuantumCountdownTimer`
- 4 horizontal cells (days/hours/minutes/seconds), each 60×80 dp. Cell value in `displayLarge`; cell label ("روز/ساعت/دقیقه/ثانیه" or "D/H/M/S") in `labelSmall`. Separator dots between cells pulse at the period of the cell they precede (i.e. the seconds-dot pulses every 1 s; the hours-dot pulses every 1 hour).
- **Persian numerals** when `Locale("fa")` is active — uses the Unicode block `U+06F0`–`U+06F9` (Extended Arabic-Indic digits used in Persian).
- **Acceleration**: animation interval is `max(60 ms, 1000 ms × (1 - (T_remaining / T_total)))` — i.e. as expiry approaches, the seconds cell ticks faster (down to a minimum of 60 ms per tick), providing a visible sense of urgency without inducing panic.

### 5.10 `QuantumAuroraBackground`
- Full-viewport `CustomPainter` drawing 3–5 blurred RGB blobs sampled from `rgbSpectrum`. Blob drift is slow (`glacial` duration per step). Always wrapped in a `RepaintBoundary` so the painter doesn't repaint when sibling widgets rebuild. **Every** screen has one as the bottom layer.

---

## 6. Forbidden UI Patterns

The following Material 2 / Material 3 widgets are **forbidden** across the entire codebase. They have Quantum replacements that must be used instead. The CI lint (`scripts/preflight.sh`) greps the diff for these class names and fails the build if any are introduced:

| Forbidden | Replacement | Reason |
|-----------|-------------|--------|
| Material 2 / Material 3 default theme | `QuantumPalette` + `QuantumTypography` | Material's color scheme is light-default and lacks glass + RGB accent support. |
| `Switch` | `QuantumToggle` (§5.6) | Material's `Switch` has a recognizable ripple and thumb-shadow that DPI probes can fingerprint. |
| `Checkbox` | `QuantumToggle` (single-state) or `QuantumCheckbox` (custom, glass-fill) | Same fingerprint concern + visual inconsistency. |
| `Dialog` / `AlertDialog` | `QuantumDialog` (custom `showDialog` with `QuantumGlassModal` wrapper) | Material dialogs use a fixed white background and a recognizable `Curves.decelerate` — both break glass + motion invariants. |
| `SnackBar` | `QuantumToast` (custom `Overlay` entry with `QuantumGlassCard` background) | Material `SnackBar` is a fixed-height bottom-anchored rectangle — instantly recognizable. |
| `CircularProgressIndicator` | `QuantumSpinner` (custom `AnimationBuilder` driving a 3-stop RGB sweep gradient ring) | Material's blue circular indicator is universally fingerprinted as "loading". |

These rules are enforced by the pre-flight CI step (see `docs/GITHUB-ACTIONS-GUIDE.md`).

---

## 7. Cross-Surface Token Parity

The same `QuantumPalette` hex values must appear, unmodified, in every surface that renders UI. CI verifies this with `scripts/preflight.sh --check-tokens`:

| Surface | File | Format |
|---------|------|--------|
| **Flutter app** | `flutter_app/lib/theme/quantum_theme.dart` | `Color(0xFFRRGGBB)` Dart constants |
| **Next.js dashboard** | `dashboard/src/styles/quantum-theme.ts` | `export const QuantumPalette = { bgDeep: "#050510", ... }` |
| **Browser extensions (Chrome + Firefox)** | `extensions/shared/quantum-tokens.css` | CSS custom properties `--quantum-bg-deep: #050510;` |
| **Android Compose (legacy `android/` tree)** | `android/app/src/main/kotlin/com/unifiedshield/ui/theme/Theme.kt` | `val bgDeep = Color(0xFF050510)` |
| **iOS SwiftUI (legacy `ios/` tree)** | `ios/UnifiedShield/App/QuantumTheme.swift` | `static let bgDeep = Color(red: 5/255, green: 5/255, blue: 16/255)` |

Token drift is a release-blocking bug. The pre-flight script diffs the resolved hex values across all 5 surfaces and fails if any mismatch is found.

---

## 8. Animation Budget

Two hard limits, enforced at code-review time and by the lint rule in `scripts/preflight.sh --check-anim-budget`:

1. **60 FPS minimum.** Every animation must render at ≥ 60 FPS on a Pixel 4a (the CI bench device) and on an iPhone 12 (the iOS bench device). Heavier painters (`QuantumAuroraBackground`, `QuantumSparkline`, `QuantumCountdownTimer`) must be wrapped in `RepaintBoundary` and must not call `markNeedsPaint()` more than once per frame.
2. **Max 3 simultaneous animations per screen.** A screen may run at most 3 concurrent `AnimationController`s. If a 4th is needed, the oldest non-essential one must be paused. Exceptions are limited to:
   - The home screen (aurora + connect-button ring + sparkline = exactly 3, no budget left).
   - The countdown timer cells (each cell's separator-dot pulse counts as 1/4 of an animation — i.e. all 4 dots together count as 1 animation).

These limits are necessary because the app runs in the background alongside the VPN tunnel; excessive GPU work would create a recognizable thermal signature that DPI/Iranian-LEO operators could correlate with VPN use.

---

## 9. Localization Impact on Design

When `Locale("fa")` is active:
- **Text direction** flips to RTL. Layouts must use `Directionality.of(context)` (never hard-code `Row` left-to-right).
- **Numerals** in the countdown and in all metric displays use Persian digits (`۰۱۲۳۴۵۶۷۸۹`).
- **Fonts** auto-swap from Inter to Vazirmatn; the swap is implemented in `quantum_theme.dart`'s `QuantumTypography.of(context, locale)` factory.
- **Padding** — Persian text glyphs typically need +2 dp trailing padding compared to Latin glyphs to look optically balanced; the `QuantumTypography` styles bake this in via `letterSpacing` and `height` adjustments when `locale.languageCode == "fa"`.

---

## 10. References

- `flutter_app/lib/theme/quantum_theme.dart` — Dart source of `QuantumPalette`
- `flutter_app/lib/theme/quantum_motion.dart` — Dart source of `QuantumCurves` / `QuantumDurations`
- `flutter_app/lib/theme/quantum_glassmorphism.dart` — Glass primitives
- `flutter_app/lib/theme/quantum_components.dart` — All 10 custom components
- `dashboard/src/styles/quantum-theme.ts` — TypeScript mirror
- `extensions/shared/quantum-tokens.css` — CSS mirror (planned, see §7)
- `android/app/src/main/kotlin/com/unifiedshield/ui/theme/Theme.kt` — Compose mirror
- `ios/UnifiedShield/App/QuantumTheme.swift` — SwiftUI mirror (planned, see §7)
