import AppKit
import SwiftUI
import WebKit

// Settings › Appearance › Colours: Search's own greys, or Rosé Pine's
// (rosepinetheme.com) — Dawn while the window is light, Moon while it is
// dark, so Light, Dark and Auto keep meaning what they say.
//
// Only what Search draws itself: the strip, the column, the panels, its own
// pages, reading mode and, with Chrome's colors on, the Web Inspector. Pages
// keep their own colours, and what macOS draws (menus, alerts, the open and
// save panels, tooltips) keeps the Mac's light or dark.
//
// Every colour in Palette asks here first, as it is drawn, and falls back to
// its grey; nothing else in the code knows which colours are on.

enum Colours: String, CaseIterable, Identifiable {
    case search
    case rosePine = "rose-pine"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .search: return "Search"
        case .rosePine: return "Rosé Pine"
        }
    }
}

/// One of Rosé Pine's variants, in its own names, and Search's roles in it.
struct RosePine {
    let base, surface, overlay, muted, subtle, text: NSColor
    let love, gold, rose, pine, foam, iris: NSColor
    let highlightLow, highlightMed, highlightHigh: NSColor
    let dark: Bool

    static let dawn = RosePine(
        base: hex(0xfaf4ed), surface: hex(0xfffaf3), overlay: hex(0xf2e9e1),
        muted: hex(0x9893a5), subtle: hex(0x797593), text: hex(0x575279),
        love: hex(0xb4637a), gold: hex(0xea9d34), rose: hex(0xd7827e),
        pine: hex(0x286983), foam: hex(0x56949f), iris: hex(0x907aa9),
        highlightLow: hex(0xf4ede8), highlightMed: hex(0xdfdad9), highlightHigh: hex(0xcecacd),
        dark: false)

    static let moon = RosePine(
        base: hex(0x232136), surface: hex(0x2a273f), overlay: hex(0x393552),
        muted: hex(0x6e6a86), subtle: hex(0x908caa), text: hex(0xe0def4),
        love: hex(0xeb6f92), gold: hex(0xf6c177), rose: hex(0xea9a97),
        pine: hex(0x3e8fb0), foam: hex(0x9ccfd8), iris: hex(0xc4a7e7),
        highlightLow: hex(0x2a283e), highlightMed: hex(0x44415a), highlightHigh: hex(0x56526e),
        dark: true)

    // Search's roles. The ground is surface and the frame around the card is
    // base: in both variants base is the one further from the page, as
    // Search's frame is from its white and its near-black, so the card still
    // stands off what it sits on. The greys of the column (side…) are steps
    // from base, as Search's are from the frame.
    var ground: NSColor { surface }
    var frame: NSColor { base }
    var ink: NSColor { text }
    /// Subtle rather than Rosé Pine's muted, which is too faint on Dawn for
    /// the small labels Search writes in it.
    var quiet: NSColor { subtle }
    var faint: NSColor { highlightHigh }
    var hairline: NSColor { mix(overlay, highlightMed, 0.6) }
    var wash: NSColor { overlay }
    var pinLive: NSColor { highlightMed }
    var hover: NSColor { dark ? mix(surface, overlay, 0.45) : highlightLow }
    var sideWash: NSColor { dark ? overlay : mix(overlay, highlightMed, 0.5) }
    var sideHover: NSColor { dark ? highlightLow : overlay }
    var sideTile: NSColor { dark ? mix(base, overlay, 0.35) : mix(base, overlay, 0.7) }
    var sidePinLive: NSColor { highlightMed }
    var resting: NSColor { highlightHigh }
    var safe: NSColor { dark ? foam : pine }
    var unsafe: NSColor { gold }
    var accent: NSColor { iris }
    /// The sheen across a peek's bones (see PeekSkeleton).
    var sheen: NSColor { dark ? mix(overlay, highlightMed, 0.5) : mix(overlay, surface, 0.6) }

    /// A space's colour (see Spaces.colours), by its place in that list.
    func space(_ index: Int) -> NSColor? {
        [muted, pine, foam, gold, love, iris].indices.contains(index) ? [muted, pine, foam, gold, love, iris][index] : nil
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
    /// Set by Prefs, read by every colour as it is drawn.
    nonisolated(unsafe) static var colours: Colours = .search

    /// Rosé Pine's variant for a window this dark, or nil for Search's greys.
    static func variant(dark: Bool) -> RosePine? {
        colours == .rosePine ? (dark ? .moon : .dawn) : nil
    }

    static func variant(for appearance: NSAppearance) -> RosePine? {
        variant(dark: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
    }

    /// The colours changed, the appearance didn't: nothing would draw again
    /// on its own, since a colour is only asked again when the appearance
    /// changes, and the same appearance given again is no change to SwiftUI.
    /// So the app is taken to the other appearance and back to `look`'s,
    /// every window laid out and drawn after each: everything that follows
    /// the appearance asks for its colours again. Both in one turn, so the
    /// screen is only ever shown the second. The pages are held where they
    /// are meanwhile: a page is told of an appearance in a message of its
    /// own, and a site watching prefers-color-scheme would draw itself light
    /// and dark again for nothing.
    static func repaint(back look: Look) {
        var held: [(WKWebView, NSAppearance?)] = []
        func hold(_ view: NSView) {
            if let web = view as? WKWebView {
                held.append((web, web.appearance))
                web.appearance = NSAppearance(named: web.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) ?? .aqua)
            } else {
                view.subviews.forEach(hold)
            }
        }
        for window in NSApp.windows { if let frame = window.contentView?.superview ?? window.contentView { hold(frame) } }
        func settle() {
            for window in NSApp.windows {
                window.contentView?.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
            }
        }
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        NSApp.appearance = NSAppearance(named: dark ? .aqua : .darkAqua)
        settle()
        NSApp.appearance = look.appearance
        settle()
        for (web, own) in held { web.appearance = own }
        NotificationCenter.default.post(name: changed, object: nil)
    }

    /// Posted once the colours have changed, for what holds a colour of its
    /// own rather than asking as it is drawn: reading mode's sheet, the
    /// inspector's.
    static let changed = Notification.Name("SearchColoursChanged")
}
