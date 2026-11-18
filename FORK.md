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
