import AppKit
import SwiftUI

// Search's colours are 0x26f's (~/.config/0x26f/0x26f.css): Rosé Pine on
// 0x96f's neutrals, its light variant while the window is light and its
// dark one while it is dark, so Light, Dark and Auto keep meaning what they
// say.
//
// Only what Search draws itself: the strip, the column, the panels, its own
// pages, reading mode and, with Chrome's colors on, the Web Inspector. Pages
// keep their own colours, and what macOS draws (menus, alerts, the open and
// save panels, tooltips) keeps the Mac's light or dark.

/// One of 0x26f's variants, in its own names, and Search's roles in it.
struct X26f {
    let base, surface, overlay, muted, subtle, text: NSColor
    let red, yellow, pink, blue, cyan, purple: NSColor
    let highlightLow, highlightMed, highlightHigh: NSColor
    let isDark: Bool

    static let light = X26f(
        base: hex(0xfcfcfa), surface: hex(0xfffaf3), overlay: hex(0xf2e9e1),
        muted: hex(0x9893a5), subtle: hex(0x797593), text: hex(0x575279),
        red: hex(0xb4637a), yellow: hex(0xea9d34), pink: hex(0xd7827e),
        blue: hex(0x286983), cyan: hex(0x56949f), purple: hex(0x907aa9),
        highlightLow: hex(0xf4ede8), highlightMed: hex(0xdfdad9), highlightHigh: hex(0xcecacd),
        isDark: false)

    static let dark = X26f(
        base: hex(0x111013), surface: hex(0x232030), overlay: hex(0x393552),
        muted: hex(0x6e6a86), subtle: hex(0x908caa), text: hex(0xe0def4),
        red: hex(0xeb6f92), yellow: hex(0xf6c177), pink: hex(0xea9a97),
        blue: hex(0x3e8fb0), cyan: hex(0x9ccfd8), purple: hex(0xc4a7e7),
        highlightLow: hex(0x242132), highlightMed: hex(0x3b3850), highlightHigh: hex(0x4b4760),
        isDark: true)

    // Search's roles. The ground is base, the background, as a terminal in
    // 0x26f has it; the frame around the card, the column beside it
    // included, is surface, as 0x26f's panels are.
    var ground: NSColor { base }
    var frame: NSColor { surface }
    var ink: NSColor { text }
    /// Subtle rather than muted, which is too faint on the light variant for
    /// the small labels Search writes in it.
    var quiet: NSColor { subtle }
    var faint: NSColor { highlightHigh }
    var hairline: NSColor { mix(overlay, highlightMed, 0.6) }
    var wash: NSColor { overlay }
    var hover: NSColor { isDark ? mix(base, overlay, 0.45) : highlightLow }
    var resting: NSColor { highlightHigh }
    var safe: NSColor { isDark ? cyan : blue }
    var unsafe: NSColor { yellow }
    var accent: NSColor { purple }
    /// The sheen across a peek's bones (see PeekSkeleton).
    var sheen: NSColor { isDark ? mix(overlay, highlightMed, 0.5) : mix(overlay, surface, 0.6) }

    /// A space's colour (see Spaces.colours), by its place in that list.
    func space(_ index: Int) -> NSColor {
        [muted, blue, cyan, yellow, red, purple][index]
    }

    /// For a stylesheet: #rrggbb.
    static func css(_ colour: NSColor) -> String {
        let c = colour.usingColorSpace(.sRGB) ?? colour
        func byte(_ part: CGFloat) -> Int { Int((min(max(part, 0), 1) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
    }

    private static func hex(_ value: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xff) / 255, green: CGFloat((value >> 8) & 0xff) / 255,
                blue: CGFloat(value & 0xff) / 255, alpha: 1)
    }

    private func mix(_ a: NSColor, _ b: NSColor, _ amount: CGFloat) -> NSColor {
        a.blended(withFraction: amount, of: b) ?? a
    }
}

enum Theme {
    /// 0x26f's variant for a window this dark.
    static func variant(dark: Bool) -> X26f { dark ? .dark : .light }

    static func variant(for appearance: NSAppearance) -> X26f {
        variant(dark: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
    }
}
