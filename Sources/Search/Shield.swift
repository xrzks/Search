import CryptoKit
import WebKit

// The ad blocker. No settings, no counter, no shield icon going green — it is
// prepared at launch and then it is simply true that the page is lighter.
//
// A content rule list is enforced inside WebKit's networking, before a request
// is made and before a stylesheet is applied, so this costs nothing at run time
// in the way a JavaScript blocker does.
//
// In this fork, two bigger lists can go with it: EasyPrivacy and EasyList,
// turned into WebKit's rules when Search is built (blocklists.py) and
// carried in the app, never fetched by Search itself. Each is a list of its
// own beside Shield's, switched in Settings › Privacy › Blocking, and goes
// on and off with it: for every site, or for none where it is paused.

/// The bigger lists, as this build carries them.
enum ShieldList: String, CaseIterable {
    case easyprivacy, easylist

    /// Its rules in the app, when build.sh could fetch the list: WebKit's
    /// JSON, deflated.
    var file: URL? { Bundle.main.url(forResource: rawValue, withExtension: "rules", subdirectory: "Blocking") }

    /// The JSON, and a hash of the file it came from, which names the
    /// compiled list. Several megabytes: never on the main thread.
    func rules() -> (json: String, hash: String)? {
        guard let file, let packed = try? Data(contentsOf: file),
              let data = try? (packed as NSData).decompressed(using: .zlib) as Data,
              let json = String(data: data, encoding: .utf8)
        else { return nil }
        return (json, SHA256.hash(data: packed).map { String(format: "%02x", $0) }.joined())
    }

    /// The ones this build has; Settings offers only those.
    static let inBuild: Set<ShieldList> = Set(allCases.filter { $0.file != nil })

    var identifierPrefix: String { "fork-shield-\(rawValue)-" }
}

@MainActor
final class Shield: ObservableObject {
    static let shared = Shield()

    private let store: WKContentRuleListStore?

    convenience init() {
        self.init(store: WKContentRuleListStore.default())
    }

    init(store: WKContentRuleListStore?) {
        self.store = store
    }

    private(set) var list: WKContentRuleList?
    private var preparing = false

    /// The bigger lists compiled so far, and the ones being compiled.
    private var bigger: [ShieldList: WKContentRuleList] = [:]
    private var compiling: Set<ShieldList> = []
    /// What went wrong with one of them, for its row in Settings.
    @Published private(set) var biggerTrouble: [ShieldList: String] = [:]
    /// The ones switched on in Settings (see choose).
    private(set) var chosen: Set<ShieldList> = []

    /// Set the one time compiling the list didn't work. The toggle in
    /// Settings can say "on" all it wants; nothing is actually blocked until
    /// this is nil, so it is the one thing worth telling a person about
    /// rather than failing the quiet way a missing ad is quiet.
    @Published private(set) var trouble: String?

    /// On unless somebody said otherwise. Every tab's controller is told when
    /// this changes, so it takes effect on the next request rather than the
    /// next launch.
    var enabled = true

    /// Sites it is off for — the ones it broke. A checkout that never
    /// finishes, a video that never starts: switching off here, for this site,
    /// beats switching off everywhere and forgetting to switch back.
    private(set) var paused: Set<String> = Set(
        Store.settings.stringArray(forKey: "shield.paused") ?? []
    )

    func isPaused(on host: String?) -> Bool {
        guard let host else { return false }
        return paused.contains(host)
    }

    func pause(_ host: String, _ off: Bool) {
        if off { paused.insert(host) } else { paused.remove(host) }
        Store.settings.set(Array(paused).sorted(), forKey: "shield.paused")
    }

    /// Before each page: the list goes on or off for the site this tab is
    /// heading to. A rule list is enforced from the moment it is added, so
    /// doing this at the navigation is what makes "off for this site" true
    /// for the whole page rather than for the second half of it.
    func tune(_ controller: WKUserContentController, for host: String?) {
        set(controller, on: enabled && !isPaused(on: host))
    }

    /// Every page's controller, and whether blocking is on for where it is:
    /// a list that is ready later, or switched on, reaches each of them.
    private let pages = NSMapTable<WKUserContentController, NSNumber>.weakToStrongObjects()

    /// Which lists each page's controller has, as it was last given or
    /// taken: one heading to another page with the same lists is left as it
    /// is, rather than the lists taken out and put back — sent to the page's
    /// process both ways — on every link followed.
    private let holding = NSMapTable<WKUserContentController, NSString>.weakToStrongObjects()

