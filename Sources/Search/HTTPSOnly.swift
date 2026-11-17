import SwiftUI
import WebKit

// HTTPS only: a plain http:// address goes over https instead, before it
// loads — typed, followed from a link or redirected to, in the page and in
// every frame of it (see Browser.decide). A page that doesn't load over
// https is asked about over its own tab: Load over HTTP lets the site, and
// remembers it; a private tab's, only until Search quits.
//
// This Mac and the network around it are left as they are: localhost,
// .local names, the loopback and private addresses (Address.local), where a
// certificate is the exception. On unless turned off in Settings › Privacy.

enum HTTPSOnly {
    static let key = "https.allowed"

    /// Let over http from private tabs, until Search quits.
    @MainActor private static var shyAllowed: Set<String> = []

    /// The sites let over http, as Load over HTTP keeps them.
    static var allowed: Set<String> { Set(Store.settings.stringArray(forKey: key) ?? []) }

    /// The https address to go to in place of `url`; nil to load it as it is.
    @MainActor static func upgrade(_ url: URL, shy: Bool) -> URL? {
        guard Shared.prefs.httpsOnly, url.scheme?.lowercased() == "http",
              let host = url.host()?.lowercased(), !host.isEmpty,
              !Address.local(host), !Dialogs.isLoopback(host),
              !shyAllowed.contains(host), !allowed.contains(host),
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        parts.scheme = "https"
        if parts.port == 80 { parts.port = nil }
        return parts.url
    }

    /// Load over HTTP: the site's pages load as they are from now on.
    @MainActor static func allow(_ host: String, shy: Bool) {
        let host = host.lowercased()
        if shy {
            shyAllowed.insert(host)
        } else {
            Store.settings.set(allowed.union([host]).sorted(), forKey: key)
        }
    }

    /// Settings › Privacy, and Clear History: the sites name places you
    /// have been. Each is asked about again next time.
    @MainActor static func forgetAll() {
        Store.settings.removeObject(forKey: key)
        shyAllowed.removeAll()
    }
}

/// In place of the page, when its address was upgraded to https and didn't
/// load over it: what is wrong, and the way to have it anyway.
struct PlainAsk: View {
    let message: String
    @ObservedObject var tab: Tab
    let plain: URL

    var body: some View {
        VStack(spacing: 10) {
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Palette.ink)
            Text("Over plain http, what you see and send can be read and changed on the way.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.muted)
            HStack(spacing: 16) {
                if tab.canGoBack {
                    Button("Go Back") { tab.back() }
                }
                Button("Load over HTTP") {
                    guard let host = plain.host() else { return }
                    HTTPSOnly.allow(host, shy: tab.shy)
                    tab.go(to: plain)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(Palette.muted)
        }
        .padding(.horizontal, 24)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.ground)
    }
}
