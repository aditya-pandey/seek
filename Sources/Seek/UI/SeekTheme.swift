import SwiftUI
import AppKit

/// Native macOS NSVisualEffectView wrapper for true hardware-accelerated frosted vibrancy.
public struct VisualEffectBlurView: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode
    public var state: NSVisualEffectView.State = .active

    public init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

public enum SeekTheme {
    // ── Frosted Obsidian Glass & Titanium Tokens (Matches Glance Visual Family) ──
    public static let glassTint         = Color(red: 0.055, green: 0.062, blue: 0.078).opacity(0.68)
    public static let inspectorTint     = Color(red: 0.035, green: 0.040, blue: 0.052).opacity(0.46)
    public static let rowSurface        = Color.white.opacity(0.032)
    public static let rowHover          = Color.white.opacity(0.065)
    public static let dividerStroke     = Color.white.opacity(0.09)

    // ── Typography ──
    public static let labelPrimary      = Color(red: 0.96, green: 0.97, blue: 0.99)
    public static let labelSecondary    = Color(red: 0.62, green: 0.66, blue: 0.73)
    public static let labelMuted        = Color(red: 0.44, green: 0.48, blue: 0.55)

    // ── Brand Accents ──
    public static let steelSapphire     = Color(red: 0.49, green: 0.66, blue: 0.93) // #7DA8ED
    public static let platinumIce       = Color(red: 0.86, green: 0.90, blue: 0.96)
    public static let emerald           = Color(red: 0.46, green: 0.76, blue: 0.64)
    public static let warmChampagne     = Color(red: 0.88, green: 0.75, blue: 0.54)
    public static let brushedGold       = Color(red: 0.84, green: 0.74, blue: 0.55)

    /// Top-lit anodized specular rim for the floating frosted palette
    public static var specularRimGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.28),
                Color.white.opacity(0.11),
                Color.white.opacity(0.05)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
