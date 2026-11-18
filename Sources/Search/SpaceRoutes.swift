import SwiftUI

// Send links to a space (idea 255; #595, #721): links to chosen sites open
// in their space, with its sign-ins, as Arc's Air Traffic Control does.
// After @AdityaAmitK's #596 and #722, made smaller.
//
// Off unless turned on in Settings › Spaces & Pins, and only with spaces on.
// A rule is a site, its subdomains with it, and a space; the most specific
// site wins. A site no rule names goes to the first of the window's
// profile's spaces, unless Open everything else in the first space is
// turned off. It sends:
//
// - a link from another app (Search as the Mac's browser);
// - a link a page opens in a new tab — a target="_blank" click, ⌘-click,
//   the middle button, Open Link in New Tab — from a page in another space;
// - an address or a search typed after ⌘T, ⌘L or ⌘K, in a new tab there,
//   with the tab you were on left as it was. A search goes where its
//   address does: the engine's, or a keyword's site.
//
// Opened in front, the tab takes you there: the window that has the space,
// or this one switched to it. Opened behind (⌘Return, a ⌘-click, the middle
// button, Open Link in New Tab), it goes into that space's row without
// going there. A link followed in its own tab, a tab picked from the
// field's list, a private tab's links and addresses, a window the page
// opens from a script or sizes ("Sign in with…", which needs its opener)
// and anything that isn't http or https stay where they are. So do, for a
// site no rule names, a link to its page's own site and a pin's links,
// which have its peek. A rule whose space has gone is passed over.

struct SpaceRoute: Equatable, Identifiable {
    /// A host, lowercased, without www.: "notion.so".
    var site: String
    var space: UUID
    var id: String { site }

    /// As it is kept in the settings: a plain dictionary, readable with
    /// `defaults read`.
    var plist: [String: String] { ["site": site, "space": space.uuidString] }

    init(site: String, space: UUID) {
        self.site = site
        self.space = space
    }

    init?(plist: Any) {
        guard let entry = plist as? [String: String],
              let site = entry["site"].flatMap(SpaceRoutes.site), let space = entry["space"].flatMap(UUID.init)
        else { return nil }
        self.init(site: site, space: space)
    }
}

enum SpaceRoutes {
    static let key = "spaces.links"
    static let rulesKey = "spaces.links.rules"
    static let restKey = "spaces.links.rest"

    // MARK: - sites

    /// What was typed, as the site a rule keeps: "https://www.Notion.so/x",
    /// "notion.so" and "*.notion.so" are all "notion.so". Nil for anything
    /// that isn't a host.
    static func site(_ typed: String) -> String? {
        var text = typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.hasPrefix("*.") { text.removeFirst(2) }
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard let host = URLComponents(string: text)?.host else { return nil }
        return clean(host)
    }

    /// The site of a web address; nil for anything but http and https.
    static func site(of url: URL) -> String? {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let host = url.host else { return nil }
        return clean(host.lowercased())
    }

