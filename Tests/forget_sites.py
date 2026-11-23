#!/usr/bin/env python3
"""Forget sites you've left (Forget.swift), checked in a hidden probe.

Build first (`./build.sh`), then `python3 Tests/forget_sites.py`. The app
starts hidden in a world of its own (see split_view.use) with Forget sites
you've left on, which a test run otherwise has off. Pages come from
127.0.0.1 and from localhost on the same port, two sites; each is given a
cookie and a local storage item from a script, never by loading a page, so a
tab brought back at launch sets nothing again. Checked:

- with localhost on the list of sites to keep, a launch forgets 127.0.0.1's
  cookie and storage and leaves localhost's;
- Clear's Cookies and sign-ins leaves localhost's too;
- the sweep while Search runs (the bench's `forget`, as the hourly timer and
  a wake run it) leaves 127.0.0.1's while a tab is open on it, asleep or
  not, forgets them once its last tab is closed, and leaves localhost's;
- with the switch off, a launch forgets nothing, nor does a sweep while
  Search runs.

Nothing here makes, shows or brings forward a window.
"""
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("forget-sites")

LOCAL = f"http://localhost:{sv.srv.server_port}"
SET = "document.cookie = 'k=1; max-age=86400; path=/'; localStorage.setItem('k', '1'); 'set'"
READ = "JSON.stringify([document.cookie.includes('k=1'), localStorage.getItem('k') === '1'])"


def opened(url, wait=1.2):
    r = sv.sp("open", url=url)["resultID"]; time.sleep(wait); return r


def give(base):
    """A cookie and a storage item for the site, from a script."""
    return sv.ev(opened(f"{base}/give"), SET)


def has(base):
    """Whether the site still has its cookie and its storage item, read from
    a page opened afresh."""
    value = sv.ev(opened(f"{base}/read"), READ)
    return value == "[true,true]", value


def nothing(base):
    return sv.ev(opened(f"{base}/read"), READ) == "[false,false]"


def tabs_on(base):
    return [x["id"] for x in sv.sp("state")["tabs"] if x["url"].startswith(base)]


def close_tabs_on(base):
    for id in tabs_on(base): sv.sp("close", id=id)


def forget():
    """The sweep while Search runs, now: whether it ran, and the sites it
    spared for a tab open on them."""
    a = sv.cmd({"do": "forget"}); time.sleep(0.5)
    return a["swept"], a["open"]


def main():
    t = sv.T()
    try:
        sv.setup(**{"forget.sites": True, "start.fresh": False})
        subprocess.run(["defaults", "write", sv.SUITE, "forget.keep", "-array", "localhost"], check=True)
        sv.launch()
        give(sv.BASE); give(LOCAL)
        t.ok("127.0.0.1 has its cookie and storage before quitting", has(sv.BASE)[0], has(sv.BASE)[1])
        t.ok("and so does localhost", has(LOCAL)[0], has(LOCAL)[1])
        sv.quit(); time.sleep(1)

        sv.launch()
        t.ok("a launch forgets the site not kept", nothing(sv.BASE))
        kept, value = has(LOCAL)
        t.ok("and leaves the site kept", kept, value)

        give(sv.BASE)
        t.ok("127.0.0.1 has them again", has(sv.BASE)[0])
        sv.cmd({"do": "clear", "what": "sites"}); time.sleep(0.5)
        t.ok("Clear's Cookies and sign-ins forgets the site not kept", nothing(sv.BASE))
        kept, value = has(LOCAL)
        t.ok("and leaves the site kept", kept, value)

        # While Search runs: a site with a tab open stays, asleep or not.
        close_tabs_on(sv.BASE)
        give(sv.BASE)
        ids = tabs_on(sv.BASE)
        for id in ids[1:]: sv.sp("close", id=id)
        has(LOCAL)  # a tab in front of it, so it can sleep
        slept = sv.sp("sleep", id=ids[0]).get("sleepResult")
        asleep = [x["asleep"] for x in sv.sp("state")["tabs"] if x["id"] == ids[0]]
        t.ok("127.0.0.1's last tab is asleep", asleep == [True], slept)
        swept, spared = forget()
        t.ok("the sweep while Search runs ran", swept)
        t.ok("and spared 127.0.0.1 for its tab", "127.0.0.1" in spared, spared)
        kept, value = has(sv.BASE)
        t.ok("so 127.0.0.1 has its cookie and storage still", kept, value)

        close_tabs_on(sv.BASE)
        swept, spared = forget()
        t.ok("with its last tab closed, 127.0.0.1 is no longer spared", swept and "127.0.0.1" not in spared, spared)
        t.ok("and the sweep forgets it", nothing(sv.BASE))
        kept, value = has(LOCAL)
        t.ok("and leaves the site kept", kept, value)

        give(sv.BASE)
        sv.quit(); time.sleep(1)
        subprocess.run(["defaults", "write", sv.SUITE, "forget.sites", "-bool", "false"], check=True)
        sv.launch()
        kept, value = has(sv.BASE)
        t.ok("with the switch off, a launch forgets nothing", kept, value)
        close_tabs_on(sv.BASE)
        swept, _ = forget()
        t.ok("nor does the sweep while Search runs", not swept)
        kept, value = has(sv.BASE)
        t.ok("so 127.0.0.1 has its cookie and storage still", kept, value)
    finally:
        t.done()
        sv.finish()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
