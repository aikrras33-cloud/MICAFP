import SwiftUI

// =============================================================================
// MARK: - Quantum Enterprise RGB Color Extensions (§6.2 of directive
// GEMINI-ENG-DIR-V1.0)
//
// 1:1 mirror of `flutter_app/lib/theme/quantum_theme.dart`'s QuantumPalette.
// Dark-first per §6.1. RGB accents used sparingly. Used by every SwiftUI
// view in UnifiedShield (StatusView, CoreSwitcherView, SettingsView, etc.).
// =============================================================================

extension Color {
    /// Initializes a `Color` from a 0xRRGGBB or 0xAARRGGBB hex literal.
    /// Example: `Color(hex: 0xFF0080)` → magenta.
    init(hex: UInt32, alpha: Double = 1.0) {
        let r: Double
        let g: Double
        let b: Double
        let a: Double
        if hex > 0xFFFFFF {
            // 0xAARRGGBB
            a = Double((hex >> 24) & 0xFF) / 255.0
            r = Double((hex >> 16) & 0xFF) / 255.0
            g = Double((hex >> 8) & 0xFF) / 255.0
            b = Double(hex & 0xFF) / 255.0
        } else {
            // 0xRRGGBB
            a = alpha
            r = Double((hex >> 16) & 0xFF) / 255.0
            g = Double((hex >> 8) & 0xFF) / 255.0
            b = Double(hex & 0xFF) / 255.0
        }
        self.init(
            .sRGB,
            red: r,
            green: g,
            blue: b,
            opacity: a
        )
    }

    // ---- Backgrounds (dark-first per §6.1) ----
    static let quantumBgDeep = Color(hex: 0x050510)
    static let quantumBgSurface = Color(hex: 0x0A0A1F)
    static let quantumBgElevated = Color(hex: 0x14142B)
    static let quantumBgTooltip = Color(hex: 0x1F1F3D)

    // ---- Text ----
    static let quantumTextPrimary = Color(hex: 0xF5F5FA)
    static let quantumTextSecondary = Color(hex: 0xA0A0B8)
    static let quantumTextTertiary = Color(hex: 0x6B6B85)
    static let quantumTextDisabled = Color(hex: 0x3F3F5F)

    // ---- RGB brand spectrum (animated gradient ring per §6.2) ----
    static let quantumRgbMagenta = Color(hex: 0xFF0080)
    static let quantumRgbFuchsia = Color(hex: 0xFF00FF)
    static let quantumRgbViolet = Color(hex: 0x8000FF)
    static let quantumRgbAzure = Color(hex: 0x0080FF)
    static let quantumRgbCyan = Color(hex: 0x00FFFF)
    static let quantumRgbSpringGreen = Color(hex: 0x00FF80)
    static let quantumRgbYellow = Color(hex: 0xFFFF00)
    static let quantumRgbOrange = Color(hex: 0xFF8000)

    /// 3-stop RGB accent set (magenta/cyan/violet) — same as Flutter
    /// `rgbAccent3`.
    static let quantumRgbAccent1 = Color(hex: 0xFF0080)
    static let quantumRgbAccent2 = Color(hex: 0x00FFFF)
    static let quantumRgbAccent3 = Color(hex: 0x8000FF)

    /// Full RGB spectrum (used by the Connect button gradient ring).
    static let quantumRgbSpectrum: [Color] = [
        Color(hex: 0xFF0080),
        Color(hex: 0xFF00FF),
        Color(hex: 0x8000FF),
        Color(hex: 0x0080FF),
        Color(hex: 0x00FFFF),
        Color(hex: 0x00FF80),
        Color(hex: 0xFFFF00),
        Color(hex: 0xFF8000),
        Color(hex: 0xFF0080), // back to magenta (loop)
    ]

    /// Gold gradient for the verified-user icon + Enterprise value (§6.4.4).
    static let quantumGoldGradient: [Color] = [
        Color(hex: 0xFFD700),
        Color(hex: 0xFFA500),
        Color(hex: 0xFFD700),
    ]

    // ---- Status colors (connection states per §6.4.2) ----
    static let quantumStatusConnected = Color(hex: 0x00FF88)
    static let quantumStatusConnecting = Color(hex: 0xFFAA00)
    static let quantumStatusDisconnected = Color(hex: 0xFF3366)
    static let quantumStatusError = Color(hex: 0xFF0000)
    static let quantumStatusWarning = Color(hex: 0xFFCC00)

    // ---- Borders (8/16/30 % white overlay) ----
    static let quantumBorderSubtle = Color(white: 1.0, opacity: 0.08)
    static let quantumBorderStrong = Color(white: 1.0, opacity: 0.16)
    static let quantumBorderFocused = Color(white: 1.0, opacity: 0.30)

    // ---- Shadows ----
    static let quantumShadowSoft = Color(white: 0.0, opacity: 0.25)
    static let quantumShadowDeep = Color(white: 0.0, opacity: 0.50)

    // ---- Light-mode mirrors (§6.6) ----
    static let quantumLightBgDeep = Color(hex: 0xFFFFFF)
    static let quantumLightBgSurface = Color(hex: 0xF7F7FB)
    static let quantumLightBgElevated = Color(hex: 0xFFFFFF)
    static let quantumLightBgTooltip = Color(hex: 0xFFFFFF)

