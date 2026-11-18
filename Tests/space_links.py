#!/usr/bin/env python3
"""Send links to a space (SpaceRoutes.swift), checked in a hidden probe.

Build first (`./build.sh`), then `python3 Tests/space_links.py`. The app
starts hidden in a world of its own (see split_view.use) with spaces and
Send links to a space on, a second space "Two", and one rule: localhost to
Two. Pages are served from 127.0.0.1, which no rule names, and link to
localhost on the same port. Checked:

- a link from another app to localhost opens in Two, and Search switches to it;
- one to 127.0.0.1 opens where you are;
- a target=_blank click and a ⌘-click from a page in the first space open
  their localhost tab in Two, and not in the first space;
- a plain link followed in its own tab stays in its space;
- an address to localhost typed after ⌘L opens in Two, and the tab it was
  typed over stays as it was; after ⌘T, the same;
- one typed with ⌘Return opens in Two's row without going there;
- a search, on an engine served from localhost, stays where you are;
- the same links from a private tab stay in the first space;
- a page opened into a space with nothing open, in front or behind, takes
  the place of its empty tab (a third space, Three, for a.localhost).

Nothing here makes, shows or brings forward a window.
"""
import json
import subprocess
import sys
import time
from http.server import BaseHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlparse

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("space-links")

LINK = 'style="display:block;font-size:60px;line-height:120px;padding:0 20px"'
PORT = sv.srv.server_port
LOCAL = f"http://localhost:{PORT}"


class H(BaseHTTPRequestHandler):
    def do_GET(self):
        page = urlparse(self.path).path
        if page == "/blank":
            body = f'<a id="go" target="_blank" href="{LOCAL}/opened-blank" {LINK}>link</a>'
        elif page == "/cmd":
            body = f'<a id="go" href="{LOCAL}/opened-cmd" {LINK}>link</a>'
        elif page == "/same":
            body = f'<a id="go" href="{LOCAL}/opened-same" {LINK}>link</a>'
        elif page == "/shy":
            body = f'<a id="go" target="_blank" href="{LOCAL}/opened-shy" {LINK}>link</a>'
        else:
            body = f"<title>{page}</title>opened {page}"
        data = ("<!doctype html><meta charset=utf-8>" + body).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass


sv.srv.RequestHandlerClass = H


def space(**f): return sv.cmd({"do": "space", **f})
def tabs(): return sv.cmd({"do": "tabs"})["tabs"]
def paths(): return [urlparse(t["url"]).path for t in tabs()]
def link(url): sv.cmd({"do": "windows", "action": "link", "url": url})
def current(): return space()["current"]


def home():
    """Back to the first space, and its tabs."""
    space(action="go", index=1); time.sleep(0.8)


def over(index=2):
    """Over to Two, or another space, and its tabs."""
    space(action="go", index=index); time.sleep(0.8)


def press(code, ch, mods=()):
    return sv.cmd({"do": "press", "code": code, "chars": ch, "mods": list(mods)})


def typed(text, mods=()):
    """Into the field, raised already or else by ⌘L, then Return."""
    sv.cmd({"do": "field", "text": text}); time.sleep(0.4)
    press(36, "\r", mods); time.sleep(1.5)


def opened(url, wait=1.0):
    r = sv.sp("open", url=url)["resultID"]; time.sleep(wait); return r


