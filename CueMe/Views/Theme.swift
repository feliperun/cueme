import SwiftUI
import AppKit
import CoreText

/// Restrained, note-first workspace tokens. Static layers keep rendering cheap.
///
/// Palette rules (enforced in review — see docs/adr + temp/IMPLEMENTATION.md):
/// - `violet` = selection + primary action. Never decorative.
/// - `mint`   = coach surfaces exclusively.
/// - `amber`  = live / recording signal only.
/// - Backgrounds are limited to `canvas` / `tree` / `list` / `paper`.
enum Theme {

    // MARK: Neutrals (warm paper set)

    static let canvas = adaptive(light: 0xF5F3EE, dark: 0x0A0B10)
    static let tree   = adaptive(light: 0xEDEAE2, dark: 0x0C0E14)
    static let list   = adaptive(light: 0xF1EFE8, dark: 0x0E1017)
    static let paper  = adaptive(light: 0xFCFBF7, dark: 0x11131B)
    static let soft   = adaptive(light: 0xE9E6DD, dark: 0x1A1D26)

    static let ink    = adaptive(light: 0x2C2A26, dark: 0xEBE9E3)
    static let ink2   = adaptive(light: 0x6D6A62, dark: 0x9E9B91)
    static let faint  = adaptive(light: 0xA49F93, dark: 0x6B6860)

    static let line   = adaptive(light: NSColor.fromHex(0xE3DFD5), dark: NSColor.white.withAlphaComponent(0.075))
    static let line2  = adaptive(light: NSColor.fromHex(0xEEEAE1), dark: NSColor.white.withAlphaComponent(0.05))

    // MARK: Accents — one meaning each

    /// Selection + primary action.
    static let violet = Color(hex: 0x6D79F2)
    static let violetDeep = Color(hex: 0x565FCA)
    static let violetSoft = adaptive(light: NSColor.fromHex(0xECECFB),
                                     dark: NSColor.fromHex(0x6D79F2).withAlphaComponent(0.22))

    /// Coach, and only coach.
    static let mint = Color(hex: 0x2EB78C)
    static let mintDeep = Color(hex: 0x1F8A68)
    static let mintSoft = adaptive(light: NSColor.fromHex(0xE1F3ED),
                                   dark: NSColor.fromHex(0x2EB78C).withAlphaComponent(0.18))

    /// Live / recording only. Raw amber for dots/fills/transport; `amberText` for copy (AA on paper).
    static let amber = Color(hex: 0xCF9633)
    static let amberText = adaptive(light: NSColor.fromHex(0x8A6415), dark: NSColor.fromHex(0xE0B457))
    static let amberSoft = adaptive(light: NSColor.fromHex(0xF5ECD9),
                                    dark: NSColor.fromHex(0xCF9633).withAlphaComponent(0.16))

    /// Failure / destructive signalling only.
    static let rose = Color(red: 0.96, green: 0.39, blue: 0.48)

    // MARK: Legacy aliases (kept while views migrate onto the new tokens)

    static let sidebar = tree
    static let panel = list
    static let panelRaised = paper
    static let surface = paper
    static let divider = line
    static let surfaceStroke = line
    static let cyan = Color(red: 0.32, green: 0.72, blue: 0.98)
    static let interactive = adaptive(
        light: NSColor.black.withAlphaComponent(0.045),
        dark: NSColor.white.withAlphaComponent(0.055)
    )

    /// Primary action fill. Solid violet — the brand gradient is retired.
    static let brand = LinearGradient(colors: [violet, violet], startPoint: .leading, endPoint: .trailing)
    /// Coach fill.
    static let coach = LinearGradient(colors: [mint, mint], startPoint: .leading, endPoint: .trailing)
    static let background = LinearGradient(
        colors: [tree.opacity(0.72), canvas],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // MARK: adaptive helpers

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        adaptive(light: NSColor.fromHex(light), dark: NSColor.fromHex(dark))
    }
}

// MARK: - Fonts
//
// Note body (titles, transcript, coach-cue quotes, minutes) uses `.read` (Literata).
// Chrome (sidebar, tabs, chips, buttons, labels) uses `.ui` (Hanken Grotesk).
// Fonts fall back to the system-nearest family when the bundled face is absent.

enum AppFonts {
    /// Registers every bundled `.ttf` (Hanken Grotesk, Literata) with the process
    /// so `Font.ui` / `Font.read` resolve to the real faces. Call once at launch,
    /// before any view renders. Idempotent — re-registration is a no-op.
    static func registerBundled() {
        guard let resourceURL = Bundle.main.resourceURL,
              let walker = FileManager.default.enumerator(at: resourceURL, includingPropertiesForKeys: nil)
        else { return }
        for case let url as URL in walker where url.pathExtension.lowercased() == "ttf" {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

private enum FontAssets {
    static let hasHanken = NSFont(name: "Hanken Grotesk", size: 12) != nil
    static let hasLiterata = NSFont(name: "Literata", size: 12) != nil
}

extension Font {
    /// UI chrome — Hanken Grotesk, falling back to the system sans.
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        FontAssets.hasHanken
            ? .custom("Hanken Grotesk", fixedSize: size).weight(weight)
            : .system(size: size, weight: weight, design: .default)
    }

    /// Reading body — Literata, falling back to the system serif (New York).
    static func read(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        FontAssets.hasLiterata
            ? .custom("Literata", fixedSize: size).weight(weight)
            : .system(size: size, weight: weight, design: .serif)
    }
}

// MARK: - Color / NSColor hex

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension NSColor {
    static func fromHex(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Componentes reutilizáveis

/// Opaque panel with a subtle border; avoids runtime blur/material costs.
struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Theme.surfaceStroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 8, y: 3)
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 14) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius))
    }
}

/// Dot de status com pulso quando ativo.
struct PulseDot: View {
    let active: Bool
    var health: RuntimeHealthLevel = .healthy

    var body: some View {
        Image(systemName: "circle.fill")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(active ? color : Color.secondary.opacity(0.5))
            .symbolEffect(.pulse, options: .repeating, isActive: active)
            .shadow(color: active ? color.opacity(0.6) : .clear, radius: 3)
        .frame(width: 16, height: 16)
    }

    private var color: Color {
        switch health {
        case .healthy: return Theme.mint
        case .degraded: return Theme.amber
        case .critical: return Theme.rose
        }
    }
}

/// Botão-ícone minimalista (header).
struct IconButtonStyle: ButtonStyle {
    var isOn: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isOn ? Theme.violet : .secondary)
            .frame(width: 28, height: 28)
            .background(Circle().fill(isOn ? Theme.violet.opacity(0.18) : Theme.interactive))
            .overlay(Circle().strokeBorder(isOn ? Theme.violet.opacity(0.45) : Theme.divider, lineWidth: 1))
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}

/// Botão principal (Iniciar/Parar).
struct PrimaryButtonStyle: ButtonStyle {
    var danger: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(danger ? Theme.rose : Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background {
                if danger {
                    Capsule().fill(Theme.rose.opacity(0.16))
                } else {
                    Capsule().fill(Theme.violet)
                }
            }
            .overlay(Capsule().strokeBorder(danger ? Theme.rose.opacity(0.5) : .clear, lineWidth: 1))
            .shadow(color: danger ? .clear : Theme.violet.opacity(0.35), radius: configuration.isPressed ? 1 : 5, y: 2)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}
