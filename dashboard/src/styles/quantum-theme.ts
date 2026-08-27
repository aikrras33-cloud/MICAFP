// =============================================================================
// quantum-theme.ts — TypeScript mirror of the Flutter QuantumPalette
//
// Per §6.9: "Mirror the same design tokens in:
//   dashboard/src/styles/quantum-theme.ts (Tailwind config + CSS variables)"
//
// This file is the single source of truth for the Quantum Enterprise RGB
// design system in the dashboard (Next.js + Tailwind) surface. It exports:
//   - `quantumPalette`       — color tokens matching Flutter QuantumPalette
//   - `quantumTypography`    — font sizes/weights matching QuantumTypography
//   - `quantumGradients`     — RGB ring + aurora + gold + enterprise banner
//   - `quantumTailwindExtend` — drop-in `theme.extend` object for Tailwind
//   - `quantumCssVars`       — string block of `:root { --bg-deep: ... }`
//
// Used by:
//   - dashboard/tailwind.config.ts (import quantumTailwindExtend)
//   - dashboard/src/app/globals.css (import quantumCssVars)
// =============================================================================

// -----------------------------------------------------------------------------
// quantumPalette — 1:1 mirror of `QuantumPalette` in
// `flutter_app/lib/theme/quantum_theme.dart`
// -----------------------------------------------------------------------------

export const quantumPalette = {
  // ---- Backgrounds (dark-first) ----
  bgDeep: '#050510',
  bgSurface: '#0A0A1F',
  bgElevated: '#14142B',
  bgTooltip: '#1F1F3D',

  // ---- Text ----
  textPrimary: '#F5F5FA',
  textSecondary: '#A0A0B8',
  textTertiary: '#6B6B85',
  textDisabled: '#3F3F5F',

  // ---- RGB brand spectrum ----
  rgbSpectrum: [
    '#FF0080', // magenta
    '#FF00FF', // fuchsia
    '#8000FF', // violet
    '#0080FF', // azure
    '#00FFFF', // cyan
    '#00FF80', // spring green
    '#FFFF00', // yellow
    '#FF8000', // orange
    '#FF0080', // back to magenta (loop)
  ] as const,

  rgbAccent3: ['#FF0080', '#00FFFF', '#8000FF'] as const,

  goldGradient: ['#FFD700', '#FFA500', '#FFD700'] as const,

  // ---- Status ----
  statusConnected: '#00FF88',
  statusConnecting: '#FFAA00',
  statusDisconnected: '#FF3366',
  statusError: '#FF0000',
  statusWarning: '#FFCC00',

  // ---- Borders (8/16/30 % white overlay) ----
  // Tailwind/Tailwind-CSS can't represent alpha easily for arbitrary hex, so
  // we use the rgba() equivalent for hover/active states.
  borderSubtle: 'rgba(255, 255, 255, 0.08)',
  borderStrong: 'rgba(255, 255, 255, 0.16)',
  borderFocused: 'rgba(255, 255, 255, 0.30)',

  // ---- Shadows ----
  shadowSoft: 'rgba(0, 0, 0, 0.25)',
  shadowDeep: 'rgba(0, 0, 0, 0.50)',

  // ---- Light-mode mirrors (§6.6) ----
  lightBgDeep: '#FFFFFF',
  lightBgSurface: '#F7F7FB',
  lightBgElevated: '#FFFFFF',
  lightBgTooltip: '#FFFFFF',

  lightTextPrimary: '#0A0A1F',
  lightTextSecondary: '#4A4A66',
  lightTextTertiary: '#7A7A95',
  lightTextDisabled: '#BFBFD0',

  lightBorderSubtle: 'rgba(0, 0, 0, 0.08)',
  lightBorderStrong: 'rgba(0, 0, 0, 0.16)',
  lightBorderFocused: 'rgba(0, 0, 0, 0.30)',

  lightShadowSoft: 'rgba(0, 0, 0, 0.08)',
  lightShadowDeep: 'rgba(0, 0, 0, 0.16)',

  // ---- Spacing (4 px base grid) ----
  spaceXxs: 4,
  spaceXs: 8,
  spaceSm: 12,
  spaceMd: 16,
  spaceLg: 20,
  spaceXl: 24,
  spaceSection: 32,

  // ---- Radii ----
  radiusCard: 20,
  radiusButton: 14,
  radiusInput: 12,
  radiusModal: 24,
  radiusPill: 9999,
} as const;

