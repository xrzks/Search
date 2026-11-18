#!/usr/bin/env python3
"""The bigger block lists: EasyPrivacy and EasyList, as WebKit's rules.

    python3 -I blocklists.py OUT     fetch (at most once a day) and convert
                                     both, into OUT/easyprivacy.rules and
                                     OUT/easylist.rules: WebKit's JSON,
                                     deflated (14 MB is 1.5)

build.sh runs it for every build, into the app's Resources/Blocking, and
Shield compiles what it finds there (Settings › Privacy › Blocking). The
lists are fetched here, when Search is built, never by Search itself: a
running Search sends nothing to easylist.to, and the lists are as fresh as
the build. The text is kept in build/lists/, so a build without a network
uses the last one fetched; with none fetched yet, that list is left out and
Settings doesn't offer it.

Only what WebKit's content rules can say the way the list means it is
converted, and the rest is left out, so a rule is never stretched into one
that blocks more than it was written to:

  - network rules: ||, |, ^ and * patterns, $third-party, $domain=, the
    resource types WebKit has had since its first content blockers, and
    $match-case; exceptions (@@) and $important, by their order in the
    list, and @@…$document as the whole site let through;
  - element hiding (##, #@#) with plain CSS selectors, everywhere or on the
    sites named.

Left out: regular-expression rules, $redirect, $csp, $removeparam and the
other options that rewrite rather than block, $popup, uBlock's and
AdGuard's extended syntax (#?#, #$#, :has-text() and the like), $domain=
lists that both name and exclude sites, and wildcard domains (google.*).
"""
import json
import re
import sys
import time
import urllib.request
import zlib
from pathlib import Path

LISTS = {
    "easyprivacy": "https://easylist.to/easylist/easyprivacy.txt",
    "easylist": "https://easylist.to/easylist/easylist.txt",
}
CACHE = Path(__file__).resolve().parent / "build" / "lists"
FRESH = 24 * 3600
# WebKit refuses a list of more than this many rules.
MOST = 150_000

# The ABP types WebKit has words for, since its first content blockers.
# XHR, WebSocket, ping and "other" are all "raw" there.
TYPES = {
    "script": "script", "image": "image", "stylesheet": "style-sheet",
    "font": "font", "media": "media", "subdocument": "document",
    "xmlhttprequest": "raw", "websocket": "raw", "ping": "raw", "other": "raw",
}
# Options that only say which requests: understood here.
PLAIN = {"third-party", "3p", "first-party", "1p", "match-case", "important", "all"}
# Exceptions that are about element hiding only: WebKit can't lift hiding
# without lifting blocking too, so these are left out.
HIDING_ONLY = {"elemhide", "ehide", "generichide", "ghide", "specifichide", "shide"}

# Pseudo-classes WebKit's CSS knows: a selector with anything else (uBO's
# :has-text(), ABP's :-abp-contains()…) is left out, since WebKit drops a
# rule whose selector it can't read.
PSEUDO = {
    "not", "has", "is", "where", "first-child", "last-child", "only-child",
    "first-of-type", "last-of-type", "only-of-type", "nth-child",
    "nth-last-child", "nth-of-type", "nth-last-of-type", "empty", "root",
    "link", "visited", "checked", "disabled", "enabled",
}

SEPARATOR = "[^a-z0-9_.%-]"
HOST = re.compile(r"^[a-z0-9.-]+$")


def fetch(name, url):
    """The list's text: fetched when the kept copy is a day old, else kept."""
    CACHE.mkdir(parents=True, exist_ok=True)
    kept = CACHE / f"{name}.txt"
    if kept.exists() and time.time() - kept.stat().st_mtime < FRESH:
        return kept.read_text(encoding="utf-8")
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "Search build"}), timeout=30) as r:
            text = r.read().decode("utf-8")
        if not text.startswith("[Adblock Plus") or "! Title:" not in text[:2000]:
            raise ValueError("not an Adblock Plus list")
        kept.write_text(text, encoding="utf-8")
        return text
    except Exception as error:  # noqa: BLE001 — any failure falls back the same way
        if kept.exists():
            print(f"blocklists: {name} not fetched ({error}), using the copy from "
                  f"{time.strftime('%d %b %Y', time.localtime(kept.stat().st_mtime))}", file=sys.stderr)
            return kept.read_text(encoding="utf-8")
        print(f"blocklists: {name} not fetched ({error}), and none kept: left out", file=sys.stderr)
        return None


