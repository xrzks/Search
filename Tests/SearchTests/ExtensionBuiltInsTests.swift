import Foundation
import XCTest
@testable import Search

/// Customized built-in elements, which WebKit lacks: an extension that uses
/// them gets the polyfill named in its pages, right after the shim; one
/// that doesn't is left without it.
@available(macOS 15.4, *)
final class ExtensionBuiltInsTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("built-ins-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("options/tabs"), withIntermediateDirectories: true)
        let manifest: [String: Any] = ["manifest_version": 3, "name": "Made Up", "version": "1.0",
                                       "options_ui": ["page": "options/options.html"]]
        try JSONSerialization.data(withJSONObject: manifest).write(to: folder.appendingPathComponent("manifest.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func write(_ text: String, _ path: String) throws {
        try text.write(to: folder.appendingPathComponent(path), atomically: true, encoding: .utf8)
    }

    private func read(_ path: String) throws -> String {
        try String(contentsOf: folder.appendingPathComponent(path), encoding: .utf8)
    }

    private var polyfill: URL { folder.appendingPathComponent(ExtensionBuiltIns.file) }

    func testPageWithBuiltInGetsPolyfillAfterShim() throws {
        try write(#"<html><head><title>x</title></head><body><input is="search-box"></body></html>"#, "options/options.html")
        try write(#"<p>plain</p>"#, "options/other.html")

        try ExtensionShims.prepare(folder, fresh: true)

        XCTAssertTrue(FileManager.default.fileExists(atPath: polyfill.path))
        let html = try read("options/options.html")
        XCTAssertTrue(html.contains("<head><script src=\"/\(ExtensionShims.file)\"></script>\(ExtensionBuiltIns.tag)<title>"), html)
        XCTAssertTrue(try read("options/other.html").contains(ExtensionBuiltIns.tag))
    }

    func testDefinitionInScriptIsEnough() throws {
        try write("<html><head></head><body><div id=menu></div></body></html>", "options/options.html")
        try write(#"class S extends HTMLButtonElement{}customElements.define("select-button",S,{extends:"button"});"#, "options/select.js")

        try ExtensionShims.prepare(folder, fresh: true)

        XCTAssertTrue(FileManager.default.fileExists(atPath: polyfill.path))
        XCTAssertTrue(try read("options/options.html").contains(ExtensionBuiltIns.tag))
    }

    func testPackageWithoutBuiltInsIsLeftWithout() throws {
        try write(#"<html><head></head><body><p class="is-x" data-is="a-b">x</p><my-thing></my-thing></body></html>"#, "options/options.html")
        try write("class T extends HTMLElement{}customElements.define('my-thing',T);", "options/thing.js")

        try ExtensionShims.prepare(folder, fresh: true)

        XCTAssertFalse(FileManager.default.fileExists(atPath: polyfill.path))
        XCTAssertFalse(try read("options/options.html").contains(ExtensionBuiltIns.file))
    }

    func testPreparedAgainNamesItOnce() throws {
        try write(#"<html><head></head><body><button is="select-button"></button></body></html>"#, "options/options.html")

        try ExtensionShims.prepare(folder, fresh: true)
        try ExtensionShims.prepare(folder, fresh: true)

        let html = try read("options/options.html")
        XCTAssertEqual(html.components(separatedBy: ExtensionBuiltIns.file).count, 2, html)
    }

    func testScriptRunsOnlyOnceInAPage() {
        XCTAssertTrue(ExtensionBuiltIns.script.hasPrefix("if (typeof document !== \"undefined\" && !self.__searchBuiltIns) {"))
        XCTAssertTrue(ExtensionBuiltIns.script.contains("@webreflection ISC"))
    }
}