    private static func clean(_ host: String) -> String? {
        var host = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host.hasSuffix(".") { host.removeLast() }
        if host.hasPrefix("www."), host.dropFirst(4).contains(".") { host.removeFirst(4) }
        guard !host.isEmpty, host.count <= 253,
              host.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." || $0 == ":" })
        else { return nil }
        // An IPv6 address as it is; a name has no empty label, and one with
        // no dot is only ever localhost.
        if host.contains(":") { return host }
        guard host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty }),
              host.contains(".") || host == "localhost"
        else { return nil }
        return host
    }

    // MARK: - matching

    /// The rule for an address: the one whose site is its host or a domain
    /// of it, the longest such site when more than one is.
    static func match(_ url: URL, in routes: [SpaceRoute]) -> SpaceRoute? {
        guard let host = site(of: url) else { return nil }
        return routes
            .filter { host == $0.site || (!host.contains(":") && host.hasSuffix("." + $0.site)) }
            .max { $0.site.count < $1.site.count }
    }

    /// Whether two sites are one: the same, or one a subdomain of the other.
    static func same(_ one: String, _ other: String) -> Bool {
        one == other || (!one.contains(":") && !other.contains(":")
            && (one.hasSuffix("." + other) || other.hasSuffix("." + one)))
    }

    /// The space a rule sends an address to: only while the setting and
    /// spaces are both on, and only a space that is still there.
    static func space(for url: URL, routes: [SpaceRoute], on: Bool, spaces: [UUID: Space]) -> Space? {
        guard on, let route = match(url, in: routes) else { return nil }
        return spaces[route.space]
    }

    @MainActor static func space(for url: URL) -> Space? {
        let prefs = Shared.prefs
        return space(for: url, routes: prefs.spaceRoutes, on: prefs.usesSpaces && prefs.sendsLinksToSpaces,
                     spaces: Spaces.known)
    }

    /// One site to one space, in place of any rule the site had.
    @MainActor static func set(_ site: String, to space: UUID) {
        var routes = Shared.prefs.spaceRoutes
        if let at = routes.firstIndex(where: { $0.site == site }) {
            routes[at].space = space
        } else {
            routes.append(SpaceRoute(site: site, space: space))
        }
        Shared.prefs.spaceRoutes = routes
    }

    @MainActor static func remove(_ site: String) {
        Shared.prefs.spaceRoutes.removeAll { $0.site == site }
    }

    // MARK: - windows

    /// The window that is to show `space`: one on screen already in it, the
    /// one in front first; otherwise `source`, or a window of the space's
    /// profile, switched to it. Nil if it couldn't be.
    @MainActor static func window(for space: Space, from source: Browser) -> Browser? {
        let windows = ([Browsers.front].compactMap { $0 } + Browsers.all.reversed()).filter { $0.isOpen && !$0.isPopup }
        if let shown = windows.first(where: { $0.spaceID == space.id }) { return shown }
        let window = space.profileID == source.profileID ? source : Browsers.open(profile: space.profileID)
        guard window.prefs.usesSpaces else { return nil }
        window.switchSpace(to: space.id)
        // With profiles in one window, the switch can bring that profile's
        // window into this one's place (see OneWindow.swift).
        return ([window] + Browsers.all.reversed()).first { $0.isOpen && !$0.isPopup && $0.spaceID == space.id }
    }

    /// The spaces a rule can name, with the profile's name before each once
    /// there is more than one profile.
    @MainActor static var choices: [(id: UUID, name: String)] {
        let profiles = Profiles.shared
        return Spaces.read().map { space in
            (space.id, profiles.several ? "\(profiles.profile(space.profileID).name) › \(space.name)" : space.name)
        }
    }
}

extension Browser {
    /// Where an address opened from this window goes: the space its rule
    /// names, or, for a web address no rule sends anywhere, the first of
    /// this profile's spaces, while Open everything else in the first space
    /// is on. `rule` says which of the two.
    func sentSpace(for url: URL) -> (space: Space, rule: Bool)? {
        if let space = SpaceRoutes.space(for: url) { return (space, true) }
        guard prefs.usesSpaces, prefs.sendsLinksToSpaces, prefs.sendsRestToFirstSpace,
              SpaceRoutes.site(of: url) != nil, let first = spaces.first
        else { return nil }
        return (first, false)
    }

    /// For a link from another app: the window it is sent to, already in
    /// its space. Nil to open it as always.
    func routed(_ url: URL) -> Browser? {
        guard !isPopup, let space = sentSpace(for: url)?.space, space.id != spaceID else { return nil }
        return SpaceRoutes.window(for: space, from: self)
    }

