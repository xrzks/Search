import SwiftUI
import WebKit

// Forget sites you've left: when Search opens, before any window or tab,
// everything WebKit keeps for a site — cookies, local storage, IndexedDB,
// service workers, caches — goes, unless the site is on the list of sites
// to keep (Settings › Privacy › Clear). Every profile's store and every
// space's own, not only the ones a window is about to show. At launch
// rather than at quit, so quitting stays instant and a crash or a force
// quit forgets just the same; no site sees the data in between, since
// Search isn't running. Private tabs keep nothing anyway.
//
// And again while Search runs, so one left open for weeks forgets too:
// about once an hour, and when the Mac wakes, the same sweep, but for the
// sites a tab is open on as well (see Running). Not when a site's last tab
// closes: that is a sweep per tab closed, and a site opened again a moment
// later would have lost its sign-in for nothing.
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
    /// keeps and the sites `open` names, read as the list is. Answers with
    /// the sites kept, by name, that had anything. `open` is asked again
    /// for each store, once its records are in: a tab opened while the
    /// sweep waited on WebKit is spared too.
    @MainActor static func sweep(_ stores: [WKWebsiteDataStore], types: Set<String>, keeping kept: [String],
                                 sparing open: () -> Set<String> = { [] }) async -> Set<String> {
        var held = Set<String>()
        for store in stores {
            let records = await store.dataRecords(ofTypes: types)
            let spared = Array(open())
            let going = records.filter { !keeps($0.displayName, in: kept) && !keeps($0.displayName, in: spared) }
            held.formUnion(records.filter { keeps($0.displayName, in: kept) }.map(\.displayName))
            if !going.isEmpty { await store.removeData(ofTypes: types, for: going) }
        }
        return held
    }

    /// Everything, from every store of every profile, but the sites kept
    /// and the ones `open` names: the sweep at launch and the one while
    /// Search runs.
    @MainActor static func forget(keeping kept: [String], sparing open: () -> Set<String> = { [] }) async {
        _ = await sweep(everyProfilesStores, types: WKWebsiteDataStore.allWebsiteDataTypes(), keeping: kept, sparing: open)
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
            Task { @MainActor in
                await forget(keeping: kept)
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

    // MARK: - while Search runs

    /// The sites a tab is open on, as a card keeps them (`site(of:)`): where
    /// its page is, where it is going, and a pin's own page, which ⌘W takes
    /// it back to. A tab asleep has its address all the same. Not a private
    /// tab's: its store is one of its own, which keeps nothing.
    @MainActor static func openSites(_ tabs: [Tab]) -> Set<String> {
        var sites = Set<String>()
        for tab in tabs where !tab.shy && tab.store.isPersistent {
            for url in [tab.address, tab.committed, tab.pin == nil ? nil : tab.home] {
                if let url, let site = site(of: url) { sites.insert(site) }
            }
        }
        return sites
    }

    /// Every tab there is: every window's, of every profile — a tucked one
    /// of a merged window, a popup's, and the last one closed, kept with its
    /// tabs asleep — each space's row, its pins, a split's two sides and a
    /// float's tab among them; the peek over a page; and the small windows.
    @MainActor static var everyTab: [Tab] {
        Browsers.all.flatMap { $0.tabs + $0.parkedTabs + [$0.peekTab].compactMap { $0 } }
            + LittleWindow.all.map(\.tab)
    }

    /// The sweep while Search runs: started once, at launch (see
    /// Links.applicationDidFinishLaunching), it runs about once an
    /// hour and when the Mac wakes, with the switch on. Never two at once.
    /// The tabs open are read as it goes, not before, and the list of sites
    /// kept as it starts.
    @MainActor final class Running {
        static let shared = Running()

        /// How often, and how soon after the last sweep one is worth
        /// another: the timer late out of a sleep and the wake come together.
        static let every: TimeInterval = 60 * 60
        static let spacing: TimeInterval = 5 * 60

        private(set) var sweeping = false
        /// When the last one finished, the launch's counted as one.
        private(set) var last = Date()
        private var timer: Timer?
        private var waking: NSObjectProtocol?

        func start() {
            guard timer == nil else { return }
            let timer = Timer(timeInterval: Self.every, repeats: true) { _ in
                MainActor.assumeIsolated { Running.shared.due() }
            }
            timer.tolerance = Self.spacing
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            waking = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { _ in MainActor.assumeIsolated { Running.shared.due() } }
        }

        /// The timer or a wake: a sweep, unless one ran a moment ago.
        private func due() {
            guard Date().timeIntervalSince(last) >= Self.spacing else { return }
            Task { await now() }
        }

        /// A sweep now: answers false, sweeping nothing, with the switch off
        /// or another sweep under way.
        @discardableResult func now() async -> Bool {
            guard Shared.prefs.forgetsSites, !sweeping else { return false }
            sweeping = true
            defer { sweeping = false; last = Date() }
            await Forget.forget(keeping: Shared.prefs.keptSites, sparing: { openSites(everyTab) })
            return true
        }
    }
}

/// Settings › Privacy › Clear, under Forget sites you've left: each
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