// -----------------------------------------------------------------------------
// quantumTypography — 1:1 mirror of `QuantumTypography` in
// `flutter_app/lib/theme/quantum_theme.dart`
// -----------------------------------------------------------------------------

export const quantumTypography = {
  fontFamily: 'Inter, system-ui, -apple-system, BlinkMacSystemFont, sans-serif',
  fontFamilyMono: '"JetBrains Mono", ui-monospace, SFMono-Regular, monospace',
  fontFamilyFa: 'Vazirmatn, Inter, sans-serif',

  // Inter sizes (Latin)
  display1: { fontSize: 32, fontWeight: 700, lineHeight: 1.2, letterSpacing: '-0.02em' },
  display2: { fontSize: 28, fontWeight: 700, lineHeight: 1.25, letterSpacing: '-0.02em' },
  display3: { fontSize: 24, fontWeight: 700, lineHeight: 1.3, letterSpacing: '-0.01em' },
  title1: { fontSize: 24, fontWeight: 600, lineHeight: 1.3, letterSpacing: '-0.01em' },
  title2: { fontSize: 20, fontWeight: 600, lineHeight: 1.35, letterSpacing: '-0.01em' },
  title3: { fontSize: 18, fontWeight: 600, lineHeight: 1.4 },
  body1: { fontSize: 16, fontWeight: 400, lineHeight: 1.5 },
  body2: { fontSize: 14, fontWeight: 400, lineHeight: 1.5 },
  label: { fontSize: 12, fontWeight: 600, lineHeight: 1.4, letterSpacing: '0.04em' },
  mono: { fontSize: 14, fontWeight: 500, lineHeight: 1.5 },
} as const;

// -----------------------------------------------------------------------------
// quantumGradients — RGB ring + aurora + gold + enterprise banner
// -----------------------------------------------------------------------------

export const quantumGradients = {
  /// Linear RGB ring (use as `linear-gradient(...)` for the connect button).
  /// Animated by tweaking `background-position` over time in CSS.
  rgbRing: `linear-gradient(90deg, ${quantumPalette.rgbSpectrum.join(', ')})`,

  /// Radial aurora background — 4 stop with low opacity.
  auroraBackground: `radial-gradient(ellipse at 50% 30%, ${quantumPalette.rgbAccent3[0]}20, ${quantumPalette.rgbAccent3[1]}1A, ${quantumPalette.rgbAccent3[2]}20, transparent)`,

  /// Horizontal red→green→blue banner (§6.4.4).
  enterpriseBanner: `linear-gradient(90deg, #FF0080 0%, #00FF88 50%, #0080FF 100%)`,

  /// Gold gradient for verified-user icon (§6.4.4).
  goldIcon: `linear-gradient(135deg, #FFD700, #FFA500, #FFD700)`,

  /// RGB gradient used by the on-state of `QuantumToggle` (§6.4.5).
  toggleOn: `linear-gradient(90deg, ${quantumPalette.rgbAccent3.join(', ')})`,
} as const;

// -----------------------------------------------------------------------------
// quantumTailwindExtend — drop-in object for `theme.extend` in Tailwind config
// -----------------------------------------------------------------------------

import type { Config } from 'tailwindcss';