    /// The lists a page with blocking on gets: Shield's own, and the bigger
    /// ones chosen and ready.
    private var inForce: [WKContentRuleList] {
        [list].compactMap { $0 } + ShieldList.allCases.filter(chosen.contains).compactMap { bigger[$0] }
    }

    private func set(_ controller: WKUserContentController, on: Bool, again: Bool = false) {
        pages.setObject(NSNumber(value: on), forKey: controller)
        let lists = on ? inForce : []
        let held = lists.map(\.identifier).joined(separator: " ") as NSString
        if !again, holding.object(forKey: controller)?.isEqual(to: held as String) == true { return }
        for known in [list].compactMap({ $0 }) + bigger.values { controller.remove(known) }
        lists.forEach(controller.add)
        holding.setObject(held, forKey: controller)
    }

    /// Every page given the lists as they now are: after one is ready, or
    /// one is switched on or off.
    private func refresh() {
        for controller in pages.keyEnumerator().allObjects as? [WKUserContentController] ?? [] {
            set(controller, on: pages.object(forKey: controller)?.boolValue ?? false)
        }
    }

    /// The bigger lists switched on in Settings: compiled the first time
    /// they are wanted (a few seconds; WebKit keeps the result), and from
    /// then on in every page with blocking on, from its next request.
    func choose(_ lists: Set<ShieldList>) {
        chosen = lists.intersection(ShieldList.inBuild)
        for wanted in chosen where bigger[wanted] == nil { compile(wanted) }
        refresh()
    }

