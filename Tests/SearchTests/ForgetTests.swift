import WebKit
import XCTest
@testable import Search

/// Forget sites you've left (Forget.swift): which of WebKit's records the
/// list of sites to keep keeps, what a site card keeps a tab's site as, and
/// which sites the sweep while Search runs spares for a tab open on them.
@MainActor
final class ForgetTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "forget-\(getpid())", 1)
        super.setUp()
    }

    func testAnEntryKeepsItsSiteItsSubdomainsAndItsDomain() {
        // WebKit names a record by the registrable domain.
        XCTAssertTrue(Forget.keeps("notion.so", in: ["notion.so"]))
        XCTAssertTrue(Forget.keeps("notion.so", in: ["mail.notion.so"]), "typing a subdomain keeps its site's data")
        XCTAssertTrue(Forget.keeps("mail.notion.so", in: ["notion.so"]))
        XCTAssertTrue(Forget.keeps("Notion.so", in: ["notion.so"]))
        XCTAssertFalse(Forget.keeps("notion.so", in: []))
        XCTAssertFalse(Forget.keeps("notion.so", in: ["figma.com"]))
        XCTAssertFalse(Forget.keeps("notnotion.so", in: ["notion.so"]), "a suffix that isn't a subdomain")
        XCTAssertFalse(Forget.keeps("so", in: ["notion.so"]))
    }

    func testAddressesAndLocalhostAreTakenAsTheyAre() {
        XCTAssertTrue(Forget.keeps("127.0.0.1", in: ["127.0.0.1"]))
        XCTAssertFalse(Forget.keeps("10.0.0.1", in: ["0.0.1"]))
        XCTAssertTrue(Forget.keeps("localhost", in: ["localhost"]))
        XCTAssertFalse(Forget.keeps("127.0.0.1", in: ["localhost"]))
    }

    func testARecordThatIsNoSiteIsForgotten() {
        XCTAssertFalse(Forget.keeps("Local documents on your computer", in: ["notion.so"]))
        XCTAssertFalse(Forget.keeps("", in: ["notion.so"]))
    }

    func testACardKeepsTheRegistrableDomain() {
        XCTAssertEqual(Forget.site(of: URL(string: "https://mail.notion.so/inbox")!), "notion.so")
        XCTAssertEqual(Forget.site(of: URL(string: "https://www.bbc.co.uk/news")!), "bbc.co.uk")
        XCTAssertEqual(Forget.site(of: URL(string: "http://127.0.0.1:8080/")!), "127.0.0.1")
        XCTAssertEqual(Forget.site(of: URL(string: "http://localhost:3000/")!), "localhost")
        XCTAssertNil(Forget.site(of: URL(string: "file:///tmp/a.html")!))
    }

    // MARK: - while Search runs

    private func tab(_ address: String, shy: Bool = false) -> Tab {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = shy ? .nonPersistent() : .default()
        let tab = Tab(shy: shy, configuration: configuration)
        tab.restore(url: URL(string: address)!, title: address)
        return tab
    }

    func testATabAsleepIsOpenOnItsSite() {
        let asleep = tab("https://mail.notion.so/inbox")
        XCTAssertTrue(asleep.asleep)
        XCTAssertEqual(Forget.openSites([asleep]), ["notion.so"])
    }

    func testAPinIsOpenOnItsOwnPageToo() {
        let pin = tab("https://www.bbc.co.uk/news")
        pin.pin = "B"
        pin.home = URL(string: "https://figma.com/files")
        XCTAssertEqual(Forget.openSites([pin]), ["bbc.co.uk", "figma.com"])
        pin.pin = nil
        XCTAssertEqual(Forget.openSites([pin]), ["bbc.co.uk"], "a home is a pin's alone")
    }

    func testAPrivateTabAndAPageThatIsNoSiteSpareNothing() {
        XCTAssertEqual(Forget.openSites([tab("https://notion.so/", shy: true)]), [])
        XCTAssertEqual(Forget.openSites([tab("file:///tmp/a.html"), tab("about:blank")]), [])
        XCTAssertEqual(Forget.openSites([tab("http://127.0.0.1:8080/"), tab("http://localhost:3000/")]), ["127.0.0.1", "localhost"])
    }

    func testASiteOpenIsSparedAsAKeptOneIs() {
        let open = Array(Forget.openSites([tab("https://mail.notion.so/"), tab("http://10.0.0.1/")]))
        XCTAssertTrue(Forget.keeps("notion.so", in: open))
        XCTAssertTrue(Forget.keeps("10.0.0.1", in: open))
        XCTAssertFalse(Forget.keeps("0.0.1", in: open))
        XCTAssertFalse(Forget.keeps("figma.com", in: open))
    }

    /// The sweep itself, on a store of its own: the site kept and the site
    /// open stay, the rest goes, and only the kept one is said to be kept.
    /// A store kept on disk, as a space's is: WebKit leaves a non-persistent
    /// store's cookies where they are when asked to remove a record's.
    /// Removed from the disk once the test is done with it.
    func testTheSweepSparesTheSitesOpenAndTheSitesKept() async throws {
        let id = UUID()
        try await sweepsOnce(WKWebsiteDataStore(forIdentifier: id))
        try await WKWebsiteDataStore.remove(forIdentifier: id)
    }

    private func sweepsOnce(_ store: WKWebsiteDataStore) async throws {
        for domain in [".notion.so", ".figma.com", ".example.com"] {
            let cookie = try XCTUnwrap(HTTPCookie(properties: [.domain: domain, .path: "/", .name: "k", .value: "1",
                                                               .expires: Date().addingTimeInterval(3600)]))
            await store.httpCookieStore.setCookie(cookie)
        }
        let types: Set<String> = [WKWebsiteDataTypeCookies]
        let before = await store.dataRecords(ofTypes: types).map(\.displayName)
        XCTAssertEqual(Set(before), ["notion.so", "figma.com", "example.com"])

        var asked = 0
        let held = await Forget.sweep([store], types: types, keeping: ["figma.com"],
                                      sparing: { asked += 1; return ["notion.so"] })
        XCTAssertEqual(held, ["figma.com"], "a site spared for its tab isn't one you keep")
        XCTAssertEqual(asked, 1, "asked once the store's records are in")
        let after = await store.dataRecords(ofTypes: types).map(\.displayName)
        XCTAssertEqual(Set(after), ["notion.so", "figma.com"])
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    }

    func testWithTheSwitchOffTheSweepWhileRunningSweepsNothing() async {
        let was = Shared.prefs.forgetsSites
        defer { Shared.prefs.forgetsSites = was }
        Shared.prefs.forgetsSites = false
        let swept = await Forget.Running.shared.now()
        XCTAssertFalse(swept)
    }
}
