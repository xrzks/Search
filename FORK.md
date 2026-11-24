# This fork

This is a fork of [driceroland/Search](https://github.com/driceroland/Search),
kept at [xrzks/Search](https://github.com/xrzks/Search). The goal is to make it
the browser I want to use. Much of that is privacy: Search already sends very
little off the Mac, and this fork goes through what it does send, and what it
keeps, and removes, narrows or puts behind a setting anything that doesn't need
to be there.

Everything that differs from upstream is listed below, so the fork can be
rebased onto upstream without losing track of what is ours. This file is where
the fork is described, with a short front page for GitHub in
`.github/README.md`, a path upstream doesn't use — `README.md`, `CHANGELOG.md`
and the other upstream documents are left as upstream has them, so merges stay
clean.

## Roadmap

Nothing is planned right now; when something is, it is listed here, and moves
to [Changes](#changes-from-upstream) with the files it touches once it lands.

## Changes from upstream

Newest first. Each entry: what changed, why, and the files it touches.

**No iPhone beta prompts** (2026-11-23). Upstream 1.0.19 asks for an email for
its iPhone beta in Help › Search for iPhone…, under the About window's version,
and on a blank tab for three days; one press sends the address to upstream's
site, `searchbrowser.app`, from a build they didn't make. Switched
off with upstream's own switch (`IPhoneAsk.on`) rather than removed, so merges
stay simple; the Help menu is empty again. Settings › About's news and beta
field, which upstream had before, is left as it is. The unit tests skip while it
is off; `iphone_ask.py` checks it is offered nowhere and that the Search menu has
no Check for Updates…. `IPhoneAsk.swift` (`on`),
`Tests/SearchTests/IPhoneAskTests.swift`, `Tests/iphone_ask.py`

**Forget sites while Search runs** (2026-11-23). Sites were forgotten only
when Search opened, so a Search left open for weeks kept every site passed
through for weeks. Now the same sweep runs while Search is open as well:
about once an hour, and when the Mac wakes from sleep, every profile's store
and every space's own, as at launch, but for the sites you keep and the
sites a tab is open on. A tab is any window's, of any profile — a tucked one
of a merged window and the last window closed, kept with its tabs, among
them — in any space, asleep or not, pinned (its pinned page counts too),
either side of a split, the floating one, the peek and a small window's; not
a private tab's, whose store keeps nothing. A tab's site is its registrable
domain, matched to WebKit's records as an entry of the list is
(`SpaceRoutes.same`, an IP address only as it is); a site in a frame of an
open page is not spared for it. The tabs are read as each store's records
come in, not before, so one opened while the sweep waits on WebKit is spared
too. Unlike the launch's, it doesn't hold the main run loop: WebKit answers
while Search goes on. Never two at once, nor one within five minutes of the
last, as the timer late out of a sleep and the wake come together. Not when
a site's last tab closes, as the roadmap had it: that is a sweep for every
tab closed, and a site opened again a moment later would have lost its
sign-in for nothing; an hour's wait is the cost. The same switch, renamed
Forget sites you've left, under the same key (`forget.sites`), so the
setting and its sync carry over; off in a test run unless turned on. The
launch's sweep and this one share `Forget.forget`. The bench's `forget` verb
(test runs only) runs the sweep now and answers with the sites spared.
`Forget.swift` (`sweep`, `forget`, `openSites`, `everyTab`, `Running`),
`Links.swift` (`applicationDidFinishLaunching`), `Prefs.swift`,
`SettingsIndex.swift`, `SiteCard.swift` (`kept`), `Bench.swift`,
`Tests/SearchTests/ForgetTests.swift`, `Tests/forget_sites.py`

**Extension pages with customized built-ins** (2026-11-18). An extension
page may make a `<button>` or an `<input>` one of its own elements, written
`<button is="select-button">` and defined with `customElements.define(…, {
extends: "button" })`. Chrome has these; WebKit doesn't, and the element
stays a plain one with nothing in it. YT Tweaks' options page, the same Web
Store package as in Chrome, showed its theme menus as empty rows that did
nothing when clicked, and its search field as a bare white box. Now, when an
extension is prepared, a page with an element marked `is`, or a script that
defines one with `extends`, gives every page of that extension
@ungap/custom-elements 1.3.0 (ISC, its notice kept), written beside the shim
as `search-builtins.js` and named right after it, so it runs before the
page's own scripts. An extension that uses none doesn't carry it, as it puts
its own class in place of every `HTML…Element` a page sees. The preparation
is raised to 7, so installed extensions are prepared again at the next
launch. `ExtensionBuiltIns.swift` (new), `ExtensionShims.swift` (`prepare`,
`version`), `Tests/SearchTests/ExtensionBuiltInsTests.swift` (new),
`Tests/extension_builtins.py` (new)

**Site search after an @** (2026-11-18). Typing the start of a site's name
offered that site's search, and a word from Site shortcuts sent what followed
to its site, so "red" or "yt cats" never reached the engine as typed. Both now
take an @ in front: "@red" then Tab searches Reddit, "@yt cats" goes to
YouTube, and "red" or "yt cats" is a search. With the @ saying so, one letter
is enough ("@x"). Shortcuts are saved and listed without their own @, and one
saved with it still works. `SiteSearch.swift` (`match`), `Keyword.swift`
(`word`, `matches`, `problem`), `Settings.swift`, `SettingsIndex.swift`,
`Tests/SearchTests/SiteSearchTests.swift`, `Tests/SearchTests/EngineSuggestTests.swift`,
`Tests/site_search.py`, `Tests/site_search_suggestions.py`

**A site after an @ in the field from any app** (2026-11-24). "@red" then Tab
searched Reddit in a window's field, but the address field raised over another
app (Settings › From any app) offered no site and sent "@yt cats" to the
default engine: the launcher has a field and a list of its own, and only asked
the window for places and for Return, never for the site an @ names. It asks
now (`Browser.siteNamed`, which the window's own field works the same list
with): "@yt" puts "Search YouTube, Tab" first in the list, Tab puts YouTube in
the field as the chip ⌘L's Tab does, and the words after it go to YouTube's
search. ⌫ in the empty field takes the site out, Escape takes the site first
and the field on the next press, and a site still in the field goes with the
field when it is put away. `Launcher.swift` (`siteOffer`, `siteChip`,
`lockSiteOffer`, `dropSiteChip`, `escape`, `guess`, `submit`),
`Browser.swift` (`siteNamed`), `Omnibox.swift` (`SiteChip`, `SiteOfferRow`
shared with the launcher), `Bench.swift` (`launcher` `tab`, `siteOffer`,
`chip`), `Tests/SearchTests/LauncherTests.swift`, `Tests/launcher.py`

**Less Office Commun** (2026-11-18). The fork keeps the name Search, but two
things still pointed at Office Commun. The AI sign-in's callback, which Search
takes before it loads, was on `officecommun.com`; it is now
`https://xrzks.github.io/Search/ai/callback`, on the fork's own GitHub Pages
host, where nothing is served. OpenRouter takes the address with each sign-in,
not from a list kept with it, so nothing there had to change. Send Feedback
drafted a mail to Office Commun about a build they didn't make; it is switched
off rather than removed: gone from the Help menu, which is left empty, from
Settings › About, whose group is now Notes, and from Settings' search.
`Links.writeFeedback` is left in place, unused, so merges from upstream stay
simple. `AISignIn.swift` (`callback`), `App.swift` (`QuitAndHelp`),
`Settings.swift`, `SettingsIndex.swift`, `Links.swift`

**Forget sites between launches** (2026-11-18). Sites you only pass through
kept their cookies, storage and cache until you cleared them, and Clear's
Cookies and sign-ins clears every site at once, signing you out of
everything. Now, when Search opens, before SwiftUI starts and so before any
tab loads, everything `WKWebsiteDataStore` keeps for a site goes (cookies,
local storage, IndexedDB, service workers, caches) unless the site is on a
list of sites to keep: every profile's store and every space's own, not only
the ones with a window open. The main run loop is run until WebKit answers, at
most ten seconds. At launch rather than at quit, so quitting stays instant and
a crash or a force quit forgets just the same. Settings › Privacy › Clear ›
Forget sites you've left (then Forget sites when Search opens), on by
default (off in a test run unless turned on), and the list under it, typed
as for Send links to a space: "notion.so", "https://www.notion.so/x" or
"*.notion.so" are kept as "notion.so". A record, which WebKit names by registrable domain, is kept when
an entry and it are one site or one is a subdomain of the other
(`SpaceRoutes.same`); an IP address only as it is, since `same` alone took
10.0.0.1 for a subdomain of 0.0.1. A line under the list says that a site you
sign in to through Google or Microsoft needs that one kept too. Clear's
Cookies and sign-ins and Cache, in Settings and in History, leave the sites
kept and say so; Clear History leaves the list alone. The site card has Keep
This Site's Sign-Ins, after Block Ads and Trackers, on while the list keeps
the site: one click adds its registrable domain, another takes off every
entry that keeps it. Not in a private tab's card, nor with the switch off. The
switch and the list sync with Settings. The bench's `clear` verb (test runs
only) clears sites or the cache as the Settings buttons do. `Forget.swift`
(new), `Identity.swift` (`Launch`), `Browser.swift` (`clearSites`,
`clearCache`, `clear`), `Prefs.swift`, `Settings.swift`, `SettingsIndex.swift`,
`Recall.swift`, `SiteCard.swift` (`kept`), `Sync.swift`, `Bench.swift`,
`Tests/SearchTests/ForgetTests.swift` (new), `Tests/forget_sites.py` (new)

**A space's empty tab makes way** (2026-11-18). A space with nothing open shows
an empty tab beside its pins, and a page opened there, in front or behind,
opened beside it and left it standing. Now the page takes its place: from a
link, a page, Send links to a space or anything else that opens a tab, in the
row on screen or in a space's row out of sight. It stays while something is
typed in it, or while it is private, half of a pair or in the float.
`Browser.swift` (`loneBlanks`, `open`), `SpaceRoutes.swift` (`openTyped`),
`Tests/space_links.py`

**No new tab row in the sidebar** (2026-11-18). The "New tab" row under the
loose tabs, and the plus that stood in for it in the column of icons, is gone,
with `Quiet`, the view it was drawn with; the list ends at its last tab. ⌘T and
File › New Tab still open one. `Side.swift`

**The fork's own front page** (2026-11-18). GitHub shows `.github/README.md` in
place of the root `README.md` when there is one, and upstream has none, so the
fork's page on GitHub says what it is without touching upstream's README: a
fork, a link here, and where upstream's README no longer holds (no updater, not
signed by Office Commun, its own identifier and folder, the download link and
cask being upstream's). A clone still opens on upstream's README.
`.github/README.md` (new)

**Bigger block lists** (2026-11-18). Shield's own list names twelve trackers;
EasyPrivacy and EasyList now go with it, as lists of their own, switched in
Settings › Privacy › Blocking: Block more trackers (EasyPrivacy, on by default)
and Block more ads (EasyList, off by default, since it hides boxes on pages too
and now and then one a site needs). Both only while Block ads and trackers is
on, and both off for a site paused in its card. `blocklists.py`, run by
`build.sh` for every build, fetches the lists from easylist.to at most once a
day into `build/lists/` (the last copy is used without a network; with none,
that list is left out and Settings doesn't offer it), converts them to WebKit's
content rules, and puts them in the app deflated (`Resources/Blocking/*.rules`,
1.2 MB for 14 MB of JSON). Search never fetches them itself, so a list is as new
as the build: `./install.sh` is how it is updated. Only what WebKit's rules can
say the way the list means it is converted (network rules with `||`, `|`, `^`,
`*`, `$third-party`, `$domain=`, the resource types, `$match-case`, exceptions,
`$important`, `@@…$document`; element hiding with plain CSS), and the rest is
left out rather than stretched: about 83 of EasyPrivacy's rules and 4,200 of
EasyList's (regular expressions, `$redirect`, `$csp`, `$removeparam`, `$popup`,
uBO's and AdGuard's extended syntax, `google.*` domains, `$domain=` lists that
both name and exclude, `$elemhide`/`$generichide` exceptions). WebKit compiles
each list the first time it is switched on, 1–3 seconds, in which pages load
without it, and keeps the result; a new build's list replaces the old one's.
`blocklists.py` (new), `build.sh`, `Shield.swift` (`ShieldList`, `choose`; the
lists each page's controller holds are tracked as a set instead of one on/off),
`Prefs.swift`, `Browser.swift`, `Settings.swift`, `SettingsIndex.swift`,
`Sync.swift`, `Tests/block_lists.py` (new)

**Campaign tags off links** (2026-11-18). WebKit's click-ID removal takes gclid,
fbclid and the like off a page's address but leaves `utm_` tags, as Safari does,
and uses Apple's list, not Copy Clean Link's. Settings › Privacy › Blocking ›
Remove campaign tags from links (on by default) loads the page at the address
Copy Clean Link would copy instead: `utm_*` and the rest of
`CleanLink.tracking`, with an address that carries a signature left as it is.
Only the page itself and only a plain GET going somewhere new: not a frame, a
form, Back or Reload. A site that sends the clean address straight back to the
tagged one, before the page arrives, is let have it. `Browser.swift` (`decide`,
`didCommit`), `Tab.swift` (`untagged`), `Prefs.swift`, `Settings.swift`,
`SettingsIndex.swift`, `Sync.swift`, `Tests/block_lists.py`

**The fork's own identity** (2026-11-18). The bundle identifier is
`io.github.xrzks.search` instead of upstream's `com.officecommun.search`, and
the folder in Application Support is "Search Fork" instead of "Search", so the
fork and upstream keep their settings, WebKit data and keychain items apart and
can be installed side by side. The first run under the new identifier brings the
old one's over before anything else starts (`Launch`, now the app's entry point,
in place of `@main` on `SearchApp`): the settings are copied, keys the new
domain already has standing; WebKit's data (`~/Library/WebKit/…`,
`~/Library/HTTPStorages/…` and its cookies file) and the Application Support
folder are moved, and whatever test runs of the new build left in the new places
goes to the Bin first. Once only, marked by `identity.carried`. Caches stay
behind. macOS's own choices are per identifier and don't follow: Search has to
be chosen as the default browser again, and camera, microphone, location and
Contacts are asked about again. Keychain services are named after the new
identifier (AI keys, the proxy password, the bench's and the agents' marks, the
agents trusted with Always allow); none of these could be kept by an ad-hoc
build before either. Test worlds keep their `com.officecommun.search.test.*`
suites. `Search.passkeys.entitlements` still names upstream's team and
identifier; it is only used with upstream's provisioning profile, which the fork
doesn't have. `Identity.swift` (new), `App.swift`, `Store.swift` (`folder`,
`ownContainer`), `AI.swift`, `Proxy.swift`, `Bench.swift`, `Prefs.swift`
(`agentsMark`), `AgentTrust.swift` (`agents`), `build.sh` (`BUNDLE_ID`),
`fresh.sh`, `bench-mcp`, `Tests/bench_mcp.py`, `Tests/split_view.py`