    static let quantumLightTextPrimary = Color(hex: 0x0A0A1F)
    static let quantumLightTextSecondary = Color(hex: 0x4A4A66)
    static let quantumLightTextTertiary = Color(hex: 0x7A7A95)
    static let quantumLightTextDisabled = Color(hex: 0xBFBFD0)

    static let quantumLightBorderSubtle = Color(white: 0.0, opacity: 0.08)
    static let quantumLightBorderStrong = Color(white: 0.0, opacity: 0.16)
    static let quantumLightBorderFocused = Color(white: 0.0, opacity: 0.30)

    static let quantumLightShadowSoft = Color(white: 0.0, opacity: 0.08)
    static let quantumLightShadowDeep = Color(white: 0.0, opacity: 0.16)
}

// =============================================================================
// MARK: - Quantum Enterprise RGB Linear Gradient helpers
//
// Mirrors of `QuantumGradients` from
// `flutter_app/lib/theme/quantum_theme.dart`.
// =============================================================================

extension LinearGradient {
    /// RGB ring gradient — 9-stop sweep over the spectrum. Used by the
    /// `quantumConnectRing` view modifier on the iOS Connect button.
    static var quantumRgbRing: LinearGradient {
        LinearGradient(
            colors: Color.quantumRgbSpectrum,
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// Horizontal red→green→blue banner for the Enterprise License Panel
    /// (§6.4.4 — the 4 pt banner at top of the panel).
    static var quantumEnterpriseBanner: LinearGradient {
        LinearGradient(
            colors: [
                Color.quantumRgbMagenta,
                Color.quantumStatusConnected,
                Color.quantumRgbAzure,
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// Gold gradient for the verified-user icon (§6.4.4).
    static var quantumGoldIcon: LinearGradient {
        LinearGradient(
            colors: Color.quantumGoldGradient,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// RGB gradient used by the on-state of `QuantumToggle` (§6.4.5).
    static var quantumToggleOn: LinearGradient {
        LinearGradient(
            colors: [
                Color.quantumRgbAccent1,
                Color.quantumRgbAccent2,
                Color.quantumRgbAccent3,
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// =============================================================================
// MARK: - Radial Aurora background gradient (§6.10)
// =============================================================================

extension RadialGradient {
    /// Subtle RGB aurora — drawn behind every screen per §6.10.
    static var quantumAurora: RadialGradient {
        RadialGradient(
            colors: [
                Color.quantumRgbAccent1.opacity(0.13),
                Color.quantumRgbAccent2.opacity(0.10),
                Color.quantumRgbAccent3.opacity(0.13),
                Color.quantumBgDeep,
            ],
            center: UnitPoint(x: 0.5, y: 0.3),
            startRadius: 0,
            endRadius: 600
        )
    }
}

// =============================================================================
// MARK: - StatusView
// =============================================================================

struct StatusView: View {
    @EnvironmentObject var tunnelManager: TunnelManager
    @State private var pulseAnimation = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Connection indicator
                    ZStack {
                        // Pulse ring
                        if tunnelManager.isConnected {
                            Circle()
                                .stroke(Color.green.opacity(0.3), lineWidth: 3)
                                .frame(width: 160, height: 160)
                                .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                                .opacity(pulseAnimation ? 0.5 : 1.0)
                                .animation(
                                    .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                                    value: pulseAnimation
                                )
                        }

                        Circle()
                            .fill(statusColor.opacity(0.12))
                            .frame(width: 130, height: 130)
                            .overlay(
                                Circle()
                                    .stroke(statusColor, lineWidth: 3)
                            )

                        Image(systemName: "shield.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 50, height: 50)
                            .foregroundColor(statusColor)
                    }
                    .onAppear { pulseAnimation = true }
                    .onDisappear { pulseAnimation = false }

                    // Status text
                    Text(tunnelManager.isConnected ? "Connected" : "Disconnected")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(statusColor)

                    if tunnelManager.isConnected {
                        Text("Core: \(tunnelManager.currentCore)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text("Uptime: \(tunnelManager.connectionUptime)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Speed indicators
                    if tunnelManager.isConnected {
                        HStack(spacing: 40) {
                            SpeedIndicator(
                                label: "Download",
                                speed: tunnelManager.downloadSpeed,
                                color: .blue
                            )
                            SpeedIndicator(
                                label: "Upload",
                                speed: tunnelManager.uploadSpeed,
                                color: .orange
                            )
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }

                    // DPI score indicator
                    if tunnelManager.isConnected {
                        DpiScoreView(score: tunnelManager.dpiScore)
                    }

                    Spacer(minLength: 20)

                    // Connect/Disconnect button
                    Button(action: {
                        if tunnelManager.isConnected {
                            tunnelManager.disconnect()
                        } else {
                            tunnelManager.connect()
                        }
                    }) {
                        Text(tunnelManager.isConnected ? "DISCONNECT" : "CONNECT")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(tunnelManager.isConnected ? Color.red : Color.green)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }
                .padding()
            }
            .navigationTitle("UnifiedShield")
        }
    }

    private var statusColor: Color {
        tunnelManager.isConnected ? .green : .gray
    }
}

struct SpeedIndicator: View {
    let label: String
    let speed: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(speed)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
    }
}

struct DpiScoreView: View {
    let score: Double

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("DPI Score")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: "%.2f", score))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(score > 0.72 ? .red : .green)
            }

            ProgressView(value: score, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle(tint: score > 0.72 ? .red : .green))

            if score > 0.72 {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("DPI detected - auto-switching core")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

#Preview {
    StatusView()
        .environmentObject(TunnelManager.shared)
}