export const quantumTailwindExtend: Config['theme'] = {
  extend: {
    colors: {
      // Quantum brand colors — accessible as `bg-bgDeep`, `text-textPrimary`,
      // `border-borderSubtle`, etc.
      bgDeep: quantumPalette.bgDeep,
      bgSurface: quantumPalette.bgSurface,
      bgElevated: quantumPalette.bgElevated,
      bgTooltip: quantumPalette.bgTooltip,
      textPrimary: quantumPalette.textPrimary,
      textSecondary: quantumPalette.textSecondary,
      textTertiary: quantumPalette.textTertiary,
      textDisabled: quantumPalette.textDisabled,
      rgbAccent1: quantumPalette.rgbAccent3[0],
      rgbAccent2: quantumPalette.rgbAccent3[1],
      rgbAccent3: quantumPalette.rgbAccent3[2],
      statusConnected: quantumPalette.statusConnected,
      statusConnecting: quantumPalette.statusConnecting,
      statusDisconnected: quantumPalette.statusDisconnected,
      statusError: quantumPalette.statusError,
      statusWarning: quantumPalette.statusWarning,
      // Light-mode mirrors (use `bg-bgDeep-light` etc.)
      'bgDeep-light': quantumPalette.lightBgDeep,
      'bgSurface-light': quantumPalette.lightBgSurface,
      'bgElevated-light': quantumPalette.lightBgElevated,
      'bgTooltip-light': quantumPalette.lightBgTooltip,
    },
    fontFamily: {
      sans: [quantumTypography.fontFamily],
      mono: [quantumTypography.fontFamilyMono],
      fa: [quantumTypography.fontFamilyFa],
    },
    borderRadius: {
      card: `${quantumPalette.radiusCard}px`,
      button: `${quantumPalette.radiusButton}px`,
      input: `${quantumPalette.radiusInput}px`,
      modal: `${quantumPalette.radiusModal}px`,
      pill: `${quantumPalette.radiusPill}px`,
    },
    spacing: {
      xxs: `${quantumPalette.spaceXxs}px`,
      xs: `${quantumPalette.spaceXs}px`,
      sm: `${quantumPalette.spaceSm}px`,
      md: `${quantumPalette.spaceMd}px`,
      lg: `${quantumPalette.spaceLg}px`,
      xl: `${quantumPalette.spaceXl}px`,
      section: `${quantumPalette.spaceSection}px`,
    },
    boxShadow: {
      soft: `0 8px 24px ${quantumPalette.shadowSoft}`,
      deep: `0 16px 48px ${quantumPalette.shadowDeep}`,
      rgbRing: `0 0 32px ${quantumPalette.rgbAccent3[0]}66, 0 0 4px ${quantumPalette.rgbAccent3[0]}`,
    },
    backgroundImage: {
      'rgb-ring': quantumGradients.rgbRing,
      'aurora': quantumGradients.auroraBackground,
      'enterprise-banner': quantumGradients.enterpriseBanner,
      'gold-icon': quantumGradients.goldIcon,
    },
    keyframes: {
      rgbRingRotate: {
        '0%': { backgroundPosition: '0% 50%' },
        '50%': { backgroundPosition: '100% 50%' },
        '100%': { backgroundPosition: '0% 50%' },
      },
      auroraDrift: {
        '0%, 100%': { transform: 'translate3d(0, 0, 0) scale(1)' },
        '50%': { transform: 'translate3d(2%, -2%, 0) scale(1.05)' },
      },
    },
    animation: {
      'rgb-ring-rotate': 'rgbRingRotate 8s linear infinite',
      'rgb-ring-fast': 'rgbRingRotate 4s linear infinite',
      'aurora-drift': 'auroraDrift 30s ease-in-out infinite',
    },
  },
};

// -----------------------------------------------------------------------------
// quantumCssVars — string block of `:root { ... }` CSS custom properties
// -----------------------------------------------------------------------------

