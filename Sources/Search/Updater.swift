import AppKit
import Security

// What this build is, and whose signature counts.
//
// There is no updater in this fork. Office Commun's feed is never read,
// nothing is fetched in the background, and no bundle is ever swapped in:
// a newer Search is a rebuild. What is left is what other parts still ask
// for — the version and build (Links, WhatsNew, Settings), the team's
// Developer ID requirement (DevToolsPackages) and a relaunch
// (DevToolsPackages' Restart).

enum Updater {
    /// What this app is: the version people read, and the build number.
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    static var build: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0
    }

    /// A test run pointed at a feed of its own (SEARCH_FEED). There is no
    /// feed here, so never.
    static var overridden: Bool { false }

    /// Quit, and open this bundle again once this process is gone.
    @MainActor static func relaunch() {
        var reopen = ["/usr/bin/open"]
        if let probe = ProcessInfo.processInfo.environment["SEARCH_PROBE"] {
            reopen += ["--env", "SEARCH_PROBE=\(probe)"]
        }
        let waiter = Process()
        waiter.executableURL = URL(fileURLWithPath: "/bin/sh")
        waiter.arguments = [
            "-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; shift; exec \"$@\"",
            "sh", String(ProcessInfo.processInfo.processIdentifier),
        ] + reopen + [Bundle.main.bundleURL.path]
        try? waiter.run()
        NSApp.terminate(nil)
    }

    /// The team that signs Office Commun's releases, and the developer
    /// tools packages.
    static let team = "7BYKA895MC"

    /// The requirement every Developer ID program from this team meets, the
    /// one `codesign -d -r-` prints for a shipped Search: Apple's anchor, the
    /// Developer ID intermediate (…6.2.6) and a Developer ID Application
    /// leaf (…6.1.13), with this team in it, for the identifier when given.
    static func developerID(team: String, identifier: String?) -> SecRequirement? {
        let text = "anchor apple generic" + (identifier.map { " and identifier \"\($0)\"" } ?? "")
            + " and certificate 1[field.1.2.840.113635.100.6.2.6]"
            + " and certificate leaf[field.1.2.840.113635.100.6.1.13]"
            + " and certificate leaf[subject.OU] = \"\(team)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess else { return nil }
        return requirement
    }
}
