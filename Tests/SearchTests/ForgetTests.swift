import XCTest
@testable import Search

/// Forget sites between launches (Forget.swift): which of WebKit's records
/// the list of sites to keep keeps, and what a site card keeps a tab's
/// site as.
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
}
