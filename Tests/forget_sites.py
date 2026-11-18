#!/usr/bin/env python3
"""Forget sites between launches (Forget.swift), checked in a hidden probe.

Build first (`./build.sh`), then `python3 Tests/forget_sites.py`. The app
starts hidden in a world of its own (see split_view.use) with Forget sites
when Search opens on, which a test run otherwise has off. Pages come from
127.0.0.1 and from localhost on the same port, two sites; each is given a
cookie and a local storage item from a script, never by loading a page, so a
tab brought back at launch sets nothing again. Checked:

- with localhost on the list of sites to keep, a launch forgets 127.0.0.1's
  cookie and storage and leaves localhost's;
- Clear's Cookies and sign-ins leaves localhost's too;
- with the switch off, a launch forgets nothing.

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

        give(sv.BASE)
        sv.quit(); time.sleep(1)
        subprocess.run(["defaults", "write", sv.SUITE, "forget.sites", "-bool", "false"], check=True)
        sv.launch()
        kept, value = has(sv.BASE)
        t.ok("with the switch off, a launch forgets nothing", kept, value)
    finally:
        t.done()
        sv.finish()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