**No "On this Mac" AI** (2026-11-18). The AI add-on's own model ran in an engine
upstream's feed offered, signed by Office Commun's team and checked against it;
with the updater gone nothing offered it, and a fork build couldn't have passed
the check. The provider, the engine and its build are taken out rather than left
to vanish from Settings unexplained. The add-on itself is still held back in
this build, as upstream has it (`AI.shipped`); when it comes back, Ollama and LM
Studio still run a model on this Mac. `AIDownload.Failure`, which upstream's
developer tools packages also use, moves to `DevToolsPackages.swift`. Upstream's
`README.md` and other documents may still mention `engine.sh`; they are left as
upstream has them. `AIEngine.swift`, `engine.sh` and `Engine/` (removed),
`AI.swift`, `AIAssist.swift`, `Updater.swift`, `DevToolsPackages.swift`,
`Bench.swift` and `bench` (the `ai engine` verb), `build.sh` (the appcast's
engine), `Proxy.swift` (comment)

**An install script** (2026-11-17, more on 2026-11-18). With the updater gone,
`./install.sh` is how the fork is updated: it builds a release and puts it in
`/Applications` (or the folder given) in place of the copy there, quitting that
copy first and opening it again after. It installs a commit: with changes in the
working tree other than Markdown, untracked files included, it stops unless
given `--dirty`. `--test` runs `swift test` first and installs nothing if it
fails. At the end it says the commit installed and how `build.sh` signed it (a
Developer ID found in the keychain, or ad-hoc). `install.sh` (new)

