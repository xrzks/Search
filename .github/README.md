# Search, forked

A fork of [driceroland/Search](https://github.com/driceroland/Search), the small
WebKit browser for the Mac by [Office Commun](https://officecommun.com), made
into the browser I want to use. Much of that is privacy: it goes through what
Search sends off the Mac, and what it keeps, and removes, narrows or puts behind
a setting anything that doesn't need to be there.

![Search, with its tabs down the left and a page taking the rest of the window](screenshot.png)

Everything that differs from upstream, and why, is in [FORK.md](../FORK.md).
Upstream's own [README](../README.md) is left as upstream has it, so merges stay
clean; most of it still holds, but not these:

- **It doesn't update itself.** The updater is gone. `./install.sh` builds a
  release of the checked-out commit and puts it in `/Applications`; the block
  lists are as new as that build.
- **It isn't signed by Office Commun.** `build.sh` signs with a Developer ID
  found in the keychain, or ad-hoc.
- **Its own identity.** The bundle identifier is `io.github.xrzks.search` and
  its data is in `~/Library/Application Support/Search Fork/`, so it installs
  beside upstream's. The first launch brings upstream's settings and site data
  over once.
- **The download link and the Homebrew cask are upstream's app**, not this fork.
  Build it instead:

```sh
git clone https://github.com/xrzks/Search.git
cd Search
./install.sh
```

Beyond that, by default: plain http goes over https, campaign tags come off
links, EasyPrivacy blocks along with Search's own list, and DuckDuckGo is the
search engine. [FORK.md](../FORK.md) has the rest.
