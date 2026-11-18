import XCTest
@testable import Search

@MainActor
final class SiteSearchTests: XCTestCase {
    func testKeywordSiteShortcutCanBeOfferedByItsKeyword() throws {
        let keyword = Keyword(keyword: "grk", template: "https://grok.com/?q=%s")

        let site = try XCTUnwrap(SiteSearch.match("@gr", learnedToo: false, keywords: [keyword]))

        XCTAssertEqual(site.name, "Grok")
        XCTAssertEqual(site.host, "grok.com")
        XCTAssertEqual(site.template, keyword.template)
        XCTAssertEqual(site.aliases, ["grk"])
    }

    func testPathSearchKeepsAnEncodedSlash() throws {
        let url = try XCTUnwrap(URL(string: "https://open.spotify.com/search/AC%2FDC"))
        XCTAssertEqual(SiteSearch.words(in: url, searchedOn: spotify), "AC/DC")
    }

    func testPathSearchDecodesAnEncodedSpace() throws {
        let url = try XCTUnwrap(URL(string: "https://open.spotify.com/search/daft%20punk"))
        XCTAssertEqual(SiteSearch.words(in: url, searchedOn: spotify), "daft punk")
    }

    func testPathSearchRejectsASubpage() throws {
        let url = try XCTUnwrap(URL(string: "https://open.spotify.com/search/a/b"))
        XCTAssertNil(SiteSearch.words(in: url, searchedOn: spotify))
    }

    private let spotify = SearchSite(name: "Spotify", host: "open.spotify.com",
                                     template: "https://open.spotify.com/search/%s")

    func testASiteIsOfferedOnlyAfterAnAt() {
        XCTAssertEqual(SiteSearch.match("@yt", learnedToo: false)?.name, "YouTube")
        XCTAssertEqual(SiteSearch.match("@red", learnedToo: false)?.name, "Reddit")
        XCTAssertNil(SiteSearch.match("yt", learnedToo: false))
        XCTAssertNil(SiteSearch.match("red", learnedToo: false))
        XCTAssertNil(SiteSearch.match("@", learnedToo: false))
    }

    func testAShortcutRunsOnlyAfterAnAt() throws {
        let keywords = [Keyword(keyword: "yt", template: "https://www.youtube.com/results?search_query=%s")]
        let (keyword, rest) = try XCTUnwrap(Keyword.match("@yt cats", in: keywords))
        XCTAssertEqual(keyword.word, "yt")
        XCTAssertEqual(rest, "cats")
        XCTAssertNil(Keyword.match("yt cats", in: keywords))
        // Saved with its @ by an older hand, it is the same shortcut.
        XCTAssertNotNil(Keyword.match("@yt cats", in: [Keyword(keyword: "@yt", template: keywords[0].template)]))
    }
}