**Typed addresses follow Send links to a space** (2026-11-17). The rules in
Settings › Spaces & Pins now also apply to an address typed into the field.
After ⌘T, ⌘K or ⌘L, or with ⇧⌘Return, the page opens in a new tab in front in
the rule's space, and the tab you were on stays as it was. ⌘Return opens it
behind, without going there: into the row of a window that shows the space, or
else into this window's row for it, asleep until it is gone to; another
profile's space that no window shows can only be had by going there, so it opens
in front. Searches (the engine, a keyword, a site in the field), Search's own
pages, open tabs picked from the list, private tabs and a rule naming the space
on screen stay where they are. `SpaceRoutes.swift` (`typedSpace`, `openTyped`),
`Browser.swift` (`submit`), `Tests/space_links.py`

**Rosé Pine colours** (2026-11-17). Settings › Appearance › Colours: Search's
own greys, or [Rosé Pine](https://rosepinetheme.com)'s, Dawn while the window is
light and Moon while it is dark, so Light, Dark and Auto keep their meaning.
Only what Search draws: the strip, the column, the panels, its own pages,
reading mode (links in iris), the spaces' colours, the accent SwiftUI tints
with, the autofill flash and, with Chrome's colors on, the Web Inspector. Pages
keep their own colours (Dusk is untouched), and what macOS draws, menus, alerts,
open and save panels, keeps the Mac's light or dark. Every `Palette` colour asks
`Theme` first and falls back to its grey. The ground is Rosé Pine's surface and
the frame around the card its base, so the card stands off what it sits on as
with Search's greys; muted text is subtle, muted being too faint on Dawn. A
change of colours takes the app to the other appearance and back in one turn,
with the pages held where they are, since a colour is only asked again when the
appearance changes. `Theme.swift` (new), `Design.swift`, `Prefs.swift`,
`Settings.swift`, `SettingsIndex.swift`, `Reader.swift`, `Inspector.swift`,
`Browser.swift`, `Spaces.swift`, `Peek.swift`, `MeCard.swift`, `Windows.swift`,
`Bench.swift` (`colours` in `ui` and `probe`),
`Tests/SearchTests/FollowFileTests.swift`

**Disabled extensions left out of update checks** (2026-11-17). At each
store check, once a day (sooner after one that failed), Google was sent the id
and version of every Web Store extension, disabled ones included. `checkForUpdates` now skips the disabled ones; an
enabled one keeps updating on its own, and one turned back on is checked at the
next round. `Extensions.swift`

**No updater** (2026-11-17). Upstream's feed at `officecommun.com` was read at
launch and every hour, with no off switch, and a fork build would have been
offered upstream's DMG in its place. The check, download and swap-in are gone,
with the Check for Updates… menu item, the Updates rows in Settings › About and
the bench's `update` command; the fork is updated by rebuilding. Upstream's
"Update ready" (for 1.0.20, not yet released: a card at the column's foot, a
pill by the tabs, and its two switches in Settings › About) is gone with it;
only its button, `CardButton`, which the coding agent's card uses too, is left
in `UpdateNotice.swift`. `Updater.swift` keeps only what other files read: the
version and build, a relaunch (the developer tools packages' Restart), and the
team and its Developer ID requirement (those packages' check). The packages'
list comes only from the feed, so with no feed none is ever offered, and
Settings › About › Developer says none is. Upstream's `README.md` and
`SECURITY.md` still describe the updater, left as they are so merges stay clean.
`Updater.swift`, `UpdateNotice.swift`, `Side.swift`, `TabBar.swift`,
`DevToolsPackages.swift` (`Updater.relaunch`), `App.swift`, `Browser.swift`,
`Prefs.swift`, `Settings.swift`, `SettingsIndex.swift`, `Bench.swift`,
`Welcome.swift`, `Links.swift`, `AIEngine.swift` (comments), `bench-mcp`,
`Tests/SearchTests/VaultAndUpdaterTests.swift`,
`Tests/SearchTests/UpdateNoticeTests.swift` (removed),
`Tests/SearchTests/AgentCardTests.swift`, `Tests/bench_mcp.py`,
`Tests/settings_layout.py`

**DuckDuckGo by default** (2026-11-17). `Engine.standard` is DuckDuckGo, so it
is both the default and where an invalid custom template falls back to.
`Engine.swift`, `Settings.swift`

**Non-interactive sign-in flows only where the extension has access**
(2026-11-17). `identity.launchWebAuthFlow` run out of sight now needs the
extension's host permission for the URL (`ExtensionFetch.granted`) and passes
`Extensions.mayOpen`; otherwise it fails with "User interaction required.", as
Chrome's does, and the extension can retry interactively.
`ExtensionShims.swift`

**Credentialed fetch in Settings** (2026-11-17). `extensions.credentialedFetch`
is shown as Settings › Extensions › Sign-ins, "Extensions send your sign-ins",
still on by default. `Prefs.swift`, `Settings.swift`, `SettingsIndex.swift`,
`ExtensionFetch.swift` (comment)

**Clear History clears more** (2026-11-17). Also hidden elements
(`hidden.json`), every site's permission answers (`capture.*` and the
floating-video exceptions, the same set as Forget choices) and the host on each
download's row; the downloads stay listed. `Browser.swift`, `Curtain.swift`,
`CaptureChoices.swift`, `Loot.swift`

**Ephemeral session** (2026-11-17). `ProxyNetwork.session` is built on
`URLSessionConfiguration.ephemeral`: the browser's own requests, the Web
Store's among them, keep no cookies or cache on disk. `Proxy.swift`

**Switches fail closed** (2026-11-17). `SwitchMark.given` counts only a
keychain mark as consent, not `errSecMissingEntitlement`. A build without
Search's provisioning profile can't leave the mark, so the bench, and Let
coding agents use Search, are off at every launch outside test runs, which
don't read it. `PageHands.swift` (`SwitchMark`)