export const quantumCssVars = `
:root {
  /* ---- Backgrounds ---- */
  --bg-deep: ${quantumPalette.bgDeep};
  --bg-surface: ${quantumPalette.bgSurface};
  --bg-elevated: ${quantumPalette.bgElevated};
  --bg-tooltip: ${quantumPalette.bgTooltip};

  /* ---- Text ---- */
  --text-primary: ${quantumPalette.textPrimary};
  --text-secondary: ${quantumPalette.textSecondary};
  --text-tertiary: ${quantumPalette.textTertiary};
  --text-disabled: ${quantumPalette.textDisabled};

  /* ---- RGB accents ---- */
  --rgb-accent-1: ${quantumPalette.rgbAccent3[0]};
  --rgb-accent-2: ${quantumPalette.rgbAccent3[1]};
  --rgb-accent-3: ${quantumPalette.rgbAccent3[2]};
  --rgb-spectrum: ${quantumPalette.rgbSpectrum.join(', ')};

  /* ---- Status ---- */
  --status-connected: ${quantumPalette.statusConnected};
  --status-connecting: ${quantumPalette.statusConnecting};
  --status-disconnected: ${quantumPalette.statusDisconnected};
  --status-error: ${quantumPalette.statusError};
  --status-warning: ${quantumPalette.statusWarning};

  /* ---- Borders ---- */
  --border-subtle: ${quantumPalette.borderSubtle};
  --border-strong: ${quantumPalette.borderStrong};
  --border-focused: ${quantumPalette.borderFocused};

  /* ---- Shadows ---- */
  --shadow-soft: ${quantumPalette.shadowSoft};
  --shadow-deep: ${quantumPalette.shadowDeep};

  /* ---- Radii ---- */
  --radius-card: ${quantumPalette.radiusCard}px;
  --radius-button: ${quantumPalette.radiusButton}px;
  --radius-input: ${quantumPalette.radiusInput}px;
  --radius-modal: ${quantumPalette.radiusModal}px;
  --radius-pill: ${quantumPalette.radiusPill}px;

  /* ---- Spacing ---- */
  --space-xxs: ${quantumPalette.spaceXxs}px;
  --space-xs: ${quantumPalette.spaceXs}px;
  --space-sm: ${quantumPalette.spaceSm}px;
  --space-md: ${quantumPalette.spaceMd}px;
  --space-lg: ${quantumPalette.spaceLg}px;
  --space-xl: ${quantumPalette.spaceXl}px;
  --space-section: ${quantumPalette.spaceSection}px;

  /* ---- Gradients ---- */
  --gradient-rgb-ring: ${quantumGradients.rgbRing};
  --gradient-aurora: ${quantumGradients.auroraBackground};
  --gradient-enterprise-banner: ${quantumGradients.enterpriseBanner};
  --gradient-gold-icon: ${quantumGradients.goldIcon};
  --gradient-toggle-on: ${quantumGradients.toggleOn};

  /* ---- Fonts ---- */
  --font-sans: ${quantumTypography.fontFamily};
  --font-mono: ${quantumTypography.fontFamilyMono};
  --font-fa: ${quantumTypography.fontFamilyFa};
}

/* ---- Light-mode overrides per §6.6 ---- */
:root[data-theme="light"] {
  --bg-deep: ${quantumPalette.lightBgDeep};
  --bg-surface: ${quantumPalette.lightBgSurface};
  --bg-elevated: ${quantumPalette.lightBgElevated};
  --bg-tooltip: ${quantumPalette.lightBgTooltip};

  --text-primary: ${quantumPalette.lightTextPrimary};
  --text-secondary: ${quantumPalette.lightTextSecondary};
  --text-tertiary: ${quantumPalette.lightTextTertiary};
  --text-disabled: ${quantumPalette.lightTextDisabled};

  --border-subtle: ${quantumPalette.lightBorderSubtle};
  --border-strong: ${quantumPalette.lightBorderStrong};
  --border-focused: ${quantumPalette.lightBorderFocused};

  --shadow-soft: ${quantumPalette.lightShadowSoft};
  --shadow-deep: ${quantumPalette.lightShadowDeep};
}
`;

// -----------------------------------------------------------------------------
// Utility helpers
// -----------------------------------------------------------------------------

/** Persian numeral map for §6.7 RTL countdown. */
const PERSIAN_DIGITS = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];

/** Converts ASCII digits in `input` to Persian digits. */
export function toPersianNumerals(input: string | number): string {
  return String(input).replace(/[0-9]/g, (d) => PERSIAN_DIGITS[+d]!);
}

/** Returns the localized greeting string for the AI Assistant (§6.4.7). */
export function aiGreeting(locale: 'en' | 'fa'): string {
  return locale === 'fa'
    ? 'سلام، من Shield AI هستم'
    : "Hi, I'm Shield AI";
}