    private func compile(_ which: ShieldList) {
        guard let store, which.file != nil, !compiling.contains(which) else { return }
        compiling.insert(which)
        biggerTrouble[which] = nil
        // Shield lives as long as Search: held throughout, not weakly.
        Task.detached(priority: .utility) {
            guard let (json, hash) = which.rules() else {
                await MainActor.run { self.failed(which, "This build's list couldn't be read") }
                return
            }
            let identifier = which.identifierPrefix + hash
            await MainActor.run {
                store.lookUpContentRuleList(forIdentifier: identifier) { found, _ in
                    MainActor.assumeIsolated {
                        if let found {
                            self.ready(which, found, store: store)
                            return
                        }
                        store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) { compiled, error in
                            MainActor.assumeIsolated {
                                guard let compiled else {
                                    self.failed(which, error?.localizedDescription ?? "Compiling the list failed")
                                    return
                                }
                                self.ready(which, compiled, store: store)
                            }
                        }
                    }
                }
            }
        }
    }

    private func failed(_ which: ShieldList, _ why: String) {
        compiling.remove(which)
        biggerTrouble[which] = why
    }

    private func ready(_ which: ShieldList, _ compiled: WKContentRuleList, store: WKContentRuleListStore) {
        compiling.remove(which)
        bigger[which] = compiled
        refresh()
        // The list from an earlier build goes; only ours, and only that one.
        let current = compiled.identifier
        store.getAvailableContentRuleListIdentifiers { identifiers in
            for old in identifiers ?? [] where old != current && old.hasPrefix(which.identifierPrefix) {
                store.removeContentRuleList(forIdentifier: old) { _ in }
            }
        }
    }

    /// Third parties whose only job is to watch or to sell. First-party
    /// requests are untouched: a site's own scripts are the site.
    private static let unwanted = [
        "doubleclick.net", "googlesyndication.com", "googleadservices.com",
        "googletagservices.com", "google-analytics.com", "googletagmanager.com",
        "adservice.google.com", "amazon-adsystem.com", "adnxs.com", "adsrvr.org",
        "criteo.com", "criteo.net", "taboola.com", "outbrain.com",
        "rubiconproject.com", "pubmatic.com", "openx.net", "casalemedia.com",
        "smartadserver.com", "sharethrough.com", "indexww.com", "bidswitch.net",
        "33across.com", "teads.tv", "moatads.com", "adroll.com",
        "scorecardresearch.com", "quantserve.com", "chartbeat.com",
        "hotjar.com", "mouseflow.com", "fullstory.com", "clarity.ms",
        "mixpanel.com", "amplitude.com", "segment.com", "segment.io",
        "branch.io", "appsflyer.com", "adjust.com", "analytics.tiktok.com",
        "connect.facebook.net", "ads-twitter.com", "analytics.twitter.com",
    ]

    /// The few slots that are reliably an advertisement and nothing else. Kept
    /// deliberately short — a generous cosmetic list is how a blocker starts
    /// eating the page it was meant to clean.
    ///
    /// The second half are the boxes a site keeps open for the ad while it
    /// loads: with the ad blocked they stay, empty, a banner's height of
    /// nothing (#159). Each is a whole class name from EasyList's generic
    /// hiding list, matched as a whole word: an element whose class is
    /// `ad-slot` goes, one whose class merely contains "ad" stays.
    private static let slots = [
        ".adsbygoogle", "ins.adsbygoogle", "[id^=\"google_ads_\"]",
        "[id^=\"div-gpt-ad\"]", "[id^=\"taboola-\"]", "#taboola-below-article",
        "iframe[src*=\"doubleclick.net\"]", "iframe[src*=\"googlesyndication\"]",
        "iframe[src*=\"amazon-adsystem\"]",
        ".ad-slot", ".ad-slot-container", ".top-banner-ad-container",
        ".ad-leaderboard", ".ad-billboard", ".ad-giga", ".ad-mpu", ".ad-mrec",
        ".ad-unit", ".adunit", ".adslot", ".dfp-ad", ".gpt-ad", ".w_ad",
    ]

    /// Slots with names too plain, or too much a site's own, to hide
    /// everywhere — AS and El País call theirs just `.ad` — hidden only on
    /// the sites EasyList's own site rules hide them on.
    private static let slotsBySite: [(sites: [String], selector: String)] = [
        (["*as.com", "*elpais.com"], ".ad"),
        (["*theguardian.com"], ".top-fronts-banner-ad-container"),
        (["*independent.co.uk", "*the-independent.com"], "#billboard-wrapper"),
        (["*cnn.com"], ".ad-slot-header__wrapper"),
    ]

    static func networkFilter(for domain: String) -> String {
        let escaped = domain.replacingOccurrences(of: ".", with: "\\.")
        // WebKit's canonical HTTP URLs end the host with a port or a slash.
        return "^https?://([^/]+\\.)?\(escaped)[:/]"
    }

    func compile() {
        guard list == nil, !preparing else { return }
        trouble = nil
        var rules: [[String: Any]] = Shield.unwanted.map { domain in
            return [
                "trigger": [
                    "url-filter": Shield.networkFilter(for: domain),
                    "load-type": ["third-party"],
                ],
                "action": ["type": "block"],
            ]
        }
        rules.append([
            "trigger": ["url-filter": ".*"],
            "action": ["type": "css-display-none", "selector": Shield.slots.joined(separator: ", ")],
        ])
        // YouTube's ad reports and ad paths (see YouTubeAds.swift).
        rules += YouTubeAds.rules
        rules += Shield.slotsBySite.map { entry in
            [
                "trigger": ["url-filter": ".*", "if-domain": entry.sites],
                "action": ["type": "css-display-none", "selector": entry.selector],
            ]
        }

        guard let data = try? JSONSerialization.data(withJSONObject: rules, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8)
        else {
            trouble = "Couldn't build the block list"
            return
        }

        guard let store else {
            trouble = "WebKit has nowhere to compile it"
            return
        }
        // Dictionary order isn't stable between launches; the sorted JSON is
        // both the rules WebKit sees and the identity of their compiled form.
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let identifier = "office-shield-" + hash
        preparing = true
        store.lookUpContentRuleList(forIdentifier: identifier) { [weak self] found, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let found {
                    self.ready(found, store: store, identifier: identifier)
                } else {
                    store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) { [weak self] compiled, error in
                        MainActor.assumeIsolated {
                            guard let self else { return }
                            guard let compiled else {
                                self.preparing = false
                                self.trouble = error?.localizedDescription ?? "Compiling the block list failed"
                                return
                            }
                            self.ready(compiled, store: store, identifier: identifier)
                        }
                    }
                }
            }
        }
    }

    private func ready(_ compiled: WKContentRuleList, store: WKContentRuleListStore, identifier: String) {
        preparing = false
        list = compiled
        // Tabs that opened while this was still preparing get it now.
        refresh()
        // Leave other users of WebKit's store alone, including extensions.
        store.getAvailableContentRuleListIdentifiers { identifiers in
            for old in identifiers ?? [] where old != identifier && (old == "office-shield" || old.hasPrefix("office-shield-")) {
                store.removeContentRuleList(forIdentifier: old) { _ in }
            }
        }
    }

    /// Every tab asks for it; whoever asks before it is ready is remembered.
    func protect(_ controller: WKUserContentController) {
        set(controller, on: enabled, again: true)
    }

    /// Switched on or off for every page that is already open.
    func apply(to controllers: [WKUserContentController]) {
        for controller in controllers { set(controller, on: enabled, again: true) }
    }
}