def main():
    t = sv.T()
    try:
        sv.setup(**{"spaces": True, "spaces.links": True, "start.fresh": False, "newtab.floating": True})
        sv.launch()
        space(action="new", name="Two"); time.sleep(0.8)
        space(action="new", name="Three"); time.sleep(0.8)
        made = {s["name"]: s["id"] for s in json.load(open(f"{sv.SUPPORT}/spaces.json"))}
        two, three = made["Two"], made["Three"]
        # The rules, written as Settings writes them, read at the next launch.
        sv.quit(); time.sleep(1)
        subprocess.run(["defaults", "write", sv.SUITE, "spaces.links.rules", "-array",
                        f'{{ site = localhost; space = "{two}"; }}',
                        f'{{ site = a.localhost; space = "{three}"; }}'], check=True)
        # An engine on localhost, which the rule names: a search still stays.
        subprocess.run(["defaults", "write", sv.SUITE, "search.engine", "custom"], check=True)
        subprocess.run(["defaults", "write", sv.SUITE, "search.custom", f"{LOCAL}/find?q=%s"], check=True)
        sv.launch(); time.sleep(1)
        home()
        first = current()
        t.ok("in the first space to begin with", first != "Two", first)

        # A space with nothing open shows an empty tab, which the first page
        # opened there replaces.
        t.ok("the first space has only its empty tab", paths() == [""], paths())
        over(3)
        t.ok("Three has only its empty tab", paths() == [""], paths())
        home()
        typed(f"http://a.localhost:{PORT}/into-empty", ["cmd"])
        over(3)
        t.ok("a page opened behind into an empty space takes its empty tab's place",
             paths() == ["/into-empty"], paths())
        home()
        link(f"{LOCAL}/into-front"); time.sleep(1.5)
        t.ok("a page opened in front into an empty space takes its empty tab's place",
             current() == "Two" and paths() == ["/into-front"], (current(), paths()))
        home()

        # From another app.
        link(f"{LOCAL}/ext"); time.sleep(1.5)
        t.ok("a link from another app to localhost switches to Two", current() == "Two", current())
        t.ok("and opens there", "/ext" in paths(), paths())
        home()
        t.ok("not in the first space", "/ext" not in paths(), paths())
        link(f"{sv.BASE}/elsewhere"); time.sleep(1.5)
        t.ok("a link no rule names stays where you are", current() == first and "/elsewhere" in paths(), (current(), paths()))

        # From a page in the first space.
        page = opened(f"{sv.BASE}/blank")
        sv.cmd({"do": "tap", "id": page, "selector": "#go"}); time.sleep(2)
        t.ok("a target=_blank click to localhost switches to Two", current() == "Two", current())
        t.ok("and opens there", "/opened-blank" in paths(), paths())
        home()
        t.ok("no tab for it in the first space", "/opened-blank" not in paths(), paths())

        page = opened(f"{sv.BASE}/cmd")
        sv.cmd({"do": "tap", "id": page, "selector": "#go", "mods": ["cmd"]}); time.sleep(2)
        t.ok("a ⌘-click to localhost opens in Two", current() == "Two" and "/opened-cmd" in paths(), (current(), paths()))
        home()

        page = opened(f"{sv.BASE}/same")
        sv.cmd({"do": "tap", "id": page, "selector": "#go"}); time.sleep(2)
        t.ok("a link followed in its own tab stays in its space",
             current() == first and "/opened-same" in paths(), (current(), paths()))

        # Typed into the field.
        page = opened(f"{sv.BASE}/typed-over")
        typed(f"{LOCAL}/typed-l")
        t.ok("an address typed after ⌘L switches to Two", current() == "Two" and "/typed-l" in paths(), (current(), paths()))
        home()
        t.ok("and the tab it was typed over stays as it was",
             "/typed-l" not in paths() and "/typed-over" in paths(), paths())

        press(17, "t", ["cmd"]); time.sleep(0.5)
        typed(f"{LOCAL}/typed-t")
        t.ok("an address typed after ⌘T opens in Two", current() == "Two" and "/typed-t" in paths(), (current(), paths()))
        home()
        t.ok("no tab for it in the first space", "/typed-t" not in paths(), paths())

        typed(f"{LOCAL}/typed-behind", ["cmd"])
        t.ok("⌘Return stays where you are", current() == first and "/typed-behind" not in paths(), (current(), paths()))
        space(action="go", index=2); time.sleep(0.8)
        t.ok("with the tab behind in Two", "/typed-behind" in paths(), paths())
        home()

        typed("red pandas")
        t.ok("a search stays where you are", current() == first and "/find" in paths(), (current(), paths()))

        # A private tab's links are never sent.
        before = sv.sp("state")
        sv.sp("private"); time.sleep(0.6)
        shy = sv.sp("state")["activeID"]
        sv.cmd({"do": "go", "id": shy, "url": f"{sv.BASE}/shy"}); time.sleep(1.2)
        sv.cmd({"do": "tap", "id": shy, "selector": "#go"}); time.sleep(2)
        t.ok("a private tab's target=_blank link stays in the first space",
             current() == first and "/opened-shy" in paths(), (current(), paths(), before.get("activeID")))
    finally:
        t.done()
        sv.finish()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
