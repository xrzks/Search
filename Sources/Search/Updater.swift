import Foundation

// What this build is.
//
// There is no updater in this fork. Office Commun's feed is never read,
// nothing is fetched in the background, and no bundle is ever swapped in:
// a newer Search is a rebuild. What is left is what other parts still ask
// for — the version and build (Links, WhatsNew, Settings).

enum Updater {
    /// What this app is: the version people read, and the build number.
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    static var build: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0
    }
}