    /// A link a page opens in a new tab, opened in the space it is sent to,
    /// in front or behind as the click asked. False when nothing sends it
    /// out of the page's space.
    func sendToSpace(_ url: URL, from source: Tab?, front: Bool) -> Bool {
        guard !isPopup, let source, !source.shy, let (space, rule) = sentSpace(for: url) else { return false }
        let here = parked.first { $0.value.tabs.contains { $0 === source } }?.key ?? spaceID
        guard space.id != here else { return false }
        if !rule {
            // Sent only for being no rule's: a link within its page's own
            // site stays with it, and a pin's links have its peek.
            if let page = source.address.flatMap(SpaceRoutes.site(of:)), let site = SpaceRoutes.site(of: url),
               SpaceRoutes.same(page, site) { return false }
            if source.pin != nil, prefs.pinsPeek { return false }
        }
        send(url, to: space, front: front)
        return true
    }

    /// The space an address or search typed into the field is sent to, when
    /// it isn't this one; nil to open it here as always. Never from a
    /// private tab, whose new tabs are private too.
    func typedSpace(for url: URL) -> Space? {
        guard !isPopup, active?.shy != true, let space = sentSpace(for: url)?.space, space.id != spaceID
        else { return nil }
        return space
    }

    /// An address in a new tab in another space: in front, going there, or
    /// behind, into the row of a window that shows the space or else this
    /// window's row for it, asleep until it is gone to. Another profile's
    /// space that no window shows can only be had by going there, so behind
    /// or not, it opens in front.
    func send(_ url: URL, to space: Space, front: Bool) {
        if !front {
            if let shown = Browsers.all.first(where: { $0.isOpen && !$0.isPopup && $0.spaceID == space.id }) {
                shown.open(url, foreground: false, mayWait: true)
                announce("Opened in \(space.name)")
                return
            }
            if spaces.contains(where: { $0.id == space.id }) {
                var row = parked[space.id] ?? loadRow(space.id)
                let lone = loneBlanks(in: row.tabs, splits: row.splits, typing: nil)
                let tab = Tab(configuration: Web.configuration(space: space.id))
                prepare(tab)
                tab.restore(url: url, title: url.host ?? "")
                row.tabs.append(tab)
                // In place of the empty tab a space with nothing open shows.
                for blank in lone { row.tabs.removeAll { $0 === blank }; blank.close() }
                if row.active == nil || lone.contains(where: { $0.id == row.active }) { row.active = tab.id }
                parked[space.id] = row
                writeSession(now: true, space: space.id, row: row)
                announce("Opened in \(space.name)")
                return
            }
        }
        guard let target = SpaceRoutes.window(for: space, from: self) else { return }
        target.open(url, foreground: true)
        if target !== self { Browsers.show(target) }
    }
}

/// Settings › Spaces & Pins, under Send links to a space: each site and its
/// space, and a line to add one.
struct SpaceRouteList: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject private var profiles = Profiles.shared
    @State private var typed = ""
    @State private var chosen: UUID?

    var body: some View {
        let choices = SpaceRoutes.choices
        ForEach(prefs.spaceRoutes) { route in
            Rule()
            Line(route.site, choices.first { $0.id == route.space }.map { "Opens in \($0.name)" }
                 ?? "Its space is gone, so links open as usual") {
                Pill("Remove") { SpaceRoutes.remove(route.site) }
            }
        }
        Rule()
        HStack(spacing: 10) {
            TextField("notion.so", text: $typed)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Palette.wash, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .onSubmit(add)
            Picker("Space", selection: Binding(get: { chosen ?? choices.first?.id }, set: { chosen = $0 })) {
                ForEach(choices, id: \.id) { Text($0.name).tag(Optional($0.id)) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            Pill("Add", action: add)
                .disabled(SpaceRoutes.site(typed) == nil)
                .opacity(SpaceRoutes.site(typed) == nil ? 0.5 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func add() {
        guard let site = SpaceRoutes.site(typed), let space = chosen ?? SpaceRoutes.choices.first?.id else { return }
        SpaceRoutes.set(site, to: space)
        typed = ""
    }
}
