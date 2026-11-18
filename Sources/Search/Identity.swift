import Foundation

// Who this build is: the fork's own bundle identifier, so it keeps its
// settings, its WebKit data and its keychain items apart from upstream's
// Search, and the two can be installed side by side.
//
// Until 18 Nov 2026 the fork was com.officecommun.search, as upstream is.
// The first run under the new identifier takes over what that one kept:
// the settings are copied (what the new one already has stands), and
// WebKit's data (cookies and sign-ins, site storage, extensions and their
// storage, compiled block lists) and the folder in Application Support are
// moved. Moved, not copied: the copy of Search that kept them is this one,
// rebuilt, and two of everything would be one too many. Caches are left
// behind, to be fetched again. What macOS keeps by identifier can't be
// carried: Search is the default browser again only once it is chosen
// again, and camera, microphone, location and Contacts are asked about
// again.
//
// Before anything else runs (see Launch): WebKit makes its folders for the
// identifier the first time anything touches it.

enum Identity {
    /// This build's bundle identifier; build.sh writes the same one.
    static let bundle = "io.github.xrzks.search"
    /// What the fork was until it had its own, and upstream still is.
    static let upstream = "com.officecommun.search"

    /// The folder in Application Support (see Store.folder).
    static let folderName = "Search Fork"

    /// What the upstream identifier kept, brought over once: the first time
    /// Search runs as itself under the new identifier, whatever is already
    /// there. Test runs of this build do use the new identifier's WebKit
    /// folder (for their own stores, and the compiled block lists), so that
    /// folder can be there before the browser ever ran; what is in the way
    /// goes to the Bin, and the old one takes its place. Never in a test
    /// run, and never by a copy built under another identifier (the tests'
    /// own copies).
    static func carryOver() {
        guard !Store.testing, Bundle.main.bundleIdentifier == bundle else { return }
        let fresh = UserDefaults.standard
        guard !fresh.bool(forKey: carried) else { return }
        let files = FileManager.default
        let library = files.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let support = files.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let moves = [
            (library.appendingPathComponent("WebKit/\(upstream)"), library.appendingPathComponent("WebKit/\(bundle)")),
            (library.appendingPathComponent("HTTPStorages/\(upstream)"), library.appendingPathComponent("HTTPStorages/\(bundle)")),
            (library.appendingPathComponent("HTTPStorages/\(upstream).binarycookies"),
             library.appendingPathComponent("HTTPStorages/\(bundle).binarycookies")),
            (support.appendingPathComponent("Search"), support.appendingPathComponent(folderName)),
        ]
        for (old, new) in moves where files.fileExists(atPath: old.path) {
            if files.fileExists(atPath: new.path) {
                guard (try? files.trashItem(at: new, resultingItemURL: nil)) != nil else { continue }
            }
            try? files.createDirectory(at: new.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? files.moveItem(at: old, to: new)
        }
        // The settings, copied: what this identifier already has stands.
        // Only the old identifier's own, not the Mac's global ones a
        // dictionaryRepresentation would bring along and pin here.
        for (key, value) in fresh.persistentDomain(forName: upstream) ?? [:] where fresh.object(forKey: key) == nil {
            fresh.set(value, forKey: key)
        }
        fresh.set(true, forKey: carried)
    }

    /// Set once carryOver has run for real.
    private static let carried = "identity.carried"
}

/// The app's entry point: what upstream left behind is brought over before
/// SwiftUI starts, then Search runs as it always has.
@main
enum Launch {
    static func main() {
        Identity.carryOver()
        SearchApp.main()
    }
}
