# This fork

This is a fork of [driceroland/Search](https://github.com/driceroland/Search),
kept at [xrzks/Search](https://github.com/xrzks/Search). The goal is to make it
the browser I want to use. Much of that is privacy: Search already sends very
little off the Mac, and this fork goes through what it does send, and what it
keeps, and removes, narrows or puts behind a setting anything that doesn't need
to be there.

Everything that differs from upstream is listed below, so the fork can be
rebased onto upstream without losing track of what is ours. This file is the
only place the fork is described — `README.md`, `CHANGELOG.md` and the other
upstream documents are left as upstream has them, so merges stay clean.

## Roadmap

What the fork plans to build, roughly in order. When something lands, its entry
moves to [Changes](#changes-from-upstream) with the files it touches.

**Forget a site when you're done with it.** Settings › Privacy › Clear only
clears every site at once, and nothing is cleared at quit. The plan: a list
of sites whose cookies and storage are kept (the ones you sign in to), and
at quit every other site's data goes, through `WKWebsiteDataStore`'s records
for each profile's and space's store, as Clear's Cookies and sign-ins does
today for all of them. Private tabs already keep nothing. To decide: whether
the kept list is typed in Settings or taken from the site card ("Keep this
site's sign-ins"), whether a site you are signed in to in an open tab is
spared at quit, and whether "at quit" should also be "when its last tab
closes", as Firefox's Cookie AutoDelete does.

## Changes from upstream

Newest first. Each entry: what changed, why, and the files it touches.

**Bigger block lists** (2026-11-18). Shield's own list names twelve
trackers; EasyPrivacy and EasyList now go with it, as lists of their own,
switched in Settings › Privacy › Blocking: Block more trackers (EasyPrivacy,
on by default) and Block more ads (EasyList, off by default, since it hides
boxes on pages too and now and then one a site needs). Both only while
Block ads and trackers is on, and both off for a site paused in its card.
`blocklists.py`, run by `build.sh` for every build, fetches the lists from
easylist.to at most once a day into `build/lists/` (the last copy is used
without a network; with none, that list is left out and Settings doesn't
offer it), converts them to WebKit's content rules, and puts them in the app
deflated (`Resources/Blocking/*.rules`, 1.2 MB for 14 MB of JSON). Search
never fetches them itself, so a list is as new as the build: `./install.sh`
is how it is updated. Only what WebKit's rules can say the way the list
means it is converted (network rules with `||`, `|`, `^`, `*`,
`$third-party`, `$domain=`, the resource types, `$match-case`, exceptions,
`$important`, `@@…$document`; element hiding with plain CSS), and the rest
is left out rather than stretched: about 83 of EasyPrivacy's rules and 4,200
of EasyList's (regular expressions, `$redirect`, `$csp`, `$removeparam`,
`$popup`, uBO's and AdGuard's extended syntax, `google.*` domains, `$domain=`
lists that both name and exclude, `$elemhide`/`$generichide` exceptions).
WebKit compiles each list the first time it is switched on, 1–3 seconds, in
which pages load without it, and keeps the result; a new build's list
replaces the old one's. `blocklists.py` (new), `build.sh`, `Shield.swift`
(`ShieldList`, `choose`; the lists each page's controller holds are tracked
as a set instead of one on/off), `Prefs.swift`, `Browser.swift`,
`Settings.swift`, `SettingsIndex.swift`, `Sync.swift`,
`Tests/block_lists.py` (new)

**Campaign tags off links** (2026-11-18). WebKit's click-ID removal takes
gclid, fbclid and the like off a page's address but leaves `utm_` tags, as
Safari does, and uses Apple's list, not Copy Clean Link's. Settings ›
Privacy › Blocking › Remove campaign tags from links (on by default) loads
the page at the address Copy Clean Link would copy instead: `utm_*` and the
rest of `CleanLink.tracking`, with an address that carries a signature left
as it is. Only the page itself and only a plain GET going somewhere new: not
a frame, a form, Back or Reload. A site that sends the clean address
straight back to the tagged one, before the page arrives, is let have it.
`Browser.swift` (`decide`, `didCommit`), `Tab.swift` (`untagged`),
`Prefs.swift`, `Settings.swift`, `SettingsIndex.swift`, `Sync.swift`,
`Tests/block_lists.py`

**The fork's own identity** (2026-11-18). The bundle identifier is
`io.github.xrzks.search` instead of upstream's `com.officecommun.search`,
and the folder in Application Support is "Search Fork" instead of "Search",
so the fork and upstream keep their settings, WebKit data and keychain items
apart and can be installed side by side. The first run under the new
identifier brings the old one's over before anything else starts (`Launch`,
now the app's entry point, in place of `@main` on `SearchApp`): the settings
are copied, keys the new domain already has standing; WebKit's data
(`~/Library/WebKit/…`, `~/Library/HTTPStorages/…` and its cookies file) and
the Application Support folder are moved, and whatever test runs of the new
build left in the new places goes to the Bin first. Once only, marked by
`identity.carried`. Caches stay behind. macOS's own choices are per
identifier and don't follow: Search has to be chosen as the default browser
again, and camera, microphone, location and Contacts are asked about again.
Keychain services are named after the new identifier (AI keys, the proxy
password, the bench's mark); none of these could be kept by an ad-hoc build
before either. Test worlds keep their `com.officecommun.search.test.*`
suites. `Search.passkeys.entitlements` still names upstream's team and
identifier; it is only used with upstream's provisioning profile, which the
fork doesn't have. `Identity.swift` (new), `App.swift`, `Store.swift`
(`folder`, `ownContainer`), `AI.swift`, `Proxy.swift`, `Bench.swift`,
`build.sh` (`BUNDLE_ID`), `fresh.sh`, `bench-mcp`, `Tests/bench_mcp.py`,
`Tests/split_view.py`

**No "On this Mac" AI** (2026-11-18). The AI add-on's own model ran in an
engine upstream's feed offered, signed by Office Commun's team and checked
against it; with the updater gone nothing offered it, and a fork build
couldn't have passed the check. The provider, the engine and its build are
taken out rather than left to vanish from Settings unexplained. The add-on
itself is still held back in this build, as upstream has it (`AI.shipped`);
when it comes back, Ollama and LM Studio still run a model on this Mac.
`Updater` no longer carries the team or its Developer ID requirement, which
only the engine read. Upstream's `README.md` and other documents may still
mention `engine.sh`; they are left as upstream has them. `AIEngine.swift`,
`engine.sh` and `Engine/` (removed), `AI.swift`, `AIAssist.swift`,
`Updater.swift`, `Bench.swift` and `bench` (the `ai engine` verb),
`build.sh` (the appcast's engine), `Proxy.swift` (comment)

**An install script** (2026-11-17). With the updater gone, `./install.sh`
is how the fork is updated: it builds a release and puts it in
`/Applications` (or the folder given) in place of the copy there, quitting
that copy first and opening it again after. `install.sh` (new)

**HTTPS only** (2026-11-17). A plain `http://` address goes over https
instead, before it loads: typed, followed from a link or redirected to, in
the page and in every frame. `Browser.decide` cancels the http navigation;
the page loads the https address in its place, and a frame is sent there by
`location.replace` from Search's own script world, where the page's scripts
can't step in. A page that doesn't load over https, a bad certificate
included, shows "… doesn't offer a secure connection" in place of the page,
with Go Back and Load over HTTP, which lets the site from then on; a private
tab's, only until Search quits. A site whose https sends it straight back to
http is asked about at once. A name with no site at all says so as before.
This Mac and the network around it are left on http: localhost, `.localhost`
and `.local` names, the loopback addresses and the private ranges
(`Address.local`, as typed addresses already had it), where a certificate is
the exception. On by default: Settings › Privacy › Blocking › Only secure
connections; the sites let over http are forgotten with Settings › Privacy ›
Site permissions › Sites let over http, and with Clear History, since they
name places you have been. `HTTPSOnly.swift` (new), `Browser.swift`
(`decide`, `fail`, `didCommit`, `clearHistory`), `Tab.swift`, `Stage.swift`,
`Little.swift`, `Dialogs.swift`, `Address.swift`, `Prefs.swift`,
`Settings.swift`, `SettingsIndex.swift`, `Tests/https_only.py` (new)

**Typed addresses follow Send links to a space** (2026-11-17). The rules in
Settings › Spaces & Pins now also apply to an address typed into the field.
After ⌘T, ⌘K or ⌘L, or with ⇧⌘Return, the page opens in a new tab in front in
the rule's space, and the tab you were on stays as it was. ⌘Return opens it
behind, without going there: into the row of a window that shows the space,
or else into this window's row for it, asleep until it is gone to; another
profile's space that no window shows can only be had by going there, so it
opens in front. Searches (the engine, a keyword, a site in the field), Search's
own pages, open tabs picked from the list, private tabs and a rule naming the
space on screen stay where they are. `SpaceRoutes.swift` (`typedSpace`,
`openTyped`), `Browser.swift` (`submit`), `Tests/space_links.py`

**Rosé Pine colours** (2026-11-17). Settings › Appearance › Colours: Search's
own greys, or [Rosé Pine](https://rosepinetheme.com)'s, Dawn while the window
is light and Moon while it is dark, so Light, Dark and Auto keep their
meaning. Only what Search draws: the strip, the column, the panels, its own
pages, reading mode (links in iris), the spaces' colours, the accent SwiftUI
tints with, the autofill flash and, with Chrome's colors on, the Web
Inspector. Pages keep their own colours (Dusk is untouched), and what macOS
draws, menus, alerts, open and save panels, keeps the Mac's light or dark.
Every `Palette` colour asks `Theme` first and falls back to its grey. The
ground is Rosé Pine's surface and the frame around the card its base, so the
card stands off what it sits on as with Search's greys; muted text is subtle,
muted being too faint on Dawn. A change of colours takes the app to the other
appearance and back in one turn, with the pages held where they are, since a
colour is only asked again when the appearance changes.
`Theme.swift` (new), `Design.swift`, `Prefs.swift`, `Settings.swift`,
`SettingsIndex.swift`, `Reader.swift`, `Inspector.swift`, `Browser.swift`,
`Spaces.swift`, `Peek.swift`, `MeCard.swift`, `Windows.swift`, `Bench.swift`
(`colours` in `ui` and `probe`)

**Fixes from the review** (2026-11-17). What the privacy review found.

- *Disabled extensions left out of update checks.* Every 20 hours Google was
  sent the id and version of every Web Store extension, disabled ones
  included. `checkForUpdates` now skips the disabled ones; an enabled one
  keeps updating on its own, and one turned back on is checked at the next
  round. `Extensions.swift`
- *No updater.* Upstream's feed at `officecommun.com` was read at launch and
  every hour, with no off switch, and a fork build would have been offered
  upstream's DMG in its place. The check, download and swap-in are gone, with
  the Check for Updates… menu item, the Updates rows in Settings › About and
  the bench's `update` command; the fork is updated by rebuilding.
  `Updater.swift` keeps only the version, build, team and Developer ID
  requirement other files read. Upstream's `README.md` and `SECURITY.md` still
  describe the updater, left as they are so merges stay clean.
  `Updater.swift`, `App.swift`, `Browser.swift`, `Prefs.swift`,
  `Settings.swift`, `SettingsIndex.swift`, `Bench.swift`, `Welcome.swift`,
  `Links.swift`, `AIEngine.swift` (comments), `bench-mcp`,
  `Tests/SearchTests/VaultAndUpdaterTests.swift`, `Tests/bench_mcp.py`,
  `Tests/settings_layout.py`
- *DuckDuckGo by default.* `Engine.standard` is DuckDuckGo, so it is both the
  default and where an invalid custom template falls back to. `Engine.swift`,
  `Settings.swift`
- *Non-interactive sign-in flows only where the extension has access.*
  `identity.launchWebAuthFlow` run out of sight now needs the extension's
  host permission for the URL (`ExtensionFetch.granted`) and passes
  `Extensions.mayOpen`; otherwise it fails with "User interaction required.",
  as Chrome's does, and the extension can retry interactively.
  `ExtensionShims.swift`
- *Credentialed fetch in Settings.* `extensions.credentialedFetch` is shown as
  Settings › Extensions › Sign-ins, "Extensions send your sign-ins", still on
  by default. `Prefs.swift`, `Settings.swift`, `SettingsIndex.swift`,
  `ExtensionFetch.swift` (comment)
- *Clear History clears more.* Also hidden elements (`hidden.json`), every
  site's permission answers (`capture.*` and the floating-video exceptions,
  the same set as Forget choices) and the host on each download's row; the
  downloads stay listed. `Browser.swift`, `Curtain.swift`,
  `CaptureChoices.swift`, `Loot.swift`
- *A smaller icon index.* `icons/pages.json` is capped at `History.cap`
  (2,000 instead of 4,000), and a page History prunes leaves it, unless a tab,
  pin or bookmark is on it, or it is the last page of such a site.
  `Icons.swift`, `History.swift`, `Pins.swift`,
  `Tests/HistoryRegression/Stubs.swift`,
  `Tests/SearchTests/FaviconMemoryTests.swift`
- *Ephemeral session.* `ProxyNetwork.session` is built on
  `URLSessionConfiguration.ephemeral`: the browser's own requests, the Web
  Store's among them, keep no cookies or cache on disk. `Proxy.swift`
- *The bench fails closed.* `Bench.Consent.given` counts only a keychain mark
  as consent, not `errSecMissingEntitlement`. A build without Search's
  provisioning profile can't leave the mark, so the bench is off at every
  launch outside test runs, which don't read it. `Bench.swift`
- *Documentation.* The proxy's help text in Settings says macOS's own services
  (translation model downloads, location, certificate checks, Safe
  Browsing's fraud warnings) don't go through it; it already named WebRTC
  over UDP, and localhost and `.local` names. Safe Browsing is WebKit's
  fraud warning (`isFraudulentWebsiteWarningEnabled`, left on), but its
  work is done by macOS's `com.apple.Safari.SafeBrowsing.Service`, shared
  with Safari, not by the network process `proxyConfigurations` applies to:
  it keeps its lists up to date on its own schedule and, on a match, asks
  for full hashes through Apple's relay with a hash prefix, not the
  address. Turning it off while a proxy is set would trade a real
  protection for that prefix, so it stays on and is named instead.
  `Translate.swift`'s header no longer says it is off unless switched on.
  `Proxy.swift`, `Translate.swift`
