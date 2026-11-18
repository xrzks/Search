import SwiftUI
import WebKit

// Forget sites between launches: when Search opens, before any window or
// tab, everything WebKit keeps for a site — cookies, local storage,
// IndexedDB, service workers, caches — goes, unless the site is on the list
// of sites to keep (Settings › Privacy › Clear). Every profile's store and
// every space's own, not only the ones a window is about to show. At launch
// rather than at quit, so quitting stays instant and a crash or a force
// quit forgets just the same; no site sees the data in between, since
// Search isn't running. Private tabs keep nothing anyway.
//
// An entry is typed as for Send links to a space: "notion.so",
// "https://www.notion.so/x" or "*.notion.so" are all the site "notion.so"
// (SpaceRoutes.site). WebKit keeps a site's data under its registrable
// domain, and names its record so, so an entry keeps a record when the two
// are the same or one is a subdomain of the other (SpaceRoutes.same):
// mail.notion.so keeps notion.so's data, and notion.so keeps
// mail.notion.so's.
//
// Clear's Cookies and sign-ins and Cache go through the list too (see
// Browser.clearSites). Clear History leaves it alone: it is a choice about
// sites, not a record of where you have been.
//
// On by default; off unless set in a test run, whose suites keep their
// sites from one launch to the next.

enum Forget {
    static let key = "forget.sites"
    static let keptKey = "forget.keep"

    /// The switch, read before Preferences is: the launch comes first.
    static var on: Bool { Store.settings.object(forKey: key) as? Bool ?? !Store.testing }

    // MARK: - the list

    /// Whether the list keeps a site: a WebKit record's name, or a host. An
    /// IP address only as it is: 10.0.0.1 ends in .0.0.1 without being in it.
    static func keeps(_ site: String, in kept: [String]) -> Bool {
        guard let site = SpaceRoutes.site(site) else { return false }
        if Hosts.isAddress(site) { return kept.contains(site) }
        return kept.contains { !Hosts.isAddress($0) && SpaceRoutes.same($0, site) }
    }

    /// The site a tab's address is kept as, from its card: the registrable
    /// domain, which is what WebKit keeps the data under. Nil for anything
    /// but http and https.
    static func site(of url: URL) -> String? {
        guard let host = SpaceRoutes.site(of: url) else { return nil }
        if Hosts.isAddress(host) || host == "localhost" { return host }
        return SpaceRoutes.site(Vault.registrable(host)) ?? host
    }

    @MainActor static func keep(_ site: String) {
        guard let site = SpaceRoutes.site(site), !Shared.prefs.keptSites.contains(site) else { return }
        Shared.prefs.keptSites.append(site)
    }

    /// Off the list: every entry that keeps it, so its data goes next time.
    @MainActor static func unkeep(_ site: String) {
        guard let site = SpaceRoutes.site(site) else { return }
        Shared.prefs.keptSites.removeAll { SpaceRoutes.same($0, site) }
    }

    // MARK: - forgetting

    /// What `types` holds in each store, gone, but for the sites the list
    /// keeps. Answers with the sites kept, by name, that had anything.
    @MainActor static func sweep(_ stores: [WKWebsiteDataStore], types: Set<String>, keeping kept: [String]) async -> Set<String> {
        var held = Set<String>()
        for store in stores {
            let records = await store.dataRecords(ofTypes: types)
            let going = records.filter { !keeps($0.displayName, in: kept) }
            held.formUnion(records.filter { keeps($0.displayName, in: kept) }.map(\.displayName))
            if !going.isEmpty { await store.removeData(ofTypes: types, for: going) }
        }
        return held
    }

    /// Every store of every profile: its own and its spaces' own.
    @MainActor static var everyProfilesStores: [WKWebsiteDataStore] {
        var found: [WKWebsiteDataStore] = []
        for profile in Profiles.shared.list {
            for store in Spaces.stores(of: profile.id) where !found.contains(where: { $0 === store }) {
                found.append(store)
            }
        }
        return found
    }

    /// At launch, before SwiftUI starts and so before any tab loads. WebKit
    /// answers on the main run loop, which isn't running yet, so it is run
    /// here until the sweep is done — a few hundred milliseconds with many
    /// sites — or, at most, `patience` seconds, after which Search opens
    /// anyway and the sweep finishes behind it.
    static func atLaunch(patience: TimeInterval = 10) {
        guard on else { return }
        let done = Flag()
        MainActor.assumeIsolated {
            let kept = (Store.settings.array(forKey: keptKey) as? [String]) ?? []
            let stores = everyProfilesStores
            Task { @MainActor in
                _ = await sweep(stores, types: WKWebsiteDataStore.allWebsiteDataTypes(), keeping: kept)
                done.set = true
            }
        }
        let deadline = Date().addingTimeInterval(patience)
        while !done.set, Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }

    private final class Flag: @unchecked Sendable {
        var set = false
    }
}

/// Settings › Privacy › Clear, under Forget sites when Search opens: each
/// site kept, and a line to add one.
struct KeptSiteList: View {
    @ObservedObject var prefs: Preferences
    @State private var typed = ""

    var body: some View {
        ForEach(prefs.keptSites, id: \.self) { site in
            Rule()
            Line(site, "Keeps its sign-ins") {
                Pill("Remove") { prefs.keptSites.removeAll { $0 == site } }
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
            Pill("Keep", action: add)
                .disabled(SpaceRoutes.site(typed) == nil)
                .opacity(SpaceRoutes.site(typed) == nil ? 0.5 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        Text("A site you sign in to through another, Google or Microsoft, needs that one kept too.")
            .font(.system(size: 11))
            .foregroundStyle(Palette.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
    }

    private func add() {
        guard let site = SpaceRoutes.site(typed) else { return }
        if !prefs.keptSites.contains(site) { prefs.keptSites.append(site) }
        typed = ""
    }
}