def domain(name):
    """WebKit's form of a site and everything under it, or None."""
    name = name.strip().lower()
    if not name or not HOST.match(name) or name.endswith(".") or "." not in name:
        return None
    return "*" + name


def sites(names, separator):
    """(if, unless) from a list of sites, or None when it can't be said."""
    yes, no = [], []
    for raw in names.split(separator):
        raw = raw.strip()
        if not raw:
            continue
        negative = raw.startswith("~")
        name = domain(raw[1:] if negative else raw)
        if name is None:
            # google.* and the like: WebKit can't name them. Leaving out one
            # site it should hide on is fine; one it shouldn't is not.
            if negative:
                return None
            continue
        (no if negative else yes).append(name)
    if yes and no:
        return None
    if not yes and not no and names.strip():
        return None
    return yes, no


def pattern(text):
    """An ABP address pattern as WebKit's url-filter, or None."""
    if not text.isascii() or any(c.isspace() for c in text):
        return None
    prefix, suffix = "", ""
    host_part = False
    if text.startswith("||"):
        text, prefix, host_part = text[2:], "^[^:]+://+([^:/]+\\.)?", True
    elif text.startswith("|"):
        text, prefix = text[1:], "^"
    if text.endswith("|"):
        text, suffix = text[:-1], "$"
    if "|" in text:
        return None
    text = text.strip("*") if not prefix and not suffix else text
    if not text:
        return ".*"
    out = []
    for i, c in enumerate(text):
        if c == "*":
            out.append(".*")
        elif c == "^":
            if host_part and i > 0 and HOST.match(text[:i].lower()):
                # Right after the host: WebKit's addresses go on with a port
                # or a path, always.
                out.append("[/:]")
            elif i == len(text) - 1 and not suffix:
                out.append(f"({SEPARATOR}.*)?$")
            else:
                out.append(SEPARATOR)
            host_part = False
        elif c in ".+?(){}[]\\$":
            out.append("\\" + c)
        else:
            if c == "/":
                host_part = False
            out.append(c)
    return prefix + "".join(out) + suffix


def network(line):
    """(rule, kind) for a network rule, kind being block, important, allow
    or site; or None when it is left out."""
    allow = line.startswith("@@")
    if allow:
        line = line[2:]
    body, options = line, ""
    if "$" in line and not (line.startswith("/") and line.rstrip("/").endswith("/")):
        body, options = line.rsplit("$", 1)
    if body.startswith("/") and body.endswith("/") and len(body) > 1:
        return None  # a regular expression
    trigger, kind = {}, "allow" if allow else "block"
    types, not_types, plugins = [], [], False
    for option in filter(None, (o.strip() for o in options.split(","))):
        negative = option.startswith("~")
        name, _, value = (option[1:] if negative else option).partition("=")
        name = name.lower()
        if name == "domain":
            said = sites(value, "|")
            if said is None:
                return None
            if said[0]:
                trigger["if-domain"] = said[0]
            if said[1]:
                trigger["unless-domain"] = said[1]
        elif name in ("third-party", "3p"):
            trigger["load-type"] = ["first-party" if negative else "third-party"]
        elif name in ("first-party", "1p"):
            trigger["load-type"] = ["third-party" if negative else "first-party"]
        elif name == "match-case":
            trigger["url-filter-is-case-sensitive"] = True
        elif name == "important":
            if not allow:
                kind = "important"
        elif name == "all":
            pass
        elif name in ("document", "doc") and allow and not negative:
            kind = "site"
        elif name in HIDING_ONLY:
            return None
        elif name in TYPES:
            (not_types if negative else types).append(TYPES[name])
        elif name == "object":
            # Plug-ins: WebKit has none. "All but plug-ins" is all it has.
            plugins = plugins or not negative
        else:
            return None  # redirect, csp, popup, removeparam, badfilter…
    if kind == "site":
        # The whole site let through: only for a pattern that is a site.
        host = re.fullmatch(r"\|\|([a-z0-9.-]+)\^?", body.lower())
        name = host and domain(host.group(1))
        if not name or "if-domain" in trigger or "unless-domain" in trigger:
            return None
        return {"trigger": {"url-filter": ".*", "if-domain": [name]},
                "action": {"type": "ignore-previous-rules"}}, kind
    if types and not_types:
        return None
    if not_types:
        types = sorted(set(TYPES.values()) - set(not_types))
    elif plugins and not types:
        return None  # only plug-ins
    if types:
        trigger["resource-type"] = sorted(set(types))
    url = pattern(body)
    if url is None:
        return None
    if url == ".*" and not trigger.get("if-domain") and not allow:
        return None  # everything, everywhere: never what a list means
    trigger = {"url-filter": url, **trigger}
    return {"trigger": trigger, "action": {"type": "ignore-previous-rules" if allow else "block"}}, kind


