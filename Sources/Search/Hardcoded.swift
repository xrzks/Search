import Foundation

// Hardcoded (see FORK.md): settings this browser doesn't offer. Each one
// is held at one value, written at every launch, and its row is gone from
// Settings and from the find field. Upstream's rows and keys are left as they
// are, so a merge only meets the few lines that ask here. To bring one back,
// take it out of `rows` (and its key out of `fixed`).
enum Hardcoded {
    /// Sections gone from the rail. Asked for by name, they open Appearance.
    static let pages: Set<SettingsPanel.Page> = [.general, .themes]

    /// Rows gone from their section and from the find field, by
    /// SettingsIndex id. A group left with no rows goes with them.
    static let rows: Set<String> = [
        // General: the whole section
        "general.default", "mail.webmail", "mail.default", "general.import",
        "icloud", "icloud.erase", "handoff", "sync", "quit.confirm",
        "downloads.folder", "downloads.ask", "downloads.button", "downloads.open",
        "downloads.screenshots", "general.exportSpaces",
        // Themes
        "home.theme",
        // Appearance
        "layout.cards", "layout.cardsFullScreen", "toolbar.left", "tabs.compact",
        "scrollbars.fade", "sidebar.foldIcons", "motion.downloads",
        "window.glass", "window.glass.style", "window.glass.clear", "window.glass.grain",
        "tabs.liquid", "sidebar.doorsUp", "helm.shown", "foot.shown",
        "sidebar.foldButton", "sidebar.narrowIcons", "tabs.highContrast",
        "tabs.reading", "tabs.pinCounts", "tabs.give",
        // Tabs
        "tabs.switcherBehindFirst", "tabs.switcherLeavesOutPins", "tabs.mirror", "tabs.keepWindow",
        "home.tiles", "tabs.clickRenames",
        // Browsing
        "reader.twins", "reader.follows", "meet.pip", "hiding.shapes", "pages.capture.copyOnly",
        // Spaces & Pins
        "arc.setup", "arc.import", "spaces", "spaces.commandNumbers", "spaces.buttons",
        "profiles", "profiles.oneWindow", "spaces.links", "links.ask", "note.spaceGradient",
        "field.hidesPage", "pins.preview",
        // Passwords
        "passkeys",
        // Keyboard & Mouse
        "autoscroll", "wheel.smooth", "pages.bounce", "keys.backspaceBack",
        "split.controls",
        // About
        "news.iphone", "bench", "agents",
    ]

    /// What the trimmed rows are held at. Rows not here (sync, the
    /// downloads folder, Glass's look) are off or unset already and have
    /// nothing left to turn them on.
    static let fixed: [String: Any] = [
        "handoff": false,
        "quit.confirm": true,
        "mail.webmail": "none",
        "downloads.ask": false,
        "downloads.button": false,
        "home.theme": "off",
        "layout.cards": true,
        "layout.cardsFullScreen": false,
        "toolbar.left": false,
        "tabs.compact": false,
        "scrollbars.fade": false,
        "sidebar.foldIcons": false,
        "motion.downloads": true,
        "window.glass": false,
        "tabs.liquid": false,
        "sidebar.doorsUp": false,
        "helm.back.hidden": false,
        "helm.forward.hidden": false,
        "helm.reload.hidden": false,
        "foot.extensions.hidden": false,
        "foot.bookmarks.hidden": false,
        "foot.profile.hidden": false,
        "sidebar.foldButton": false,
        "sidebar.narrowIcons": false,
        "tabs.highContrast": false,
        "tabs.reading": false,
        "tabs.pinCounts": false,
        "tabs.give": false,
        "tabs.switcherBehindFirst": false,
        "tabs.switcherLeavesOutPins": true,
        "tabs.mirror": false,
        "tabs.keepWindow": false,
        "home.tiles": false,
        "tabs.clickRenames": false,
        "reader.twins": true,
        "reader.follows": true,
        "meet.pip": false,
        "hiding.shapes": false,
        "pages.capture.copyOnly": true,
        "spaces": false,
        "profiles.oneWindow": false,
        "field.hidesPage": false,
        SpaceRoutes.key: false,
        "pins.home": true,
        "pins.peek": true,
        "pins.preview": false,
        "passkeys": false,
        "autoscroll": false,
        "wheel.smooth": false,
        "pages.bounce": false,
        "keys.backspaceBack": false,
        "split.controls": true,
        "bench": false,
        "agents": false,
    ]

    /// A switch upstream fixed for everyone (Retired, in Prefs.swift) is
    /// held at this fork's value instead, where `fixed` names one.
    nonisolated static func held(_ key: String) -> Bool? { fixed[key] as? Bool }

    static func offers(_ id: String) -> Bool { !rows.contains(id) }
    static func offers(_ page: SettingsPanel.Page) -> Bool { !pages.contains(page) }

    /// A trimmed section asked for by name opens this one instead.
    static func page(_ page: SettingsPanel.Page) -> SettingsPanel.Page {
        offers(page) ? page : .appearance
    }

    /// At launch, before Preferences reads them. Not under test, where the
    /// settings are the tests' own.
    static func apply() {
        guard !Store.testing else { return }
        let store = Store.settings
        for (key, value) in fixed { store.set(value, forKey: key) }
        let open = store.string(forKey: "settings.page").flatMap(SettingsPanel.Page.named)
        if open == nil { store.set(SettingsPanel.Page.appearance.rawValue, forKey: "settings.page") }
    }
}
