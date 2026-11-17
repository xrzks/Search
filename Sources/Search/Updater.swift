import Foundation
import Security

// What this build is, and whose signature counts.
//
// There is no updater in this fork. Office Commun's feed is never read,
// nothing is fetched in the background, and no bundle is ever swapped in:
// a newer Search is a rebuild. What is left is what other parts still ask
// for — the version and build (Links, WhatsNew, Settings) and the team's
// Developer ID requirement (AIEngine).

enum Updater {
    /// What this app is: the version people read, and the build number.
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    static var build: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0
    }

    /// The team that signs Office Commun's releases, and the AI engine.
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