def plain_css(selector):
    """Whether WebKit will read this selector as the list means it."""
    if not selector.isascii() or "{" in selector or "}" in selector:
        return False
    if selector.startswith("+js(") or ":style(" in selector or ":remove(" in selector:
        return False
    stripped = re.sub(r'"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'', '""', selector)
    stripped = re.sub(r"\[[^\]]*\]", "[]", stripped)
    if "::" in stripped:
        return False
    return all(p.lower() in PSEUDO for p in re.findall(r":([A-Za-z-]+)", stripped))


def convert(text):
    """WebKit's rules for one list's text, and how many were left out."""
    blocks, allows, importants, sites_let = [], [], [], []
    hiding = {}        # selector -> (if, unless) lists of site-limited rules
    everywhere = []    # selectors hidden on every site, in order
    spared = {}        # selector -> sites it is not hidden on (#@#)
    gone = set()       # selectors #@# lifts everywhere
    left = 0
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("!") or line.startswith("["):
            continue
        cosmetic = re.match(r"^([^#$/|@*^]*?)(##|#@#)(.+)$", line)
        if cosmetic:
            names, marker, selector = cosmetic.groups()
            if not plain_css(selector):
                left += 1
                continue
            said = sites(names, ",") if names else ([], [])
            if said is None:
                left += 1
                continue
            yes, no = said
            if marker == "#@#":
                if not names:
                    gone.add(selector)
                elif yes:
                    spared.setdefault(selector, set()).update(yes)
                else:
                    left += 1
            elif not yes and not no:
                everywhere.append(selector)
            else:
                hiding.setdefault(selector, []).append((yes, no))
            continue
        if "#" in line and re.search(r"#[@?$%]*[?$%]#|\$\$|\$@\$", line):
            left += 1  # extended hiding, scriptlets, HTML filters
            continue
        made = network(line)
        if made is None:
            left += 1
            continue
        rule, kind = made
        {"block": blocks, "allow": allows, "important": importants, "site": sites_let}[kind].append(rule)

    hides = []
    for selector in dict.fromkeys(everywhere):
        if selector in gone:
            continue
        trigger = {"url-filter": ".*"}
        if selector in spared:
            trigger["unless-domain"] = sorted(spared[selector])
        hides.append({"trigger": trigger, "action": {"type": "css-display-none", "selector": selector}})
    for selector, where in hiding.items():
        if selector in gone:
            continue
        for yes, no in where:
            yes = [s for s in yes if s not in spared.get(selector, ())]
            if no:
                trigger = {"url-filter": ".*", "unless-domain": sorted(set(no) | spared.get(selector, set()))}
            elif yes:
                trigger = {"url-filter": ".*", "if-domain": yes}
            else:
                continue
            hides.append({"trigger": trigger, "action": {"type": "css-display-none", "selector": selector}})

    # Order is meaning: an exception lifts what came before it, $important
    # comes after the exceptions so they can't lift it, and a site let
    # through comes last, as @@…$document beats $important.
    rules = blocks + hides + allows + importants + sites_let
    return rules, left


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: python3 -I blocklists.py OUT")
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    for name, url in LISTS.items():
        target = out / f"{name}.rules"
        target.unlink(missing_ok=True)
        text = fetch(name, url)
        if text is None:
            continue
        rules, left = convert(text)
        if len(rules) > MOST:
            print(f"blocklists: {name} has {len(rules)} rules, more than WebKit takes ({MOST}): left out", file=sys.stderr)
            continue
        version = re.search(r"^! Version: *(\S+)", text, re.M)
        # Raw DEFLATE, which NSData's .zlib inflates (see ShieldList.rules).
        squeeze = zlib.compressobj(9, zlib.DEFLATED, -15)
        text = json.dumps(rules, separators=(",", ":"), sort_keys=True).encode("utf-8")
        target.write_bytes(squeeze.compress(text) + squeeze.flush())
        print(f"blocklists: {name} {version.group(1) if version else '?'}: {len(rules)} rules, {left} left out")


if __name__ == "__main__":
    main()
